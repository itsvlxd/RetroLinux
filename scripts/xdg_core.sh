#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/xdg.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "xdg"

ensure_dirs() {
    local result=$(rx_xdg_ensure_dirs)
    local created=$(echo "$result" | grep -oP 'created=\K[0-9]+')
    rx_log_file "INFO" "XDG directories ensured (${created:-0} created)"
    echo "OK|created=${created:-0}"
}

get_dir() {
    local name="$1"
    [[ -z $name ]] && echo "result=error|reason=no_name" && return 1
    local path=$(rx_xdg_get_dir "$name")
    if [[ -n $path ]]; then
        echo "OK|$path"
    else
        echo "result=error|reason=dir_not_found|name=$name"
        return 1
    fi
}

set_dir() {
    local name="$1"
    local path="$2"
    [[ -z $name || -z $path ]] && echo "result=error|reason=missing_args" && return 1
    local result=$(rx_xdg_set_dir "$name" "$path")
    if [[ $result == OK* ]]; then
        rx_log_file "INFO" "XDG dir set: $name=$path"
        echo "$result"
    else
        echo "result=error|reason=set_failed"
        return 1
    fi
}

list_dirs() {
    rx_xdg_list_dirs
}

set_default() {
    local mime="$1"
    local app="$2"
    [[ -z $mime || -z $app ]] && echo "result=error|reason=missing_args" && return 1
    local result=$(rx_xdg_set_default "$mime" "$app")
    if [[ $result == OK* ]]; then
        rx_log_file "INFO" "Default set: $mime=$app"
        echo "$result"
    else
        echo "$result"
        return 1
    fi
}

get_default() {
    local mime="$1"
    [[ -z $mime ]] && echo "result=error|reason=no_mime" && return 1
    local app=$(rx_xdg_get_default "$mime")
    if [[ -n $app ]]; then
        echo "OK|$app"
    else
        echo "result=error|reason=no_default|mime=$mime"
        return 1
    fi
}

list_defaults() {
    rx_xdg_list_defaults
}

reset_defaults() {
    local result=$(rx_xdg_reset_defaults)
    rx_log_file "INFO" "Default applications reset"
    echo "$result"
}

find_handlers() {
    local mime="$1"
    [[ -z $mime ]] && echo "result=error|reason=no_mime" && return 1
    rx_xdg_find_handlers "$mime"
}

portal_status() {
    local backend=$(rx_xdg_get_portal_backend)
    local running="no"
    pgrep -f "xdg-desktop-portal" >/dev/null 2>&1 && running="yes"
    echo "backend=$backend|running=$running"
}

portal_list() {
    rx_xdg_list_portals
}

portal_set() {
    local backend="$1"
    [[ -z $backend ]] && echo "result=error|reason=no_backend" && return 1
    local result=$(rx_xdg_set_portal_backend "$backend")
    if [[ $result == OK* ]]; then
        rx_log_file "INFO" "Portal backend set to: $backend"
        echo "$result"
    else
        echo "$result"
        return 1
    fi
}

configure_xdg_open() {
    local result=$(rx_xdg_configure_xdg_open)
    if [[ $result == OK* ]]; then
        rx_log_file "INFO" "xdg-open wrapper configured"
        echo "$result"
    else
        echo "$result"
        return 1
    fi
}

bridge_flatpak() {
    if ! command -v flatpak >/dev/null 2>&1; then
        echo "result=error|reason=flatpak_not_installed"
        return 1
    fi
    local result=$(rx_xdg_bridge_flatpak)
    if [[ $result == OK* ]]; then
        rx_log_file "INFO" "Flatpak MIME bridge applied"
        echo "$result"
    else
        echo "result=error|reason=bridge_failed"
        return 1
    fi
}

full_status() {
    echo "===DIRS==="
    rx_xdg_list_dirs
    echo "===DEFAULTS==="
    rx_xdg_list_defaults
    echo "===PORTAL==="
    portal_status
}

case "$1" in
    "--ensure-dirs") ensure_dirs ;;
    "--get-dir") get_dir "$2" ;;
    "--set-dir") set_dir "$2" "$3" ;;
    "--list-dirs") list_dirs ;;
    "--set-default") set_default "$2" "$3" ;;
    "--get-default") get_default "$2" ;;
    "--list-defaults") list_defaults ;;
    "--reset-defaults") reset_defaults ;;
    "--find-handlers") find_handlers "$2" ;;
    "--portal-status") portal_status ;;
    "--portal-list") portal_list ;;
    "--portal-set") portal_set "$2" ;;
    "--configure-xdg-open") configure_xdg_open ;;
    "--bridge-flatpak") bridge_flatpak ;;
    "--status") full_status ;;
esac
