#!/bin/bash
# Description: Verify modules have required files

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

MISSING=()

MODULES_DIRS=()
while IFS= read -r -d '' dir; do
    MODULES_DIRS+=("$dir")
done < <(find "$RETRO_DIR/modules" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

for mod_dir in "${MODULES_DIRS[@]}"; do
    mod_name=$(basename "$mod_dir")

    has_install=false
    [[ -f "$mod_dir/install.sh" ]] && has_install=true

    if [[ ! -f "$mod_dir/packages.sh" ]]; then
        [[ $has_install == true ]] && continue
        MISSING+=("$mod_name: missing packages.sh")
    fi
    if [[ ! -f "$mod_dir/properties.json" ]]; then
        [[ $has_install == true ]] && continue
        MISSING+=("$mod_name: missing properties.json")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "FAIL: ${#MISSING[@]} modules missing required files"
    for m in "${MISSING[@]}"; do
        echo "ERROR: $m"
    done
    exit 1
else
    echo "PASS: All modules have required structure"
    exit 0
fi