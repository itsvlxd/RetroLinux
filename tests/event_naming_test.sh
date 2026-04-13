#!/bin/bash
# Description: Verify event hooks follow on_event_* pattern

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

VIOLATIONS=()

EVENT_FILES=()
while IFS= read -r -d '' file; do
    [[ -f "$file" ]] || continue
    EVENT_FILES+=("$file")
done < <(find "$RETRO_DIR/scripts/events" -name "*.sh" -type f -print0 2>/dev/null)

for file in "${EVENT_FILES[@]}"; do
    while IFS= read -r line; do
        func=$(echo "$line" | sed -n 's/^\(on_[a-z_][a-z0-9_]*\).*/\1/p')
        [[ -z $func ]] && continue
        [[ $func == "on_" ]] && continue
        if [[ ! $func =~ ^on_event_ && ! $func =~ ^on_(power|battery|usb|bluetooth|pkg|retro|slideshow) ]]; then
            VIOLATIONS+=("$(basename "$file"): $func doesn't follow on_event_* or on_<category>_* pattern")
        fi
    done < <(grep -E "^on_[a-z_][a-z0-9_]*\\(\\)" "$file" 2>/dev/null)
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo "FAIL: ${#VIOLATIONS[@]} event hooks have incorrect naming"
    for v in "${VIOLATIONS[@]}"; do
        echo "ERROR: $v"
    done
    exit 1
else
    echo "PASS: All event hooks follow on_event_* pattern"
    exit 0
fi