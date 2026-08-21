pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.modules.services

Singleton {
    id: root

    // Check pin status
    function isPinned(appId) {
        const pinnedApps = Config.pinnedApps?.apps || [];
        return pinnedApps.some(id => id.toLowerCase() === appId.toLowerCase());
    }

    // Toggle pin
    function togglePin(appId) {
        let pinnedApps = Config.pinnedApps?.apps || [];
        const normalizedAppId = appId.toLowerCase();
        
        if (isPinned(appId)) {
            // Unpin
            Config.pinnedApps.apps = pinnedApps.filter(id => id.toLowerCase() !== normalizedAppId);
        } else {
            // Pin
            Config.pinnedApps.apps = pinnedApps.concat([appId]);
        }

        // Persist changes
        Config.savePinnedApps();
    }

    // Index of an app in the pinned list, or -1 if not pinned
    function pinnedIndex(appId) {
        const pinnedApps = Config.pinnedApps?.apps || [];
        const normalized = appId.toLowerCase();
        for (let i = 0; i < pinnedApps.length; i++) {
            if (pinnedApps[i].toLowerCase() === normalized) return i;
        }
        return -1;
    }

    // Pin an app at the given index (inserting if missing, moving if present)
    function pinApp(appId, index) {
        let pinnedApps = (Config.pinnedApps?.apps || []).slice();
        const normalized = appId.toLowerCase();
        const existing = pinnedApps.findIndex(id => id.toLowerCase() === normalized);
        const clamped = Math.max(0, Math.min(index, existing >= 0 ? pinnedApps.length - 1 : pinnedApps.length));

        if (existing >= 0) {
            if (existing !== clamped) {
                pinnedApps.splice(existing, 1);
                pinnedApps.splice(clamped, 0, appId);
            }
        } else {
            pinnedApps.splice(clamped, 0, appId);
        }

        Config.pinnedApps.apps = pinnedApps;
        Config.savePinnedApps();
    }

    // Reorder a pinned app to the given index within the pinned list
    function reorderPinned(appId, toIndex) {
        const normalized = appId.toLowerCase();
        let pinnedApps = (Config.pinnedApps?.apps || []).slice();
        const from = pinnedApps.findIndex(id => id.toLowerCase() === normalized);
        if (from < 0) return;

        pinnedApps.splice(from, 1);
        const clamped = Math.max(0, Math.min(toIndex, pinnedApps.length));
        pinnedApps.splice(clamped, 0, appId);

        Config.pinnedApps.apps = pinnedApps;
        Config.savePinnedApps();
    }

    // Get entry
    function getDesktopEntry(appId) {
        if (!appId) return null;
        return DesktopEntries.heuristicLookup(appId) || null;
    }

    // Launch
    function launchApp(appId) {
        const entry = getDesktopEntry(appId);
        if (entry) {
            AppSearch.launchApp(entry);
        }
    }

    // Cache entries
    property var _appCache: ({})
    property var _previousKeys: []

    // Combined app list
    property list<var> apps: []

    // Debounce update
    Timer {
        id: updateTimer
        interval: 100
        repeat: false
        onTriggered: root._updateApps()
    }

    // Update on toplevel change
    Connections {
        target: ToplevelManager.toplevels
        function onObjectInsertedPost() {
            updateTimer.restart();
        }
        function onObjectRemovedPost() {
            updateTimer.restart();
        }
    }

    // Update on config change
    Connections {
        target: Config.pinnedApps ?? null
        function onAppsChanged() {
            updateTimer.restart();
        }
    }

    Connections {
        target: Config.dock ?? null
        function onIgnoredAppRegexesChanged() {
            updateTimer.restart();
        }
    }

    // Init
    Component.onCompleted: {
        _updateApps();
    }

    function _updateApps() {
        var map = new Map();

        // Get config
        const pinnedApps = Config.pinnedApps?.apps ?? [];
        const ignoredRegexStrings = Config.dock?.ignoredAppRegexes ?? [];
        const ignoredRegexes = ignoredRegexStrings.map(pattern => new RegExp(pattern, "i"));

        // Add pinned
        for (const appId of pinnedApps) {
            const key = appId.toLowerCase();
            if (!map.has(key)) {
                map.set(key, {
                    appId: appId,
                    pinned: true,
                    toplevels: []
                });
            }
        }

        // Collect unpinned
        var unpinnedRunningApps = [];
        const toplevels = ToplevelManager.toplevels.values;
        for (let i = 0; i < toplevels.length; i++) {
            const toplevel = toplevels[i];
            // Skip ignored
            if (ignoredRegexes.some(re => re.test(toplevel.appId))) continue;
            
            const key = toplevel.appId.toLowerCase();
            
            // Check if pinned
            if (map.has(key)) {
                // Add to pinned app
                map.get(key).toplevels.push(toplevel);
            } else {
                // Track unpinned
                const existing = unpinnedRunningApps.find(app => app.key === key);
                if (!existing) {
                    unpinnedRunningApps.push({
                        key: key,
                        appId: toplevel.appId,
                        toplevels: [toplevel]
                    });
                } else {
                    existing.toplevels.push(toplevel);
                }
            }
        }

        // Add separator if needed
        if (pinnedApps.length > 0 && unpinnedRunningApps.length > 0) {
            map.set("SEPARATOR", { 
                appId: "SEPARATOR", 
                pinned: false, 
                toplevels: [] 
            });
        }

        // Add unpinned to map
        for (const app of unpinnedRunningApps) {
            map.set(app.key, {
                appId: app.appId,
                pinned: false,
                toplevels: app.toplevels
            });
        }

        // New keys list
        var newKeys = Array.from(map.keys());

        // Cleanup entries
        for (const oldKey of _previousKeys) {
            if (!map.has(oldKey) && _appCache[oldKey]) {
                _appCache[oldKey].destroy();
                delete _appCache[oldKey];
            }
        }

        // Sync entries
        var values = [];
        for (const [key, value] of map) {
            if (_appCache[key]) {
                // Update entry
                _appCache[key].toplevels = value.toplevels;
                _appCache[key].pinned = value.pinned;
                values.push(_appCache[key]);
            } else {
                // Create entry
                const entry = appEntryComp.createObject(root, { 
                    appId: value.appId, 
                    toplevels: value.toplevels, 
                    pinned: value.pinned 
                });
                _appCache[key] = entry;
                values.push(entry);
            }
        }

        _previousKeys = newKeys;
        apps = values;
    }

    // App entry component
    component TaskbarAppEntry: QtObject {
        required property string appId
        property var toplevels: []
        property int toplevelCount: toplevels.length
        property bool pinned
    }
    
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
