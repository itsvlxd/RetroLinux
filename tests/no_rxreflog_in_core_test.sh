#!/bin/bash
# Description: Verify core scripts use rx_log_file for logging, not rx_log

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

if [[ ${#CORE_SCRIPTS[@]} -eq 0 ]]; then
    echo "WARN: No core scripts found"
    exit 1
fi

for script in "${CORE_SCRIPTS[@]}"; do
    local_name=$(basename "$script")

    if grep -qE 'rx_log "(info|success|warn|error)"' "$script" 2>/dev/null; then
        VIOLATIONS+=("$local_name: contains rx_log (use rx_log_file for backend logging)")
    fi

    if grep -qE 'rx_log_file "(INFO|WARN|ERROR|SUCCESS)"' "$script" 2>/dev/null; then
        continue
    fi
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: ${#VIOLATIONS[@]} core scripts have logging violations"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: Core scripts follow logging conventions"
    exit 0
fi
