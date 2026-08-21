import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.bar.workspaces
import qs.modules.services
import qs.modules.components
import qs.config

Item {
    id: scrollingOverviewRoot

    // Config values
    readonly property real scale: Config.overview.scale
    readonly property int totalWorkspaces: Config.overview.rows * Config.overview.columns
    readonly property int visibleWorkspaces: 3  // Show 3 workspaces at a time in viewport
    readonly property real workspaceSpacing: Config.overview.workspaceSpacing
    readonly property real workspacePadding: 4
    readonly property color activeBorderColor: Styling.srItem("overprimary")

    // Monitor info
    property var currentScreen: null
    readonly property var monitor: currentScreen ? AxctlService.monitorFor(currentScreen) : AxctlService.focusedMonitor
    readonly property int monitorId: monitor?.id ?? -1
    readonly property var monitors: CompositorData.monitors
    readonly property var monitorData: monitors.find(m => m.id === monitorId) ?? null

    readonly property string barPosition: Config.bar.position
    readonly property var barPanel: monitor ? Visibilities.getBarPanelForScreen(monitor.name) : null
    readonly property bool isBarPinned: barPanel ? barPanel.pinned : (Config.bar.pinnedOnStartup ?? true)
    readonly property int barReserved: isBarPinned ? (Config.showBackground ? 44 : 40) : 0

    // Window data
    readonly property var windowList: CompositorData.windowList

    // Focused window address for centering
    readonly property string focusedWindowAddress: AxctlService.focusedClient?.address ?? ""

    // Search functionality
    property string searchQuery: ""
    property var matchingWindows: []
    property int selectedMatchIndex: 0

    // Keyboard navigation (arrow keys) — source of truth is the window address
    property string keyboardSelectedAddress: ""

    function resetSearch() {
        searchQuery = "";
        matchingWindows = [];
        selectedMatchIndex = 0;
    }

    onSearchQueryChanged: {
        updateMatchingWindows();
        if (searchQuery.length === 0) {
            keyboardInitialize();
        }
    }
    onWindowListChanged: updateMatchingWindows()

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

    function fuzzyScore(query, target) {
        if (query.length === 0)
            return 0;
        if (target.length === 0)
            return -1;
        if (target.includes(query))
            return 1000 + (100 - target.length);
        let queryIndex = 0;
        let consecutiveMatches = 0;
        let maxConsecutive = 0;
        let score = 0;
        for (let i = 0; i < target.length && queryIndex < query.length; i++) {
            if (target[i] === query[queryIndex]) {
                queryIndex++;
                consecutiveMatches++;
                maxConsecutive = Math.max(maxConsecutive, consecutiveMatches);
                if (i === 0 || target[i - 1] === ' ' || target[i - 1] === '-' || target[i - 1] === '_') {
                    score += 10;
                }
            } else {
                consecutiveMatches = 0;
            }
        }
        if (queryIndex !== query.length)
            return -1;
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
        Visibilities.setActiveModule("", true);
        Qt.callLater(() => {
            AxctlService.dispatch(`focuswindow address:${win.address}`);
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

    // All windows on this monitor with on-screen centers (in flickable content coords)
    readonly property var navigationWindows: {
        const monId = monitorId;
        const rowHeight = workspaceRowHeight;
        const viewportOffset = workspaceWidth / 3;
        const result = [];
        for (let ws = 1; ws <= totalWorkspaces; ws++) {
            for (const win of windowList) {
                if (!win)
                    continue;
                if ((win.workspace ? win.workspace.id : null) !== ws || win.monitor !== monId)
                    continue;

                let baseX = ((win.at && win.at[0] !== undefined ? win.at[0] : 0) || 0) - ((monitorData && monitorData.x !== undefined ? monitorData.x : 0) || 0);
                if (barPosition === "left")
                    baseX -= barReserved;
                const x = (baseX * scale) + viewportOffset;

                let baseY = ((win.at && win.at[1] !== undefined ? win.at[1] : 0) || 0) - ((monitorData && monitorData.y !== undefined ? monitorData.y : 0) || 0);
                if (barPosition === "top")
                    baseY -= barReserved;
                const y = Math.max(baseY * scale, 0) + (ws - 1) * rowHeight;

                const w = Math.round(((win.size && win.size[0] !== undefined ? win.size[0] : 100) || 100) * scale);
                const h = Math.round(((win.size && win.size[1] !== undefined ? win.size[1] : 100) || 100) * scale);

                result.push({
                    windowData: win,
                    address: win.address,
                    workspaceId: ws,
                    row: ws,
                    centerX: x + w / 2,
                    centerY: y + h / 2
                });
            }
        }
        return result;
    }

    function scrollToWorkspace(id) {
        const targetY = (id - 1) * workspaceRowHeight;
        const centeredY = targetY - (workspaceFlickable.height - workspaceHeight) / 2;
        workspaceFlickable.contentY = Math.max(0, Math.min(centeredY, workspaceFlickable.contentHeight - workspaceFlickable.height));
    }

    function keyboardInitialize() {
        const list = navigationWindows;
        if (list.length === 0) {
            keyboardSelectedAddress = "";
            return;
        }
        let chosen = null;
        const focused = AxctlService.focusedClient?.address;
        if (focused)
            chosen = list.find(w => w.address === focused) || null;
        if (!chosen)
            chosen = list[0];
        keyboardSelectedAddress = chosen.address;
        scrollToWorkspace(chosen.workspaceId);
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

        // Horizontal moves stay within the same workspace to avoid jumping rows
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

        // Wrap: horizontal wraps within the same workspace, vertical wraps globally
        if (best === -1 && candidates.length > 1) {
            best = 0;
            for (let i = 1; i < candidates.length; i++) {
                if (shouldWrapReplace(direction, cur, candidates[i], candidates[best]))
                    best = i;
            }
        }

        // Only window in its workspace (or nothing to move to) — stay put
        if (best === -1)
            return;

        keyboardSelectedAddress = candidates[best].address;
        scrollToWorkspace(candidates[best].workspaceId);
    }

    function activateSelectedWindow() {
        const address = keyboardSelectedAddress;
        if (!address)
            return;
        Visibilities.setActiveModule("", true);
        Qt.callLater(() => {
            AxctlService.dispatch(`focuswindow address:${address}`);
        });
    }

    // Calculate workspace dimensions
    // Triple the width for scrolling mode to take advantage of horizontal space
    readonly property real workspaceWidth: {
        if (!monitorData)
            return 800;
        const isRotated = (monitorData.transform % 2 === 1);
        const monitorScale = monitorData.scale || 1.0;
        const width = isRotated ? (monitor?.height || 1920) : (monitor?.width || 1920);
        let scaledWidth = (width / monitorScale) * scale;
        if (barPosition === "left" || barPosition === "right") {
            scaledWidth -= barReserved * scale;
        }
        return Math.max(0, Math.round(scaledWidth * 3));  // Triple width
    }

    readonly property real workspaceHeight: {
        if (!monitorData)
            return 150;
        const isRotated = (monitorData.transform % 2 === 1);
        const monitorScale = monitorData.scale || 1.0;
        const height = isRotated ? (monitor?.width || 1080) : (monitor?.height || 1080);
        let scaledHeight = (height / monitorScale) * scale;
        if (barPosition === "top" || barPosition === "bottom") {
            scaledHeight -= barReserved * scale;
        }
        return Math.max(0, Math.round(scaledHeight + workspacePadding * 2));
    }

    // Dragging state
    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    // Calculate which workspace is at a given Y position (relative to flickable content)
    function getWorkspaceAtY(globalY) {
        // Convert global Y to content Y (accounting for flickable position and margins)
        const flickableGlobalY = workspaceFlickable.mapToItem(null, 0, 0).y;
        const contentY = globalY - flickableGlobalY + workspaceFlickable.contentY;

        // Calculate workspace index
        const wsIndex = Math.floor(contentY / workspaceRowHeight);
        if (wsIndex >= 0 && wsIndex < totalWorkspaces) {
            return wsIndex + 1;  // Workspace IDs are 1-based
        }
        return -1;
    }

    // Size for the overview
    implicitWidth: workspaceWidth + workspacePadding * 2
    implicitHeight: workspaceHeight * 3 + workspaceSpacing * 3

    // Expose flickable for external scrollbar
    property alias flickable: workspaceFlickable
    readonly property bool needsScrollbar: workspaceFlickable.contentHeight > workspaceFlickable.height

    // Track if user is manually scrolling (set externally by scrollbar)
    property bool isManualScrolling: false

    // Calculate target scroll position to center active workspace
    readonly property int activeWorkspaceId: monitor?.activeWorkspace?.id || 1
    readonly property real workspaceRowHeight: workspaceHeight + workspaceSpacing

    // Scroll to center active workspace when it changes
    onActiveWorkspaceIdChanged: workspaceFlickable.scrollToActiveWorkspace()

    // Vertical flickable containing all workspaces
    Flickable {
        id: workspaceFlickable
        anchors.fill: parent
        anchors.margins: workspacePadding
        contentWidth: width
        contentHeight: workspaceColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Behavior on contentY {
            enabled: Config.animDuration > 0 && !scrollingOverviewRoot.isManualScrolling
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        Component.onCompleted: scrollToActiveWorkspace()

        function scrollToActiveWorkspace() {
            const targetY = (scrollingOverviewRoot.activeWorkspaceId - 1) * scrollingOverviewRoot.workspaceRowHeight;
            const centeredY = targetY - (height - workspaceHeight) / 2;
            contentY = Math.max(0, Math.min(centeredY, contentHeight - height));
        }

        // Content item containing workspaces and indicator
        Item {
            id: contentItem
            width: parent.width
            height: workspaceColumn.implicitHeight

            Column {
                id: workspaceColumn
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: workspaceSpacing

                Repeater {
                    model: totalWorkspaces
                    delegate: ScrollingWorkspace {
                        id: scrollingWorkspace
                        required property int index
                        workspaceId: index + 1
                        workspaceWidth: scrollingOverviewRoot.workspaceWidth
                        workspaceHeight: scrollingOverviewRoot.workspaceHeight
                        workspacePadding: scrollingOverviewRoot.workspacePadding
                        scale_: scrollingOverviewRoot.scale
                        monitorId: scrollingOverviewRoot.monitorId
                        monitorData: scrollingOverviewRoot.monitorData
                        barPosition: scrollingOverviewRoot.barPosition
                        barReserved: scrollingOverviewRoot.barReserved
                        windowList: scrollingOverviewRoot.windowList
                        isActive: (scrollingOverviewRoot.monitor?.activeWorkspace?.id || 0) === workspaceId
                        activeBorderColor: scrollingOverviewRoot.activeBorderColor
                        focusedWindowAddress: scrollingOverviewRoot.focusedWindowAddress

                        // Search integration
                        searchQuery: scrollingOverviewRoot.searchQuery
                        checkWindowMatched: scrollingOverviewRoot.isWindowMatched
                        checkWindowSelected: scrollingOverviewRoot.isWindowSelected

                        // Dragging - use bidirectional binding
                        draggingFromWorkspace: scrollingOverviewRoot.draggingFromWorkspace
                        onDraggingFromWorkspaceChanged: {
                            if (draggingFromWorkspace !== scrollingOverviewRoot.draggingFromWorkspace) {
                                scrollingOverviewRoot.draggingFromWorkspace = draggingFromWorkspace;
                            }
                        }
                        draggingTargetWorkspace: scrollingOverviewRoot.draggingTargetWorkspace
                        onDraggingTargetWorkspaceChanged: {
                            if (draggingTargetWorkspace !== scrollingOverviewRoot.draggingTargetWorkspace) {
                                scrollingOverviewRoot.draggingTargetWorkspace = draggingTargetWorkspace;
                            }
                        }

                        // Provide drag overlay reference
                        dragOverlay: dragOverlayItem
                        overviewRoot: scrollingOverviewRoot

                        width: scrollingOverviewRoot.workspaceWidth
                        height: scrollingOverviewRoot.workspaceHeight
                    }
                }
            }

            // Floating active workspace indicator (inside content, moves with scroll)
            Rectangle {
                id: focusedWorkspaceIndicator
                readonly property int activeWorkspaceId: scrollingOverviewRoot.monitor?.activeWorkspace?.id || 1

                x: 0
                y: (activeWorkspaceId - 1) * (workspaceHeight + workspaceSpacing)
                width: workspaceWidth
                height: workspaceHeight
                color: "transparent"
                radius: Styling.radius(1)
                border.width: 2
                border.color: scrollingOverviewRoot.activeBorderColor
                z: 10

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

    // Drag overlay - windows being dragged are reparented here to escape clipping
    Item {
        id: dragOverlayItem
        anchors.fill: parent
        z: 1000
    }
}
