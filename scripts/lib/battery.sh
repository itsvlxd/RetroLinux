#!/bin/bash

BAT_PATH=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)
AC_PATH=$(find /sys/class/power_supply/ \( -name "AC*" -o -name "ADP*" \) | head -n 1)

is_on_battery() {
    [[ ! -d /sys/class/power_supply/BAT0 && ! -d /sys/class/power_supply/BAT1 ]] && echo "false" && return

    if grep -q "Discharging" /sys/class/power_supply/BAT*/status 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

get_bat_status() {
    if [[ -z $AC_PATH ]]; then
        cat "$BAT_PATH/status" 2>/dev/null | tr '[:upper:]' '[:lower:]'
        return
    fi

    local ac_online=$(cat "$AC_PATH/online" 2>/dev/null || echo "0")
    local cap=$(cat "$BAT_PATH/capacity" 2>/dev/null || echo "0")

    if [[ $ac_online -eq 1 ]]; then
        [[ $cap -eq 100 ]] && echo "full" || echo "charging"
    else
        echo "discharging"
    fi
}
