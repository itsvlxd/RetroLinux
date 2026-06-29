#!/bin/bash

if [[ -z $RETRO_DIR ]]; then
    RETRO_DIR="/opt/retrolinux"
fi
source "$RETRO_DIR/lib/helpers.sh"

OPACITY=$(get_var "RETRO_OPACITY" "1.0")
FONT=$(get_var "KITTY_FONT" "JetBrainsMono Nerd Font")
EMOJI=$(get_var "RETRO_FONT_EMOJI" "Apple Color Emoji")
SIZE=$(get_var "KITTY_FONT_SIZE" "9.5")
PADDING=$(get_var "KITTY_PADDING" "5")
FONT_WIDTH=$(get_var "KITTY_FONT_WIDTH" "105")
FONT_HEIGHT=$(get_var "KITTY_FONT_HEIGHT" "95")
SCROLLBACK=$(get_var "KITTY_SCROLLBACK" "10000")
DYNAMIC_OPACITY=$(get_var "KITTY_DYNAMIC_OPACITY" "true")
AUDIO_BELL=$(get_var "KITTY_AUDIO_BELL" "false")
TAB_EDGE=$(get_var "KITTY_TAB_EDGE" "bottom")
TAB_STYLE=$(get_var "KITTY_TAB_STYLE" "powerline")
THEME="$HOME/.config/retro/themes/kitty-colors.conf"
OVERRIDES="$HOME/.config/retro/themes/kitty-overrides.conf"

if [ "$DYNAMIC_OPACITY" = "true" ] || [ "$DYNAMIC_OPACITY" = "1" ]; then DYNAMIC_OPACITY_BOOL="yes"; else DYNAMIC_OPACITY_BOOL="no"; fi
if [ "$AUDIO_BELL" = "true" ] || [ "$AUDIO_BELL" = "1" ]; then AUDIO_BELL_BOOL="yes"; else AUDIO_BELL_BOOL="no"; fi

mkdir -p "$(dirname "$OVERRIDES")"
cat >"$OVERRIDES" <<OVERCONF
modify_font cell_width $FONT_WIDTH%
modify_font cell_height $FONT_HEIGHT%
scrollback_lines $SCROLLBACK
dynamic_background_opacity $DYNAMIC_OPACITY_BOOL
enable_audio_bell $AUDIO_BELL_BOOL
tab_bar_edge $TAB_EDGE
tab_bar_style $TAB_STYLE
OVERCONF

exec kitty \
    --directory "${RETRO_CWD:-$HOME}" \
    -o "background_opacity=$OPACITY" \
    -o "font_family=$FONT" \
    -o "font_size=$SIZE" \
    -o "window_padding_width=$PADDING" \
    -o "symbol_map U+E000-U+F8FF,U+F0000-U+FFFFF $FONT" \
    -o "symbol_map U+1F300-U+1F9FF,U+1F600-U+1F64F $EMOJI" \
    -o "include=$THEME" \
    -o "include=$OVERRIDES" \
    -o "allow_remote_control=yes" \
    -o "listen_on=unix:/tmp/kitty-{kitty_pid}" \
    "$@"
