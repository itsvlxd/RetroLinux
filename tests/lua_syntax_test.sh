#!/bin/bash
# Description: Verify all Lua files are syntactically valid

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

VIOLATIONS=()

LUA_FILES=()
while IFS= read -r -d '' file; do
    LUA_FILES+=("$file")
done < <(find "$RETRO_DIR/daemon" "$RETRO_DIR/lib/lua" -name "*.lua" -type f -print0 2>/dev/null)

if [[ ${#LUA_FILES[@]} -eq 0 ]]; then
    echo "WARN: No Lua files found"
    exit 1
fi

for file in "${LUA_FILES[@]}"; do
    local_name=$(echo "$file" | sed "s|$RETRO_DIR/||")

    if ! luac -p "$file" 2>/dev/null; then
        VIOLATIONS+=("$local_name: syntax error")
    fi
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: ${#VIOLATIONS[@]} Lua files have syntax errors"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: All Lua files are syntactically valid"
    exit 0
fi
