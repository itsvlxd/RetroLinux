#!/bin/bash

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

FAILED_SCRIPTS=()

echo "Testing core script execution..."

core_scripts=(
    "audio_core.sh"
    "battery_core.sh"
    "network_core.sh"
    "bluetooth_core.sh"
    "service_core.sh"
    "driver_core.sh"
    "power_core.sh"
    "cleanup_core.sh"
    "wallpaper_core.sh"
    "variable_core.sh"
    "timeshift_core.sh"
    "benchmark_core.sh"
    "event_core.sh"
)

for script in "${core_scripts[@]}"; do
    script_path="$RETRO_DIR/scripts/$script"
    [[ ! -f $script_path ]] && continue

    output=$(bash "$script_path" 2>&1 | head -1)

    if [[ $output =~ "error" || $output =~ "Error" || $output =~ "not found" || $output =~ "unrecognized" ]]; then
        FAILED_SCRIPTS+=("$script: $output")
    fi
done

if [[ ${#FAILED_SCRIPTS[@]} -gt 0 ]]; then
    echo "FAIL: ${#FAILED_SCRIPTS[@]} scripts have issues"
    for err in "${FAILED_SCRIPTS[@]}"; do
        echo "ERROR: $err"
    done
    exit 1
else
    echo "PASS: All core scripts execute without critical errors"
    exit 0
fi

