#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/variable.sh"

rx_format_time() {
    local T=$1
    [[ -z $T || $T == "null" ]] && echo "Disabled" && return

    if ((T < 60)); then
        echo "${T} seconds"
    elif ((T < 3600)); then
        echo "$((T / 60)) minutes"
    elif ((T < 86400)); then
        echo "$((T / 3600)) hours"
    elif ((T < 604800)); then
        echo "$((T / 86400)) days"
    elif ((T < 2592000)); then
        echo "$((T / 604800)) weeks"
    else
        echo "$((T / 2592000)) months"
    fi
}

rx_format_size() {
    local size=$1
    [[ -z $size || $size == "0" ]] && echo "0 B" && return

    local units=('B' 'KB' 'MB' 'GB')
    local i=0

    while (($(echo "$size > 1024" | bc -l) && i < 3)); do
        size=$(echo "scale=2; $size / 1024" | bc -l)
        ((i++))
    done
    echo "${size} ${units[$i]}"
}

rx_format_string() {
    local name="$1"
    name="${name%.*}"
    name="${name//.[0-9]*x[0-9]*/}"
    name="${name//-/ }"
    name="${name//_/ }"

    echo "$name" | sed -E 's/(^| )([a-z])/\1\U\2/g'
}

get_opacity_hex() {
    local base_opacity=$(get_var "RETRO_OPACITY" "1.0")

    [[ $base_opacity == "1.0" ]] && {
        echo "FF"
        return
    }

    local multiplier="${1:-1.0}"

    local opacity_int=$(echo "($base_opacity * $multiplier * 255 + 0.5) / 1" | bc)

    ((opacity_int > 255)) && opacity_int=255
    ((opacity_int < 0)) && opacity_int=0

    printf "%02x" "$opacity_int"
}

get_battery_icon() {
    local cap=$1
    local stat=$2

    [[ $stat == *"charging"* && $stat != *"discharging"* ]] && echo "󱐋" && return

    if ((cap >= 95)); then
        echo "󰁹"
    elif ((cap >= 85)); then
        echo "󰂂"
    elif ((cap >= 75)); then
        echo "󰂁"
    elif ((cap >= 65)); then
        echo "󰂀"
    elif ((cap >= 55)); then
        echo "󰁿"
    elif ((cap >= 45)); then
        echo "󰁾"
    elif ((cap >= 35)); then
        echo "󰁽"
    elif ((cap >= 25)); then
        echo "󰁼"
    elif ((cap >= 15)); then
        echo "󰁻"
    else
        echo "󰂃"
    fi
}

check_dep() {
    local cmd="$1"
    local pkgs="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        local helper=$(get_var "PKG_HELPER")
        : "${helper:="yay"}"
        rx_log "error" "Missing required dependency: ${PINK}$cmd${RESET}"
        rx_confirm "Would you like to install [${GRAY}$pkgs${RESET}] using $helper?" "N" || { rx_log "info" "Dependency required. Aborting."; return 1; }
        
        rx_log "info" "Installing..."
        $helper -S $pkgs
        if ! command -v "$cmd" >/dev/null 2>&1; then
            rx_log "error" "Installation failed or aborted."
            return 1
        fi
    fi
    return 0
}
