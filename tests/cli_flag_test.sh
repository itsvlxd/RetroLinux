#!/bin/bash

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

FAILED_FLAGS=()

echo "Testing CLI flags in core scripts..."

test_flag() {
    local script="$1"
    local flag="$2"
    local timeout_flag="$3"

    local output
    if [[ $timeout_flag == "yes" ]]; then
        output=$(timeout 5 bash "$script_path" "$flag" 2>&1 || echo "TIMEOUT")
    else
        output=$(bash "$script_path" "$flag" 2>&1 || echo "ERROR")
    fi

    if [[ $output == "TIMEOUT" || $output == *"command not found"* ]]; then
        return 1
    fi
    return 0
}

core_scripts=(
    "audio_core.sh"
    "battery_core.sh"
    "network_core.sh"
    "service_core.sh"
    "driver_core.sh"
    "variable_core.sh"
    "xdg_core.sh"
)

for script in "${core_scripts[@]}"; do
    script_path="$RETRO_DIR/scripts/$script"
    [[ ! -f $script_path ]] && continue

    if ! test_flag "$script" "--help" "no"; then
        FAILED_FLAGS+=("$script --help failed")
    fi
done

if [[ ${#FAILED_FLAGS[@]} -gt 0 ]]; then
    echo "FAIL: ${#FAILED_FLAGS[@]} CLI flags failed"
    for err in "${FAILED_FLAGS[@]}"; do
        echo "ERROR: $err"
    done
    exit 1
else
    echo "PASS: Core scripts respond to --help"
    exit 0
fi

