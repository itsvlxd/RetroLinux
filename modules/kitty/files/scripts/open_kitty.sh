#!/bin/bash

get_var() {
    local val=$(retro -var get "$1" 2>/dev/null)
    echo "${val:-$2}"
}

OPACITY=$(get_var "RETRO_OPACITY" "1.0")
FONT=$(get_var "KITTY_FONT" "JetBrainsMono Nerd Font")
EMOJI=$(get_var "RETRO_FONT_EMOJI" "Apple Color Emoji")
SIZE=$(get_var "KITTY_FONT_SIZE" "9.5")
PW=$(get_var "KITTY_PADDING_WIDTH" "5")
PH=$(get_var "KITTY_PADDING_HEIGHT" "5")
THEME="$HOME/.cache/retro/themes/kitty-colors.conf"

nohup kitty \
    --directory "$HOME" \
    -o "background_opacity=$OPACITY" \
    -o "font_family=$FONT" \
    -o "font_size=$SIZE" \
    -o "window_padding_width $PH $PW" \
    -o "symbol_map U+E000-U+F8FF,U+F0000-U+FFFFF $FONT" \
    -o "symbol_map U+1F300-U+1F9FF,U+1F600-U+1F64F $EMOJI" \
    -o "include=$THEME" \
    -o "allow_remote_control yes" \
    -o "listen_on unix:/tmp/kitty-$BASHPID" \
    "$@" >/dev/null 2>&1 &

exit 0
