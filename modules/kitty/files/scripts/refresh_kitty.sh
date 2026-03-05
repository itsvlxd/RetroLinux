#!/bin/bash

VARS="$HOME/.config/hypr/scripts/vars.sh"
THEME_FILE="$HOME/.cache/retro/themes/kitty-colors.conf"

CURRENT_STATE=$(bash "$VARS" get transparency)
if [ "$CURRENT_STATE" = "true" ]; then
    OPACITY="0.85"
else
    OPACITY="1.0"
fi

apply_theme() {
    local target=$1
    kitty @ $target set-colors -a "$THEME_FILE" 2>/dev/null
    kitty @ $target set-background-opacity "$OPACITY" 2>/dev/null
}

for sock in /tmp/kitty-*; do
    if [ -S "$sock" ]; then
        apply_theme "--to unix:$sock"
    fi
done

apply_theme ""
