import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.modules.bar.workspaces
import qs.modules.theme
import qs.modules.bar.clock
import qs.modules.bar.systray
import qs.modules.widgets.overview
import qs.modules.widgets.dashboard
import qs.modules.widgets.powermenu
import qs.modules.widgets.presets
import qs.modules.corners
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.modules.bar
import qs.config
import "." as Bar

Item {
    id: root

    required property ShellScreen screen

    property string barPosition: (Config.bar && Config.bar.position !== undefined && ["top", "bottom", "left", "right"].includes(Config.bar.position) ? Config.bar.position : "top")
    property string orientation: barPosition === "left" || barPosition === "right" ? "vertical" : "horizontal"

    // Auto-hide properties
    onPinnedChanged: {
        if (Config.bar && Config.bar.pinnedOnStartup !== pinned) {
            Config.bar.pinnedOnStartup = pinned;
        }
    }

    property bool pinned: (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true)

    // Monitor reference and reference to toplevels on monitor
    readonly property var compositorMonitor: AxctlService.monitorFor(screen)
    readonly property var toplevels: (!compositorMonitor || !compositorMonitor.activeWorkspace || !AxctlService.clients.values) ? [] : AxctlService.clients.values.filter(c => c.workspace.id === compositorMonitor.activeWorkspace.id)

    // Fullscreen detection - use ToplevelManager (native Wayland) for reliable detection
    readonly property bool activeWindowFullscreen: {
        const toplevel = ToplevelManager.activeToplevel;
        if (!toplevel || !toplevel.activated)
            return false;
        return toplevel.fullscreen === true;
    }


    // Whether auto-hide should be active (not pinned, or fullscreen forces it)
    readonly property bool shouldAutoHide: !pinned || activeWindowFullscreen

    onShouldAutoHideChanged: {
        if (!shouldAutoHide) {
            hoverActive = false;
            hideDelayTimer.stop();
        }
    }

    // Hover state with delay to prevent flickering
    property bool hoverActive: false

    // Track if mouse is over bar area
    readonly property bool isMouseOverBar: barMouseArea.containsMouse

    // Check if notch hover is active (for synchronized reveal when bar is at same side)
    // NOTE: We access Visibilities.notchPanels directly because UnifiedShellPanel registers itself as the panel ref
    readonly property var notchPanelRef: Visibilities.notchPanels[screen.name]
    readonly property string notchPosition: (Config.notchPosition !== undefined ? Config.notchPosition : "top")
    readonly property bool notchHoverActive: {
        if (barPosition !== notchPosition)
            return false;
        
        if (notchPanelRef) {
            // UnifiedShellPanel exposes 'notchHoverActive' property alias pointing to notchContent.hoverActive
            // We need to check if that property exists on the panel object
            if (typeof notchPanelRef.notchHoverActive !== 'undefined') {
                return notchPanelRef.notchHoverActive;
            }
            // Fallback for compatibility
            if (typeof notchPanelRef.hoverActive !== 'undefined') {
                return notchPanelRef.hoverActive;
            }
        }
        return false;
    }

    // Check if notch is open (dashboard, powermenu, etc.)
    readonly property var screenVisibilities: Visibilities.getForScreen(screen.name)
    readonly property bool notchOpen: screenVisibilities ? (screenVisibilities.launcher || screenVisibilities.dashboard || screenVisibilities.powermenu || screenVisibilities.tools) : false

    // Radius logic for "Squished" style
    readonly property real outerRadius: Styling.radius(0)
    readonly property real innerRadius: (Config.bar && Config.bar.pillStyle === "squished") ? Styling.radius(0) / 2 : Styling.radius(0)
    readonly property bool pinButtonVisible: (Config.bar && Config.bar.showPinButton !== undefined ? Config.bar.showPinButton : true)

    // Reveal logic
    readonly property bool reveal: {
        // If not auto-hiding, always reveal
        if (!shouldAutoHide)
            return true;

        // If fullscreen and not available on fullscreen, hide
        if (activeWindowFullscreen && !(Config.bar && Config.bar.availableOnFullscreen !== undefined ? Config.bar.availableOnFullscreen : false)) {
            return false;
        }

        // Show if: hovering, notch hovering (when at top), notch open
        // IMPORTANT: notchHoverActive must be checked to synchronize with notch
        return isMouseOverBar || hoverActive || notchHoverActive || notchOpen;
    }

    // Timer to delay hiding the bar after mouse leaves
    Timer {
        id: hideDelayTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (!root.isMouseOverBar) {
                root.hoverActive = false;
            }
        }
    }

    // Watch for mouse state changes
    onIsMouseOverBarChanged: {
        if (isMouseOverBar) {
            hideDelayTimer.stop();
            hoverActive = true;
        } else {
            // Si está fijada, podemos resetear el hoverActive inmediatamente
            // Si está en auto-hide, usamos el timer para dar margen
            if (shouldAutoHide) {
                hideDelayTimer.restart();
            } else {
                hoverActive = false;
            }
        }
    }

    // Integrated dock configuration
    readonly property bool integratedDockEnabled: (Config.dock && Config.dock.enabled !== undefined ? Config.dock.enabled : false) && (Config.dock && Config.dock.theme !== undefined ? Config.dock.theme : "default") === "integrated"
    // Map dock position for integrated based on orientation
    readonly property string integratedDockPosition: {
        const pos = (Config.dock && Config.dock.position !== undefined ? Config.dock.position : "center");

        if (root.orientation === "horizontal") {
            if (pos === "left" || pos === "start")
                return "start";
            if (pos === "right" || pos === "end")
                return "end";
            return "center";
        }
        
        // Vertical always falls back to center logic inside the column but we treat it as appended to group
        return "center";
    }

    // Radius helpers for dock connections
    readonly property bool dockAtStart: integratedDockEnabled && integratedDockPosition === "start"
    readonly property bool dockAtEnd: integratedDockEnabled && integratedDockPosition === "end"

    readonly property int frameOffset: (Config.bar && Config.bar.frameEnabled !== undefined ? Config.bar.frameEnabled : false) ? (Config.bar && Config.bar.frameThickness !== undefined ? Config.bar.frameThickness : 6) : 0

    // Size derived from barBg properties
    readonly property real barScale: (Config.bar && Config.bar.scale !== undefined ? Config.bar.scale : 1.0)
    readonly property int barPaddingTop: barBg.paddingTop
    readonly property int barPaddingRight: barBg.paddingRight
    readonly property int barPaddingBottom: barBg.paddingBottom
    readonly property int barPaddingLeft: barBg.paddingLeft
    readonly property int topOuterMargin: (orientation === "vertical" || barPosition === "top") ? barBg.outerMargin : 0
    readonly property int bottomOuterMargin: (orientation === "vertical" || barPosition === "bottom") ? barBg.outerMargin : 0
    readonly property int leftOuterMargin: (orientation === "horizontal" || barPosition === "left") ? barBg.outerMargin : 0
    readonly property int rightOuterMargin: (orientation === "horizontal" || barPosition === "right") ? barBg.outerMargin : 0

    readonly property int contentImplicitWidth: orientation === "horizontal" ? (horizontalLoader.item && horizontalLoader.item.implicitWidth !== undefined ? horizontalLoader.item.implicitWidth : 0) : (verticalLoader.item && verticalLoader.item.implicitWidth !== undefined ? verticalLoader.item.implicitWidth : 0)
    readonly property int contentImplicitHeight: orientation === "horizontal" ? (horizontalLoader.item && horizontalLoader.item.implicitHeight !== undefined ? horizontalLoader.item.implicitHeight : 0) : (verticalLoader.item && verticalLoader.item.implicitHeight !== undefined ? verticalLoader.item.implicitHeight : 0)

    readonly property int barTargetWidth: orientation === "vertical" ? (Math.round(contentImplicitWidth) + barPaddingLeft + barPaddingRight) : 0
    readonly property int barTargetHeight: orientation === "horizontal" ? (Math.round(contentImplicitHeight) + barPaddingTop + barPaddingBottom) : 0

    readonly property bool actualContainBar: (Config.bar && Config.bar.containBar !== undefined ? Config.bar.containBar : false) && (Config.bar && Config.bar.frameEnabled !== undefined ? Config.bar.frameEnabled : false)
    readonly property int totalBarWidth: barTargetWidth + 
        ((root.barPosition === "left" || root.orientation === "horizontal") ? (root.frameOffset + root.leftOuterMargin) : 0) +
        ((root.barPosition === "right" || root.orientation === "horizontal") ? (root.frameOffset + root.rightOuterMargin) : 0)

    readonly property int totalBarHeight: barTargetHeight + 
        ((root.barPosition === "top" || root.orientation === "vertical") ? (root.frameOffset + root.topOuterMargin) : 0) +
        ((root.barPosition === "bottom" || root.orientation === "vertical") ? (root.frameOffset + root.bottomOuterMargin) : 0)

    // Base outer margin for reservation logic (4px + border when !containBar)
    readonly property int baseOuterMargin: barBg.outerMargin

    // Shadow logic for bar components
    readonly property bool shadowsEnabled: Config.showBackground && (!actualContainBar || (Config.bar && Config.bar.keepBarShadow !== undefined ? Config.bar.keepBarShadow : false))

    // The hitbox for the mask
    property alias barHitbox: barMouseArea

    // MouseArea for hover detection - contains bar content (like Dock)
    MouseArea {
        id: barMouseArea
        hoverEnabled: true

        // Size includes margins
        width: root.orientation === "horizontal" ? root.width : (root.reveal ? root.totalBarWidth : Math.max((Config.bar && Config.bar.hoverRegionHeight !== undefined ? Config.bar.hoverRegionHeight : 8), 4) + root.frameOffset)
        height: root.orientation === "vertical" ? root.height : (root.reveal ? root.totalBarHeight : Math.max((Config.bar && Config.bar.hoverRegionHeight !== undefined ? Config.bar.hoverRegionHeight : 8), 4) + root.frameOffset)


        // Position using x/y
        x: {
            if (root.barPosition === "right") return parent.width - width;
            return 0;
        }
        y: {
            if (root.barPosition === "bottom") return parent.height - height;
            return 0;
        }

        Behavior on x {
            enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0 && root.orientation === "vertical"
            NumberAnimation {
                duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 4
                easing.type: Easing.OutCubic
            }
        }
        Behavior on y {
            enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0 && root.orientation === "horizontal"
            NumberAnimation {
                duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 4
                easing.type: Easing.OutCubic
            }
        }

        Behavior on width {
            enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0 && root.orientation === "vertical"
            NumberAnimation {
                duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 4
                easing.type: Easing.OutCubic
            }
        }
        Behavior on height {
            enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0 && root.orientation === "horizontal"
            NumberAnimation {
                duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 4
                easing.type: Easing.OutCubic
            }
        }

        // Bar content inside MouseArea (clicks pass through to children)
        Item {
            id: bar

            anchors {
                top: (root.barPosition === "top" || root.orientation === "vertical") ? parent.top : undefined
                bottom: (root.barPosition === "bottom" || root.orientation === "vertical") ? parent.bottom : undefined
                left: (root.barPosition === "left" || root.orientation === "horizontal") ? parent.left : undefined
                right: (root.barPosition === "right" || root.orientation === "horizontal") ? parent.right : undefined

                topMargin: (root.barPosition === "top" || root.orientation === "vertical") ? (root.frameOffset + root.topOuterMargin) : 0
                bottomMargin: (root.barPosition === "bottom" || root.orientation === "vertical") ? (root.frameOffset + root.bottomOuterMargin) : 0
                leftMargin: (root.barPosition === "left" || root.orientation === "horizontal") ? (root.frameOffset + root.leftOuterMargin) : 0
                rightMargin: (root.barPosition === "right" || root.orientation === "horizontal") ? (root.frameOffset + root.rightOuterMargin) : 0
            }


            // layer.enabled: true
            // layer.effect: Shadow {}

            // Opacity animation
            opacity: root.reveal ? 1 : 0
            Behavior on opacity {
                enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
                NumberAnimation {
                    duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 2
                    easing.type: Easing.OutCubic
                }
            }

            // Slide animation
            transform: Translate {
                x: {
                    if (!root.shouldAutoHide)
                        return 0;
                    if (root.barPosition === "left")
                        return root.reveal ? 0 : -bar.width - (root.frameOffset + root.leftOuterMargin);
                    if (root.barPosition === "right")
                        return root.reveal ? 0 : bar.width + (root.frameOffset + root.rightOuterMargin);
                    return 0;
                }
                y: {
                    if (!root.shouldAutoHide)
                        return 0;
                    if (root.barPosition === "top")
                        return root.reveal ? 0 : -bar.height - (root.frameOffset + root.topOuterMargin);
                    if (root.barPosition === "bottom")
                        return root.reveal ? 0 : bar.height + (root.frameOffset + root.bottomOuterMargin);
                    return 0;
                }
                Behavior on x {
                    enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
                    NumberAnimation {
                        duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 2
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
                    NumberAnimation {
                        duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 2
                        easing.type: Easing.OutCubic
                    }
                }
            }

            states: [
                State {
                    name: "top"
                    when: root.barPosition === "top"
                    PropertyChanges {
                        target: bar
                        height: root.barTargetHeight
                    }
                },
                State {
                    name: "bottom"
                    when: root.barPosition === "bottom"
                    PropertyChanges {
                        target: bar
                        height: root.barTargetHeight
                    }
                },
                State {
                    name: "left"
                    when: root.barPosition === "left"
                    PropertyChanges {
                        target: bar
                        width: root.barTargetWidth
                    }
                },
                State {
                    name: "right"
                    when: root.barPosition === "right"
                    PropertyChanges {
                        target: bar
                        width: root.barTargetWidth
                    }
                }
            ]

            BarBg {
                id: barBg
                anchors.fill: parent
                position: root.barPosition

                Loader {
                    id: horizontalLoader
                    active: root.orientation === "horizontal"
                    anchors.fill: parent
                    sourceComponent: RowLayout {
                        spacing: 4 * root.barScale

                        Repeater {
                            model: root.barLeftOrder
                            delegate: Item {
                                required property string modelData
                                required property int index
                                property string side: "left"
                                property int sideCount: root.barLeftOrder.length

                                visible: root.barItemVisible(modelData)
                                Layout.fillWidth: root.orientation === "vertical"
                                Layout.fillHeight: root.orientation === "horizontal"
                                Layout.alignment: root.barItemAlignment(modelData)
                                implicitWidth: itemLoader.implicitWidth * root.barScale
                                implicitHeight: itemLoader.implicitHeight * root.barScale

                                Loader {
                                    id: itemLoader
                                    anchors.centerIn: parent
                                    width: parent.width / root.barScale
                                    height: parent.height / root.barScale
                                    scale: root.barScale
                                    sourceComponent: root.barItemFor(modelData)
                                    onLoaded: {
                                        if (item) {
                                            item.startRadius = Qt.binding(function() { return root.barItemStartRadius(side, index); });
                                            item.endRadius = Qt.binding(function() { return root.barItemEndRadius(side, index, sideCount); });
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.orientation === "horizontal" && integratedDockEnabled

                            Bar.IntegratedDock {
                                bar: root
                                orientation: root.orientation
                                anchors.verticalCenter: parent.verticalCenter
                                enableShadow: root.shadowsEnabled

                                startRadius: root.dockAtStart ? root.innerRadius : root.outerRadius
                                endRadius: root.dockAtEnd ? root.innerRadius : root.outerRadius

                                property real targetX: {
                                    if (integratedDockPosition === "start")
                                        return 0;
                                    if (integratedDockPosition === "end")
                                        return parent.width - width;

                                    return (bar.width - width) / 2 - (parent.x + 4);
                                }

                                x: Math.max(0, Math.min(parent.width - width, targetX))

                                width: Math.min(implicitWidth, parent.width)
                                height: implicitHeight
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            visible: !(root.orientation === "horizontal" && integratedDockEnabled)
                        }

                        Repeater {
                            model: root.barRightOrder
                            delegate: Item {
                                required property string modelData
                                required property int index
                                property string side: "right"
                                property int sideCount: root.barRightOrder.length

                                visible: root.barItemVisible(modelData)
                                Layout.fillWidth: root.orientation === "vertical"
                                Layout.fillHeight: root.orientation === "horizontal"
                                Layout.alignment: root.barItemAlignment(modelData)
                                implicitWidth: itemLoader.implicitWidth * root.barScale
                                implicitHeight: itemLoader.implicitHeight * root.barScale

                                Loader {
                                    id: itemLoader
                                    anchors.centerIn: parent
                                    width: parent.width / root.barScale
                                    height: parent.height / root.barScale
                                    scale: root.barScale
                                    sourceComponent: root.barItemFor(modelData)
                                    onLoaded: {
                                        if (item) {
                                            item.startRadius = Qt.binding(function() { return root.barItemStartRadius(side, index); });
                                            item.endRadius = Qt.binding(function() { return root.barItemEndRadius(side, index, sideCount); });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Loader {
                    id: verticalLoader
                    active: root.orientation === "vertical"
                    anchors.fill: parent
                    sourceComponent: ColumnLayout {
                        spacing: 4 * root.barScale

                        Repeater {
                            model: root.barLeftOrder
                            delegate: Item {
                                required property string modelData
                                required property int index
                                property string side: "left"
                                property int sideCount: root.barLeftOrder.length

                                visible: root.barItemVisible(modelData)
                                Layout.fillWidth: root.orientation === "vertical"
                                Layout.fillHeight: root.orientation === "horizontal"
                                Layout.alignment: root.barItemAlignment(modelData)
                                implicitWidth: itemLoader.implicitWidth * root.barScale
                                implicitHeight: itemLoader.implicitHeight * root.barScale

                                Loader {
                                    id: itemLoader
                                    anchors.centerIn: parent
                                    width: parent.width / root.barScale
                                    height: parent.height / root.barScale
                                    scale: root.barScale
                                    sourceComponent: root.barItemFor(modelData)
                                    onLoaded: {
                                        if (item) {
                                            item.startRadius = Qt.binding(function() { return root.barItemStartRadius(side, index); });
                                            item.endRadius = Qt.binding(function() { return root.barItemEndRadius(side, index, sideCount); });
                                        }
                                    }
                                }
                            }
                        }

                        // Center Group Container (dock)
                        Item {
                            Layout.fillHeight: true
                            Layout.fillWidth: true

                            Bar.IntegratedDock {
                                bar: root
                                orientation: root.orientation
                                visible: integratedDockEnabled
                                anchors.fill: parent
                                enableShadow: root.shadowsEnabled

                                startRadius: root.innerRadius
                                endRadius: root.innerRadius
                            }
                        }

                        Repeater {
                            model: root.barRightOrder
                            delegate: Item {
                                required property string modelData
                                required property int index
                                property string side: "right"
                                property int sideCount: root.barRightOrder.length

                                visible: root.barItemVisible(modelData)
                                Layout.fillWidth: root.orientation === "vertical"
                                Layout.fillHeight: root.orientation === "horizontal"
                                Layout.alignment: root.barItemAlignment(modelData)
                                implicitWidth: itemLoader.implicitWidth * root.barScale
                                implicitHeight: itemLoader.implicitHeight * root.barScale

                                Loader {
                                    id: itemLoader
                                    anchors.centerIn: parent
                                    width: parent.width / root.barScale
                                    height: parent.height / root.barScale
                                    scale: root.barScale
                                    sourceComponent: root.barItemFor(modelData)
                                    onLoaded: {
                                        if (item) {
                                            item.startRadius = Qt.binding(function() { return root.barItemStartRadius(side, index); });
                                            item.endRadius = Qt.binding(function() { return root.barItemEndRadius(side, index, sideCount); });
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    property var barLeftOrder: (Config.bar && Config.bar.barLeftOrder) ? Config.bar.barLeftOrder : ["launcher", "workspaces", "pin"]
    property var barRightOrder: (Config.bar && Config.bar.barRightOrder) ? Config.bar.barRightOrder : ["tools", "tray", "wifi", "bluetooth", "controls", "battery", "clock", "power"]

    function barItemFor(id) {
        switch (id) {
        case "launcher": return launcherComponent;
        case "workspaces": return workspacesComponent;
        case "layout": return layoutComponent;
        case "pin": return pinComponent;
        case "presets": return presetsComponent;
        case "tools": return toolsComponent;
        case "tray": return trayComponent;
        case "wifi": return wifiComponent;
        case "bluetooth": return bluetoothComponent;
        case "quickshare": return quickshareComponent;
        case "controls": return controlsComponent;
        case "battery": return batteryComponent;
        case "clock": return clockComponent;
        case "power": return powerComponent;
        case "typingSounds": return typingSoundsComponent;
        case "docker": return dockerComponent;
        }
        return undefined;
    }

    function barItemStartRadius(side, index) {
        if (index !== 0)
            return root.innerRadius;
        if (side === "left")
            return root.outerRadius;
        if (root.orientation === "vertical")
            return root.integratedDockEnabled ? root.innerRadius : root.outerRadius;
        return root.dockAtEnd ? root.innerRadius : root.outerRadius;
    }

    function barItemEndRadius(side, index, count) {
        if (index !== count - 1)
            return root.innerRadius;
        if (side === "right")
            return root.outerRadius;
        if (root.orientation === "vertical")
            return root.integratedDockEnabled ? root.innerRadius : root.outerRadius;
        return root.dockAtStart ? root.innerRadius : root.outerRadius;
    }

    function barItemAlignment(id) {
        if (id === "pin")
            return root.orientation === "vertical" ? Qt.AlignHCenter : Qt.AlignVCenter;
        if (root.orientation === "vertical" && (id === "layout" || id === "workspaces"))
            return Qt.AlignHCenter;
        return 0;
    }

    function barItemVisible(id) {
        switch (id) {
        case "workspaces": return (Config.workspaces && Config.workspaces.enabled !== false);
        case "pin": return (Config.bar && Config.bar.showPinButton !== undefined ? Config.bar.showPinButton : true);
        default: return true;
        }
    }

    Component {
        id: launcherComponent
        LauncherButton {
            vertical: root.orientation === "vertical"
            enableShadow: root.shadowsEnabled
        }
    }

    Component {
        id: workspacesComponent
        Workspaces {
            orientation: root.orientation
            visible: (Config.workspaces && Config.workspaces.enabled !== false)
            bar: QtObject {
                property var screen: root.screen
            }
        }
    }

    Component {
        id: layoutComponent
        LayoutSelectorButton {
            bar: root
            layerEnabled: root.shadowsEnabled
        }
    }

    Component {
        id: pinComponent
        Button {
            id: pinButton
            implicitWidth: 36
            implicitHeight: 36
            visible: (Config.bar && Config.bar.showPinButton !== undefined ? Config.bar.showPinButton : true)

            property real startRadius: root.innerRadius
            property real endRadius: root.innerRadius

            background: StyledRect {
                id: pinButtonBg
                variant: root.pinned ? "primary" : "bg"
                enableShadow: root.shadowsEnabled

                topLeftRadius: root.orientation === "vertical" ? pinButton.startRadius : pinButton.startRadius
                topRightRadius: root.orientation === "vertical" ? pinButton.startRadius : pinButton.endRadius
                bottomLeftRadius: root.orientation === "vertical" ? pinButton.endRadius : pinButton.startRadius
                bottomRightRadius: root.orientation === "vertical" ? pinButton.endRadius : pinButton.endRadius

                Rectangle {
                    anchors.fill: parent
                    color: Styling.srItem("overprimary")
                    opacity: root.pinned ? 0 : (pinButton.pressed ? 0.5 : (pinButton.hovered ? 0.25 : 0))
                    radius: (parent.radius !== undefined ? parent.radius : 0)

                    Behavior on opacity {
                        enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
                        NumberAnimation {
                            duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 2
                        }
                    }
                }
            }

            contentItem: Text {
                text: Icons.pin
                font.family: Icons.font
                font.pixelSize: 18
                color: root.pinned ? pinButtonBg.item : (pinButton.pressed ? Colors.background : (Styling.srItem("overprimary") || Colors.foreground))
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                rotation: root.pinned ? 0 : 45
                Behavior on rotation {
                    enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
                    NumberAnimation {
                        duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 2
                    }
                }

                Behavior on color {
                    enabled: (Config.animDuration !== undefined ? Config.animDuration : 0) > 0
                    ColorAnimation {
                        duration: (Config.animDuration !== undefined ? Config.animDuration : 0) / 2
                    }
                }
            }

            onClicked: root.pinned = !root.pinned

            StyledToolTip {
                show: pinButton.hovered
                tooltipText: root.pinned ? "Unpin bar" : "Pin bar"
            }
        }
    }

    Component {
        id: presetsComponent
        PresetsButton {
            vertical: root.orientation === "vertical"
            enableShadow: root.shadowsEnabled
        }
    }

    Component {
        id: toolsComponent
        ToolsButton {
            vertical: root.orientation === "vertical"
            enableShadow: root.shadowsEnabled
        }
    }

    Component {
        id: trayComponent
        SysTray {
            bar: root
            enableShadow: root.shadowsEnabled
        }
    }

    Component {
        id: wifiComponent
        Bar.QuickPopupButton {
            iconName: NetworkService.wifiEnabled ? Icons.wifiHigh : Icons.wifiOff
            tooltipText: "Wi-Fi"
            panelSource: "../widgets/dashboard/controls/WifiPanel.qml"
            isActive: NetworkService.wifiEnabled
            bar: root
            vertical: root.orientation === "vertical"
            layerEnabled: root.shadowsEnabled
        }
    }

    Component {
        id: bluetoothComponent
        Bar.QuickPopupButton {
            iconName: BluetoothService.enabled ? Icons.bluetooth : Icons.bluetoothOff
            tooltipText: "Bluetooth"
            panelSource: "../widgets/dashboard/controls/BluetoothPanel.qml"
            isActive: BluetoothService.enabled
            bar: root
            vertical: root.orientation === "vertical"
            layerEnabled: root.shadowsEnabled
        }
    }

    Component {
        id: quickshareComponent
        Bar.QuickPopupButton {
            iconName: Icons.quickshare
            tooltipText: "QuickShare"
            panelSource: "../widgets/dashboard/controls/QuickSharePanel.qml"
            isActive: QuickShareService.running
            bar: root
            vertical: root.orientation === "vertical"
            layerEnabled: root.shadowsEnabled
        }
    }

    Component {
        id: controlsComponent
        ControlsButton {
            bar: root
            layerEnabled: root.shadowsEnabled
        }
    }

    Component {
        id: batteryComponent
        Bar.BatteryIndicator {
            bar: root
            layerEnabled: root.shadowsEnabled
        }
    }

    Component {
        id: clockComponent
        Clock {
            bar: root
            layerEnabled: root.shadowsEnabled
        }
    }

    Component {
        id: powerComponent
        PowerButton {
            vertical: root.orientation === "vertical"
            enableShadow: root.shadowsEnabled
        }
    }

    Component {
        id: typingSoundsComponent
        Bar.QuickPopupButton {
            iconName: TypingSoundsService.enabled ? Icons.keyboard : Icons.keyboard
            tooltipText: "Typing Sounds"
            panelSource: "../widgets/dashboard/controls/TypingSoundsPanel.qml"
            isActive: TypingSoundsService.enabled
            bar: root
            vertical: root.orientation === "vertical"
            layerEnabled: root.shadowsEnabled
        }
    }

    Component {
        id: dockerComponent
        Bar.QuickPopupButton {
            iconName: Icons.docker
            tooltipText: "Docker"
            panelSource: "../widgets/dashboard/controls/DockerPanel.qml"
            isActive: DockerService.runningCount > 0
            popupWidth: 350
            popupHeight: 450
            bar: root
            vertical: root.orientation === "vertical"
            layerEnabled: root.shadowsEnabled
        }
    }
}
