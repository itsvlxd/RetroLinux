#!/bin/bash
# Validate package names in every module's packages.sh file.

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

FAILURES=()
WARNINGS=()

NAME_REGEX='^[a-z0-9@._+-]+$'

PKG_FILES=()
while IFS= read -r -d '' f; do
    PKG_FILES+=("$f")
done < <(find "$RETRO_DIR/modules" -mindepth 2 -maxdepth 2 -name packages.sh -print0 2>/dev/null)

if [[ ${#PKG_FILES[@]} -eq 0 ]]; then
    echo "ERROR: no module packages.sh files found"
    exit 1
fi

SYNC_DB_OK=false
if pacman -Si pacman >/dev/null 2>&1; then
    SYNC_DB_OK=true
fi

for f in "${PKG_FILES[@]}"; do
    mod=$(basename "$(dirname "$f")")
    [[ -f $f ]] || continue
    for pkg in $(grep -v '^#' "$f" | xargs); do
        if [[ ! $pkg =~ $NAME_REGEX ]]; then
            FAILURES+=("$mod: invalid package name '$pkg'")
            continue
        fi
        if [[ $SYNC_DB_OK == true ]]; then
            if ! pacman -Si "$pkg" >/dev/null 2>&1; then
                WARNINGS+=("$mod: '$pkg' not found in sync repos (may be AUR)")
            fi
        fi
    done
done

for w in "${WARNINGS[@]}"; do
    echo "WARN: $w"
done

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo "FAIL: ${#FAILURES[@]} invalid package name(s)"
    for f in "${FAILURES[@]}"; do
        echo "ERROR: $f"
    done
    exit 1
fi

echo "PASS: all module package names are syntactically valid"
exit 0
