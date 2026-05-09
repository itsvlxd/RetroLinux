#!/bin/bash

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

SC_ERRORS=0
SC_WARNINGS=0
ERROR_DETAILS=""

check_shellcheck() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "WARN: shellcheck not installed, skipping"
        return 1
    fi
    return 0
}

if ! check_shellcheck; then
    exit 1
fi

SC_ARGS=(
    --shell=bash
    --severity=warning
    --exclude=SC1090
    --exclude=SC1091
    --exclude=SC2086
    --exclude=SC2310
    --exclude=SC2244
    --exclude=SC2155
    --exclude=SC2168
)

SCRIPT_DIRS=(
    "$RETRO_DIR/lib"
    "$RETRO_DIR/scripts"
    "$RETRO_DIR/cmds"
    "$RETRO_DIR/tests"
)

SHELL_FILES=()
for dir in "${SCRIPT_DIRS[@]}"; do
    if [[ -d $dir ]]; then
        while IFS= read -r -d '' file; do
            SHELL_FILES+=("$file")
        done < <(find "$dir" -maxdepth 3 -name "*.sh" -type f -print0 2>/dev/null)
    fi
done

if [[ ${#SHELL_FILES[@]} -eq 0 ]]; then
    echo "WARN: No shell scripts found to check"
    exit 1
fi

for file in "${SHELL_FILES[@]}"; do
    result=$(shellcheck "${SC_ARGS[@]}" "$file" 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        continue
    fi

    err_file=$(basename "$file")
    while IFS= read -r line; do
        if echo "$line" | grep -qE "SC[0-9]+ \((error|Error)\)"; then
            ((SC_ERRORS++))
            ERROR_DETAILS="${ERROR_DETAILS}${err_file}: ${line}"$'\n'
        elif echo "$line" | grep -qE "\(warning\)"; then
            ((SC_WARNINGS++))
        fi
    done <<<"$result"
done

if [[ $SC_ERRORS -gt 0 ]]; then
    echo "FAIL: Found $SC_ERRORS errors and $SC_WARNINGS warnings"
    echo "$ERROR_DETAILS"
    exit 1
elif [[ $SC_WARNINGS -gt 0 ]]; then
    echo "WARN: Found $SC_WARNINGS warnings (non-blocking)"
    exit 0
else
    echo "PASS: All shell scripts passed shellcheck"
    exit 0
fi