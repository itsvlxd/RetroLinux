#!/bin/bash
# Description: Verify all Lua event files follow required structure

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

VIOLATIONS=()

EVENT_DIR="$RETRO_DIR/daemon/events"

if [[ ! -d $EVENT_DIR ]]; then
    echo "WARN: Event directory not found: $EVENT_DIR"
    exit 1
fi

for file in "$EVENT_DIR"/*.lua; do
    [[ -f $file ]] || continue
    name=$(basename "$file" .lua)

    if ! grep -q 'local Events = {}' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: missing 'Events' table declaration")
    fi

    if ! grep -q 'return Events' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: does not return Events table")
    fi

    while IFS= read -r line; do
        func=$(echo "$line" | sed -n 's/.*function Events\.\([a-z_][a-z0-9_]*\).*/\1/p')
        [[ -z $func ]] && continue
        if [[ ! $func =~ ^on_ ]]; then
            VIOLATIONS+=("$name: function '$func' does not start with 'on_'")
        fi
    done < <(grep -E 'function Events\.' "$file" 2>/dev/null)
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: ${#VIOLATIONS[@]} event structure violations"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: All event files follow required structure"
    exit 0
fi
