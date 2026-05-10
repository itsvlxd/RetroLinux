#!/bin/bash

BAT_PATH=$(find /sys/class/power_supply/ -name "BAT*" -type l 2>/dev/null | head -n 1)
AC_PATH=$(find /sys/class/power_supply/ \( -name "AC*" -o -name "ADP*" \) -type l 2>/dev/null | head -n 1)

has_battery() {
    [[ -n "$BAT_PATH" && -d "$BAT_PATH" ]] && echo "true" || echo "false"
}

is_on_battery() {
    [[ $(has_battery) != "true" ]] && echo "false" && return

    if [[ -n "$AC_PATH" ]]; then
        local ac_online=$(cat "$AC_PATH/online" 2>/dev/null || echo "1")
        [[ $ac_online -eq 0 ]] && echo "true" && return
    fi

    local ucsi_source=$(find /sys/class/power_supply/ -name "ucsi-source-psy-*" -type l 2>/dev/null | head -1)
    if [[ -n "$ucsi_source" ]]; then
        local ucsi_online=$(cat "$ucsi_source/online" 2>/dev/null || echo "1")
        [[ $ucsi_online -eq 0 ]] && echo "true" && return
    fi

    if grep -q "Discharging" /sys/class/power_supply/BAT*/status 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

get_bat_status() {
    [[ $(has_battery) != "true" ]] && echo "unknown" && return

    local ucsi_source=$(find /sys/class/power_supply/ -name "ucsi-source-psy-*" -type l 2>/dev/null | head -1)
    local ucsi_online=1
    if [[ -n "$ucsi_source" ]]; then
        ucsi_online=$(cat "$ucsi_source/online" 2>/dev/null || echo "1")
    fi

    if [[ -n "$AC_PATH" ]]; then
        local ac_online=$(cat "$AC_PATH/online" 2>/dev/null || echo "0")
        [[ $ac_online -eq 0 && $ucsi_online -eq 0 ]] && echo "discharging" && return
    fi

    if [[ $ucsi_online -eq 0 ]]; then
        echo "discharging"
        return
    fi

    local bat_status
    bat_status=$(cat "$BAT_PATH/status" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [[ -n "$bat_status" ]] && echo "$bat_status"
}