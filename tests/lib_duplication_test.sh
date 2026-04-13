#!/bin/bash
# Description: Check for duplicate function definitions in cmds

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

DUPLICATES=()

declare -A FUNC_MAP

CMDS_FILES=()
while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue
    CMDS_FILES+=("$file")
done < <(find "$RETRO_DIR/cmds" -name "*.sh" -type f -print0 2>/dev/null)

for file in "${CMDS_FILES[@]}"; do
    while IFS= read -r line; do
        func_name=$(echo "$line" | sed -n 's/.*^\([a-z_][a-z0-9_]*\).*/\1/p' | head -1)
        [[ -z $func_name ]] && continue
        [[ $func_name == *"("* ]] && continue
        if [[ -n ${FUNC_MAP[$func_name]} ]]; then
            DUPLICATES+=("$func_name: ${FUNC_MAP[$func_name]} and $(basename "$file")")
        else
            FUNC_MAP[$func_name]=$(basename "$file")
        fi
    done < <(grep -E "^[[:space:]]*cmd_[a-z_][a-z0-9_]*[[:space:]]*\(\)" "$file" 2>/dev/null)
done

if [[ ${#DUPLICATES[@]} -gt 0 ]]; then
    echo "FAIL: Found ${#DUPLICATES[@]} duplicate functions"
    for d in "${DUPLICATES[@]}"; do
        echo "ERROR: $d"
    done
    exit 1
else
    echo "PASS: No duplicate functions in cmds"
    exit 0
fi