#!/usr/bin/env bash

if sys_bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n 1) && [ -n "$sys_bat" ]; then
    capacity=$(cat "$sys_bat/capacity" 2>/dev/null)
    status=$(cat "$sys_bat/status" 2>/dev/null)

    if [ -n "$capacity" ]; then
        [ "$status" = "Charging" ] && icon="󰂄" || icon="󰁹"
        echo "#[bg=brightblack,fg=green] ${icon} ${capacity}% #[bg=default] "
    fi
fi
