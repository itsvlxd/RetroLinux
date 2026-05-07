#!/bin/bash

OUTPUT_RASI="$RETRO_CONFIG/themes/variables.rasi"
TEMP_FILE=$(mktemp)

mkdir -p "$(dirname "$OUTPUT_RASI")"

get_val() {
    local val=$(retro variable get "$1" 2>/dev/null)
    echo "${val:-$2}"
}

FONT=$(get_val "ROFI_FONT" "JetBrains Mono Nerd Font")
FONT_SIZE=$(get_val "ROFI_FONT_SIZE" "9.5")
ROUNDING=$(get_val "ROFI_ROUNDING" "10")
PADDING=$(get_val "ROFI_PADDING" "5")
BORDER=$(get_val "ROFI_BORDER_SIZE" "2")

cat <<EOF >"$TEMP_FILE"
/**
 * RETRO AUTO-GENERATED VARIABLES
 **/

* {
    rofi-font:          "$FONT $FONT_SIZE";
    rofi-border:        ${BORDER}px solid;
    rofi-radius:        ${ROUNDING}px;
    rofi-padding:       ${PADDING}px;
}
EOF

if mv "$TEMP_FILE" "$OUTPUT_RASI"; then
    chmod 644 "$OUTPUT_RASI"
else
    rm -f "$TEMP_FILE"
    exit 1
fi
