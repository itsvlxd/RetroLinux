pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.modules.corners
import qs.modules.globals
import qs.config

Item {
    id: root

    required property ShellScreen screen
    property bool unifiedEffectActive: false
    
    // Pass pinned state from parent or config
    readonly property bool keepHidden: Config.dock?.keepHidden ?? false
    property bool pinned: Config.dock?.pinnedOnStartup ?? false

    // Theme configuration
    readonly property string theme: Config.dock?.theme ?? "default"
    readonly property bool isFloating: theme === "floating"
    readonly property bool isDefault: theme === "default"

    // Position configuration with fallback logic to avoid bar collision
    readonly property string userPosition: Config.dock?.position ?? "bottom"
    readonly property string barPosition: Config.bar?.position ?? "top"
    readonly property string notchPosition: Config.notchPosition ?? "top"

    // Effective position
    readonly property string position: {
        if (notchPosition === "bottom" && userPosition === "bottom") {
            return (barPosition === "left") ? "right" : "left";
        }
        if (userPosition !== barPosition) {
            return userPosition;
        }
        switch (userPosition) {
        case "bottom":
            if (notchPosition === "bottom" || barPosition === "bottom") {
                 return (barPosition === "left") ? "right" : "left";
            }
            return "left";
        case "left":
            return "right";
        case "right":
            return "left";
        case "top":
            return "bottom";
        default:
            return "bottom";
        }
    }

    readonly property bool isBottom: position === "bottom"
    readonly property bool isLeft: position === "left"
    readonly property bool isRight: position === "right"
    readonly property bool isVertical: isLeft || isRight

    // Margin calculations
    readonly property int dockMargin: Config.dock?.margin ?? 8
    readonly property int compositorGapsOut: Config.compositor?.gapsOut ?? 4

    readonly property int windowSideMargin: dockMargin > 0 ? Math.max(0, dockMargin - compositorGapsOut) : 0
    readonly property int edgeSideMargin: isDefault ? 0 : dockMargin

    // Reference to the bar panel on this screen
    readonly property var barPanelRef: Visibilities.barPanels[screen.name]
    readonly property bool barPinned: {
        if (barPanelRef && typeof barPanelRef.pinned !== 'undefined') {
            return barPanelRef.pinned;
        }
        return true;
    }

    // Monitor reference and refrence to toplevels on monitor
    readonly property var compositorMonitor: AxctlService.monitorFor(screen)
    readonly property var toplevels: (!compositorMonitor || !compositorMonitor.activeWorkspace || !AxctlService.clients.values) ? [] : AxctlService.clients.values.filter(c => c.workspace.id === compositorMonitor.activeWorkspace.id)

    // Check if there are any windows on the current monitor and workspace
    readonly property bool hasWindows: toplevels.length > 0

    // Fullscreen detection
    readonly property bool activeWindowFullscreen: {
        if (!compositorMonitor || !toplevels) return false;

        // Check all toplevels on active workspace
        for (var i = 0; i < toplevels.length; i++) {
            if (toplevels[i].fullscreen == true) {
               return true;
            }
        }
        return false;
    }

    // Reveal logic
    property bool reveal: {
        // Priority: Fullscreen check
        if (activeWindowFullscreen) {
            return (Config.dock?.availableOnFullscreen ?? false) && (Config.dock?.hoverToReveal && dockMouseArea.containsMouse);
        }

        // If keepHidden is true, ONLY show on hover
        // IMPORTANT: keepHidden overrides pinned and desktop mode
        if (keepHidden) {
            return (Config.dock?.hoverToReveal && dockMouseArea.containsMouse);
        }

        return root.pinned || (Config.dock?.hoverToReveal && dockMouseArea.containsMouse) || !hasWindows
    }

    readonly property int totalMargin: root.windowSideMargin + root.edgeSideMargin
    readonly property int shadowSpace: 32
    readonly property real dockScale: Config.dock?.scale ?? 1.0
    readonly property int dockSize: Math.round((Config.dock?.height ?? 56) * dockScale)

    // Drag-and-drop state
    property string dragAppId: ""
    property int dragPinnedIndex: -1
    property bool appDragging: false
    property bool desktopDragging: false
    readonly property bool showInsertion: appDragging || desktopDragging
    property int insertionIndex: -1
    property point dragCursorPos: Qt.point(0, 0)

    readonly property real dragIconSize: Math.round((Config.dock?.iconSize ?? 40) * (Config.dock?.scale ?? 1.0))

    function iconForAppId(appId) {
        if (!appId) return "image-missing";
        const entry = DesktopEntries.heuristicLookup(appId);
        if (entry && entry.icon) return entry.icon;
        return AppSearch.guessIcon(appId);
    }

    function appIdFromPath(path) {
        if (!path) return "";
        const str = path.toString();
        if (!str.endsWith(".desktop")) return "";
        const base = str.substring(str.lastIndexOf("/") + 1);
        return base.slice(0, -8);
    }

    // Insertion index within the pinned region for a point in dockContainer coords
    function insertionIndexAt(pos) {
        var rep = root.isVertical ? appsRepeaterVertical : appsRepeaterHorizontal;
        var layout = root.isVertical ? dockLayoutVertical : dockLayoutHorizontal;
        var local = layout.mapFromItem(dockContainer, pos.x, pos.y);
        var cursor = root.isVertical ? local.y : local.x;
        var pinnedCount = (Config.pinnedApps?.apps || []).length;
        for (var i = 0; i < pinnedCount; i++) {
            var it = rep.itemAt(i);
            if (!it) return i;
            var origin = layout.mapFromItem(it, 0, 0);
            var center = root.isVertical ? origin.y + it.height / 2 : origin.x + it.width / 2;
            if (cursor < center) return i;
        }
        return pinnedCount;
    }

    // Position (along the dock axis, in dockContainer coords) of the insertion boundary
    function insertionBoundary(index) {
        var rep = root.isVertical ? appsRepeaterVertical : appsRepeaterHorizontal;
        var layout = root.isVertical ? dockLayoutVertical : dockLayoutHorizontal;
        var pinnedCount = (Config.pinnedApps?.apps || []).length;
        var clamped = Math.max(0, Math.min(index, pinnedCount));
        var p;
        if (pinnedCount === 0) {
            p = layout.mapToItem(dockContainer, 0, 0);
        } else if (clamped >= pinnedCount) {
            var last = rep.itemAt(pinnedCount - 1);
            if (!last) return root.isVertical ? layout.height : layout.width;
            p = last.mapToItem(dockContainer, root.isVertical ? last.width / 2 : last.width, root.isVertical ? last.height : last.height / 2);
        } else {
            var item = rep.itemAt(clamped);
            if (!item) return 0;
            p = item.mapToItem(dockContainer, 0, root.isVertical ? 0 : item.height / 2);
        }
        return root.isVertical ? p.y : p.x;
    }

    // Drops are only valid along the dock's own line
    function dragWithinBounds(pos) {
        if (root.isVertical) return pos.y >= -8 && pos.y <= dockContainer.height + 8;
        return pos.x >= -8 && pos.x <= dockContainer.width + 8;
    }

    function updateInsertion(pos) {
        root.dragCursorPos = Qt.point(pos.x, pos.y);
        root.insertionIndex = root.dragWithinBounds(pos) ? root.insertionIndexAt(pos) : -1;
    }

    function beginAppDrag(button) {
        root.dragAppId = button.dragAppId;
        root.dragPinnedIndex = button.dragPinnedIndex;
        root.appDragging = true;
        var c = button.appDragHandler.centroid.position;
        root.updateInsertion(dockContainer.mapFromItem(button, c.x, c.y));
    }

    function updateAppDrag(button) {
        if (!root.appDragging) return;
        var c = button.appDragHandler.centroid.position;
        root.updateInsertion(dockContainer.mapFromItem(button, c.x, c.y));
    }

    function endAppDrag(button) {
        if (!root.appDragging) return;
        var c = button.appDragHandler.centroid.position;
        var pos = dockContainer.mapFromItem(button, c.x, c.y);
        if (root.dragWithinBounds(pos)) {
            var computed = root.insertionIndexAt(pos);
            var target = computed;
            if (root.dragPinnedIndex >= 0 && root.dragPinnedIndex < computed) target = computed - 1;
            if (root.dragPinnedIndex >= 0) {
                TaskbarApps.reorderPinned(root.dragAppId, target);
            } else {
                TaskbarApps.pinApp(root.dragAppId, target);
            }
        }
        root.dragAppId = "";
        root.dragPinnedIndex = -1;
        root.appDragging = false;
        root.insertionIndex = -1;
    }

    function pinDroppedApp(appId, dropX, dropY) {
        var pos = Qt.point(dropX, dropY);
        if (!root.dragWithinBounds(pos)) return;
        TaskbarApps.pinApp(appId, root.insertionIndexAt(pos));
    }

    implicitWidth: root.isVertical ? dockSize + totalMargin + shadowSpace * 2 : dockContent.implicitWidth + shadowSpace * 2
    implicitHeight: root.isVertical ? dockContent.implicitHeight + shadowSpace * 2 : dockSize + totalMargin + shadowSpace * 2

    readonly property int frameOffset: Config.bar?.frameEnabled ? (Config.bar?.frameThickness ?? 6) : 0

    // The hitbox for the mask
    readonly property Item dockHitbox: dockMouseArea

    // Content sizing helper
    Item {
        id: dockContent
        implicitWidth: root.isVertical ? root.dockSize : dockLayoutHorizontal.implicitWidth + 16
        implicitHeight: root.isVertical ? dockLayoutVertical.implicitHeight + 16 : root.dockSize
    }

    MouseArea {
        id: dockMouseArea
        hoverEnabled: true

        // Size
        width: root.isVertical ? (root.reveal ? root.dockSize + root.totalMargin + root.shadowSpace : (Config.dock?.hoverRegionHeight ?? 4) + root.frameOffset) : dockContent.implicitWidth + 20
        height: root.isVertical ? dockContent.implicitHeight + 20 : (root.reveal ? root.dockSize + root.totalMargin + root.shadowSpace : (Config.dock?.hoverRegionHeight ?? 4) + root.frameOffset)

        // Position using x/y
        x: {
            const base = root.isBottom ? (parent.width - width) / 2 : (root.isLeft ? 0 : parent.width - width);
            // If left, keep at 0 to cover the frame area. If right, keep at right edge.
            if (root.isLeft) return 0;
            if (root.isRight) return parent.width - width;
            return base;
        }
        y: {
            const base = root.isVertical ? (parent.height - height) / 2 : parent.height - height;
            // If bottom, keep at bottom edge to cover the frame area.
            if (root.isBottom) return parent.height - height;
            return base;
        }

        Behavior on x {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration / 4
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration / 4
                easing.type: Easing.OutCubic
            }
        }

        Behavior on width {
            enabled: Config.animDuration > 0 && root.isVertical
            NumberAnimation {
                duration: Config.animDuration / 4
                easing.type: Easing.OutCubic
            }
        }

        Behavior on height {
            enabled: Config.animDuration > 0 && !root.isVertical
            NumberAnimation {
                duration: Config.animDuration / 4
                easing.type: Easing.OutCubic
            }
        }

        // Dock container
        Item {
            id: dockContainer

            // Corner size for default theme
            readonly property int cornerSize: root.isDefault && Config.roundness > 0 ? Config.roundness + 4 : 0

            // Size
            width: {
                if (root.isDefault && cornerSize > 0) {
                    if (root.isBottom)
                        return dockContent.implicitWidth + cornerSize * 2;
                }
                return dockContent.implicitWidth;
            }
            height: {
                if (root.isDefault && cornerSize > 0) {
                    if (root.isVertical)
                        return dockContent.implicitHeight + cornerSize * 2;
                }
                return dockContent.implicitHeight;
            }

            // Position using x/y
            x: {
                const base = root.isBottom ? (parent.width - width) / 2 : (root.isLeft ? root.edgeSideMargin : parent.width - width - root.edgeSideMargin);
                if (root.isLeft) return base + root.frameOffset;
                if (root.isRight) return base - root.frameOffset;
                return base;
            }
            y: {
                const base = root.isVertical ? (parent.height - height) / 2 : parent.height - height - root.edgeSideMargin;
                if (root.isBottom) return base - root.frameOffset;
                return base;
            }

            Behavior on x {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 4
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on y {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 4
                    easing.type: Easing.OutCubic
                }
            }

            // Animation for dock reveal
            opacity: root.reveal ? 1 : 0
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                    easing.type: Easing.OutCubic
                }
            }

            // Slide animation
            transform: Translate {
                x: root.isVertical ? (root.reveal ? 0 : (root.isLeft ? -(dockContainer.width + root.edgeSideMargin) : (dockContainer.width + root.edgeSideMargin))) : 0
                y: root.isBottom ? (root.reveal ? 0 : (dockContainer.height + root.edgeSideMargin)) : 0
                Behavior on x {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Full background container with masking (default theme)
            Item {
                id: dockFullBgContainer
                visible: root.isDefault
                anchors.fill: parent

                // Background rect
                StyledRect {
                    id: dockBackground
                    anchors.fill: parent

                    variant: "bg"
                    // enableShadow: true
                    enableBorder: false

                    readonly property int fullRadius: Styling.radius(4)

                    topLeftRadius: {
                        if (root.isBottom) return fullRadius;
                        if (root.isLeft) return 0;
                        if (root.isRight) return fullRadius;
                        return fullRadius;
                    }
                    topRightRadius: {
                        if (root.isBottom) return fullRadius;
                        if (root.isLeft) return fullRadius;
                        if (root.isRight) return 0;
                        return fullRadius;
                    }
                    bottomLeftRadius: {
                        if (root.isBottom) return 0;
                        if (root.isLeft) return 0;
                        if (root.isRight) return fullRadius;
                        return fullRadius;
                    }
                    bottomRightRadius: {
                        if (root.isBottom) return 0;
                        if (root.isLeft) return fullRadius;
                        if (root.isRight) return 0;
                        return fullRadius;
                    }
                }

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: dockMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
            }

            // Mask for the full background
            Item {
                id: dockMask
                visible: false
                anchors.fill: parent

                layer.enabled: true
                layer.smooth: true

                RoundCorner {
                    id: corner1
                    x: {
                        if (root.isBottom) return 0;
                        if (root.isLeft) return 0;
                        if (root.isRight) return parent.width - dockContainer.cornerSize;
                        return 0;
                    }
                    y: {
                        if (root.isBottom) return parent.height - dockContainer.cornerSize;
                        return 0;
                    }
                    size: Math.max(dockContainer.cornerSize, 1)
                    corner: {
                        if (root.isBottom) return RoundCorner.CornerEnum.BottomRight;
                        if (root.isLeft) return RoundCorner.CornerEnum.BottomLeft;
                        if (root.isRight) return RoundCorner.CornerEnum.BottomRight;
                        return RoundCorner.CornerEnum.BottomRight;
                    }
                    color: "white"
                }

                RoundCorner {
                    id: corner2
                    x: {
                        if (root.isBottom) return parent.width - dockContainer.cornerSize;
                        if (root.isLeft) return 0;
                        if (root.isRight) return parent.width - dockContainer.cornerSize;
                        return 0;
                    }
                    y: parent.height - dockContainer.cornerSize
                    size: Math.max(dockContainer.cornerSize, 1)
                    corner: {
                        if (root.isBottom) return RoundCorner.CornerEnum.BottomLeft;
                        if (root.isLeft) return RoundCorner.CornerEnum.TopLeft;
                        if (root.isRight) return RoundCorner.CornerEnum.TopRight;
                        return RoundCorner.CornerEnum.BottomLeft;
                    }
                    color: "white"
                }

                Rectangle {
                    id: centerMask
                    width: dockContent.implicitWidth
                    height: dockContent.implicitHeight
                    color: "white"

                    x: root.isBottom ? dockContainer.cornerSize : 0
                    y: root.isBottom ? 0 : dockContainer.cornerSize

                    topLeftRadius: dockBackground.topLeftRadius
                    topRightRadius: dockBackground.topRightRadius
                    bottomLeftRadius: dockBackground.bottomLeftRadius
                    bottomRightRadius: dockBackground.bottomRightRadius
                }
            }

            // Background for floating theme
            StyledRect {
                id: dockBackgroundFloating
                visible: root.isFloating
                anchors.fill: parent
                variant: "bg"
                // enableShadow: true
                radius: Styling.radius(4)
                enableBorder: !root.unifiedEffectActive
            }

            // Horizontal layout
            RowLayout {
                id: dockLayoutHorizontal
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: (dockContent.implicitHeight - implicitHeight) / 2
                spacing: Math.round((Config.dock?.spacing ?? 4) * root.dockScale)
                visible: !root.isVertical

                Loader {
                    active: Config.dock?.showPinButton ?? true
                    visible: active
                    Layout.alignment: Qt.AlignVCenter

                    sourceComponent: Button {
                        id: pinButton
                        implicitWidth: Math.round(32 * root.dockScale)
                        implicitHeight: Math.round(32 * root.dockScale)

                        background: StyledRect {
                            visible: root.pinned || pinButton.hovered
                            variant: root.pinned ? "primary" : "focus"
                            radius: Styling.radius(-2)
                            enableShadow: false
                            enableBorder: false
                        }

                        contentItem: Text {
                            text: Icons.pin
                            font.family: Icons.font
                            font.pixelSize: Math.round(16 * root.dockScale)
                            color: root.pinned ? Styling.srItem("primary") : Colors.overBackground
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter

                            rotation: root.pinned ? 0 : 45
                            Behavior on rotation {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: Config.animDuration / 2
                                }
                            }

                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation {
                                    duration: Config.animDuration / 2
                                }
                            }
                        }

                        onClicked: root.pinned = !root.pinned

                        StyledToolTip {
                            show: pinButton.hovered
                            tooltipText: root.pinned ? "Unpin dock" : "Pin dock"
                        }
                    }
                }

                Loader {
                    active: Config.dock?.showPinButton ?? true
                    visible: active
                    Layout.alignment: Qt.AlignVCenter

                    sourceComponent: Separator {
                        vert: true
                        implicitHeight: (Config.dock?.iconSize ?? 40) * 0.6 * root.dockScale
                    }
                }

                Repeater {
                    id: appsRepeaterHorizontal
                    model: TaskbarApps.apps

                    DockAppButton {
                        id: appBtnH
                        required property var modelData
                        appToplevel: modelData
                        Layout.alignment: Qt.AlignVCenter
                        dockPosition: "bottom"
                        appDragHandler.onActiveChanged: {
                            if (appBtnH.appDragHandler.active) root.beginAppDrag(appBtnH);
                            else root.endAppDrag(appBtnH);
                        }
                        appDragHandler.onCentroidChanged: {
                            if (appBtnH.appDragHandler.active) root.updateAppDrag(appBtnH);
                        }
                        opacity: (root.appDragging && root.dragAppId === appBtnH.dragAppId) ? 0.35 : 1.0
                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration / 2
                            }
                        }
                    }
                }

                Loader {
                    active: Config.dock?.showOverviewButton ?? true
                    visible: active
                    Layout.alignment: Qt.AlignVCenter

                    sourceComponent: Separator {
                        vert: true
                        implicitHeight: (Config.dock?.iconSize ?? 40) * 0.6 * root.dockScale
                    }
                }

                Loader {
                    active: Config.dock?.showOverviewButton ?? true
                    visible: active
                    Layout.alignment: Qt.AlignVCenter

                    sourceComponent: Button {
                        id: overviewButton
                        implicitWidth: Math.round(32 * root.dockScale)
                        implicitHeight: Math.round(32 * root.dockScale)

                        background: StyledRect {
                            visible: overviewButton.hovered
                            variant: "focus"
                            radius: Styling.radius(-2)
                            enableShadow: false
                            enableBorder: false
                        }

                        contentItem: Text {
                            text: Icons.overview
                            font.family: Icons.font
                            font.pixelSize: Math.round(18 * root.dockScale)
                            color: Colors.overBackground
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            let visibilities = Visibilities.getForScreen(root.screen.name);
                            if (visibilities) {
                                visibilities.overview = !visibilities.overview;
                            }
                        }

                        StyledToolTip {
                            show: overviewButton.hovered
                            tooltipText: "Overview"
                        }
                    }
                }
            }

            // Vertical layout
            ColumnLayout {
                id: dockLayoutVertical
                anchors.horizontalCenter: parent.horizontalCenter
                y: dockContainer.cornerSize + (dockContent.implicitHeight - implicitHeight) / 2
                spacing: Math.round((Config.dock?.spacing ?? 4) * root.dockScale)
                visible: root.isVertical

                Loader {
                    active: Config.dock?.showPinButton ?? true
                    visible: active
                    Layout.alignment: Qt.AlignHCenter

                    sourceComponent: Button {
                        id: pinButtonV
                        implicitWidth: Math.round(32 * root.dockScale)
                        implicitHeight: Math.round(32 * root.dockScale)

                        background: StyledRect {
                            visible: root.pinned || pinButtonV.hovered
                            variant: root.pinned ? "primary" : "focus"
                            radius: Styling.radius(-2)
                            enableShadow: false
                            enableBorder: false
                        }

                        contentItem: Text {
                            text: Icons.pin
                            font.family: Icons.font
                            font.pixelSize: Math.round(16 * root.dockScale)
                            color: root.pinned ? Styling.srItem("primary") : Colors.overBackground
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter

                            rotation: root.pinned ? 0 : 45
                            Behavior on rotation {
                                enabled: Config.animDuration > 0
                                NumberAnimation {
                                    duration: Config.animDuration / 2
                                }
                            }

                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation {
                                    duration: Config.animDuration / 2
                                }
                            }
                        }

                        onClicked: root.pinned = !root.pinned

                        StyledToolTip {
                            show: pinButtonV.hovered
                            tooltipText: root.pinned ? "Unpin dock" : "Pin dock"
                        }
                    }
                }

                Loader {
                    active: Config.dock?.showPinButton ?? true
                    visible: active
                    Layout.alignment: Qt.AlignHCenter

                    sourceComponent: Separator {
                        vert: false
                        implicitWidth: (Config.dock?.iconSize ?? 40) * 0.6 * root.dockScale
                    }
                }

                Repeater {
                    id: appsRepeaterVertical
                    model: TaskbarApps.apps

                    DockAppButton {
                        id: appBtnV
                        required property var modelData
                        appToplevel: modelData
                        Layout.alignment: Qt.AlignHCenter
                        dockPosition: root.position
                        appDragHandler.onActiveChanged: {
                            if (appBtnV.appDragHandler.active) root.beginAppDrag(appBtnV);
                            else root.endAppDrag(appBtnV);
                        }
                        appDragHandler.onCentroidChanged: {
                            if (appBtnV.appDragHandler.active) root.updateAppDrag(appBtnV);
                        }
                        opacity: (root.appDragging && root.dragAppId === appBtnV.dragAppId) ? 0.35 : 1.0
                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration / 2
                            }
                        }
                    }
                }

                Loader {
                    active: Config.dock?.showOverviewButton ?? true
                    visible: active
                    Layout.alignment: Qt.AlignHCenter

                    sourceComponent: Separator {
                        vert: false
                        implicitWidth: (Config.dock?.iconSize ?? 40) * 0.6 * root.dockScale
                    }
                }

                Loader {
                    active: Config.dock?.showOverviewButton ?? true
                    visible: active
                    Layout.alignment: Qt.AlignHCenter

                    sourceComponent: Button {
                        id: overviewButtonV
                        implicitWidth: Math.round(32 * root.dockScale)
                        implicitHeight: Math.round(32 * root.dockScale)

                        background: StyledRect {
                            visible: overviewButtonV.hovered
                            variant: "focus"
                            radius: Styling.radius(-2)
                            enableShadow: false
                            enableBorder: false
                        }

                        contentItem: Text {
                            text: Icons.overview
                            font.family: Icons.font
                            font.pixelSize: Math.round(18 * root.dockScale)
                            color: Colors.overBackground
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            let visibilities = Visibilities.getForScreen(root.screen.name);
                            if (visibilities) {
                                visibilities.overview = !visibilities.overview;
                            }
                        }

                        StyledToolTip {
                            show: overviewButtonV.hovered
                            tooltipText: "Overview"
                        }
                    }
                }
            }

            // Drop target for desktop icons (pin into dock)
            DropArea {
                id: dockDropArea
                anchors.fill: parent
                z: 4000
                keys: ["desktopIcon"]
                enabled: root.reveal

                onEntered: {
                    root.desktopDragging = true;
                    root.updateInsertion(Qt.point(drag.x, drag.y));
                }
                onPositionChanged: drag => {
                    root.updateInsertion(Qt.point(drag.x, drag.y));
                }
                onExited: {
                    root.desktopDragging = false;
                    root.insertionIndex = -1;
                }
                onDropped: drop => {
                    root.desktopDragging = false;
                    root.insertionIndex = -1;
                    var src = drop.source;
                    if (src && src.isDesktopFile) {
                        var appId = root.appIdFromPath(src.path);
                        if (appId) {
                            root.pinDroppedApp(appId, drop.x, drop.y);
                            drop.acceptProposedAction();
                        }
                    }
                }
            }

            // Drag ghost, clamped to the dock's own line
            Item {
                id: dragGhost
                visible: root.appDragging
                z: 5001
                width: root.dragIconSize + 8
                height: root.dragIconSize + 8
                x: root.isVertical ? (dockContainer.width - width) / 2 : root.dragCursorPos.x - width / 2
                y: root.isVertical ? root.dragCursorPos.y - height / 2 : (dockContainer.height - height) / 2
                scale: 1.1
                transformOrigin: Item.Center
                opacity: 0.85

                Behavior on x {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutCubic
                    }
                }

                StyledRect {
                    anchors.fill: parent
                    radius: Styling.radius(-2)
                    variant: "focus"
                }

                Image {
                    anchors.centerIn: parent
                    width: root.dragIconSize
                    height: root.dragIconSize
                    source: "image://icon/" + root.iconForAppId(root.dragAppId)
                    sourceSize.width: root.dragIconSize * 2
                    sourceSize.height: root.dragIconSize * 2
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                }
            }

            // Insertion indicator along the dock's line
            Rectangle {
                id: insertionLine
                visible: root.insertionIndex >= 0 && root.showInsertion
                z: 5000
                width: root.isVertical ? Math.round(dockLayoutVertical.width) : 3
                height: root.isVertical ? 3 : Math.round(dockLayoutHorizontal.height)
                x: root.isVertical ? (dockContainer.width - width) / 2 : root.insertionBoundary(root.insertionIndex) - width / 2
                y: root.isVertical ? root.insertionBoundary(root.insertionIndex) - height / 2 : (dockContainer.height - height) / 2
                radius: 2
                color: Styling.srItem("overprimary")

                Behavior on x {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // Unified outline canvas
            Canvas {
                id: outlineCanvas
                anchors.fill: parent
                z: 5000
                antialiasing: true

                readonly property var borderData: Config.theme.srBg.border
                readonly property int borderWidth: borderData[1]
                readonly property color borderColor: Config.resolveColor(borderData[0])

                visible: root.isDefault && borderWidth > 0 && !root.unifiedEffectActive

                onPaint: {
                    if (!root.isDefault) return;
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    if (borderWidth <= 0) return;

                    ctx.strokeStyle = borderColor;
                    ctx.lineWidth = borderWidth;
                    ctx.lineJoin = "round";
                    ctx.lineCap = "butt";

                    var offset = borderWidth / 2;
                    var cs = dockContainer.cornerSize;
                    var hasFillets = cs > offset;
                    var filletRadius = hasFillets ? cs - offset : 0;

                    var tl = centerMask.topLeftRadius;
                    var tr = centerMask.topRightRadius;
                    var bl = centerMask.bottomLeftRadius;
                    var br = centerMask.bottomRightRadius;

                    ctx.beginPath();

                    if (root.isBottom) {
                        if (hasFillets) {
                            ctx.moveTo(offset, height - offset);
                            ctx.arc(offset, height - cs, filletRadius, Math.PI / 2, 0, true);
                            ctx.lineTo(cs, tl > 0 ? tl + offset : offset);
                            if (tl > 0) ctx.arcTo(cs, offset, cs + tl, offset, tl - offset);
                            else ctx.lineTo(cs, offset);
                            ctx.lineTo(width - cs - tr, offset);
                            if (tr > 0) ctx.arcTo(width - cs, offset, width - cs, offset + tr, tr - offset);
                            else ctx.lineTo(width - cs, offset);
                            ctx.lineTo(width - cs, height - cs);
                            ctx.arc(width - offset, height - cs, filletRadius, Math.PI, Math.PI / 2, true);
                        } else {
                            ctx.moveTo(offset, height - offset);
                            ctx.lineTo(offset, tl > 0 ? tl + offset : offset);
                            if (tl > 0) ctx.arcTo(offset, offset, offset + tl, offset, tl - offset);
                            else ctx.lineTo(offset, offset);
                            ctx.lineTo(width - tr - offset, offset);
                            if (tr > 0) ctx.arcTo(width - offset, offset, width - offset, offset + tr, tr - offset);
                            else ctx.lineTo(width - offset, offset);
                            ctx.lineTo(width - offset, height - offset);
                        }
                    } else if (root.isLeft) {
                        if (hasFillets) {
                            ctx.moveTo(offset, offset);
                            ctx.arc(cs, offset, filletRadius, Math.PI, Math.PI / 2, true);
                            ctx.lineTo(width - tr - offset, cs);
                            if (tr > 0) ctx.arcTo(width - offset, cs, width - offset, cs + tr, tr - offset);
                            else ctx.lineTo(width - offset, cs);
                            ctx.lineTo(width - offset, height - cs - br);
                            if (br > 0) ctx.arcTo(width - offset, height - cs, width - offset - br, height - cs, br - offset);
                            else ctx.lineTo(width - offset, height - cs);
                            ctx.lineTo(cs, height - cs);
                            ctx.arc(cs, height - offset, filletRadius, 3 * Math.PI / 2, Math.PI, true);
                        } else {
                            ctx.moveTo(offset, offset);
                            ctx.lineTo(width - tr - offset, offset);
                            if (tr > 0) ctx.arcTo(width - offset, offset, width - offset, offset + tr, tr - offset);
                            else ctx.lineTo(width - offset, offset);
                            ctx.lineTo(width - offset, height - br - offset);
                            if (br > 0) ctx.arcTo(width - offset, height - offset, width - offset - br, height - offset, br - offset);
                            else ctx.lineTo(width - offset, height - offset);
                            ctx.lineTo(offset, height - offset);
                        }
                    } else if (root.isRight) {
                        if (hasFillets) {
                            ctx.moveTo(width - offset, offset);
                            ctx.arc(width - cs, offset, filletRadius, 0, Math.PI / 2, false);
                            ctx.lineTo(tl + offset, cs);
                            if (tl > 0) ctx.arcTo(offset, cs, offset, cs + tl, tl - offset);
                            else ctx.lineTo(offset, cs);
                            ctx.lineTo(offset, height - cs - bl);
                            if (bl > 0) ctx.arcTo(offset, height - cs, offset + bl, height - cs, bl - offset);
                            else ctx.lineTo(offset, height - cs);
                            ctx.lineTo(width - cs, height - cs);
                            ctx.arc(width - cs, height - offset, filletRadius, 3 * Math.PI / 2, 2 * Math.PI, false);
                        } else {
                            ctx.moveTo(width - offset, offset);
                            ctx.lineTo(tl + offset, offset);
                            if (tl > 0) ctx.arcTo(offset, offset, offset, offset + tl, tl - offset);
                            else ctx.lineTo(offset, offset);
                            ctx.lineTo(offset, height - bl - offset);
                            if (bl > 0) ctx.arcTo(offset, height - offset, offset + bl, height - offset, bl - offset);
                            else ctx.lineTo(offset, height - offset);
                            ctx.lineTo(width - offset, height - offset);
                        }
                    }

                    ctx.stroke();
                }

                Connections {
                    target: Colors
                    function onPrimaryChanged() { outlineCanvas.requestPaint(); }
                }
                Connections {
                    target: Config.theme.srBg
                    function onBorderChanged() { outlineCanvas.requestPaint(); }
                }
                Connections {
                    target: root
                    function onPositionChanged() { outlineCanvas.requestPaint(); }
                }
                Connections {
                    target: dockContainer
                    function onWidthChanged() { outlineCanvas.requestPaint(); }
                    function onHeightChanged() { outlineCanvas.requestPaint(); }
                }
            }
        }
    }
}
