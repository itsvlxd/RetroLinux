pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    function _eval(luaCode) {
        var proc = Qt.createQmlObject('import Quickshell.Io; Process {}', root)
        proc.command = ["hyprctl", "eval", luaCode]
        proc.onExited.connect(function() { proc.destroy() })
        proc.running = true
    }

    function focusWorkspace(id) {
        _eval('hl.dispatch(hl.dsp.focus({ workspace = "' + id + '" }))')
    }

    function focusWindow(address) {
        _eval('hl.dispatch(hl.dsp.focus({ window = "address:' + address + '" }))')
    }

    function closeWindow(address) {
        _eval('hl.dispatch(hl.dsp.window.close({ window = "address:' + address + '" }))')
    }

    function moveWindowToWorkspace(address, workspaceId) {
        _eval('hl.dispatch(hl.dsp.window.move({ workspace = ' + workspaceId + ', window = "address:' + address + '" }))')
    }

    function moveWindowPixel(address, xPercent, yPercent) {
        _eval('hl.dispatch(hl.dsp.movewindowpixel({ exact = "' + xPercent + '% ' + yPercent + '%" }))')
    }

    function toggleSpecialWorkspace(name) {
        if (name) {
            _eval("hl.dispatch(hl.dsp.workspace.toggle_special('" + name + "'))")
        } else {
            _eval("hl.dispatch(hl.dsp.workspace.toggle_special())")
        }
    }

    function toggleFullscreen() {
        _eval("hl.dispatch(hl.dsp.window.fullscreen({}))")
    }

    function focusMonitor(monitorId) {
        _eval("hl.dispatch(hl.dsp.focus({ monitor = '" + monitorId + "' }))")
    }
}
