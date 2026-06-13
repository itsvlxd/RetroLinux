#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

OPACITY=$(get_var "RETRO_OPACITY" "1.0")
FONT=$(get_var "KITTY_FONT" "JetBrainsMono Nerd Font")
EMOJI=$(get_var "RETRO_FONT_EMOJI" "Apple Color Emoji")
SIZE=$(get_var "KITTY_FONT_SIZE" "9.5")
PADDING=$(get_var "KITTY_PADDING" "5")

THEME_FILE="$HOME/.config/retro/themes/kitty-colors.conf"
FONTS_FILE="$HOME/.config/retro/themes/kitty-fonts.conf"

mkdir -p "$(dirname "$FONTS_FILE")"
cat >"$FONTS_FILE" <<FONTCONF
font_family      $FONT
font_size        $SIZE
window_padding_width    $PADDING
symbol_map U+E000-U+F8FF $FONT
FONTCONF

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
