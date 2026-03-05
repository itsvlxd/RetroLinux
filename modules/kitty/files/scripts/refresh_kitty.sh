#!/bin/bash

OPACITY=$(retro -var get transparency)
THEME_FILE="$HOME/.cache/retro/themes/kitty-colors.conf"

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
