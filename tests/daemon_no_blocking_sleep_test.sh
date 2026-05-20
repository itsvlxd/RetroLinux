#!/bin/bash
# Description: Verify watchers don't use blocking os.execute("sleep")

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

    if grep -qE 'os\.execute\("sleep' "$file" 2>/dev/null; then
        VIOLATIONS+=("$name: uses blocking os.execute(\"sleep\") - use Watcher.sleep() or coroutine.yield()")
    fi
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: ${#VIOLATIONS[@]} watchers use blocking sleep"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: No watchers use blocking sleep"
    exit 0
fi
