#!/bin/bash
# Description: Verify no hardcoded absolute paths

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

VIOLATIONS=()

ALL_SCRIPTS=()
while IFS= read -r -d '' script; do
    ALL_SCRIPTS+=("$script")
done < <(find "$RETRO_DIR/lib" "$RETRO_DIR/scripts" "$RETRO_DIR/cmds" -name "*.sh" -type f -print0 2>/dev/null)

for script in "${ALL_SCRIPTS[@]}"; do
    while IFS= read -r line; do
        echo "$line" | grep -qE "/home/[^/]+/|/Users/[^/]+/" || continue
        echo "$line" | grep -q "sed.*s.*/home" && continue
        echo "$line" | grep -qv "^[[:space:]]*#" || continue
        base=$(basename "$script")
        VIOLATIONS+=("$base: hardcoded user path detected")
    done < <(grep -nE "/home/[^/]+/|/Users/[^/]+/" "$script" 2>/dev/null)
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: ${#VIOLATIONS[@]} hardcoded paths found"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: No hardcoded absolute paths"
    exit 0
fi