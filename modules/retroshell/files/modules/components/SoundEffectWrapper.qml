import QtQuick
import QtMultimedia

Item {
    id: root
    property string keycode: ""
    property alias source: player.source
    property alias volume: player.volume

    // Define sourcePath and volumeValue aliases for clean dynamic loading
    property alias sourcePath: player.source
    property alias volumeValue: player.volume

    SoundEffect {
        id: player
    }

    Component.onDestruction: {
        player.stop();
    }

    function play() {
        player.play();
    }
}
