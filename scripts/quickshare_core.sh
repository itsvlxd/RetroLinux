#!/bin/bash

RETRO_DIR="${RETRO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "quickshare"

QS_PY="$RETRO_DIR/scripts/python/quickshare_receive.py"
QS_PYTHON="${QS_PYTHON:-python3}"
QS_SETTINGS="$HOME/.config/retro/quickshare.json"
QS_PIDFILE="/tmp/.quickshare.pid"
QS_LEGACY_PIDFILE="/tmp/.rquickshare.pid"
QS_DEFAULT_DIR="$HOME/Downloads"

qs_pid() {
    if [[ -f $QS_PIDFILE ]] && kill -0 "$(cat "$QS_PIDFILE" 2>/dev/null)" 2>/dev/null; then
        cat "$QS_PIDFILE"
        return 0
    fi
    pgrep -f "quickshare_[r]eceive" 2>/dev/null | head -1
}

qs_running() {
    [[ -n $(qs_pid) ]] && return 0 || return 1
}

qs_read_setting() {
    local key="$1"
    local val=""
    if [[ -f $QS_SETTINGS ]] && command -v jq >/dev/null 2>&1; then
        val=$(jq -r ".$key // empty" "$QS_SETTINGS" 2>/dev/null)
    fi
    echo "$val"
}

qs_write_settings() {
    local dir="$1"
    local auto="$2"
    local settings_dir
    settings_dir=$(dirname "$QS_SETTINGS")
    mkdir -p "$settings_dir"
    cat >"$QS_SETTINGS" <<EOF
{
	"download_path": "$dir",
	"auto_accept": $auto
}
EOF
}

qs_get_dir() {
    local dir
    dir=$(get_var "QUICKSHARE_DOWNLOAD_DIR" "")
    if [[ -z $dir ]]; then
        dir=$(qs_read_setting "download_path")
    fi
    [[ -z $dir || $dir == "null" ]] && dir="$QS_DEFAULT_DIR"
    echo "$dir"
}

qs_get_auto_accept() {
    local auto
    auto=$(get_var "QUICKSHARE_AUTO_ACCEPT" "")
    if [[ -z $auto ]]; then
        auto=$(qs_read_setting "auto_accept")
    fi
    [[ $auto != "true" ]] && echo "false" || echo "true"
}

qs_dir_configured() {
    local val
    val=$(get_var "QUICKSHARE_DOWNLOAD_DIR" "")
    if [[ -z $val ]]; then
        val=$(qs_read_setting "download_path")
    fi
    if [[ -z $val || $val == "null" ]]; then
        echo "false"
    else
        echo "true"
    fi
}

qs_get_autostart() {
    echo "true"
}

qs_start() {
    set_var "QUICKSHARE_ENABLED" "true"
    if qs_running; then
        echo "OK|already_running|$(qs_pid)"
        return 0
    fi
    if ! command -v "$QS_PYTHON" >/dev/null 2>&1; then
        rx_log_file "error" "python3 not found — cannot start Quick Share receiver"
        echo "ERR|python_not_found"
        return 1
    fi

    local dir auto args
    dir=$(qs_get_dir)
    auto=$(qs_get_auto_accept)
    args=(--dir "$dir")
    [[ $auto == "true" ]] && args+=(--yes)

    nohup env DISPLAY="$DISPLAY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" RETRO_DIR="$RETRO_DIR" \
        "$QS_PYTHON" "$QS_PY" "${args[@]}" >/dev/null 2>&1 &
    local pid=$!
    echo "$pid" >"$QS_PIDFILE"

    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        rx_log_file "info" "Quick Share receiver started (PID: $pid, dir: $dir)"
        echo "OK|$pid"
    else
        rm -f "$QS_PIDFILE"
        rx_log_file "error" "Quick Share receiver failed to start"
        echo "ERR|start_failed"
        return 1
    fi
}

qs_stop() {
    set_var "QUICKSHARE_ENABLED" "false"
    local pid
    pid=$(qs_pid)
    if [[ -n $pid ]]; then
        kill "$pid" 2>/dev/null
        for _ in $(seq 1 20); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -9 "$pid" 2>/dev/null
    fi
    pkill -f "quickshare_[s]end.py" 2>/dev/null
    rm -f "$QS_PIDFILE" "$QS_LEGACY_PIDFILE"
    rx_log_file "info" "Quick Share receiver stopped"
    echo "OK|stopped"
}

qs_set_dir() {
    local new_dir="${1:-$QS_DEFAULT_DIR}"
    [[ -z $new_dir ]] && { echo "ERR|empty_path"; return 1; }
    mkdir -p "$new_dir" 2>/dev/null
    set_var "QUICKSHARE_DOWNLOAD_DIR" "$new_dir"
    qs_write_settings "$new_dir" "$(qs_get_auto_accept)"
    rx_log_file "info" "Quick Share download dir set to $new_dir"
    echo "OK|$new_dir"
}

qs_set_dir_interactive() {
    if ! command -v zenity >/dev/null 2>&1; then
        rx_log_file "error" "zenity not found — cannot open folder picker"
        echo "ERR|zenity_not_found"
        return 1
    fi
    local result_file="/tmp/.qs_zenity_dir_$$"
    rm -f "$result_file"
    if [[ -n $WAYLAND_DISPLAY ]]; then
        GDK_BACKEND=wayland zenity --file-selection --directory --title="Select Quick Share Download Folder" >"$result_file" 2>/dev/null &
    else
        zenity --file-selection --directory --title="Select Quick Share Download Folder" >"$result_file" 2>/dev/null &
    fi
    local zenity_pid=$!
    _qs_zenity_float "$zenity_pid"
    wait "$zenity_pid"
    local dir_path
    dir_path=$(cat "$result_file" 2>/dev/null)
    rm -f "$result_file"

    if [[ -z $dir_path ]]; then
        echo "ERR|canceled"
        return 1
    fi
    qs_set_dir "$dir_path"
}

qs_pick_file() {
    if ! command -v zenity >/dev/null 2>&1; then
        rx_log_file "error" "zenity not found — cannot open file picker"
        echo "ERR|zenity_not_found"
        return 1
    fi
    local result_file="/tmp/.qs_zenity_file_$$"
    rm -f "$result_file"
    if [[ -n $WAYLAND_DISPLAY ]]; then
        GDK_BACKEND=wayland zenity --file-selection --title="Select a file to send via Quick Share" >"$result_file" 2>/dev/null &
    else
        zenity --file-selection --title="Select a file to send via Quick Share" >"$result_file" 2>/dev/null &
    fi
    local zenity_pid=$!
    _qs_zenity_float "$zenity_pid"
    wait "$zenity_pid"
    local file_path
    file_path=$(cat "$result_file" 2>/dev/null)
    rm -f "$result_file"

    if [[ -z $file_path ]]; then
        echo "ERR|canceled"
        return 1
    fi
    echo "OK|$file_path"
    return 0
}

_qs_hyprctl() {
    if [[ -z $HYPRLAND_INSTANCE_SIGNATURE ]]; then
        local sig
        sig=$(ls -t "${XDG_RUNTIME_DIR:-/tmp}/hypr/" 2>/dev/null | head -1)
        [[ -n $sig ]] && export HYPRLAND_INSTANCE_SIGNATURE="$sig"
    fi
    hyprctl "$@"
}

_qs_zenity_float() {
    local zenity_pid="$1"
    local tries=0
    local addr=""
    while [[ $tries -lt 120 && -z $addr ]]; do
        sleep 0.05
        addr=$(_qs_hyprctl clients -j 2>/dev/null | jq -r '.[] | select((.class == "xdg-desktop-portal-gtk") or (.class == "zenity") or (.title | test("Select a file|Quick Share"; "i"))) | .address' | head -1)
        ((tries++))
    done
    if [[ -n $addr ]]; then
        _qs_hyprctl dispatch 'hl.dsp.window.float({ action = "enable", window = "address:'"$addr"'" })' >/dev/null 2>&1
        _qs_hyprctl dispatch 'hl.dsp.window.center({ window = "address:'"$addr"'" })' >/dev/null 2>&1
        local confirmed=0
        while [[ $confirmed -lt 10 ]]; do
            local fl
            fl=$(_qs_hyprctl clients -j 2>/dev/null | jq -r --arg a "$addr" '.[] | select(.address == $a) | .floating' | head -1)
            [[ $fl == "true" ]] && break
            sleep 0.1
            _qs_hyprctl dispatch 'hl.dsp.window.float({ action = "enable", window = "address:'"$addr"'" })' >/dev/null 2>&1
            ((confirmed++))
        done
    fi
}

qs_set_auto_accept() {
    local state="${1:-false}"
    case "$state" in
        on|true|enable|1) state="true" ;;
        off|false|disable|0) state="false" ;;
        *) { echo "ERR|invalid_state"; return 1; } ;;
    esac
    set_var "QUICKSHARE_AUTO_ACCEPT" "$state"
    qs_write_settings "$(qs_get_dir)" "$state"
    rx_log_file "info" "Quick Share auto-accept set to $state"
    echo "OK|$state"
}

qs_restart() {
    qs_stop >/dev/null 2>&1
    qs_start
}

qs_status() {
    local state="stopped"
    local pid=""
    if qs_running; then
        state="running"
        pid=$(qs_pid)
    fi
    echo "$state|$(qs_get_dir)|$(qs_get_autostart)|${pid}|$(qs_get_auto_accept)"
}

qs_enabled_status() {
    local val
    val=$(get_var "QUICKSHARE_ENABLED" "true")
    [[ $val != "false" ]] && echo "true" || echo "false"
}

qs_set_enabled() {
    local state="${1:-true}"
    case "$state" in
        on|true|enable|1) state="true" ;;
        off|false|disable|0) state="false" ;;
        *) { echo "ERR|invalid_state"; return 1; } ;;
    esac
    set_var "QUICKSHARE_ENABLED" "$state"
    echo "OK|$state"
}

qs_scan() {
    python3 "$RETRO_DIR/scripts/python/quickshare_scan.py"
}

qs_send() {
    local ip="$1"
    local port="$2"
    local file_path="$3"
    [[ -z $ip || -z $port || -z $file_path ]] && { echo "ERR|missing_args"; return 1; }
    [[ ! -f $file_path ]] && { echo "ERR|file_not_found"; return 1; }
    rx_log_file "info" "Sending $file_path to $ip:$port"
    exec python3 "$RETRO_DIR/scripts/python/quickshare_send.py" "$file_path" --target "$ip:$port"
}

qs_cancel_receive() {
    local payload_id="$1"
    [[ -z $payload_id ]] && { echo "ERR|missing_id"; return 1; }
    mkdir -p /tmp/retro_logs/quickshare_cancel
    touch "/tmp/retro_logs/quickshare_cancel/$payload_id"
    rx_log_file "warn" "Cancel requested for receive transfer $payload_id"
    echo "OK|$payload_id"
}

qs_clear_transfer() {
    local payload_id="$1"
    [[ -z $payload_id ]] && { echo "ERR|missing_id"; return 1; }
    mkdir -p /tmp/retro_logs/quickshare_clear
    touch "/tmp/retro_logs/quickshare_clear/$payload_id"
    echo "OK|$payload_id"
}

qs_clear_send() {
    local pid="$1"
    [[ -z $pid ]] && { echo "ERR|missing_id"; return 1; }
    python3 - "$pid" <<'PY'
import json, os, sys
path = "/tmp/retro_logs/quickshare_send_transfers.json"
pid = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    data = {"transfers": []}
data["transfers"] = [e for e in data.get("transfers", []) if str(e.get("id")) != pid and str(e.get("pid")) != pid]
try:
    tmp = path + ".tmp"
    json.dump(data, open(tmp, "w"))
    os.replace(tmp, path)
except Exception:
    pass
PY
    echo "OK|$pid"
}

qs_accept_offer() {
    local offer_id="$1"
    local decision="$2"
    [[ -z $offer_id ]] && { echo "ERR|missing_id"; return 1; }
    case "$decision" in
        accept|deny) ;;
        *) { echo "ERR|invalid_decision"; return 1; } ;;
    esac
    mkdir -p /tmp/retro_logs/quickshare_decision
    echo "$decision" >"/tmp/retro_logs/quickshare_decision/$offer_id"
    echo "OK|$offer_id"
}

case "$1" in
    --status) qs_status ;;
    --dir-configured) qs_dir_configured ;;
    --auto-accept-status) qs_get_auto_accept ;;
    --enabled-status) qs_enabled_status ;;
    --set-enabled) qs_set_enabled "$2" ;;
    --start) qs_start ;;
    --stop) qs_stop ;;
    --restart) qs_restart ;;
    --set-dir) qs_set_dir "$2" ;;
    --set-dir-interactive) qs_set_dir_interactive ;;
    --pick-file) qs_pick_file ;;
    --scan) qs_scan ;;
    --send) qs_send "$2" "$3" "$4" ;;
    --cancel-receive) qs_cancel_receive "$2" ;;
    --clear-transfer) qs_clear_transfer "$2" ;;
    --clear-send) qs_clear_send "$2" ;;
    --accept-offer) qs_accept_offer "$2" "$3" ;;
    --auto-accept) qs_set_auto_accept "${2:-false}" ;;
    *)
        echo "ERROR: Usage: quickshare_core.sh <--status|--start|--stop|--set-dir PATH|--auto-accept on|off>"
        exit 1
        ;;
esac
