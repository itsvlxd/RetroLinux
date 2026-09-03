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

    property bool groupByCompose: false
    property var expandedContainers: ({})
    property var expandedProjects: ({})

    function toggleContainer(cid) {
        var e = root.expandedContainers;
        e[cid] = !e[cid];
        root.expandedContainers = e;
        root.expandedContainersChanged();
        Qt.callLater(scrollTimer.restart);
    }

    function toggleProject(pname) {
        var e = root.expandedProjects;
        e[pname] = !e[pname];
        root.expandedProjects = e;
        root.expandedProjectsChanged();
        Qt.callLater(scrollTimer.restart);
    }

    function ensureVisible(lv, idx) {
        if (idx >= 0) lv.positionViewAtIndex(idx, ListView.Contain);
    }

    function getContainerIndex(cid) {
        var conts = DockerService.containers;
        for (var i = 0; i < conts.length; i++) {
            if (conts[i].id === cid) return i;
        }
        return -1;
    }

    function getProjectIndex(pname) {
        var projs = DockerService.composeProjects;
        for (var i = 0; i < projs.length; i++) {
            if (projs[i].name === pname) return i;
        }
        return -1;
    }

    Timer {
        id: scrollTimer
        interval: 50
        repeat: false
        onTriggered: {
            var e = root.expandedContainers;
            for (var cid in e) {
                if (e[cid]) {
                    var idx = root.getContainerIndex(cid);
                    if (idx >= 0) root.ensureVisible(containerList, idx);
                    return;
                }
            }
            var ep = root.expandedProjects;
            for (var pname in ep) {
                if (ep[pname]) {
                    var idx2 = root.getProjectIndex(pname);
                    if (idx2 >= 0) root.ensureVisible(projectList, idx2);
                    return;
                }
            }
        }
    }

    implicitWidth: Math.min(parent ? parent.width : 0, maxContentWidth)

    Component.onCompleted: DockerService.refresh()

    // ── Shared header content ──
    ColumnLayout {
        id: headerColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 6

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
                    icon: root.groupByCompose ? Icons.list : Icons.folder,
                    tooltip: root.groupByCompose ? "Flat view" : "Compose view",
                    onClicked: function() { root.groupByCompose = !root.groupByCompose; }
                },
                {
                    icon: Icons.sync,
                    tooltip: "Refresh",
                    onClicked: function() { DockerService.refresh(); }
                }
            ]
        }

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
    }

    // ── Flat container list ──
    ListView {
        id: containerList
        anchors.top: headerColumn.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !root.groupByCompose && DockerService.dockerAvailable
        clip: true
        spacing: 4
        model: DockerService.containers

        delegate: Item {
            id: cDel
            width: containerList.width
            height: cCard.height

            property var cData: modelData
            property bool isExpanded: root.expandedContainers[modelData.id] || false

            StyledRect {
                id: cCard
                width: parent.width
                height: headerRow.height + (cDel.isExpanded ? expandedCol.height : 0)
                variant: "common"
                radius: Styling.radius(0)
                border.color: cDel.cData.isRunning
                    ? Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.5)
                    : cDel.cData.isPaused
                        ? Qt.rgba(Colors.warning.r, Colors.warning.g, Colors.warning.b, 0.5)
                        : Colors.outline
                border.width: 1
                clip: true

                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
                }

                // ── Header row ──
                Item {
                    id: headerRow
                    width: parent.width
                    height: 44

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: cDel.cData.isRunning
                            ? Styling.srItem("overprimary")
                            : cDel.cData.isPaused ? Colors.warning : Colors.outline
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 24
                        anchors.right: cArrow.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            text: cDel.cData.name
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: cDel.cData.image
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overSurfaceVariant
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Text {
                        id: cArrow
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: cDel.isExpanded ? Icons.caretDown : Icons.caretRight
                        font.family: Icons.font
                        font.pixelSize: 12
                        color: Colors.overSurfaceVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleContainer(cDel.cData.id)
                    }
                }

                // ── Expanded content (inside the card) ──
                Column {
                    id: expandedCol
                    anchors.top: headerRow.bottom
                    width: parent.width
                    visible: cDel.isExpanded
                    spacing: 0

                    // Divider line
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Colors.outline
                        opacity: 0.3
                    }

                    // Ports
                    Flow {
                        width: parent.width
                        visible: DockerService.showPorts && cDel.cData.ports && cDel.cData.ports.length > 0
                        spacing: 4
                        leftPadding: 10
                        rightPadding: 10
                        topPadding: 6
                        bottomPadding: 6

                        Repeater {
                            model: cDel.cData.ports || []
                            delegate: Item {
                                height: 20
                                width: cPortRow.width + 12

                                StyledRect {
                                    anchors.fill: parent
                                    radius: 10
                                    color: Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.15)
                                    border.color: Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.3)
                                    border.width: 1

                                    Row {
                                        id: cPortRow
                                        anchors.centerIn: parent
                                        spacing: 3
                                        Text {
                                            text: modelData.hostPort
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-3)
                                            font.weight: Font.Medium
                                            color: Styling.srItem("overprimary")
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "\u2192"
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-3)
                                            color: Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.6)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: modelData.containerPort.replace("/tcp", "").replace("/udp", "")
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-3)
                                            color: Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.8)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Action buttons
                    StyledRect {
                        width: parent.width
                        height: actionRow.height + 12
                        variant: "focus"
                        radius: Styling.radius(0)

                        Row {
                            id: actionRow
                            anchors.centerIn: parent
                            spacing: 4

                            Repeater {
                                model: ListModel {
                                    ListElement { iconCode: "play"; act: "start" }
                                    ListElement { iconCode: "sync"; act: "restart" }
                                    ListElement { iconCode: "pause"; act: "pause" }
                                    ListElement { iconCode: "stop"; act: "stop" }
                                    ListElement { iconCode: "terminal"; act: "shell" }
                                    ListElement { iconCode: "file"; act: "logs" }
                                }

                                delegate: Item {
                                    width: 36
                                    height: 28

                                    property bool isActionEnabled: {
                                        var c = cDel.cData;
                                        if (!c) return false;
                                        switch (act) {
                                        case "start": return !c.isRunning;
                                        case "restart": return c.isRunning && !c.isPaused;
                                        case "pause": return c.isRunning && !c.isPaused;
                                        case "stop": return c.isRunning || c.isPaused;
                                        case "shell": return c.isRunning;
                                        case "logs": return true;
                                        }
                                        return false;
                                    }

                                    property string iconText: {
                                        switch (iconCode) {
                                        case "play": return Icons.play;
                                        case "sync": return Icons.sync;
                                        case "pause": return Icons.pause;
                                        case "stop": return Icons.stop;
                                        case "terminal": return Icons.terminal;
                                        case "file": return Icons.file;
                                        }
                                        return "";
                                    }

                                    StyledRect {
                                        anchors.fill: parent
                                        radius: Styling.radius(0)
                                        variant: "primary"
                                        opacity: isActionEnabled ? 1.0 : 0.4

                                        Text {
                                            anchors.centerIn: parent
                                            text: iconText
                                            font.family: Icons.font
                                            font.pixelSize: 13
                                            color: Styling.srItem("primary")
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: isActionEnabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                            enabled: isActionEnabled
                                            onClicked: {
                                                var c = cDel.cData;
                                                if (!c) return;
                                                var cid = c.id || c.name;
                                                if (act === "shell") DockerService.openExec(cid);
                                                else if (act === "logs") DockerService.openLogs(cid);
                                                else DockerService.executeAction(cid, act);
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

        StyledRect {
            anchors.centerIn: parent
            width: parent.width - 20
            height: 60
            visible: DockerService.containers.length === 0
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

    // ── Compose project list ──
    ListView {
        id: projectList
        anchors.top: headerColumn.bottom
        anchors.topMargin: 6
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.groupByCompose && DockerService.dockerAvailable
        clip: true
        spacing: 4
        model: DockerService.composeProjects

        delegate: Item {
            id: pDel
            width: projectList.width
            height: pCard.height

            property var pData: modelData
            property bool isExpanded: root.expandedProjects[modelData.name] || false

            StyledRect {
                id: pCard
                width: parent.width
                height: pHeaderRow.height + (pDel.isExpanded ? pExpandedCol.height : 0)
                variant: "common"
                radius: Styling.radius(0)
                border.color: pDel.pData.runningCount === pDel.pData.totalCount && pDel.pData.totalCount > 0
                    ? Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.5)
                    : pDel.pData.runningCount > 0
                        ? Qt.rgba(Colors.warning.r, Colors.warning.g, Colors.warning.b, 0.5)
                        : Colors.outline
                border.width: 1
                clip: true

                Behavior on height {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
                }

                // ── Project header ──
                Item {
                    id: pHeaderRow
                    width: parent.width
                    height: 44

                    Text {
                        text: Icons.folder
                        font.family: Icons.font
                        font.pixelSize: 14
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: pDel.pData.runningCount === pDel.pData.totalCount && pDel.pData.totalCount > 0
                            ? Styling.srItem("overprimary")
                            : pDel.pData.runningCount > 0
                                ? Colors.warning
                                : Colors.overSurfaceVariant
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 32
                        anchors.right: pCountText.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            text: pDel.pData.name
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Bold
                            color: Colors.overBackground
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: pDel.pData.containers.length + " service" + (pDel.pData.containers.length !== 1 ? "s" : "")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            color: Colors.overSurfaceVariant
                        }
                    }

                    Text {
                        id: pCountText
                        anchors.right: pArrow.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: pDel.pData.runningCount + "/" + pDel.pData.totalCount
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        font.weight: Font.Medium
                        color: pDel.pData.runningCount === pDel.pData.totalCount && pDel.pData.totalCount > 0
                            ? Styling.srItem("overprimary")
                            : Colors.overSurfaceVariant
                    }

                    Text {
                        id: pArrow
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: pDel.isExpanded ? Icons.caretDown : Icons.caretRight
                        font.family: Icons.font
                        font.pixelSize: 12
                        color: Colors.overSurfaceVariant
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleProject(pDel.pData.name)
                    }
                }

                // ── Expanded content (inside the card) ──
                Column {
                    id: pExpandedCol
                    anchors.top: pHeaderRow.bottom
                    width: parent.width
                    visible: pDel.isExpanded
                    spacing: 0

                    // Divider
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Colors.outline
                        opacity: 0.3
                    }

                    // Project actions
                    StyledRect {
                        width: parent.width
                        height: pActionRow.height + 12
                        variant: "focus"
                        radius: Styling.radius(0)

                        Row {
                            id: pActionRow
                            anchors.centerIn: parent
                            spacing: 4

                            Repeater {
                                model: ListModel {
                                    ListElement { iconCode: "play"; act: "start" }
                                    ListElement { iconCode: "sync"; act: "restart" }
                                    ListElement { iconCode: "stop"; act: "stop" }
                                    ListElement { iconCode: "file"; act: "logs" }
                                }

                                delegate: Item {
                                    width: 36
                                    height: 28

                                    property bool isActionEnabled: {
                                        var p = pDel.pData;
                                        if (!p) return false;
                                        switch (act) {
                                        case "start": return p.runningCount < p.totalCount;
                                        case "restart": return p.runningCount > 0;
                                        case "stop": return p.runningCount > 0;
                                        case "logs": return true;
                                        }
                                        return false;
                                    }

                                    property string iconText: {
                                        switch (iconCode) {
                                        case "play": return Icons.play;
                                        case "sync": return Icons.sync;
                                        case "stop": return Icons.stop;
                                        case "file": return Icons.file;
                                        }
                                        return "";
                                    }

                                    StyledRect {
                                        anchors.fill: parent
                                        radius: Styling.radius(0)
                                        variant: "primary"
                                        opacity: isActionEnabled ? 1.0 : 0.4

                                        Text {
                                            anchors.centerIn: parent
                                            text: iconText
                                            font.family: Icons.font
                                            font.pixelSize: 13
                                            color: Styling.srItem("primary")
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: isActionEnabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                            enabled: isActionEnabled
                                            onClicked: {
                                                var p = pDel.pData;
                                                if (!p) return;
                                                if (act === "logs") DockerService.executeComposeAction(p.workingDir, p.configFile, "logs");
                                                else DockerService.executeComposeAction(p.workingDir, p.configFile, act);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Services container
                    StyledRect {
                        width: parent.width
                        height: servicesCol.implicitHeight + 16
                        variant: "internalbg"
                        radius: Styling.radius(0)

                        ColumnLayout {
                            id: servicesCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            Text {
                                text: "Services"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.bold: true
                                color: Colors.overSurfaceVariant
                                Layout.leftMargin: 2
                            }

                            Repeater {
                                model: pDel.pData ? pDel.pData.containers : []

                                delegate: Item {
                                    id: sDel
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: sCard.height

                                    property var sData: modelData
                                    property bool isExpanded: root.expandedContainers[modelData.name] || false

                                    StyledRect {
                                        id: sCard
                                        width: parent.width
                                        height: sHeaderRow.height + (sDel.isExpanded ? sExpandedContent.height : 0)
                                        variant: "common"
                                        radius: Styling.radius(0)
                                        border.color: sDel.sData.isRunning
                                            ? Qt.rgba(Styling.srItem("overprimary").r, Styling.srItem("overprimary").g, Styling.srItem("overprimary").b, 0.4)
                                            : sDel.sData.isPaused
                                                ? Qt.rgba(Colors.warning.r, Colors.warning.g, Colors.warning.b, 0.4)
                                                : Colors.outline
                                        border.width: 1
                                        clip: true

                                        Behavior on height {
                                            enabled: Config.animDuration > 0
                                            NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
                                        }

                                        Item {
                                            id: sHeaderRow
                                            width: parent.width
                                            height: 40

                                            Rectangle {
                                                width: 6
                                                height: 6
                                                radius: 3
                                                anchors.left: parent.left
                                                anchors.leftMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: sDel.sData.isRunning
                                                    ? Styling.srItem("overprimary")
                                                    : sDel.sData.isPaused ? Colors.warning : Colors.outline
                                            }

                                            Column {
                                                anchors.left: parent.left
                                                anchors.leftMargin: 24
                                                anchors.right: sStatusCol.left
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 1

                                                Text {
                                                    text: sDel.sData.composeService || sDel.sData.name
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(-2)
                                                    font.weight: Font.Medium
                                                    color: Colors.overBackground
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                }

                                                Text {
                                                    text: sDel.sData.image
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(-3)
                                                    color: Colors.overSurfaceVariant
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                    visible: text.length > 0
                                                }
                                            }

                                            Column {
                                                id: sStatusCol
                                                anchors.right: sArrow.left
                                                anchors.rightMargin: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 0

                                                Text {
                                                    text: sDel.sData.status
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(-3)
                                                    font.weight: Font.Medium
                                                    color: sDel.sData.isRunning
                                                        ? Styling.srItem("overprimary")
                                                        : sDel.sData.isPaused
                                                            ? Colors.warning
                                                            : Colors.overSurfaceVariant
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }

                                            Text {
                                                id: sArrow
                                                anchors.right: parent.right
                                                anchors.rightMargin: 10
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: sDel.isExpanded ? Icons.caretDown : Icons.caretRight
                                                font.family: Icons.font
                                                font.pixelSize: 10
                                                color: Colors.overSurfaceVariant
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleContainer(sDel.sData.name)
                                            }
                                        }

                                        Column {
                                            id: sExpandedContent
                                            anchors.top: sHeaderRow.bottom
                                            width: parent.width
                                            visible: sDel.isExpanded
                                            spacing: 0

                                            Rectangle {
                                                width: parent.width
                                                height: 1
                                                color: Colors.outline
                                                opacity: 0.2
                                            }

                                            StyledRect {
                                                width: parent.width
                                                height: sActionRow.height + 10
                                                variant: "focus"
                                                radius: Styling.radius(0)

                                                Row {
                                                    id: sActionRow
                                                    anchors.centerIn: parent
                                                    spacing: 4

                                                    Repeater {
                                                        model: ListModel {
                                                            ListElement { iconCode: "play"; act: "start" }
                                                            ListElement { iconCode: "sync"; act: "restart" }
                                                            ListElement { iconCode: "pause"; act: "pause" }
                                                            ListElement { iconCode: "stop"; act: "stop" }
                                                            ListElement { iconCode: "terminal"; act: "shell" }
                                                            ListElement { iconCode: "file"; act: "logs" }
                                                        }

                                                        delegate: Item {
                                                            width: 32
                                                            height: 26

                                                            property bool isActionEnabled: {
                                                                var c = sDel.sData;
                                                                if (!c) return false;
                                                                switch (act) {
                                                                case "start": return !c.isRunning;
                                                                case "restart": return c.isRunning && !c.isPaused;
                                                                case "pause": return c.isRunning && !c.isPaused;
                                                                case "stop": return c.isRunning || c.isPaused;
                                                                case "shell": return c.isRunning;
                                                                case "logs": return true;
                                                                }
                                                                return false;
                                                            }

                                                            property string iconText: {
                                                                switch (iconCode) {
                                                                case "play": return Icons.play;
                                                                case "sync": return Icons.sync;
                                                                case "pause": return Icons.pause;
                                                                case "stop": return Icons.stop;
                                                                case "terminal": return Icons.terminal;
                                                                case "file": return Icons.file;
                                                                }
                                                                return "";
                                                            }

                                                            StyledRect {
                                                                anchors.fill: parent
                                                                radius: Styling.radius(0)
                                                                variant: "primary"
                                                                opacity: isActionEnabled ? 1.0 : 0.4

                                                                Text {
                                                                    anchors.centerIn: parent
                                                                    text: iconText
                                                                    font.family: Icons.font
                                                                    font.pixelSize: 12
                                                                    color: Styling.srItem("primary")
                                                                }

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: isActionEnabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                                                    enabled: isActionEnabled
                                                                    onClicked: {
                                                                        var c = sDel.sData;
                                                                        if (!c) return;
                                                                        var cid = c.id || c.name;
                                                                        if (act === "shell") DockerService.openExec(cid);
                                                                        else if (act === "logs") DockerService.openLogs(cid);
                                                                        else DockerService.executeAction(cid, act);
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
                            }
                        }
                    }

                    Item {
                        width: 1
                        height: 4
                    }
                }
            }
        }

        StyledRect {
            anchors.centerIn: parent
            width: parent.width - 20
            height: 60
            visible: DockerService.composeProjects.length === 0
            variant: "common"
            enableShadow: false
            radius: Styling.radius(0)

            Text {
                anchors.centerIn: parent
                text: "No compose projects found"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                font.weight: Font.Medium
                color: Colors.overSurfaceVariant
            }
        }
    }
}
