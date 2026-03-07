#!/bin/bash

source "$RETRO_DIR/scripts/lib/battery.sh"
source "$RETRO_DIR/scripts/lib/variable.sh"

PWR_CORE="$RETRO_DIR/scripts/power_core.sh"
WALL_CORE="$RETRO_DIR/scripts/wallpaper_core.sh"

on_battery_saver_enabled() {
    bash "$PWR_CORE" --set saver

    bash "$WALL_CORE" --restore
}

on_battery_saver_disabled() {
    if [[ $(get_var "PWR_CURRENT") == "saver" ]]; then
        bash "$PWR_CORE" --toggle
    fi

    bash "$WALL_CORE" --restore
}
