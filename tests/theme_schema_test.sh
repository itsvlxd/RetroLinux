#!/bin/bash
# Description: Verify all theme JSONs are valid JSON

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

VIOLATIONS=()

while IFS= read -r -d '' file; do
    if ! jq empty "$file" 2>/dev/null; then
        local_name=$(echo "$file" | sed "s|$RETRO_DIR/||")
        VIOLATIONS+=("$local_name: invalid JSON")
    fi
done < <(find "$RETRO_DIR/themes" -name "*.json" -type f -print0 2>/dev/null)

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: ${#VIOLATIONS[@]} theme files have invalid JSON"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: All theme files are valid JSON"
    exit 0
fi
