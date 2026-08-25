pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.components
import qs.modules.globals
import qs.config

Singleton {
    id: root

    // ── Stored settings (synced from Config, NOT bound) ──
    // Using stored properties prevents flickering when Config.saveTypingSounds()
    // rewrites the JSON file — the adapter briefly becomes undefined during write,
    // which would flip readonly bindings and kill the input process.
    property bool enabled: false
    property int volume: 100
    property bool mouseEnabled: false
    property string selectedPackId: "nk-cream"
    property string selectedDevicePath: "all"

    // Guard: have we ever successfully synced from Config?
    property bool _configSynced: false

    // Sync from Config on startup and when config changes externally.
    // Guarded by Config.typingSoundsReady to avoid reading adapter defaults
    // before the JSON file has been loaded — this is what caused the
    // true→false→fake-true startup toggle.
    function _syncFromConfig() {
        if (!Config.typingSoundsReady) return;
        var cfg = Config.typingSounds;
        if (!cfg) return;
        var newEnabled = cfg.enabled !== undefined ? cfg.enabled : false;
        var newVolume = cfg.volume !== undefined ? cfg.volume : 100;
        var newMouse = cfg.mouseEnabled !== undefined ? cfg.mouseEnabled : false;
        var newPack = cfg.selectedPackId !== undefined ? cfg.selectedPackId : "nk-cream";
        var newDevice = cfg.selectedDevicePath !== undefined ? cfg.selectedDevicePath : "all";

        // Adapter flicker guard: during a Config FileView reload cycle the
        // adapter briefly resets to its QML defaults (enabled: false, etc.).
        // If we've already synced once with real values, refuse to downgrade
        // enabled from true → false in a single tick — that's a reload artifact.
        if (_configSynced && newEnabled !== root.enabled && newEnabled === false
                && root.enabled === true) {
            console.warn("[TypingSounds] Skipping enabled=false during Config adapter flicker");
            return;
        }

        _configSynced = true;

        // Only trigger change handlers for values that actually changed
        if (newEnabled !== root.enabled) root.enabled = newEnabled;
        if (newVolume !== root.volume) root.volume = newVolume;
        if (newMouse !== root.mouseEnabled) root.mouseEnabled = newMouse;
        if (newPack !== root.selectedPackId) root.selectedPackId = newPack;
        if (newDevice !== root.selectedDevicePath) root.selectedDevicePath = newDevice;
    }

    // ── Derived paths ──
    readonly property string soundPacksDir: {
        var rd = Quickshell.env("RETRO_DIR") || "/opt/retrolinux";
        return rd + "/modules/retroshell/files/assets/typing-sounds-soundpacks";
    }
    readonly property string selectedPackPath: soundPacksDir + "/" + selectedPackId
    readonly property string sliceScript: {
        var rd = Quickshell.env("RETRO_DIR") || "/opt/retrolinux";
        return rd + "/modules/retroshell/files/scripts/slice_audio.py";
    }
    readonly property string cacheBaseDir: {
        var home = Quickshell.env("HOME") || "/home/" + Quickshell.env("USER") || "/tmp";
        return home + "/.cache/retroshell/typing-sounds";
    }
    readonly property string cachePath: cacheBaseDir + "/" + selectedPackId

    // ── Runtime state ──
    property var currentDefines: ({})
    property var _pendingDefines: ({})
    property var soundMap: ({})
    property var soundKeys: []
    property bool isPreparing: false
    property bool inputToolMissing: false
    property bool notInInputGroup: false
    property string cacheFormatVersion: ""
    property bool cacheFormatReady: false

    // ── Available packs (scanned at startup) ──
    property var availablePacks: []  // [{id, name, path}]

    // ── Keyboard devices ──
    property var availableDevices: [{label: "All Keyboards (Auto)", value: "all"}]

    readonly property string requiredTool: selectedDevicePath === "all" ? "libinput" : "evtest"

    // ── Helper functions ──

    function usableDefines(defines) {
        const result = {};
        for (const keycode of Object.keys(defines || {})) {
            const define = defines[keycode];
            if (define !== null && define !== undefined && define !== "") {
                result[keycode] = define;
            }
        }
        return result;
    }

    function triggerKeySound(keycode) {
        if (!root.enabled || root.isPreparing) return;
        const effect = root.soundMap[keycode.toString()];
        if (effect) {
            effect.play();
        } else {
            const fallback = root.soundMap["57"];
            if (fallback) fallback.play();
        }
    }

    function triggerMouseSound() {
        root.triggerKeySound("30");
    }

    function saveSetting(key, value) {
        // Update local stored property directly — this does NOT trigger
        // the Config FileView write, so no adapter flickering
        if (key === "enabled") root.enabled = value;
        else if (key === "volume") root.volume = value;
        else if (key === "mouseEnabled") root.mouseEnabled = value;
        else if (key === "selectedPackId") root.selectedPackId = value;
        else if (key === "selectedDevicePath") root.selectedDevicePath = value;

        // Write to Config for persistence
        if (Config.typingSounds) {
            Config.typingSounds[key] = value;
            Config.saveTypingSounds();
        }
    }

    // ── Tool availability checks ──

    function checkTools() {
        toolCheck.running = true;
        groupCheck.running = true;
    }

    Process {
        id: toolCheck
        command: ["sh", "-c", "command -v " + root.requiredTool + " >/dev/null 2>&1"]
        running: false
        onExited: (exitCode) => {
            root.inputToolMissing = (exitCode !== 0);
        }
    }

    Process {
        id: groupCheck
        command: ["sh", "-c", "id -nG | tr ' ' '\\n' | grep -qx input"]
        running: false
        onExited: (exitCode) => {
            root.notInInputGroup = (exitCode !== 0);
        }
    }

    // ── Sound pack scanning ──

    function scanSoundPacks() {
        var script = `
import os, json, sys
res = []
pack_dir = sys.argv[1]
if os.path.exists(pack_dir):
    for d in sorted(os.listdir(pack_dir)):
        dp = os.path.join(pack_dir, d)
        if not os.path.isdir(dp):
            continue
        cfg = os.path.join(dp, 'config.json')
        if os.path.exists(cfg):
            try:
                with open(cfg) as f:
                    name = json.load(f).get('name', d)
                    res.append({"id": d, "name": name, "path": dp})
            except:
                res.append({"id": d, "name": d, "path": dp})
print(json.dumps(res))
`;
        scanPacksProc.command = ["python3", "-c", script, root.soundPacksDir];
        scanPacksProc.running = true;
    }

    Process {
        id: scanPacksProc
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    root.availablePacks = JSON.parse(data.trim());
                } catch(e) {
                    console.warn("[TypingSounds] Failed to parse pack list:", e);
                }
            }
        }
    }

    // ── Device scanning ──

    function scanDevices() {
        var script = `
import os, json, re
include_pattern = "kanata"
exclude_pattern = ["power button", "video bus", "speaker", "headphone",
    "lid switch", "touchpad", "extra buttons", "uinput", "server",
    "hitune", "inphic", "instant", "webcam", "video"]
devs = []
if os.path.exists('/proc/bus/input/devices'):
    with open('/proc/bus/input/devices', encoding='utf-8', errors='replace') as f:
        content = f.read()
    sections = content.strip().split('\\n\\n')
    for section in sections:
        name = ""
        handlers = ""
        for line in section.split('\\n'):
            if line.startswith('N: Name='):
                m = re.search(r'Name="([^"]+)"', line)
                if m: name = m.group(1)
            elif line.startswith('H: Handlers='):
                handlers = line.split('=')[1]
        if name and handlers:
            lower_name = name.lower()
            is_included = include_pattern in lower_name
            is_excluded = any(x in lower_name for x in exclude_pattern)
            if 'kbd' in handlers and (is_included or ('mouse' not in handlers and not is_excluded)):
                event_match = re.search(r'event(\\d+)', handlers)
                if event_match:
                    event_path = "/dev/input/event" + event_match.group(1)
                    devs.append({"label": name + " (" + event_path.split('/')[-1] + ")", "value": event_path})
print(json.dumps(devs))
`;
        scanDevicesProc.command = ["python3", "-c", script];
        scanDevicesProc.running = true;
    }

    Process {
        id: scanDevicesProc
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    var devs = JSON.parse(data.trim());
                    root.availableDevices = [{label: "All Keyboards (Auto)", value: "all"}].concat(devs);
                } catch(e) {
                    console.warn("[TypingSounds] Failed to parse device list:", e);
                }
            }
        }
    }

    // ── Pack loading (single chain: config → cache marker → done) ──

    property bool _chainActive: false

    function loadPack() {
        if (!cacheFormatReady || !selectedPackId) {
            isPreparing = false;
            return;
        }

        // Stop any in-flight processes from a previous loadPack call
        if (cacheCheckProc.running) cacheCheckProc.running = false;
        if (sliceProc.running) sliceProc.running = false;

        console.log("[TypingSounds] Loading pack:", selectedPackId);

        // Fast path: check if cache marker exists via bash (avoids FileView chain delays)
        cacheCheckProc.command = ["sh", "-c",
            "cat '" + cachePath + "/.complete' 2>/dev/null"];
        cacheCheckProc.running = true;
    }

    Process {
        id: cacheCheckProc
        running: false
        property string buffer: ""
        property bool cacheValid: false
        stdout: SplitParser {
            onRead: data => cacheCheckProc.buffer += data
        }
        onExited: (exitCode) => {
            var marker = cacheCheckProc.buffer.trim();
            cacheCheckProc.buffer = "";
            cacheValid = (exitCode === 0 && marker === root.cacheFormatVersion);
            if (cacheValid) {
                console.log("[TypingSounds] Cache valid for:", root.selectedPackId);
            } else {
                console.log("[TypingSounds] Cache missing/outdated for:", root.selectedPackId);
                root.isPreparing = true;
            }
            // Now read the pack config to get defines
            root.currentDefines = {};
            root.soundMap = {};
            root._chainActive = true;
            configFileReader.path = root.selectedPackPath + "/config.json";
        }
    }

    FileView {
        id: configFileReader
        printErrors: false
        onLoaded: {
            try {
                const raw = text();
                if (!raw || raw.trim().length === 0) {
                    console.warn("[TypingSounds] Empty config.json");
                    root._finishPreparing(false);
                    return;
                }
                const config = JSON.parse(raw);
                if (!config || !config.defines) {
                    console.warn("[TypingSounds] Invalid config.json");
                    root._finishPreparing(false);
                    return;
                }
                root._pendingDefines = config.defines;

                if (cacheCheckProc.cacheValid) {
                    // Fast path: cache already verified, load defines directly
                    console.log("[TypingSounds] Loading defines from cache:", root.cachePath);
                    root.currentDefines = root.usableDefines(root._pendingDefines);
                    root.soundKeys = Object.keys(root.currentDefines);
                    root._finishPreparing(true);
                } else {
                    // Slow path: need to check/slice cache
                    console.log("[TypingSounds] Config loaded, checking cache at:", root.cachePath);
                    cacheMarkerReader.path = root.cachePath + "/.complete";
                }
            } catch(e) {
                console.warn("[TypingSounds] Failed to parse config.json:", e);
                root._finishPreparing(false);
            }
        }
        onLoadFailed: {
            console.warn("[TypingSounds] Config file not found:", path);
            root._finishPreparing(false);
        }
    }

    FileView {
        id: cacheMarkerReader
        printErrors: false
        onLoaded: {
            const markerVersion = text().trim();
            if (markerVersion === root.cacheFormatVersion) {
                console.log("[TypingSounds] Cache complete for:", root.selectedPackId);
                root.currentDefines = root.usableDefines(root._pendingDefines);
                root.soundKeys = Object.keys(root.currentDefines);
                root._finishPreparing(true);
            } else {
                console.log("[TypingSounds] Cache outdated (", markerVersion, "vs", root.cacheFormatVersion, "), rebuilding");
                sliceProc.command = [
                    "python3", root.sliceScript,
                    "--pack-dir", root.selectedPackPath,
                    "--cache-dir", root.cachePath
                ];
                sliceProc.running = true;
            }
        }
        onLoadFailed: {
            console.log("[TypingSounds] No cache found, slicing:", root.selectedPackId);
            sliceProc.command = [
                "python3", root.sliceScript,
                "--pack-dir", root.selectedPackPath,
                "--cache-dir", root.cachePath
            ];
            sliceProc.running = true;
        }
    }

    function _finishPreparing(success) {
        _chainActive = false;
        isPreparing = false;
        if (success) {
            console.log("[TypingSounds] Pack loaded, defines:", Object.keys(currentDefines).length, "soundMap:", Object.keys(soundMap).length);
            _startInputMonitor();
        } else {
            console.log("[TypingSounds] Pack load failed");
        }
    }

    function _startInputMonitor() {
        if (root.enabled && !root.inputToolMissing && !root.notInInputGroup && !inputProc.running) {
            console.log("[TypingSounds] Starting input monitor");
            inputProc.running = true;
        }
    }

    // ── Slice process ──

    Process {
        id: sliceProc
        running: false
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim()) {
                    console.error("[TypingSounds] Slicing details:", text.trim());
                }
            }
        }
        onExited: (exitCode) => {
            if (exitCode === 0) {
                console.log("[TypingSounds] Slicing succeeded");
                root.currentDefines = root.usableDefines(root._pendingDefines);
                root.soundKeys = Object.keys(root.currentDefines);
                root._finishPreparing(true);
            } else {
                console.error("[TypingSounds] Slicing failed:", exitCode);
                root._finishPreparing(false);
            }
        }
    }

    // ── Dynamic sound effect loading ──

    Item {
        id: soundLoaderContainer
        visible: false
        Repeater {
            id: soundRepeater
            model: root.soundKeys
            delegate: SoundEffectWrapper {
                keycode: modelData
                sourcePath: "file://" + root.cachePath + "/" + modelData + ".wav"
                volumeValue: Math.min(root.volume / 200.0, 1.0)

                Component.onCompleted: {
                    root.soundMap[keycode] = this;
                }
                Component.onDestruction: {
                    delete root.soundMap[keycode];
                }
            }
        }
    }

    // ── Input monitoring ──

    Process {
        id: inputProc
        command: {
            const cmd = root.selectedDevicePath === "all"
                ? ["libinput", "debug-events", "--show-keycodes"]
                : ["evtest", root.selectedDevicePath];
            return cmd;
        }
        running: false

        onRunningChanged: {
            console.log("[TypingSounds] inputProc running:", running);
        }
        onExited: (exitCode) => {
            console.log("[TypingSounds] inputProc exited with code:", exitCode);
            // Auto-restart if it was killed externally (not by us disabling)
            if (root.enabled && !root.isPreparing && exitCode !== 0) {
                console.log("[TypingSounds] inputProc crashed, restarting in 1s");
                restartTimer.start();
            }
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.includes("EV_KEY")) {
                    const keyMatch = data.match(/code\s+(\d+)/);
                    if (keyMatch && data.includes("value 1")) {
                        const code = parseInt(keyMatch[1]);
                        if (code >= 272 && code <= 287) {
                            if (root.mouseEnabled) root.triggerMouseSound();
                        } else {
                            root.triggerKeySound(code);
                        }
                    }
                } else if (data.includes("KEYBOARD_KEY")) {
                    const keyMatch = data.match(/\((\d+)\)/);
                    if (keyMatch && data.includes("pressed")) {
                        root.triggerKeySound(keyMatch[1]);
                    }
                } else if (root.mouseEnabled && data.includes("POINTER_BUTTON")) {
                    if (data.includes("pressed")) root.triggerMouseSound();
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim())
                    console.warn("[TypingSounds] inputProc stderr:", text.trim());
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.enabled && !inputProc.running) {
                console.log("[TypingSounds] Auto-restarting input monitor");
                inputProc.running = true;
            }
        }
    }

    // ── Cache format version (read once at startup) ──

    FileView {
        id: cacheVersionReader
        printErrors: false
        path: root.sliceScript.replace("slice_audio.py", "cache_format.json")
        onLoaded: {
            try {
                root.cacheFormatVersion = JSON.parse(text()).version.toString();
                root.cacheFormatReady = true;
                console.log("[TypingSounds] Cache format version:", root.cacheFormatVersion);
                root._syncFromConfig();
                root.loadPack();
            } catch(e) {
                console.error("[TypingSounds] Failed to read cache format:", e);
                root.cacheFormatVersion = "4";
                root.cacheFormatReady = true;
                root._syncFromConfig();
                root.loadPack();
            }
        }
        onLoadFailed: {
            console.warn("[TypingSounds] Missing cache_format.json, defaulting to v4");
            root.cacheFormatVersion = "4";
            root.cacheFormatReady = true;
            root._syncFromConfig();
            root.loadPack();
        }
    }

    // ── React to config changes ──

    // React to Config becoming ready — this is the primary sync trigger
    // on startup, replacing the unreliable timer-based approach.
    Connections {
        target: Config
        function onTypingSoundsReadyChanged() {
            if (Config.typingSoundsReady) {
                console.log("[TypingSounds] Config ready, syncing");
                root._syncFromConfig();
                root.checkTools();
                if (root.enabled) {
                    if (root.cacheFormatReady && Object.keys(root.currentDefines).length === 0) {
                        root.loadPack();
                    } else if (Object.keys(root.currentDefines).length > 0) {
                        root._startInputMonitor();
                    }
                }
            }
        }
    }

    onSelectedPackIdChanged: {
        console.log("[TypingSounds] Pack changed to:", selectedPackId);
        loadPack();
    }

    onEnabledChanged: {
        console.log("[TypingSounds] enabled changed to:", enabled);
        if (enabled) {
            checkTools();
            if (cacheFormatReady && Object.keys(currentDefines).length === 0) {
                loadPack();
            } else {
                _startInputMonitor();
            }
        } else {
            if (inputProc.running) inputProc.running = false;
        }
    }

    // Periodically re-sync from config to catch external edits (e.g. from GTK settings app)
    Timer {
        id: configSyncTimer
        interval: 5000
        repeat: true
        running: true
        onTriggered: root._syncFromConfig()
    }

    // Re-check config after a short delay in case the adapter loads late.
    Timer {
        id: lateInitTimer
        interval: 3000
        repeat: false
        running: true
        onTriggered: {
            root._syncFromConfig();
            if (root.enabled) {
                root.checkTools();
                if (root.cacheFormatReady && Object.keys(root.currentDefines).length === 0) {
                    root.loadPack();
                }
                root._startInputMonitor();
            }
        }
    }

    // ── Init ──

    Component.onCompleted: {
        // Sync initial values from Config
        _syncFromConfig();
        console.log("[TypingSounds] Service init, pack:", selectedPackId, "enabled:", enabled);
        checkTools();
        scanSoundPacks();
        scanDevices();
        // cacheVersionReader auto-loads via its path binding → triggers loadPack()
    }
}
