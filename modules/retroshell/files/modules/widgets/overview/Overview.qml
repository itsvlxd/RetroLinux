import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.components
import qs.modules.bar.workspaces
import qs.modules.services
import qs.config



Item {
    id: overviewRoot

    // Cache config values to avoid repeated lookups
    readonly property real scale: Config.overview.scale
    readonly property int rows: Config.overview.rows
    readonly property int columns: Config.overview.columns
    readonly property int workspacesShown: rows * columns
    readonly property real workspaceSpacing: Config.overview.workspaceSpacing
    readonly property real workspacePadding: 8
    readonly property color activeBorderColor: Styling.srItem("overprimary")

    // Use the screen's monitor instead of focused monitor for multi-monitor support
    property var currentScreen: null  // This will be set from parent
    readonly property var monitor: currentScreen ? AxctlService.monitorFor(currentScreen) : AxctlService.focusedMonitor
    readonly property int workspaceGroup: Math.floor((monitor?.activeWorkspace?.id - 1 || 0) / workspacesShown)

    // Cache these references
    readonly property var windowList: CompositorData.windowList
    readonly property var monitors: CompositorData.monitors
    readonly property int monitorId: monitor?.id ?? -1
    readonly property var monitorData: monitors.find(m => m.id === monitorId) ?? null

    readonly property string barPosition: Config.bar.position
    readonly property var barPanel: monitor ? Visibilities.getBarPanelForScreen(monitor.name) : null
    readonly property bool isBarPinned: barPanel ? barPanel.pinned : (Config.bar.pinnedOnStartup ?? true)
    readonly property int barReserved: isBarPinned ? (Config.showBackground ? 44 : 40) : 0

    // Search functionality (controlled from parent)
    property string searchQuery: ""
    property var matchingWindows: []
    property int selectedMatchIndex: 0

    // Keyboard navigation (arrow keys) — source of truth is the window address
    property string keyboardSelectedAddress: ""

    // Reset search state
    function resetSearch() {
        searchQuery = "";
        matchingWindows = [];
        selectedMatchIndex = 0;
    }

    // Update matching windows when search query or window list changes
    onSearchQueryChanged: {
        updateMatchingWindows();
        if (searchQuery.length === 0) {
            keyboardInitialize();
        }
    }
    onWindowListChanged: updateMatchingWindows()

    // Fuzzy match: checks if all characters of query appear in order in target
    function fuzzyMatch(query, target) {
        if (query.length === 0)
            return true;
        if (target.length === 0)
            return false;

        let queryIndex = 0;
        for (let i = 0; i < target.length && queryIndex < query.length; i++) {
            if (target[i] === query[queryIndex]) {
                queryIndex++;
            }
        }
        return queryIndex === query.length;
    }

    // Score a fuzzy match (higher is better)
    function fuzzyScore(query, target) {
        if (query.length === 0)
            return 0;
        if (target.length === 0)
            return -1;

        // Exact match gets highest score
        if (target.includes(query))
            return 1000 + (100 - target.length);

        // Check for fuzzy match
        let queryIndex = 0;
        let consecutiveMatches = 0;
        let maxConsecutive = 0;
        let score = 0;

        for (let i = 0; i < target.length && queryIndex < query.length; i++) {
            if (target[i] === query[queryIndex]) {
                queryIndex++;
                consecutiveMatches++;
                maxConsecutive = Math.max(maxConsecutive, consecutiveMatches);
                // Bonus for matches at word boundaries
                if (i === 0 || target[i - 1] === ' ' || target[i - 1] === '-' || target[i - 1] === '_') {
                    score += 10;
                }
            } else {
                consecutiveMatches = 0;
            }
        }

        if (queryIndex !== query.length)
            return -1; // No match

        return score + maxConsecutive * 5;
    }

    function updateMatchingWindows() {
        if (searchQuery.length === 0) {
            matchingWindows = [];
            selectedMatchIndex = 0;
            return;
        }

        const query = searchQuery.toLowerCase();
        const matches = windowList.filter(win => {
            if (!win)
                return false;
            const title = (win.title || "").toLowerCase();
            const windowClass = (win.class || "").toLowerCase();
            return fuzzyMatch(query, title) || fuzzyMatch(query, windowClass);
        }).map(win => ({
                    window: win,
                    score: Math.max(fuzzyScore(query, (win.title || "").toLowerCase()), fuzzyScore(query, (win.class || "").toLowerCase()))
                })).sort((a, b) => b.score - a.score).map(item => item.window);

        matchingWindows = matches;
        selectedMatchIndex = matches.length > 0 ? 0 : -1;
    }

    function navigateToSelectedWindow() {
        if (matchingWindows.length === 0 || selectedMatchIndex < 0)
            return;

        const win = matchingWindows[selectedMatchIndex];
        if (!win)
            return;

        // Close overview and focus the matched window
        Visibilities.setActiveModule("", true);
        Qt.callLater(() => {
            HyprService.focusWindow(win.address);
        });
    }

    function selectNextMatch() {
        if (matchingWindows.length === 0)
            return;
        selectedMatchIndex = (selectedMatchIndex + 1) % matchingWindows.length;
    }

    function selectPrevMatch() {
        if (matchingWindows.length === 0)
            return;
        selectedMatchIndex = (selectedMatchIndex - 1 + matchingWindows.length) % matchingWindows.length;
    }

    function isWindowMatched(windowAddress) {
        if (searchQuery.length === 0)
            return false;
        return matchingWindows.some(win => win?.address === windowAddress);
    }

    function isWindowSelected(windowAddress) {
        if (searchQuery.length > 0) {
            if (matchingWindows.length === 0 || selectedMatchIndex < 0)
                return false;
            return matchingWindows[selectedMatchIndex]?.address === windowAddress;
        }
        return keyboardSelectedAddress === windowAddress;
    }

    // Visible windows in this workspace group, with on-screen centers for spatial navigation
    readonly property var navigationWindows: {
        const minWs = workspaceGroup * workspacesShown;
        const maxWs = (workspaceGroup + 1) * workspacesShown;
        const monId = monitorId;
        const result = [];
        for (const win of windowList) {
            if (!win)
                continue;
            const wsId = win?.workspace?.id;
            if (!(wsId > minWs && wsId <= maxWs) || win.monitor !== monId)
                continue;

            const colIndex = (wsId - 1) % columns;
            const rowIndex = Math.floor(((wsId - 1) % workspacesShown) / columns);
            const xOff = Math.round((workspaceImplicitWidth + workspacePadding + workspaceSpacing) * colIndex + workspacePadding / 2);
            const yOff = Math.round((workspaceImplicitHeight + workspacePadding + workspaceSpacing) * rowIndex + workspacePadding / 2);

            let baseX = (win.at?.[0] || 0) - (monitorData?.x || 0);
            if (barPosition === "left")
                baseX -= barReserved;
            let baseY = (win.at?.[1] || 0) - (monitorData?.y || 0);
            if (barPosition === "top")
                baseY -= barReserved;

            const x = Math.round(Math.max(baseX * scale, 0) + xOff);
            const y = Math.round(Math.max(baseY * scale, 0) + yOff);
            const w = Math.round((win.size?.[0] || 100) * scale);
            const h = Math.round((win.size?.[1] || 100) * scale);

            result.push({
                windowData: win,
                address: win.address,
                row: rowIndex,
                centerX: x + w / 2,
                centerY: y + h / 2
            });
        }
        return result;
    }

    function keyboardInitialize() {
        const list = navigationWindows;
        if (list.length === 0) {
            keyboardSelectedAddress = "";
            return;
        }
        const focused = AxctlService.focusedClient?.address;
        if (focused && list.some(w => w.address === focused)) {
            keyboardSelectedAddress = focused;
        } else {
            keyboardSelectedAddress = list[0].address;
        }
    }

    // For wrap-around: pick the extreme window along the opposite axis, tie-broken by proximity
    function shouldWrapReplace(direction, cur, cand, currentBest) {
        if (direction === "right" || direction === "left") {
            if (cand.centerX === currentBest.centerX)
                return Math.abs(cand.centerY - cur.centerY) < Math.abs(currentBest.centerY - cur.centerY);
            if (direction === "right")
                return cand.centerX < currentBest.centerX;
            return cand.centerX > currentBest.centerX;
        }
        if (cand.centerY === currentBest.centerY)
            return Math.abs(cand.centerX - cur.centerX) < Math.abs(currentBest.centerX - cur.centerX);
        if (direction === "down")
            return cand.centerY < currentBest.centerY;
        return cand.centerY > currentBest.centerY;
    }

    function keyboardMove(direction) {
        const list = navigationWindows;
        if (list.length === 0)
            return;

        let currentIndex = -1;
        if (keyboardSelectedAddress) {
            currentIndex = list.findIndex(w => w.address === keyboardSelectedAddress);
        }
        if (currentIndex < 0)
            currentIndex = 0;
        const cur = list[currentIndex];

        // Horizontal moves stay within the same grid row to avoid jumping rows
        const isHorizontal = direction === "left" || direction === "right";
        const candidates = isHorizontal ? list.filter(w => w.row === cur.row) : list;

        let best = -1;
        let bestDist = Infinity;
        for (let i = 0; i < candidates.length; i++) {
            const w = candidates[i];
            if (w.address === cur.address)
                continue;
            const dx = w.centerX - cur.centerX;
            const dy = w.centerY - cur.centerY;
            const inDirection = direction === "right" ? dx > 0
                : direction === "left" ? dx < 0
                : direction === "down" ? dy > 0
                : dy < 0;
            if (!inDirection)
                continue;
            const dist = dx * dx + dy * dy;
            if (dist < bestDist) {
                bestDist = dist;
                best = i;
            }
        }

        // Wrap: horizontal wraps within the same row, vertical wraps globally
        if (best === -1 && candidates.length > 1) {
            best = 0;
            for (let i = 1; i < candidates.length; i++) {
                if (shouldWrapReplace(direction, cur, candidates[i], candidates[best]))
                    best = i;
            }
        }

        // Only window in its row (or nothing to move to) — stay put
        if (best === -1)
            return;

        keyboardSelectedAddress = candidates[best].address;
    }

    function activateSelectedWindow() {
        const address = keyboardSelectedAddress;
        if (!address)
            return;
        Visibilities.setActiveModule("", true);
        Qt.callLater(() => {
            HyprService.focusWindow(address);
        });
    }

    // Pre-calculate workspace dimensions once
    readonly property real workspaceImplicitWidth: {
        if (!monitorData)
            return 200;
        const isRotated = (monitorData.transform % 2 === 1);
        const monitorScale = monitorData.scale || 1.0;
        const width = isRotated ? (monitor?.height || 1920) : (monitor?.width || 1920);
        let scaledWidth = (width / monitorScale) * scale;
        if (barPosition === "left" || barPosition === "right") {
            scaledWidth -= barReserved * scale;
        }
        return Math.max(0, Math.round(scaledWidth));
    }

    readonly property real workspaceImplicitHeight: {
        if (!monitorData)
            return 150;
        const isRotated = (monitorData.transform % 2 === 1);
        const monitorScale = monitorData.scale || 1.0;
        const height = isRotated ? (monitor?.width || 1080) : (monitor?.height || 1080);
        let scaledHeight = (height / monitorScale) * scale;
        if (barPosition === "top" || barPosition === "bottom") {
            scaledHeight -= barReserved * scale;
        }
        return Math.max(0, Math.round(scaledHeight));
    }

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    implicitWidth: overviewBackground.implicitWidth
    implicitHeight: overviewBackground.implicitHeight

    Item {
        id: overviewBackground
        anchors.centerIn: parent

        implicitWidth: workspaceColumnLayout.implicitWidth
        implicitHeight: workspaceColumnLayout.implicitHeight

        ColumnLayout {
            id: workspaceColumnLayout
            anchors.centerIn: parent
            spacing: workspaceSpacing

            Repeater {
                model: overviewRoot.rows
                delegate: RowLayout {
                    id: row
                    property int rowIndex: index
                    spacing: workspaceSpacing

                    Repeater {
                        model: overviewRoot.columns
                        Rectangle {
                            id: workspace
                            property int colIndex: index
                            property int workspaceValue: overviewRoot.workspaceGroup * workspacesShown + rowIndex * overviewRoot.columns + colIndex + 1
                            property color defaultWorkspaceColor: Colors.background
                            property color hoveredWorkspaceColor: Colors.surfaceContainer
                            property color hoveredBorderColor: Colors.outline
                            property bool hoveredWhileDragging: false

                            implicitWidth: overviewRoot.workspaceImplicitWidth + workspacePadding
                            implicitHeight: overviewRoot.workspaceImplicitHeight + workspacePadding
                            color: "transparent"
                            radius: Styling.radius(2)
                            border.width: 2
                            border.color: hoveredWhileDragging ? hoveredBorderColor : "transparent"
                            clip: true

                            // Wallpaper background for each workspace
                            TintedWallpaper {
                                id: workspaceWallpaper
                                anchors.fill: parent
                                radius: Styling.radius(2)
                                tintEnabled: GlobalStates.wallpaperManager ? GlobalStates.wallpaperManager.tintEnabled : false

                                property string lockscreenFramePath: {
                                    if (!GlobalStates.wallpaperManager)
                                        return "";
                                    return GlobalStates.wallpaperManager.getLockscreenFramePath(GlobalStates.wallpaperManager.currentWallpaper);
                                }

                                source: lockscreenFramePath ? "file://" + lockscreenFramePath : ""
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: {
                                    if (overviewRoot.draggingTargetWorkspace === -1) {
                                        Visibilities.setActiveModule("");
                                        HyprService.focusWorkspace(workspaceValue);
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    overviewRoot.draggingTargetWorkspace = workspaceValue;
                                    if (overviewRoot.draggingFromWorkspace == overviewRoot.draggingTargetWorkspace)
                                        return;
                                    hoveredWhileDragging = true;
                                }
                                onExited: {
                                    hoveredWhileDragging = false;
                                    if (overviewRoot.draggingTargetWorkspace == workspaceValue)
                                        overviewRoot.draggingTargetWorkspace = -1;
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: workspaceColumnLayout.implicitWidth
            implicitHeight: workspaceColumnLayout.implicitHeight

            // Pre-filter windows for this monitor and workspace group
            readonly property var filteredWindowData: {
                const minWs = overviewRoot.workspaceGroup * overviewRoot.workspacesShown;
                const maxWs = (overviewRoot.workspaceGroup + 1) * overviewRoot.workspacesShown;
                const monId = overviewRoot.monitorId;
                const toplevels = ToplevelManager.toplevels.values;

                return overviewRoot.windowList.filter(win => {
                    const wsId = win?.workspace?.id;
                    return wsId > minWs && wsId <= maxWs && win.monitor === monId;
                }).map(win => ({
                            windowData: win,
                            toplevel: (() => {
                                const cls = win.class || "";
                                if (!cls) return null;
                                const candidates = toplevels.filter(t => t.appId === cls);
                                if (candidates.length <= 1) return candidates[0] || null;
                                return candidates.find(t => t.title === (win.title || "")) || candidates[0];
                            })()
                        }));
            }

            Repeater {
                model: windowSpace.filteredWindowData

                delegate: OverviewWindow {
                    id: window
                    required property var modelData
                    windowData: modelData.windowData
                    toplevel: modelData.toplevel
                    scale: overviewRoot.scale
                    availableWorkspaceWidth: overviewRoot.workspaceImplicitWidth
                    availableWorkspaceHeight: overviewRoot.workspaceImplicitHeight
                    monitorData: overviewRoot.monitorData
                    barPosition: overviewRoot.barPosition
                    barReserved: overviewRoot.barReserved

                    // Search highlighting
                    isSearchMatch: overviewRoot.isWindowMatched(windowData?.address)
                    isSearchSelected: overviewRoot.isWindowSelected(windowData?.address)

                    property int workspaceColIndex: (windowData?.workspace.id - 1) % overviewRoot.columns
                    property int workspaceRowIndex: Math.floor((windowData?.workspace.id - 1) % overviewRoot.workspacesShown / overviewRoot.columns)

                    xOffset: Math.round((overviewRoot.workspaceImplicitWidth + workspacePadding + workspaceSpacing) * workspaceColIndex + workspacePadding / 2)
                    yOffset: Math.round((overviewRoot.workspaceImplicitHeight + workspacePadding + workspaceSpacing) * workspaceRowIndex + workspacePadding / 2)

                    onDragStarted: overviewRoot.draggingFromWorkspace = windowData?.workspace.id || -1
                    onDragFinished: targetWorkspace => {
                        overviewRoot.draggingFromWorkspace = -1;
                        if (targetWorkspace !== -1 && targetWorkspace !== windowData?.workspace.id) {
                            HyprService.moveWindowToWorkspace(windowData?.address, targetWorkspace);
                        }
                    }
                    onWindowClicked: {
                        // Close overview and focus the specific clicked window
                        // Skip generic focus restoration since we're handling it specifically
                        Visibilities.setActiveModule("", true);
                        Qt.callLater(() => {
                            HyprService.focusWindow(windowData.address);
                        });
                    }
                    onWindowClosed: {
                        HyprService.closeWindow(windowData.address);
                    }
                }
            }

            Rectangle {
                id: focusedWorkspaceIndicator
                property int activeWorkspaceInGroup: (monitor?.activeWorkspace?.id || 1) - (overviewRoot.workspaceGroup * overviewRoot.workspacesShown)
                property int activeWorkspaceRowIndex: Math.floor((activeWorkspaceInGroup - 1) / overviewRoot.columns)
                property int activeWorkspaceColIndex: (activeWorkspaceInGroup - 1) % overviewRoot.columns

                x: Math.round((overviewRoot.workspaceImplicitWidth + workspacePadding + workspaceSpacing) * activeWorkspaceColIndex)
                y: Math.round((overviewRoot.workspaceImplicitHeight + workspacePadding + workspaceSpacing) * activeWorkspaceRowIndex)
                width: Math.round(overviewRoot.workspaceImplicitWidth + workspacePadding)
                height: Math.round(overviewRoot.workspaceImplicitHeight + workspacePadding)
                color: "transparent"
                radius: Styling.radius(2)
                border.width: 2
                border.color: overviewRoot.activeBorderColor

                Behavior on x {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on y {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }
    }
}
