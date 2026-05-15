#!/bin/bash
# Central init script sourced ONCE by the daemon at startup.
# All event files should NOT source anything individually.

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/battery.sh"
source "$RETRO_DIR/lib/icons.sh"
source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/cmds/tools/app.sh"
source "$RETRO_DIR/scripts/battery_core.sh"

PWR_CORE="$RETRO_DIR/scripts/power_core.sh"
BAT_CORE="$RETRO_DIR/scripts/battery_core.sh"
WALL_CORE="$RETRO_DIR/scripts/wallpaper_core.sh"

rx_log_register "power"
rx_log_register "battery"
rx_log_register "wallpaper"
rx_log_register "bluetooth"
