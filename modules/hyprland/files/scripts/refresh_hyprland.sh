#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"

OUTPUT="$HOME/.config/retro/themes/variables.lua"
TEMP_FILE=$(mktemp)

mkdir -p "$(dirname "$OUTPUT")"

BORDER=$(get_var "RETRO_BORDER_SIZE" "2")
ROUNDING=$(get_var "RETRO_ROUNDING" "0")
SHADOW=$(get_var "RETRO_SHADOW" "true")
BLUR=$(get_var "RETRO_BLUR" "true")
GAP_IN=$(get_var "RETRO_GAP_IN" "5")
GAP_OUT=$(get_var "RETRO_GAP_OUT" "20")
TRANS=$(get_var "RETRO_OPACITY" "1.0")
INACTIVE_TRANS=$(get_var "RETRO_INACTIVE_OPACITY" "1.0")
ROUNDING_POWER=$(get_var "RETRO_ROUNDING_POWER" "2")
SHADOW_RANGE=$(get_var "RETRO_SHADOW_RANGE" "4")
SHADOW_RENDER_POWER=$(get_var "RETRO_SHADOW_RENDER_POWER" "3")
BLUR_SIZE=$(get_var "RETRO_BLUR_SIZE" "8")
BLUR_PASSES=$(get_var "RETRO_BLUR_PASSES" "1")
BLUR_VIBRANCY=$(get_var "RETRO_BLUR_VIBRANCY" "0.1696")
RESIZE_ON_BORDER=$(get_var "RETRO_RESIZE_ON_BORDER" "true")
ALLOW_TEARING=$(get_var "RETRO_ALLOW_TEARING" "false")
EXTEND_GRAB=$(get_var "RETRO_EXTEND_BORDER_GRAB_AREA" "15")
HOVER_ICON=$(get_var "RETRO_HOVER_ICON_ON_BORDER" "true")
FULLSCREEN_OPACITY=$(get_var "RETRO_FULLSCREEN_OPACITY" "1.0")
DIM_INACTIVE=$(get_var "RETRO_DIM_INACTIVE" "false")
DIM_STRENGTH=$(get_var "RETRO_DIM_STRENGTH" "0.5")
DIM_AROUND=$(get_var "RETRO_DIM_AROUND" "0.4")
DIM_SPECIAL=$(get_var "RETRO_DIM_SPECIAL" "0.2")
SHADOW_OFFSET=$(get_var "RETRO_SHADOW_OFFSET" "0,0")
SHADOW_SCALE=$(get_var "RETRO_SHADOW_SCALE" "1.0")
SHADOW_COLOR=$(get_var "RETRO_SHADOW_COLOR" "0x1A1A1AEE")
SHADOW_COLOR_INACTIVE=$(get_var "RETRO_SHADOW_COLOR_INACTIVE" "0x00003300")
BLUR_IGNORE_OPACITY=$(get_var "RETRO_BLUR_IGNORE_OPACITY" "true")
BLUR_NEW_OPT=$(get_var "RETRO_BLUR_NEW_OPT" "true")
BLUR_XRAY=$(get_var "RETRO_BLUR_XRAY" "false")
BLUR_NOISE=$(get_var "RETRO_BLUR_NOISE" "0.0117")
BLUR_CONTRAST=$(get_var "RETRO_BLUR_CONTRAST" "0.8916")
BLUR_BRIGHTNESS=$(get_var "RETRO_BLUR_BRIGHTNESS" "0.8172")
BLUR_VIB_DARKNESS=$(get_var "RETRO_BLUR_VIBRANCY_DARKNESS" "0.0")
BLUR_SPECIAL=$(get_var "RETRO_BLUR_SPECIAL" "false")
BLUR_POPUPS=$(get_var "RETRO_BLUR_POPUPS" "false")
BLUR_POPUPS_IGNOREALPHA=$(get_var "RETRO_BLUR_POPUPS_IGNOREALPHA" "0.2")
BLUR_INPUT_METHODS=$(get_var "RETRO_BLUR_INPUT_METHODS" "false")
BLUR_INPUT_METHODS_IGNOREALPHA=$(get_var "RETRO_BLUR_INPUT_METHODS_IGNOREALPHA" "0.2")
DIM_MODAL=$(get_var "RETRO_DIM_MODAL" "true")
BORDER_PART_OF_WINDOW=$(get_var "RETRO_BORDER_PART_OF_WINDOW" "true")
SHADOW_SHARP=$(get_var "RETRO_SHADOW_SHARP" "false")
GLOW_ENABLED=$(get_var "RETRO_GLOW_ENABLED" "false")
GLOW_RANGE=$(get_var "RETRO_GLOW_RANGE" "10")
GLOW_RENDER_POWER=$(get_var "RETRO_GLOW_RENDER_POWER" "3")
GLOW_COLOR=$(get_var "RETRO_GLOW_COLOR" "0xee1a1a1a")
SNAP_ENABLED=$(get_var "RETRO_SNAP_ENABLED" "true")
SNAP_WINDOW_GAP=$(get_var "RETRO_SNAP_WINDOW_GAP" "10")
SNAP_MONITOR_GAP=$(get_var "RETRO_SNAP_MONITOR_GAP" "10")
SNAP_BORDER_OVERLAP=$(get_var "RETRO_SNAP_BORDER_OVERLAP" "false")
SNAP_RESPECT_GAPS=$(get_var "RETRO_SNAP_RESPECT_GAPS" "false")
LAYOUT=$(get_var "RETRO_LAYOUT" "dwindle")
ANIMATIONS=$(get_var "RETRO_ANIMATIONS" "true")
KITTY_ACTIVE_OPACITY=$(get_var "KITTY_OPACITY_ACTIVE" "1.0")

if [ "$SHADOW" = "true" ] || [ "$SHADOW" = "1" ]; then SHADOW_BOOL="true"; else SHADOW_BOOL="false"; fi
if [ "$BLUR" = "true" ] || [ "$BLUR" = "1" ]; then BLUR_BOOL="true"; else BLUR_BOOL="false"; fi
if [ "$RESIZE_ON_BORDER" = "true" ] || [ "$RESIZE_ON_BORDER" = "1" ]; then RESIZE_ON_BORDER_BOOL="true"; else RESIZE_ON_BORDER_BOOL="false"; fi
if [ "$ALLOW_TEARING" = "true" ] || [ "$ALLOW_TEARING" = "1" ]; then ALLOW_TEARING_BOOL="true"; else ALLOW_TEARING_BOOL="false"; fi
if [ "$HOVER_ICON" = "true" ] || [ "$HOVER_ICON" = "1" ]; then HOVER_ICON_BOOL="true"; else HOVER_ICON_BOOL="false"; fi
if [ "$SNAP_ENABLED" = "true" ] || [ "$SNAP_ENABLED" = "1" ]; then SNAP_ENABLED_BOOL="true"; else SNAP_ENABLED_BOOL="false"; fi
if [ "$SNAP_BORDER_OVERLAP" = "true" ] || [ "$SNAP_BORDER_OVERLAP" = "1" ]; then SNAP_BORDER_OVERLAP_BOOL="true"; else SNAP_BORDER_OVERLAP_BOOL="false"; fi
if [ "$SNAP_RESPECT_GAPS" = "true" ] || [ "$SNAP_RESPECT_GAPS" = "1" ]; then SNAP_RESPECT_GAPS_BOOL="true"; else SNAP_RESPECT_GAPS_BOOL="false"; fi
if [ "$DIM_MODAL" = "true" ] || [ "$DIM_MODAL" = "1" ]; then DIM_MODAL_BOOL="true"; else DIM_MODAL_BOOL="false"; fi
if [ "$BORDER_PART_OF_WINDOW" = "true" ] || [ "$BORDER_PART_OF_WINDOW" = "1" ]; then BORDER_PART_OF_WINDOW_BOOL="true"; else BORDER_PART_OF_WINDOW_BOOL="false"; fi
if [ "$SHADOW_SHARP" = "true" ] || [ "$SHADOW_SHARP" = "1" ]; then SHADOW_SHARP_BOOL="true"; else SHADOW_SHARP_BOOL="false"; fi
if [ "$BLUR_INPUT_METHODS" = "true" ] || [ "$BLUR_INPUT_METHODS" = "1" ]; then BLUR_INPUT_METHODS_BOOL="true"; else BLUR_INPUT_METHODS_BOOL="false"; fi
if [ "$GLOW_ENABLED" = "true" ] || [ "$GLOW_ENABLED" = "1" ]; then GLOW_ENABLED_BOOL="true"; else GLOW_ENABLED_BOOL="false"; fi
if [ "$DIM_INACTIVE" = "true" ] || [ "$DIM_INACTIVE" = "1" ]; then DIM_INACTIVE_BOOL="true"; else DIM_INACTIVE_BOOL="false"; fi
if [ "$BLUR_IGNORE_OPACITY" = "true" ] || [ "$BLUR_IGNORE_OPACITY" = "1" ]; then BLUR_IGNORE_OPACITY_BOOL="true"; else BLUR_IGNORE_OPACITY_BOOL="false"; fi
if [ "$BLUR_NEW_OPT" = "true" ] || [ "$BLUR_NEW_OPT" = "1" ]; then BLUR_NEW_OPT_BOOL="true"; else BLUR_NEW_OPT_BOOL="false"; fi
if [ "$BLUR_XRAY" = "true" ] || [ "$BLUR_XRAY" = "1" ]; then BLUR_XRAY_BOOL="true"; else BLUR_XRAY_BOOL="false"; fi
if [ "$BLUR_SPECIAL" = "true" ] || [ "$BLUR_SPECIAL" = "1" ]; then BLUR_SPECIAL_BOOL="true"; else BLUR_SPECIAL_BOOL="false"; fi
if [ "$BLUR_POPUPS" = "true" ] || [ "$BLUR_POPUPS" = "1" ]; then BLUR_POPUPS_BOOL="true"; else BLUR_POPUPS_BOOL="false"; fi
if [ "$ANIMATIONS" = "true" ] || [ "$ANIMATIONS" = "1" ]; then ANIMATIONS_BOOL="true"; else ANIMATIONS_BOOL="false"; fi

cat <<EOF >"$TEMP_FILE"
-- This file has been generated by Retro. Do not edit manually.

return {
    retro_opacity = $TRANS,
    retro_inactive_opacity = $INACTIVE_TRANS,
    retro_border_size = $BORDER,
    retro_rounding = $ROUNDING,
    retro_rounding_power = $ROUNDING_POWER,
    retro_gap_in = $GAP_IN,
    retro_gap_out = $GAP_OUT,
    retro_shadow = $SHADOW_BOOL,
    retro_shadow_range = $SHADOW_RANGE,
    retro_shadow_render_power = $SHADOW_RENDER_POWER,
    retro_blur = $BLUR_BOOL,
    retro_blur_size = $BLUR_SIZE,
    retro_blur_passes = $BLUR_PASSES,
    retro_blur_vibrancy = $BLUR_VIBRANCY,
    retro_fullscreen_opacity = $FULLSCREEN_OPACITY,
    retro_dim_inactive = $DIM_INACTIVE_BOOL,
    retro_dim_strength = $DIM_STRENGTH,
    retro_dim_around = $DIM_AROUND,
    retro_dim_special = $DIM_SPECIAL,
    retro_shadow_offset = "$SHADOW_OFFSET",
    retro_shadow_scale = $SHADOW_SCALE,
    retro_shadow_color = "$SHADOW_COLOR",
    retro_shadow_color_inactive = "$SHADOW_COLOR_INACTIVE",
    retro_blur_ignore_opacity = $BLUR_IGNORE_OPACITY_BOOL,
    retro_blur_new_optimizations = $BLUR_NEW_OPT_BOOL,
    retro_blur_xray = $BLUR_XRAY_BOOL,
    retro_blur_noise = $BLUR_NOISE,
    retro_blur_contrast = $BLUR_CONTRAST,
    retro_blur_brightness = $BLUR_BRIGHTNESS,
    retro_blur_vibrancy_darkness = $BLUR_VIB_DARKNESS,
    retro_blur_special = $BLUR_SPECIAL_BOOL,
    retro_blur_popups = $BLUR_POPUPS_BOOL,
    retro_blur_popups_ignorealpha = $BLUR_POPUPS_IGNOREALPHA,
    retro_blur_input_methods = $BLUR_INPUT_METHODS_BOOL,
    retro_blur_input_methods_ignorealpha = $BLUR_INPUT_METHODS_IGNOREALPHA,
    retro_dim_modal = $DIM_MODAL_BOOL,
    retro_border_part_of_window = $BORDER_PART_OF_WINDOW_BOOL,
    retro_shadow_sharp = $SHADOW_SHARP_BOOL,
    retro_glow_enabled = $GLOW_ENABLED_BOOL,
    retro_glow_range = $GLOW_RANGE,
    retro_glow_render_power = $GLOW_RENDER_POWER,
    retro_glow_color = "$GLOW_COLOR",
    retro_resize_on_border = $RESIZE_ON_BORDER_BOOL,
    retro_allow_tearing = $ALLOW_TEARING_BOOL,
    retro_extend_border_grab_area = $EXTEND_GRAB,
    retro_hover_icon_on_border = $HOVER_ICON_BOOL,
    retro_snap_enabled = $SNAP_ENABLED_BOOL,
    retro_snap_window_gap = $SNAP_WINDOW_GAP,
    retro_snap_monitor_gap = $SNAP_MONITOR_GAP,
    retro_snap_border_overlap = $SNAP_BORDER_OVERLAP_BOOL,
    retro_snap_respect_gaps = $SNAP_RESPECT_GAPS_BOOL,
    retro_layout = "$LAYOUT",
    retro_kitty_active_opacity = $KITTY_ACTIVE_OPACITY,
    retro_animations = $ANIMATIONS_BOOL,
}
EOF

if mv "$TEMP_FILE" "$OUTPUT"; then
    chmod 644 "$OUTPUT"
    hyprctl reload >/dev/null 2>&1
else
    rm -f "$TEMP_FILE"
    exit 1
fi
