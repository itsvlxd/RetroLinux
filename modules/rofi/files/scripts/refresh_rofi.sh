#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"

OUTPUT_RASI="$RETRO_CONFIG/themes/variables.rasi"
TEMP_FILE=$(mktemp)

mkdir -p "$(dirname "$OUTPUT_RASI")"

FONT=$(get_var "ROFI_FONT" "JetBrains Mono Nerd Font")
FONT_SIZE=$(get_var "ROFI_FONT_SIZE" "9.5")
ROUNDING=$(get_var "ROFI_ROUNDING" "10")
PADDING=$(get_var "ROFI_PADDING" "5")
BORDER=$(get_var "ROFI_BORDER_SIZE" "2")
ICON_SIZE=$(get_var "ROFI_ICON_SIZE" "128")
SPACING=$(get_var "ROFI_SPACING" "5")
Y_OFFSET=$(get_var "ROFI_Y_OFFSET" "40")
INPUT_PADDING=$(get_var "ROFI_INPUT_PADDING" "12")

cat <<EOF >"$TEMP_FILE"
/**
 * RETRO AUTO-GENERATED VARIABLES
 **/

* {
    rofi-font:          "$FONT $FONT_SIZE";
    rofi-border:        ${BORDER}px solid;
    rofi-radius:        ${ROUNDING}px;
    rofi-padding:       ${PADDING}px;
    rofi-icon-size:     ${ICON_SIZE}px;
    rofi-spacing:       ${SPACING}px;
    rofi-input-padding: ${INPUT_PADDING}px;
    rofi-y-offset:      ${Y_OFFSET}%;
}
EOF

if mv "$TEMP_FILE" "$OUTPUT_RASI"; then
    chmod 644 "$OUTPUT_RASI"
else
    rm -f "$TEMP_FILE"
    exit 1
fi
