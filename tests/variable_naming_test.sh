#!/bin/bash
# Description: Verify function naming conventions (cmd_, rx_, _)

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

VIOLATIONS=()

ALL_SCRIPTS=()
while IFS= read -r -d '' script; do
    ALL_SCRIPTS+=("$script")
done < <(find "$RETRO_DIR" -name "*.sh" -type f -print0 2>/dev/null)

for script in "${ALL_SCRIPTS[@]}"; do
    while IFS= read -r line; do
        func=$(echo "$line" | sed -n 's/.*^\([a-z_][a-z0-9_]*\).*/\1/p')
        [[ -z $func ]] && continue
        [[ $func == *"("* ]] && continue
        [[ ${#func} -lt 3 ]] && continue
        case "$func" in
            cmd_*|rx_*|_*)
                ;;
            *)
                if echo "$line" | grep -qE "^\s*[_a-z][_a-z0-9]*\s*\(\)"; then
                    base=$(basename "$script")
                    VIOLATIONS+=("$base: $func missing proper prefix (cmd_, rx_, or _)")
                fi
                ;;
        esac
    done < <(grep -E "^[[:space:]]*[_a-z][a-z0-9_]*[[:space:]]*\(\)" "$script" 2>/dev/null)
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: Found ${#VIOLATIONS[@]} naming violations"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: All functions follow naming conventions"
    exit 0
fi