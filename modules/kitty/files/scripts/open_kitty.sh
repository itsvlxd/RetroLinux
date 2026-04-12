#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

OPACITY=$(get_var "RETRO_OPACITY" "1.0")
FONT=$(get_var "KITTY_FONT" "JetBrainsMono Nerd Font")
EMOJI=$(get_var "RETRO_FONT_EMOJI" "Apple Color Emoji")
SIZE=$(get_var "KITTY_FONT_SIZE" "9.5")
PADDING=$(get_var "KITTY_PADDING" "5")
THEME="$HOME/.cache/retro/themes/kitty-colors.conf"

exec kitty \
    --directory "${RETRO_CWD:-$HOME}" \
    -o "background_opacity=$OPACITY" \
    -o "font_family=$FONT" \
    -o "font_size=$SIZE" \
    -o "window_padding_width=$PADDING" \
    -o "symbol_map U+E000-U+F8FF,U+F0000-U+FFFFF $FONT" \
    -o "symbol_map U+1F300-U+1F9FF,U+1F600-U+1F64F $EMOJI" \
    -o "include=$THEME" \
    -o "allow_remote_control=yes" \
    -o "listen_on=unix:/tmp/kitty-{kitty_pid}" \
    "$@"

