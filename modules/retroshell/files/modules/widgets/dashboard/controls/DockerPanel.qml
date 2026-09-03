import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property int selectedIndex: {
        var conts = DockerService.containers;
        for (var i = 0; i < conts.length; i++) {
            if (conts[i].id === selectedId) return i;
        }
        return 0;
    }
    property string selectedId: DockerService.containers.length > 0 ? DockerService.containers[0].id : ""
    property var selectedContainer: {
        var conts = DockerService.containers;
        for (var i = 0; i < conts.length; i++) {
            if (conts[i].id === selectedId) return conts[i];
        }
        return null;
    }

    property int selectedProjectIndex: 0
    property var selectedProject: {
        var projs = DockerService.composeProjects;
        if (selectedProjectIndex >= 0 && selectedProjectIndex < projs.length)
            return projs[selectedProjectIndex];
        return null;
    }

    implicitWidth: Math.min(parent ? parent.width : 0, maxContentWidth)

    Component.onCompleted: DockerService.refresh()

    ListView {
        id: listView
        anchors.fill: parent
        clip: true
        spacing: 6
        model: 1

        header: Item {
            width: listView.width
            height: contentColumn.implicitHeight + 6

            ColumnLayout {
                id: contentColumn
                width: parent.width
                spacing: 6

                // ── Titlebar ──
                PanelTitlebar {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    title: "Docker"
                    statusText: DockerService.dockerAvailable
                        ? DockerService.runningCount + " running"
                        : "Not available"
                    statusColor: DockerService.dockerAvailable
                        ? Styling.srItem("overprimary")
                        : Colors.error
                    actions: [
                        {
                            icon: Icons.sync,
                            tooltip: "Refresh",
                            onClicked: function() { DockerService.refresh(); }
                        }
                    ]
                }

                // ── Warning banner ──
                StyledRect {
                    Layout.fillWidth: true
                    visible: !DockerService.dockerAvailable
                    variant: "common"
                    enableShadow: false
                    radius: Styling.radius(0)

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        text: "Docker is not running or not installed"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.warning
                        wrapMode: Text.WordWrap
                    }
                }

                // ── Container selector ──
                StyledRect {
                    Layout.fillWidth: true
                    visible: DockerService.dockerAvailable
                    variant: "common"
                    enableShadow: false
                    radius: Styling.radius(0)
                    implicitHeight: containerInner.implicitHeight + 20

                    ColumnLayout {
                        id: containerInner
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Container"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.bold: true
                                color: Colors.overBackground
                                horizontalAlignment: Text.AlignLeft
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                        Text {
                            text: Icons.docker
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Colors.primary
                        }

                                StyledCombo {
                                    id: containerCombo
                                    Layout.fillWidth: true
                                    model: DockerService.containers.map(function(c) {
                                        var statusIcon = c.isRunning ? "\u25CF" : (c.isPaused ? "\u23F8" : "\u25CB");
                                        return statusIcon + " " + c.name;
                                    })
                                    currentIndex: root.selectedIndex
                                    onActivated: index => {
                                        var conts = DockerService.containers;
                                        if (index >= 0 && index < conts.length)
                                            root.selectedId = conts[index].id;
                                    }
                                }
                            }
                        }

                        // ── Selected container info ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.selectedContainer !== null
                            spacing: 4

                            Text {
                                text: "Image"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.bold: true
                                color: Colors.overBackground
                                horizontalAlignment: Text.AlignLeft
                            }

                            StyledRect {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                variant: "focus"
                                radius: Styling.radius(0)

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    text: root.selectedContainer ? root.selectedContainer.image : ""
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.overBackground
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // ── Port mappings ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: DockerService.showPorts && root.selectedContainer && root.selectedContainer.ports && root.selectedContainer.ports.length > 0
                            spacing: 4

                            Text {
                                text: "Ports"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.bold: true
                                color: Colors.overBackground
                                horizontalAlignment: Text.AlignLeft
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: (root.selectedContainer && root.selectedContainer.ports) ? root.selectedContainer.ports : []

                                    delegate: Item {
                                        required property var modelData
                                        height: 22
                                        width: portLabel.width + 12

                                        StyledRect {
                                            anchors.fill: parent
                                            radius: 11
                                            color: Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.15)
                                            border.color: Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.3)
                                            border.width: 1

                                            Row {
                                                id: portLabel
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    text: modelData.hostPort
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(-2)
                                                    font.weight: Font.Medium
                                                    color: Styling.srItem("overprimary")
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    text: "\u2192"
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(-2)
                                                    color: Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.6)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    text: modelData.containerPort.replace("/tcp", "").replace("/udp", "")
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(-2)
                                                    color: Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.8)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Container actions ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.selectedContainer !== null
                            spacing: 4

                            Text {
                                text: "Actions"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.bold: true
                                color: Colors.overBackground
                                horizontalAlignment: Text.AlignLeft
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                // Start / Restart
                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    variant: "primary"
                                    radius: Styling.radius(0)
                                    opacity: root.selectedContainer && !root.selectedContainer.isPaused ? 1.0 : 0.4

                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.selectedContainer && root.selectedContainer.isRunning) ? Icons.sync : Icons.play
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: Styling.srItem("primary")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.selectedContainer && !root.selectedContainer.isPaused ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        enabled: root.selectedContainer && !root.selectedContainer.isPaused
                                        onClicked: {
                                            var c = root.selectedContainer;
                                            if (c) DockerService.executeAction(c.id || c.name, c.isRunning ? "restart" : "start");
                                        }
                                    }
                                }

                                // Pause
                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    variant: "primary"
                                    radius: Styling.radius(0)
                                    opacity: root.selectedContainer && (root.selectedContainer.isRunning || root.selectedContainer.isPaused) ? 1.0 : 0.4

                                    Text {
                                        anchors.centerIn: parent
                                        text: Icons.pause
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: Styling.srItem("primary")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.selectedContainer && (root.selectedContainer.isRunning || root.selectedContainer.isPaused) ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        enabled: root.selectedContainer && (root.selectedContainer.isRunning || root.selectedContainer.isPaused)
                                        onClicked: {
                                            var c = root.selectedContainer;
                                            if (c) DockerService.executeAction(c.id || c.name, c.isPaused ? "unpause" : "pause");
                                        }
                                    }
                                }

                                // Stop
                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    variant: "primary"
                                    radius: Styling.radius(0)
                                    opacity: root.selectedContainer && (root.selectedContainer.isRunning || root.selectedContainer.isPaused) ? 1.0 : 0.4

                                    Text {
                                        anchors.centerIn: parent
                                        text: Icons.stop
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: Styling.srItem("primary")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.selectedContainer && (root.selectedContainer.isRunning || root.selectedContainer.isPaused) ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        enabled: root.selectedContainer && (root.selectedContainer.isRunning || root.selectedContainer.isPaused)
                                        onClicked: {
                                            var c = root.selectedContainer;
                                            if (c) DockerService.executeAction(c.id || c.name, "stop");
                                        }
                                    }
                                }

                                // Shell
                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    variant: "primary"
                                    radius: Styling.radius(0)
                                    opacity: root.selectedContainer && root.selectedContainer.isRunning ? 1.0 : 0.4

                                    Text {
                                        anchors.centerIn: parent
                                        text: Icons.terminal
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: Styling.srItem("primary")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.selectedContainer && root.selectedContainer.isRunning ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        enabled: root.selectedContainer && root.selectedContainer.isRunning
                                        onClicked: {
                                            var c = root.selectedContainer;
                                            if (c) DockerService.openExec(c.id || c.name);
                                        }
                                    }
                                }

                                // Logs
                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    variant: "primary"
                                    radius: Styling.radius(0)
                                    opacity: root.selectedContainer ? 1.0 : 0.5

                                    Text {
                                        anchors.centerIn: parent
                                        text: Icons.file
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: Styling.srItem("primary")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.selectedContainer ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        enabled: root.selectedContainer
                                        onClicked: {
                                            var c = root.selectedContainer;
                                            if (c) DockerService.openLogs(c.id || c.name);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Compose projects section ──
                StyledRect {
                    Layout.fillWidth: true
                    visible: DockerService.dockerAvailable && DockerService.composeProjects.length > 0
                    variant: "common"
                    enableShadow: false
                    radius: Styling.radius(0)
                    implicitHeight: projectInner.implicitHeight + 20

                    ColumnLayout {
                        id: projectInner
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Compose Project"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.bold: true
                                color: Colors.overBackground
                                horizontalAlignment: Text.AlignLeft
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                        Text {
                            text: Icons.docker
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Colors.primary
                        }

                                StyledCombo {
                                    id: projectCombo
                                    Layout.fillWidth: true
                                    model: DockerService.composeProjects.map(function(p) {
                                        return p.name + " (" + p.runningCount + "/" + p.totalCount + ")";
                                    })
                                    currentIndex: root.selectedProjectIndex
                                    onActivated: index => {
                                        var projs = DockerService.composeProjects;
                                        if (index >= 0 && index < projs.length)
                                            root.selectedProjectIndex = index;
                                    }
                                }
                            }
                        }

                        // ── Project actions ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.selectedProject !== null
                            spacing: 4

                            Text {
                                text: "Project Actions"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.bold: true
                                color: Colors.overBackground
                                horizontalAlignment: Text.AlignLeft
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                // Start All
                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    variant: "primary"
                                    radius: Styling.radius(0)
                                    opacity: root.selectedProject && root.selectedProject.runningCount < root.selectedProject.totalCount ? 1.0 : 0.5

                                    Text {
                                        anchors.centerIn: parent
                                        text: Icons.play
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: Styling.srItem("primary")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.selectedProject && root.selectedProject.runningCount < root.selectedProject.totalCount ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        enabled: root.selectedProject && root.selectedProject.runningCount < root.selectedProject.totalCount
                                        onClicked: {
                                            var p = root.selectedProject;
                                            if (p) DockerService.executeComposeAction(p.workingDir, p.configFile, "start");
                                        }
                                    }
                                }

                                // Restart All
                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    variant: "primary"
                                    radius: Styling.radius(0)
                                    opacity: root.selectedProject && root.selectedProject.runningCount > 0 ? 1.0 : 0.5

                                    Text {
                                        anchors.centerIn: parent
                                        text: Icons.sync
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: Styling.srItem("primary")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.selectedProject && root.selectedProject.runningCount > 0 ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        enabled: root.selectedProject && root.selectedProject.runningCount > 0
                                        onClicked: {
                                            var p = root.selectedProject;
                                            if (p) DockerService.executeComposeAction(p.workingDir, p.configFile, "restart");
                                        }
                                    }
                                }

                                // Stop All
                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    variant: "primary"
                                    radius: Styling.radius(0)
                                    opacity: root.selectedProject && root.selectedProject.runningCount > 0 ? 1.0 : 0.5

                                    Text {
                                        anchors.centerIn: parent
                                        text: Icons.stop
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: Styling.srItem("primary")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.selectedProject && root.selectedProject.runningCount > 0 ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        enabled: root.selectedProject && root.selectedProject.runningCount > 0
                                        onClicked: {
                                            var p = root.selectedProject;
                                            if (p) DockerService.executeComposeAction(p.workingDir, p.configFile, "stop");
                                        }
                                    }
                                }

                                // View Logs
                                StyledRect {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    variant: "primary"
                                    radius: Styling.radius(0)
                                    opacity: root.selectedProject ? 1.0 : 0.5

                                    Text {
                                        anchors.centerIn: parent
                                        text: Icons.file
                                        font.family: Icons.font
                                        font.pixelSize: 14
                                        color: Styling.srItem("primary")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: root.selectedProject ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        enabled: root.selectedProject
                                        onClicked: {
                                            var p = root.selectedProject;
                                            if (p) DockerService.executeComposeAction(p.workingDir, p.configFile, "logs");
                                        }
                                    }
                                }
                            }

                            // ── Nested containers in project ──
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.selectedProject !== null && root.selectedProject.containers.length > 0
                                spacing: 4

                                Text {
                                    text: "Services"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.bold: true
                                    color: Colors.overBackground
                                    horizontalAlignment: Text.AlignLeft
                                }

                                Repeater {
                                    model: root.selectedProject ? root.selectedProject.containers : []

                                    delegate: StyledRect {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        variant: "common"
                                        radius: Styling.radius(0)
                                        border.color: modelData.isRunning
                                            ? Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.5)
                                            : modelData.isPaused
                                                ? Qt.rgba(Colors.warning.r, Colors.warning.g, Colors.warning.b, 0.5)
                                                : Colors.outline
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 8

                                            Rectangle {
                                                width: 6
                                                height: 6
                                                radius: 3
                                                color: modelData.isRunning
                                                    ? Styling.srItem("overprimary")
                                                    : modelData.isPaused ? Colors.warning : Colors.outline
                                            }

                                            Text {
                                                text: modelData.composeService || modelData.name
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(-2)
                                                color: Colors.overBackground
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: modelData.status
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(-3)
                                                color: Colors.overSurfaceVariant
                                            }

                                            // Mini actions
                                            Text {
                                                text: "\u25B6"
                                                font.family: Icons.font
                                                font.pixelSize: 12
                                                color: !modelData.isRunning ? Colors.primary : Colors.outline
                                                opacity: !modelData.isRunning ? 1.0 : 0.3

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    cursorShape: !modelData.isRunning ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                                    enabled: !modelData.isRunning
                                                    onClicked: DockerService.executeAction(modelData.id || modelData.name, "start")
                                                }
                                            }

                                            Text {
                                                text: "\u25A0"
                                                font.family: Icons.font
                                                font.pixelSize: 12
                                                color: (modelData.isRunning || modelData.isPaused) ? Colors.error : Colors.outline
                                                opacity: (modelData.isRunning || modelData.isPaused) ? 1.0 : 0.3

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    cursorShape: (modelData.isRunning || modelData.isPaused) ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                                    enabled: modelData.isRunning || modelData.isPaused
                                                    onClicked: DockerService.executeAction(modelData.id || modelData.name, "stop")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Empty state ──
                StyledRect {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    visible: DockerService.dockerAvailable && DockerService.containers.length === 0
                    variant: "common"
                    enableShadow: false
                    radius: Styling.radius(0)

                    Text {
                        anchors.centerIn: parent
                        text: "No containers found"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        font.weight: Font.Medium
                        color: Colors.overSurfaceVariant
                    }
                }
            }
        }
    }
}
