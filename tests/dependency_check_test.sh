#!/bin/bash
# Description: Verify dependencies use check_dep

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

WARNINGS=()

CORE_SCRIPTS=()
while IFS= read -r -d '' script; do
    CORE_SCRIPTS+=("$script")
done < <(find "$RETRO_DIR/scripts" -maxdepth 1 -name "*_core.sh" -type f -print0 2>/dev/null)

COMMANDS=("wpctl" "pactl" "ip" "rfkill" "lspci" "systemctl" "bluetoothctl" "xdotool" "playerctl" "jq")

for script in "${CORE_SCRIPTS[@]}"; do
    script_name=$(basename "$script")
    for cmd in "${COMMANDS[@]}"; do
        if grep -q "\`$cmd\`" "$script" 2>/dev/null || grep -q "\$\$cmd" "$script" 2>/dev/null; then
            if ! grep -q "check_dep.*$cmd" "$script" 2>/dev/null; then
                WARNINGS+=("$script_name: uses $cmd without check_dep")
            fi
        fi
    done
done

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "FAIL: ${#WARNINGS[@]} dependencies may lack check_dep"
    for w in "${WARNINGS[@]}"; do
        echo "ERROR: $w"
    done
    exit 1
else
    echo "PASS: Dependencies use check_dep"
    exit 0
fi