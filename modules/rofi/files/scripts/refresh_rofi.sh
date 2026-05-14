#!/bin/bash

OUTPUT_RASI="$RETRO_CONFIG/themes/variables.rasi"
TEMP_FILE=$(mktemp)

mkdir -p "$(dirname "$OUTPUT_RASI")"

_vars_file="${RETRO_CONFIG:-$HOME/.config/retro}/variables.sh"

get_val() {
    local key="$1"
    local default="$2"
    if [[ -f "$_vars_file" ]]; then
        local val=$(grep -m 1 "^export $key=" "$_vars_file" 2>/dev/null | sed 's/^export [^=]*="//; s/"$//')
        if [[ -n $val ]]; then
            echo "$val"
            return
        fi
    fi
    echo "$default"
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
