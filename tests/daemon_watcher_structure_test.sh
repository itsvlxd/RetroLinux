#!/bin/bash
# Description: Verify all Lua watchers follow required structure

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

VIOLATIONS=()

WATCHER_DIR="$RETRO_DIR/daemon/watchers"

if [[ ! -d $WATCHER_DIR ]]; then
    echo "WARN: Watcher directory not found: $WATCHER_DIR"
    exit 1
fi

for file in "$WATCHER_DIR"/*.lua; do
    [[ -f $file ]] || continue
    name=$(basename "$file" .lua)

    if ! grep -q 'require("watcher")' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: missing require(\"watcher\")")
    fi

    if ! grep -q 'return {' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: does not return a table")
    fi

    if ! grep -q 'name = ' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: missing 'name' field")
    fi

    if ! grep -q 'interval = ' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: missing 'interval' field")
    fi

    if ! grep -q 'enabled = function' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: missing 'enabled' function")
    fi

    if ! grep -q 'start = function' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: missing 'start' function")
    fi

    if [[ $name != "usb" ]] && ! grep -q 'coroutine.yield()' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: start function missing coroutine.yield() (blocking loop)")
    fi
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: ${#VIOLATIONS[@]} watcher structure violations"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: All watchers follow required structure"
    exit 0
fi
