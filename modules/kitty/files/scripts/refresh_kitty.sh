#!/bin/bash

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

THEME_FILE="$HOME/.config/retro/themes/kitty-colors.conf"
FONTS_FILE="$HOME/.config/retro/themes/kitty-fonts.conf"
OVERRIDES_FILE="$HOME/.config/retro/themes/kitty-overrides.conf"

mkdir -p "$(dirname "$FONTS_FILE")"
cat >"$FONTS_FILE" <<FONTCONF
font_family      $FONT
font_size        $SIZE
window_padding_width    $PADDING
symbol_map U+E000-U+F8FF $FONT
FONTCONF

if [ "$DYNAMIC_OPACITY" = "true" ] || [ "$DYNAMIC_OPACITY" = "1" ]; then DYNAMIC_OPACITY_BOOL="yes"; else DYNAMIC_OPACITY_BOOL="no"; fi
if [ "$AUDIO_BELL" = "true" ] || [ "$AUDIO_BELL" = "1" ]; then AUDIO_BELL_BOOL="yes"; else AUDIO_BELL_BOOL="no"; fi

cat >"$OVERRIDES_FILE" <<OVERCONF
modify_font cell_width $FONT_WIDTH%
modify_font cell_height $FONT_HEIGHT%
scrollback_lines $SCROLLBACK
dynamic_background_opacity $DYNAMIC_OPACITY_BOOL
enable_audio_bell $AUDIO_BELL_BOOL
tab_bar_edge $TAB_EDGE
tab_bar_style $TAB_STYLE
OVERCONF

apply_settings() {
    local target=$1

    kitty @ $target set-colors -a "$THEME_FILE"

    kitty @ $target set-font-size "$SIZE"
    kitty @ $target set-background-opacity "$OPACITY"

    kitty @ $target set-spacing \
        padding-top="$PADDING" \
        padding-bottom="$PADDING" \
        padding-left="$PADDING" \
        padding-right="$PADDING"
}

for sock in /tmp/kitty-*; do
    if [ -S "$sock" ]; then
        apply_settings "--to unix:$sock" 2>/dev/null
    fi
done

apply_settings "" 2>/dev/null
