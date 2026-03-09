#!/bin/bash

get_var() {
    local val
    val=$(retro -var get "$1" 2>/dev/null)
    echo "${val:-$2}"
}

OPACITY=$(get_var "RETRO_ACTIVE_OPACITY" "1.0")
FONT=$(get_var "KITTY_FONT" "JetBrainsMono Nerd Font")
SIZE=$(get_var "KITTY_FONT_SIZE" "9.5")
P_WIDTH=$(get_var "KITTY_PADDING_WIDTH" "5")
P_HEIGHT=$(get_var "KITTY_PADDING_HEIGHT" "5")

THEME_FILE="$HOME/.cache/retro/themes/kitty-colors.conf"

apply_settings() {
    local target=$1

    kitty @ $target set-colors -a "$THEME_FILE"

    kitty @ $target set-font-family "$FONT"
    kitty @ $target set-font-size "$SIZE"
    kitty @ $target set-background-opacity "$OPACITY"
    kitty @ $target set-font-symbols --ranges U+E000-U+F8FF,U+F0000-U+FFFFF "$FONT"

    kitty @ $target set-spacing \
        padding-top="$P_HEIGHT" \
        padding-bottom="$P_HEIGHT" \
        padding-left="$P_WIDTH" \
        padding-right="$P_WIDTH"
}

for sock in /tmp/kitty-*; do
    if [ -S "$sock" ]; then
        apply_settings "--to unix:$sock" 2>/dev/null
    fi
done

apply_settings "" 2>/dev/null
