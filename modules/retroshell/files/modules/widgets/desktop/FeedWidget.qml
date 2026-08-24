import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.config
import qs.modules.widgets.desktop

// Desktop feed widget — 2x4 (320x160) single full-cover article, swipeable
// through the top articles. Source: devto (default) | hackernews | dailydev.
WidgetHost {
    id: root

    implicitWidth: 320
    implicitHeight: 160
    contentMargins: 0
    cardBorder: false

    readonly property string source: (root.widgetData && root.widgetData.source)
        ? String(root.widgetData.source) : "devto"
    readonly property string tag: (root.widgetData && root.widgetData.tag)
        ? String(root.widgetData.tag) : "linux"
    readonly property string apiKey: (root.widgetData && root.widgetData.apiKey)
        ? String(root.widgetData.apiKey) : ""
    readonly property bool autoSwipe: (root.widgetData && root.widgetData.autoSwipe !== undefined)
        ? root.widgetData.autoSwipe === true : true
    readonly property int swipeInterval: (root.widgetData && root.widgetData.swipeInterval)
        ? Number(root.widgetData.swipeInterval) : 30
    readonly property int count: (root.widgetData && root.widgetData.count)
        ? Math.max(3, Math.min(10, Number(root.widgetData.count))) : 5

    contentComponent: Component {
        Item {
            id: content
            anchors.fill: parent

            property var articles: []
            property int currentIndex: 0

            function refresh() {
                var cmd = ["python3", Quickshell.shellDir + "/scripts/feed_fetch.py",
                           root.source, root.tag, root.apiKey, String(root.count)];
                fetchProc.command = cmd;
                fetchProc.running = true;
            }

            function next() {
                if (content.articles.length === 0) return;
                content.currentIndex = (content.currentIndex + 1) % content.articles.length;
            }

            function prev() {
                if (content.articles.length === 0) return;
                content.currentIndex = (content.currentIndex - 1 + content.articles.length) % content.articles.length;
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
                            if (content.currentIndex >= content.articles.length)
                                content.currentIndex = 0;
                        } catch (e) {
                            console.warn("FeedWidget: parse error", e);
                        }
                    }
                }
            }

            // Refetch every 30 minutes.
            Timer {
                interval: 1800000
                repeat: true
                running: true
                onTriggered: content.refresh()
            }

            // Auto-swipe every N seconds (configurable, can be disabled).
            Timer {
                id: autoSwipeTimer
                interval: Math.max(5000, root.swipeInterval * 1000)
                repeat: true
                running: root.autoSwipe && content.articles.length > 1
                onTriggered: content.next()
            }

            Connections {
                target: root
                function onSourceChanged() { content.currentIndex = 0; content.refresh(); }
                function onTagChanged() { content.currentIndex = 0; content.refresh(); }
                function onApiKeyChanged() { content.currentIndex = 0; content.refresh(); }
                function onAutoSwipeChanged() {
                    autoSwipeTimer.running = root.autoSwipe && content.articles.length > 1;
                }
            }

            FeedCard {
                anchors.fill: parent
                articles: content.articles
                currentIndex: content.currentIndex
                source: root.source
                tag: root.tag
                onPreviousRequested: content.prev()
                onNextRequested: content.next()
                onOpenRequested: function (url) {
                    if (url) Qt.openUrlExternally(url);
                }
            }

            Component.onCompleted: content.refresh()
        }
    }
}