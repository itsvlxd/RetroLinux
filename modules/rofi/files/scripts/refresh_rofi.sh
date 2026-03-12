#!/bin/bash

OUTPUT_RASI="$HOME/.cache/retro/themes/variables.rasi"
TEMP_FILE=$(mktemp)

mkdir -p "$(dirname "$OUTPUT_RASI")"

get_val() {
    local val=$(retro -var get "$1" 2>/dev/null)
    echo "${val:-$2}"
}

ROUNDING=$(get_val "RETRO_ROUNDING" "10")
#OPACITY=$(get_val "RETRO_OPACITY" "0.9")
#SELECTED=$(get_val "RETRO_COLOR_SELECTED" "#BD93F9")
#BG=$(get_val "RETRO_COLOR_BG" "#282A36")
#FG=$(get_val "RETRO_COLOR_FG" "#F8F8F2")

cat <<EOF >"$TEMP_FILE"
/**
 * RETRO AUTO-GENERATED ROFI VARIABLES
 **/

* {
    retro-border: ${ROUNDING}px;
    retro-rounding: ${ROUNDING}px 15px;
}
EOF

if mv "$TEMP_FILE" "$OUTPUT_RASI"; then
    chmod 644 "$OUTPUT_RASI"
else
    rm -f "$TEMP_FILE"
    exit 1
fi
