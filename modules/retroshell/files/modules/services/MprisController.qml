pragma Singleton
pragma ComponentBehavior: Bound

import QtQml.Models
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.config

Singleton {
    id: root

    // --- Properties ---
    property var trackedPlayer: null
    property var filteredPlayers: {
        const filtered = Mpris.players.values.filter(player => {
            const dbusName = (player.dbusName || "").toLowerCase();
            if (!Config.bar.enableFirefoxPlayer && dbusName.includes("firefox")) {
                return false;
            }
            return true;
        });
        const preferred = filtered.filter(player => root._isPreferred(player));
        const others = filtered.filter(player => !root._isPreferred(player));
        return preferred.concat(others);
    }

    property var activePlayer: trackedPlayer ? trackedPlayer : (filteredPlayers.length > 0 ? root._defaultPlayer(filteredPlayers) : null)
    
    property bool isInitializing: true
    property string cachedDbusName: ""
    property bool _hasExplicitPick: false

    property bool isPlaying: activePlayer ? activePlayer.isPlaying : false
    property bool canTogglePlaying: activePlayer ? activePlayer.canTogglePlaying : false
    property bool canGoPrevious: activePlayer ? activePlayer.canGoPrevious : false
    property bool canGoNext: activePlayer ? activePlayer.canGoNext : false
    property bool canChangeVolume: activePlayer && activePlayer.volumeSupported && activePlayer.canControl
    property bool loopSupported: activePlayer && activePlayer.loopSupported && activePlayer.canControl
    property var loopState: activePlayer ? activePlayer.loopState : (typeof MprisLoopState !== 'undefined' ? MprisLoopState.None : 0)
    property bool shuffleSupported: activePlayer && activePlayer.shuffleSupported && activePlayer.canControl
    property bool hasShuffle: activePlayer ? activePlayer.shuffle : false

    // --- Handlers ---
    onFilteredPlayersChanged: {
        if (root.isInitializing && root.filteredPlayers.length > 0) {
            if (root.cachedDbusName) {
                for (let i = 0; i < root.filteredPlayers.length; i++) {
                    const player = root.filteredPlayers[i];
                    if (player.dbusName === root.cachedDbusName) {
                        root.trackedPlayer = player;
                        root.isInitializing = false;
                        root._hasExplicitPick = true;
                        return;
                    }
                }
                root.trackedPlayer = root._defaultPlayer(root.filteredPlayers);
                root.isInitializing = false;
            } else {
                root.trackedPlayer = root._defaultPlayer(root.filteredPlayers);
                root.isInitializing = false;
            }
        }
    }

    Component.onCompleted: {
        root.cachedDbusName = StateService.get("lastPlayerDbusName", "");
        if (StateService.initialized) {
            root.loadLastPlayer();
        }
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            root.cachedDbusName = StateService.get("lastPlayerDbusName", "");
            root.loadLastPlayer();
        }
    }

    // --- Functions ---
    function _isPreferred(player) {
        if (!player) return false;
        const dbusName = (player.dbusName || "").toLowerCase();
        const desktopEntry = (player.desktopEntry || "").toLowerCase();
        const identity = (player.identity || "").toLowerCase();
        return dbusName.includes("spotify") || desktopEntry.includes("spotify") || identity.includes("spotify");
    }

    function _hasPreferred() {
        return root.filteredPlayers.some(player => root._isPreferred(player));
    }

    function _defaultPlayer(players) {
        if (!players || players.length === 0) return null;
        for (let i = 0; i < players.length; i++) {
            if (root._isPreferred(players[i])) return players[i];
        }
        return players[0];
    }

    function loadLastPlayer() {
        if (!root.cachedDbusName) {
            root.trackedPlayer = root._defaultPlayer(root.filteredPlayers);
            root.isInitializing = false;
            return;
        }

        for (let i = 0; i < root.filteredPlayers.length; i++) {
            const player = root.filteredPlayers[i];
            if (player.dbusName === root.cachedDbusName) {
                root.trackedPlayer = player;
                root.isInitializing = false;
                root._hasExplicitPick = true;
                return;
            }
        }
    }

    function saveLastPlayer() {
        if (!root.trackedPlayer || root.isInitializing)
            return;

        StateService.set("lastPlayerDbusName", root.trackedPlayer.dbusName);
    }

    function togglePlaying() {
        if (root.canTogglePlaying)
            root.activePlayer.togglePlaying();
    }

    function previous() {
        if (root.canGoPrevious) {
            root.activePlayer.previous();
        }
    }

    function next() {
        if (root.canGoNext) {
            root.activePlayer.next();
        }
    }

    function setLoopState(loopState) {
        if (root.loopSupported) {
            root.activePlayer.loopState = loopState;
        }
    }

    function setShuffle(shuffle) {
        if (root.shuffleSupported) {
            root.activePlayer.shuffle = shuffle;
        }
    }

    function setActivePlayer(player) {
        const targetPlayer = player ? player : (root.filteredPlayers.length > 0 ? root.filteredPlayers[0] : null);

        root.trackedPlayer = targetPlayer;
        root._hasExplicitPick = targetPlayer != null;
        root.saveLastPlayer();
    }

    function cyclePlayer(direction) {
        const players = root.filteredPlayers;
        if (players.length === 0)
            return;

        const currentIndex = players.indexOf(root.activePlayer);
        let newIndex;

        if (direction > 0) {
            newIndex = (currentIndex + 1) % players.length;
        } else {
            newIndex = (currentIndex - 1 + players.length) % players.length;
        }

        root.trackedPlayer = players[newIndex];
        root._hasExplicitPick = true;
        root.saveLastPlayer();
    }

    // --- Components ---
    Instantiator {
        model: Mpris.players

        Connections {
            required property var modelData
            target: modelData

            Component.onCompleted: {
                const dbusName = (modelData.dbusName || "").toLowerCase();
                const shouldIgnore = !Config.bar.enableFirefoxPlayer && dbusName.includes("firefox");

                if (!shouldIgnore && !root._hasExplicitPick) {
                    if (root._isPreferred(modelData) || root.trackedPlayer == null || (modelData.isPlaying && !root._hasPreferred())) {
                        root.trackedPlayer = modelData;
                    }
                }
            }

            Component.onDestruction: {
                if (root.trackedPlayer === modelData) {
                    for (let i = 0; i < root.filteredPlayers.length; i++) {
                        const player = root.filteredPlayers[i];
                        if (player.playbackState.isPlaying) {
                            root.trackedPlayer = player;
                            break;
                        }
                    }

                    if (root.trackedPlayer === modelData) {
                        root.trackedPlayer = root._defaultPlayer(root.filteredPlayers);
                    }
                    root._hasExplicitPick = false;
                }
            }

            function onPlaybackStateChanged() {
                // Comentado para evitar cambio automático de player
                // if (root.trackedPlayer !== modelData) root.trackedPlayer = modelData
            }
        }
    }
}
