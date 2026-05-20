#!/bin/bash
# Description: Verify mirror overwrite logic works correctly

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

source "$RETRO_DIR/lib/fs.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/variable.sh"

FAILURES=()

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Test 1: rx_mirror_add_missing copies missing files but doesn't overwrite existing
test_add_missing() {
    local src="$TEST_DIR/src"
    local dest="$TEST_DIR/dest"

    mkdir -p "$src/subdir"
    mkdir -p "$dest"
    echo "existing" > "$dest/existing.txt"
    echo "new" > "$src/new.txt"
    echo "new_sub" > "$src/subdir/file.txt"

    rx_mirror_add_missing "$src" "$dest"

    if [[ ! -f "$dest/new.txt" ]]; then
        FAILURES+=("add_missing: failed to copy new file")
    fi
    if [[ ! -f "$dest/subdir/file.txt" ]]; then
        FAILURES+=("add_missing: failed to create missing subdir with file")
    fi
    if [[ "$(cat "$dest/existing.txt")" != "existing" ]]; then
        FAILURES+=("add_missing: overwrote existing file")
    fi
}

# Test 2: rx_mirror_add_missing skips when nothing is missing
test_add_missing_skip() {
    local src="$TEST_DIR/src2"
    local dest="$TEST_DIR/dest2"

    mkdir -p "$src"
    echo "data" > "$src/file.txt"
    mkdir -p "$dest"
    echo "data" > "$dest/file.txt"

    local before_log=""
    rx_mirror_add_missing "$src" "$dest"
    local after_log=""

    if [[ -f "$dest/file.txt" && "$(cat "$dest/file.txt")" == "data" ]]; then
        : # pass
    else
        FAILURES+=("add_missing_skip: corrupted existing data")
    fi
}

# Test 3: rx_mirror_add_missing creates dest if it doesn't exist
test_add_missing_new_dest() {
    local src="$TEST_DIR/src3"
    local dest="$TEST_DIR/dest3"

    mkdir -p "$src"
    echo "new" > "$src/file.txt"

    rx_mirror_add_missing "$src" "$dest"

    if [[ ! -f "$dest/file.txt" ]]; then
        FAILURES+=("add_missing_new_dest: failed to create new dest with files")
    fi
}

test_add_missing
test_add_missing_skip
test_add_missing_new_dest

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo -e "\e[31mFAIL: ${#FAILURES[@]} test(s) failed\e[0m"
    for f in "${FAILURES[@]}"; do
        echo -e "  \e[33m[!] $f\e[0m"
    done
    exit 1
else
    echo -e "\e[32mPASS: Mirror overwrite tests passed\e[0m"
    exit 0
fi
