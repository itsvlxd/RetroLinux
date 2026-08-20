#!/bin/bash

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

EMPTY_SCRIPTS=()

echo "Checking that core scripts define functions..."

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
    "xdg_core.sh"
    "firewall_core.sh"
    "ssh_core.sh"
)

for script in "${core_scripts[@]}"; do
    script_path="$RETRO_DIR/scripts/$script"
    [[ ! -f $script_path ]] && continue

    func_count=$(grep -c "^[^#]*()" "$script_path" 2>/dev/null || echo 0)

    if [[ $func_count -eq 0 ]]; then
        EMPTY_SCRIPTS+=("$script has no functions")
    fi
done

if [[ ${#EMPTY_SCRIPTS[@]} -gt 0 ]]; then
    echo "FAIL: ${#EMPTY_SCRIPTS[@]} scripts have no functions"
    for err in "${EMPTY_SCRIPTS[@]}"; do
        echo "ERROR: $err"
    done
    exit 1
else
    echo "PASS: All core scripts define functions"
    exit 0
fi

