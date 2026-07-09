#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"

OUTPUT_RASI="$RETRO_CONFIG/themes/variables.rasi"
TEMP_FILE=$(mktemp)

mkdir -p "$(dirname "$OUTPUT_RASI")"

FONT=$(get_var "ROFI_FONT" "JetBrains Mono Nerd Font")
FONT_SIZE=$(get_var "ROFI_FONT_SIZE" "9.5")

# Clipboard overrides (user-configurable via AppsPage)
CLIP_BORDER=$(get_var "CLIP_BORDER_SIZE" "2")
CLIP_ROUNDING=$(get_var "CLIP_ROUNDING" "10")
CLIP_RADIUS_TL=$(get_var "CLIP_RADIUS_TL" "10")
CLIP_RADIUS_TR=$(get_var "CLIP_RADIUS_TR" "10")
CLIP_RADIUS_BR=$(get_var "CLIP_RADIUS_BR" "10")
CLIP_RADIUS_BL=$(get_var "CLIP_RADIUS_BL" "10")
CLIP_PADDING=$(get_var "CLIP_PADDING" "5")
CLIP_ICON_SIZE=$(get_var "CLIP_ICON_SIZE" "128")
CLIP_SPACING=$(get_var "CLIP_SPACING" "5")
CLIP_Y_OFFSET=$(get_var "CLIP_Y_OFFSET" "40")
CLIP_INPUT_PADDING=$(get_var "CLIP_INPUT_PADDING" "12")

# Gallery / global fallback (hardcoded defaults, not user-configurable)
GALLERY_BORDER="2"
GALLERY_RADIUS="10"
GALLERY_PADDING="5"
GALLERY_ICON_SIZE="128"
GALLERY_SPACING="5"
GALLERY_Y_OFFSET="40"
GALLERY_INPUT_PADDING="12"

cat <<EOF >"$TEMP_FILE"
/**
 * RETRO AUTO-GENERATED VARIABLES
 **/

* {
    /* Global — used by all rofi themes */
    rofi-font:          "$FONT $FONT_SIZE";

    /* Gallery / launcher fallback */
    rofi-border:        ${GALLERY_BORDER}px solid;
    rofi-radius:        ${GALLERY_RADIUS}px;
    rofi-padding:       ${GALLERY_PADDING}px;
    rofi-icon-size:     ${GALLERY_ICON_SIZE}px;
    rofi-spacing:       ${GALLERY_SPACING}px;
    rofi-input-padding: ${GALLERY_INPUT_PADDING}px;
    rofi-y-offset:      ${GALLERY_Y_OFFSET}%;

    /* Clipboard overrides (used by clipboard.rasi) */
    clip-border:        ${CLIP_BORDER}px solid;
    clip-radius:        ${CLIP_RADIUS_TL}px ${CLIP_RADIUS_TR}px ${CLIP_RADIUS_BR}px ${CLIP_RADIUS_BL}px;
    clip-rounding:      ${CLIP_ROUNDING}px;
    clip-padding:       ${CLIP_PADDING}px;
    clip-icon-size:     ${CLIP_ICON_SIZE}px;
    clip-spacing:       ${CLIP_SPACING}px;
    clip-input-padding: ${CLIP_INPUT_PADDING}px;
    clip-y-offset:      ${CLIP_Y_OFFSET}%;
}
EOF

if mv "$TEMP_FILE" "$OUTPUT_RASI"; then
    chmod 644 "$OUTPUT_RASI"
else
    rm -f "$TEMP_FILE"
    exit 1
fi
