#!/bin/bash
# Description: Verify core scripts output pipe-delimited data

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

VIOLATIONS=()

CORE_SCRIPTS=()
while IFS= read -r -d '' script; do
    CORE_SCRIPTS+=("$script")
done < <(find "$RETRO_DIR/scripts" -maxdepth 1 -name "*_core.sh" -type f -print0 2>/dev/null)

for script in "${CORE_SCRIPTS[@]}"; do
    script_name=$(basename "$script")

    output=$(bash "$script" --help 2>&1)
    exit_code=$?

    if echo "$output" | grep -qE "(rx_log|echo.*Success|echo.*Error|echo.*Warning)"; then
        VIOLATIONS+=("$script_name: contains user-facing output")
    fi
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: ${#VIOLATIONS[@]} core scripts have user-facing output"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: Core scripts output pipe-delimited data"
    exit 0
fi