import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.config
import qs.modules.widgets.desktop

// Desktop DEV.to feed widget — 2x2 (1 featured article) or 2x4 (3 articles).
WidgetHost {
    id: root

    implicitWidth: 160
    implicitHeight: 160
    contentMargins: 0

    property bool wide: false

    readonly property string tag: (root.widgetData && root.widgetData.tag)
        ? String(root.widgetData.tag) : "linux"

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            property var articles: []

            function refresh() {
                var cmd = ["python3", Quickshell.shellDir + "/scripts/devto_fetch.py"];
                if (root.tag)
                    cmd.push(root.tag);
                fetchProc.command = cmd;
                fetchProc.running = true;
            }

            Process {
                id: fetchProc
                running: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        var out = text.trim();
                        if (!out) return;
                        try {
                            content.articles = JSON.parse(out);
                        } catch (e) {
                            console.warn("DevtoWidget: parse error", e);
                        }
                    }
                }
            }

            // Refresh every 30 minutes.
            Timer {
                interval: 1800000
                repeat: true
                running: true
                onTriggered: content.refresh()
            }

            Connections {
                target: root
                function onTagChanged() { content.refresh(); }
            }

            DevtoCard {
                anchors.fill: parent
                wide: root.wide
                articles: content.articles
                tag: root.tag
            }

            Component.onCompleted: content.refresh()
        }
    }
}