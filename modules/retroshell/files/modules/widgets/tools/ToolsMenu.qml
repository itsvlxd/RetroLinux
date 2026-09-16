import QtQuick
import qs.modules.components
import qs.modules.theme
import qs.modules.globals
import Quickshell.Io

import qs.modules.services
import qs.config

ActionGrid {
    id: root

    signal itemSelected

    function recheck() {
        Shazam.recheck();
        Tesseract.recheck();
    }

    QtObject {
        id: recordAction
        property string icon: ScreenRecorder.isRecording ? Icons.stop : Icons.recordScreen
        property string text: ScreenRecorder.isRecording ? ScreenRecorder.duration : ""
        property string tooltip: ScreenRecorder.isRecording ? "Stop Recording" : "Screen Recorder"
        property string command: ""
        property string variant: ScreenRecorder.isRecording ? "error" : "primary"
        property string type: "button"
    }

    QtObject {
        id: shazamAction
        property string icon: Shazam.isListening ? Icons.stop : Icons.equalizer
        property var image: Shazam.isListening ? "" : Qt.resolvedUrl("../../../assets/Shazam_icon.svg")
        property string text: Shazam.isListening ? "Listening" : ""
        property string tooltip: Shazam.isListening ? "Stop Shazam" : "Shazam"
        property string command: ""
        property string variant: Shazam.isListening ? "error" : "primary"
        property string type: "button"
    }

    QtObject {
        id: ocrAction
        property string icon: Icons.textT
        property string tooltip: "OCR"
        property string command: ""
        property string type: "button"
    }

    layout: "row"
    buttonSize: 48
    iconSize: 20
    spacing: 8

    function itemFor(id) {
        switch (id) {
        case "separator":
            return { type: "separator" };
        case "screenshot":
            return { icon: Icons.camera, tooltip: "Screenshot", command: "" };
        case "screenshots":
            return { icon: Icons.screenshots, tooltip: "Open Screenshots", command: "" };
        case "recorder":
            return recordAction;
        case "recordings":
            return { icon: Icons.recordings, tooltip: "Open Recordings", command: "" };
        case "colorpicker":
            return { icon: Icons.picker, tooltip: "Color Picker", command: "" };
        case "ocr":
            return Tesseract.available ? ocrAction : null;
        case "qr":
            return { icon: Icons.qrCode, tooltip: "QR Code", command: "" };
        case "lens":
            return { icon: Icons.google, tooltip: "Google Lens", command: "" };
        case "shazam":
            return Shazam.available ? shazamAction : null;
        case "webcam":
            return {
                icon: GlobalStates.webcamOverlayVisible ? Icons.webcamSlash : Icons.webcam,
                tooltip: "Webcam Overlay",
                command: ""
            };
        case "docker":
            return { icon: Icons.docker, tooltip: "Docker Manager", command: "" };
        }
        return null;
    }

    actions: {
        const order = (Config.bar && Config.bar.toolboxOrder)
            ? Config.bar.toolboxOrder : ["screenshot", "screenshots", "separator", "recorder", "recordings", "separator", "colorpicker", "ocr", "qr", "lens", "shazam", "webcam", "docker"];
        const result = [];
        for (let i = 0; i < order.length; i++) {
            const item = itemFor(order[i]);
            if (item)
                result.push(item);
        }
        return result;
    }

    Process {
        id: colorPickerProc
    }

    Process {
        id: ocrProc
    }

    Process {
        id: qrProc
    }

    Process {
        id: openFolderProc
        // Usamos nohup para desvincular el proceso de visualización de carpetas
        command: ["bash", "-c", "nohup xdg-open \"$0\" > /dev/null 2>&1 &"]
    }

    property Timer screenshotDelay: Timer {
        interval: 100
        repeat: false
        onTriggered: GlobalStates.screenshotToolVisible = true
    }

    onActionTriggered: action => {
        console.log("Tools action triggered:", action.tooltip);

        if (action.tooltip === "Screenshot") {
            Screenshot.initialize();
            root.itemSelected();
            screenshotDelay.start();
        } else if (action.tooltip === "Screen Recorder") {
            ScreenRecorder.initialize();
            GlobalStates.screenRecordToolVisible = true;
            root.itemSelected();
        } else if (action.tooltip === "Stop Recording") {
            ScreenRecorder.toggleRecording();
            root.itemSelected();
        } else if (action.tooltip === "Open Screenshots") {
            // Usamos xdg-user-dir en el comando bash para respetar las rutas del sistema
            var cmd = "dir=\"$(xdg-user-dir PICTURES)/Screenshots\"; mkdir -p \"$dir\"; nohup xdg-open \"$dir\" > /dev/null 2>&1 &";
            
            openFolderProc.command = ["bash", "-c", cmd];
            openFolderProc.running = true;
            
            root.itemSelected();
        } else if (action.tooltip === "Open Recordings") {
            // Usamos xdg-user-dir para videos, manteniendo la subcarpeta Recordings
            var cmd = "dir=\"$(xdg-user-dir VIDEOS)/Recordings\"; mkdir -p \"$dir\"; nohup xdg-open \"$dir\" > /dev/null 2>&1 &";
            
            openFolderProc.command = ["bash", "-c", cmd];
            openFolderProc.running = true;
            
             root.itemSelected();
        } else if (action.tooltip === "Color Picker") {
            var scriptPath = Qt.resolvedUrl("../../../scripts/colorpicker.py").toString().replace("file://", "");
            // Run detached so it survives when the menu closes
            colorPickerProc.command = ["bash", "-c", "nohup python3 \"" + scriptPath + "\" > /dev/null 2>&1 &"];
            colorPickerProc.running = true;
            root.itemSelected();
        } else if (action.tooltip === "OCR") {
            var scriptPath = Qt.resolvedUrl("../../../scripts/ocr.sh").toString().replace("file://", "");
            
            // Build languages string from Config
            var ocrConfig = Config.system.ocr;
            var langs = [];
            
            if (ocrConfig) {
                if (ocrConfig.eng !== false) langs.push("eng"); // Default true
                if (ocrConfig.spa !== false) langs.push("spa"); // Default true
                if (ocrConfig.lat === true) langs.push("lat");
                if (ocrConfig.jpn === true) langs.push("jpn");
                if (ocrConfig.chi_sim === true) langs.push("chi_sim");
                if (ocrConfig.chi_tra === true) langs.push("chi_tra");
                if (ocrConfig.kor === true) langs.push("kor");
                if (ocrConfig.deu === true) langs.push("deu");
                if (ocrConfig.fra === true) langs.push("fra");
                if (ocrConfig.pol === true) langs.push("pol");
                if (ocrConfig.ron === true) langs.push("ron");
                if (ocrConfig.swe === true) langs.push("swe");
            } else {
                langs = ["eng", "spa"];
            }
            
            if (langs.length === 0) langs.push("eng");
            var langString = langs.join("+");

            ocrProc.command = ["bash", "-c", "nohup \"" + scriptPath + "\" \"" + langString + "\" > /dev/null 2>&1 &"];
            ocrProc.running = true;
            root.itemSelected();
        } else if (action.tooltip === "QR Code") {
            var scriptPath = Qt.resolvedUrl("../../../scripts/qr_scan.sh").toString().replace("file://", "");
            qrProc.command = ["bash", "-c", "nohup \"" + scriptPath + "\" > /dev/null 2>&1 &"];
            qrProc.running = true;
            root.itemSelected();
        } else if (action.tooltip === "Google Lens") {
            Screenshot.initialize();
            Screenshot.captureMode = "lens";
            root.itemSelected();
            screenshotDelay.start();
        } else if (action.tooltip === "Shazam") {
            Shazam.startListening();
            root.itemSelected();
        } else if (action.tooltip === "Stop Shazam") {
            Shazam.stopListening();
            root.itemSelected();
        } else if (action.tooltip === "Webcam Overlay") {
            GlobalStates.webcamOverlayVisible = !GlobalStates.webcamOverlayVisible;
        } else if (action.tooltip === "Docker Manager") {
            DockerService.refresh();
            root.itemSelected();
        }
    }
}
