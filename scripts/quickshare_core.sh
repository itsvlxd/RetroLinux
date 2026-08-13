#!/bin/bash

RETRO_DIR="${RETRO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "quickshare"

QS_BIN="rquickshare"
QS_SETTINGS="$HOME/.local/share/dev.mandre.rquickshare/.settings.json"
QS_AUTOSTART="$HOME/.config/autostart/rquickshare.desktop"
QS_PIDFILE="/tmp/.rquickshare.pid"
QS_DEFAULT_DIR="$HOME/Downloads"

qs_running() {
    if [[ -f $QS_PIDFILE ]] && kill -0 "$(cat "$QS_PIDFILE" 2>/dev/null)" 2>/dev/null; then
        return 0
    fi
    pgrep -x rquickshare >/dev/null 2>&1
}

qs_get_pid() {
    if [[ -f $QS_PIDFILE ]] && kill -0 "$(cat "$QS_PIDFILE" 2>/dev/null)" 2>/dev/null; then
        cat "$QS_PIDFILE"
    else
        pgrep -x rquickshare 2>/dev/null | head -1
    fi
}

qs_get_dir() {
    local dir=""
    if [[ -f $QS_SETTINGS ]] && command -v jq >/dev/null 2>&1; then
        dir=$(jq -r '.download_path // ""' "$QS_SETTINGS" 2>/dev/null)
    fi
    [[ -z $dir || $dir == "null" ]] && dir="$QS_DEFAULT_DIR"
    echo "$dir"
}

qs_get_autostart() {
    [[ -f $QS_AUTOSTART ]] && echo "true" || echo "false"
}

qs_start() {
    if qs_running; then
        echo "OK|already_running|$(qs_get_pid)"
        return 0
    fi
    if ! command -v "$QS_BIN" >/dev/null 2>&1; then
        rx_log_file "error" "rquickshare binary not found — install r-quick-share (AUR)"
        echo "ERR|binary_not_found"
        return 1
    fi

    nohup env DISPLAY="$DISPLAY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" "$QS_BIN" >/dev/null 2>&1 &
    local pid=$!
    echo "$pid" >"$QS_PIDFILE"

    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        rx_log_file "info" "rquickshare started (PID: $pid)"
        echo "OK|$pid"
    else
        rm -f "$QS_PIDFILE"
        rx_log_file "error" "rquickshare failed to start"
        echo "ERR|start_failed"
        return 1
    fi
}

qs_stop() {
    if ! qs_running; then
        rm -f "$QS_PIDFILE"
        echo "OK|already_stopped"
        return 0
    fi
    pkill -x rquickshare 2>/dev/null
    rm -f "$QS_PIDFILE"
    rx_log_file "info" "rquickshare stopped"
    echo "OK|stopped"
}

qs_set_dir() {
    local new_dir="${1:-$QS_DEFAULT_DIR}"
    [[ -z $new_dir ]] && { echo "ERR|empty_path"; return 1; }
    mkdir -p "$new_dir" 2>/dev/null

    local settings_dir
    settings_dir=$(dirname "$QS_SETTINGS")
    mkdir -p "$settings_dir"

    if [[ ! -f $QS_SETTINGS ]] || ! command -v jq >/dev/null 2>&1; then
        cat >"$QS_SETTINGS" <<EOF
{
	"download_path": "$new_dir"
}
EOF
    else
        jq --arg d "$new_dir" '.download_path = $d' "$QS_SETTINGS" >"$QS_SETTINGS.tmp" 2>/dev/null \
            && mv "$QS_SETTINGS.tmp" "$QS_SETTINGS"
    fi
    rx_log_file "info" "QuickShare download dir set to $new_dir"
    echo "OK|$new_dir"
}

qs_set_autostart() {
    local state="${1:-true}"
    case "$state" in
        on|true|enable|1) state="true" ;;
        off|false|disable|0) state="false" ;;
        *) { echo "ERR|invalid_state"; return 1; } ;;
    esac
    if [[ $state == "true" ]]; then
        mkdir -p "$(dirname "$QS_AUTOSTART")"
        cat >"$QS_AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=rquickshare
Comment=Android Quick Share receiver
Exec=/usr/bin/rquickshare
Terminal=false
EOF
        rx_log_file "info" "QuickShare autostart enabled"
        echo "OK|enabled"
    else
        rm -f "$QS_AUTOSTART"
        rx_log_file "info" "QuickShare autostart disabled"
        echo "OK|disabled"
    fi
}

qs_status() {
    local state="stopped"
    local pid=""
    if qs_running; then
        state="running"
        pid=$(qs_get_pid)
    fi
    echo "$state|$(qs_get_dir)|$(qs_get_autostart)|${pid}"
}

case "$1" in
    --status) qs_status ;;
    --start) qs_start ;;
    --stop) qs_stop ;;
    --set-dir) qs_set_dir "$2" ;;
    --autostart) qs_set_autostart "${2:-true}" ;;
    *)
        echo "ERROR: Usage: quickshare_core.sh <--status|--start|--stop|--set-dir PATH|--autostart on|off>"
        exit 1
        ;;
esac
