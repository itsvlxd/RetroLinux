#!/bin/bash
# Description: Verify all commands call register_command

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

MISSING=()

CMDS_FILES=()
while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue
    CMDS_FILES+=("$file")
done < <(find "$RETRO_DIR/cmds" -maxdepth 2 -name "*.sh" -type f -print0 2>/dev/null)

for file in "${CMDS_FILES[@]}"; do
    [[ "$file" == *"clipboard/"* ]] && continue
    if ! grep -q "register_command" "$file" 2>/dev/null; then
        MISSING+=("$(basename "$file") missing register_command")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "FAIL: ${#MISSING[@]} commands missing register_command"
    for m in "${MISSING[@]}"; do
        echo "ERROR: $m"
    done
    exit 1
else
    echo "PASS: All commands call register_command"
    exit 0
fi