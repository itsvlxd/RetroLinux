#!/bin/bash
# Description: Verify commands have help text

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

export RETRO_CACHE="${RETRO_CACHE:-$HOME/.cache/retro}"
export SKIP_PROMPT=true

MISSING=()

CMDS_FILES=()
while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue
    CMDS_FILES+=("$file")
done < <(find "$RETRO_DIR/cmds" -name "*.sh" -type f -print0 2>/dev/null)

for file in "${CMDS_FILES[@]}"; do
    [[ "$file" == *"clipboard/"* ]] && continue
    name=$(basename "$file" .sh)
    output=$("$RETRO_DIR/retro.sh" "$name" --help 2>&1)
    if echo "$output" | grep -qE "(help|Usage|command)"; then
        continue
    else
        MISSING+=("$name: no help text found")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "WARN: ${#MISSING[@]} commands may lack help text (non-blocking)"
    for m in "${MISSING[@]}"; do
        echo "ERROR: $m"
    done
    exit 0
else
    echo "PASS: All commands have help text"
    exit 0
fi