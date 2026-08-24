import QtQuick
import QtQuick.Layouts
import qs.modules.theme
import qs.config

// Feed card — single article with full-cover background, swipeable through the
// loaded articles (2x4, 320x160). Source-aware branding; click opens the URL.
Rectangle {
    id: root

    property bool showBackground: true
    property var articles: [] // [{id,title,url,readTime,upvotes,source,author,image}]
    property int currentIndex: 0
    property string source: "devto" // devto | hackernews | dailydev
    property string tag: "linux"

    signal previousRequested()
    signal nextRequested()
    signal openRequested(string url)

    readonly property var currentArticle: (root.articles.length > 0 && root.currentIndex >= 0 && root.currentIndex < root.articles.length)
        ? root.articles[root.currentIndex] : null

    function accentColor() {
        if (root.source === "hackernews") return "#FF6600";
        if (root.source === "dailydev") return "#A259FF";
        return Colors.magenta;
    }

    function brandLabel() {
        if (root.source === "hackernews") return "HackerNews";
        if (root.source === "dailydev") return "daily.dev";
        return "DEV";
    }

    function feedTitle() {
        return "Dev Feed";
    }

    readonly property real brandMaxWidth: 92

    // Auto-scale the badge font so the brand always fits the badge.
    function badgeFontSize() {
        var label = root.brandLabel();
        var base = 9;
        var est = label.length * base * 0.62 + 14;
        if (est > root.brandMaxWidth)
            return Math.max(7, Math.floor(base * root.brandMaxWidth / est));
        return base;
    }

    function badgeBg() {
        if (root.source === "hackernews") return "#FF6600";
        if (root.source === "dailydev") return "#A259FF";
        return "#FFFFFF";
    }

    function badgeFg() {
        if (root.source === "hackernews") return "#FFFFFF";
        if (root.source === "dailydev") return "#FFFFFF";
        return "#000000";
    }

    radius: 20
    clip: true

    // Surface fallback (behind the cover)
    Rectangle {
        anchors.fill: parent
        visible: root.showBackground
        radius: 20
        color: Colors.surfaceContainer
    }

    Item {
        id: articleView
        anchors.fill: parent
        opacity: 1

        // Article cover background
        Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: root.currentArticle && root.currentArticle.image ? root.currentArticle.image : ""
            visible: root.currentArticle && root.currentArticle.image
            cache: false
        }

        // Scrim for readability
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
                GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.15) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
            }
        }

        // ── Header overlay ──
        RowLayout {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 10
            spacing: 6

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: Math.min(root.brandMaxWidth, brandText.implicitWidth + 14)
                height: 18
                radius: 9
                color: root.badgeBg()

                Text {
                    id: brandText
                    anchors.centerIn: parent
                    text: root.brandLabel()
                    color: root.badgeFg()
                    font.family: Config.theme.font
                    font.pixelSize: root.badgeFontSize()
                    font.weight: Font.Black
                    elide: Text.ElideRight
                    width: parent.width - 10
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.feedTitle()
                color: "#FFFFFF"
                font.family: Config.theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.alignment: Qt.AlignVCenter
            }

            // Tag pill
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: root.tag.length > 0
                height: 16
                width: tagPillText.implicitWidth + 10
                radius: 8
                color: Qt.rgba(0, 0, 0, 0.45)

                Text {
                    id: tagPillText
                    anchors.centerIn: parent
                    text: "#" + root.tag
                    color: root.accentColor()
                    font.family: Config.theme.font
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }
        }

        // ── Bottom article overlay ──
        ColumnLayout {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 10
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: root.currentArticle ? root.currentArticle.title : ""
                color: "#FFFFFF"
                font.family: Config.theme.font
                font.pixelSize: 14
                font.weight: Font.Bold
                maximumLineCount: 2
                elide: Text.ElideRight
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Text {
                    text: Icons.caretUp
                    font.family: Icons.font
                    font.pixelSize: 10
                    color: root.accentColor()
                }

                Text {
                    text: root.currentArticle ? (root.currentArticle.upvotes || 0) : 0
                    color: root.accentColor()
                    font.family: Config.theme.font
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }

                Text {
                    visible: root.currentArticle && root.currentArticle.readTime > 0
                    text: root.currentArticle ? ("· " + root.currentArticle.readTime + " min read") : ""
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.family: Config.theme.font
                    font.pixelSize: 11
                }

                Text {
                    visible: root.currentArticle && root.currentArticle.source
                    text: root.currentArticle ? ("· " + root.currentArticle.source) : ""
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.family: Config.theme.font
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Item { Layout.fillWidth: true }
            }
        }

        // Tap vs drag: tap opens, horizontal drag swipes.
        MouseArea {
            anchors.fill: parent
            property real pressX: 0
            property real pressY: 0
            cursorShape: Qt.PointingHandCursor

            onPressed: (m) => { pressX = m.x; pressY = m.y; }
            onReleased: (m) => {
                var dx = m.x - pressX;
                var dy = m.y - pressY;
                if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) {
                    if (dx < 0) root.nextRequested();
                    else root.previousRequested();
                } else if (Math.abs(dx) < 12 && Math.abs(dy) < 12) {
                    if (root.currentArticle)
                        root.openRequested(root.currentArticle.url);
                }
            }
        }
    }

    // Fade content in on index change
    onCurrentIndexChanged: {
        articleView.opacity = 0;
        slideIn.start();
    }

    NumberAnimation {
        id: slideIn
        target: articleView
        property: "opacity"
        to: 1
        duration: 260
        easing.type: Easing.OutQuad
    }

    // ── Swipe arrows ──
    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 6
        text: Icons.caretLeft
        font.family: Icons.font
        font.pixelSize: 16
        color: Qt.rgba(1, 1, 1, 0.75)
        z: 5

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: root.previousRequested()
        }
    }

    Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 6
        text: Icons.caretRight
        font.family: Icons.font
        font.pixelSize: 16
        color: Qt.rgba(1, 1, 1, 0.75)
        z: 5

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: root.nextRequested()
        }
    }

    // ── Dots (bottom-right) ──
    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 12
        spacing: 3
        z: 5

        Repeater {
            model: root.articles.length
            delegate: Rectangle {
                width: 5
                height: 5
                radius: 2.5
                color: index === root.currentIndex ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.35)
            }
        }
    }
}