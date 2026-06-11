#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "theme"

THEMES_DIR="$RETRO_DIR/themes"

_load_theme_def() {
    local name="$1"
    local file="$THEMES_DIR/${name}.json"
    [[ ! -f $file ]] && return 1
    local palette_path
    palette_path=$(jq -r '.palette // empty' "$file" 2>/dev/null)
    local display_name
    display_name=$(jq -r '.name // empty' "$file" 2>/dev/null)
    local author
    author=$(jq -r '.author // empty' "$file" 2>/dev/null)
    local description
    description=$(jq -r '.description // empty' "$file" 2>/dev/null)
    echo "$palette_path|${display_name:-$name}|${author:--}|$description"
}

_list_themes() {
    local files=("$THEMES_DIR"/*.json)
    if [[ ! -e ${files[0]} ]]; then
        return
    fi
    for f in "${files[@]}"; do
        local base
        base=$(basename "$f" .json)
        local display
        display=$(jq -r '.name // empty' "$f" 2>/dev/null)
        local description
        description=$(jq -r '.description // empty' "$f" 2>/dev/null)
        echo "${display:-$base}|$base|$description"
    done
}

rx_theme_set() {
    local key="$1"
    local value="$2"
    local var_name=""

    case "$key" in
        opacity) var_name="RETRO_OPACITY" ;;
        inactive_opacity) var_name="RETRO_INACTIVE_OPACITY" ;;
        rounding) var_name="RETRO_ROUNDING" ;;
        rounding_power) var_name="RETRO_ROUNDING_POWER" ;;
        gap_in) var_name="RETRO_GAP_IN" ;;
        gap_out) var_name="RETRO_GAP_OUT" ;;
        border) var_name="RETRO_BORDER_SIZE" ;;
        shadow) var_name="RETRO_SHADOW" ;;
        shadow_range) var_name="RETRO_SHADOW_RANGE" ;;
        shadow_power) var_name="RETRO_SHADOW_RENDER_POWER" ;;
        blur) var_name="RETRO_BLUR" ;;
        blur_size) var_name="RETRO_BLUR_SIZE" ;;
        blur_passes) var_name="RETRO_BLUR_PASSES" ;;
        blur_vibrancy) var_name="RETRO_BLUR_VIBRANCY" ;;
        kitty_font) var_name="KITTY_FONT" ;;
        kitty_font_size) var_name="KITTY_FONT_SIZE" ;;
        kitty_padding) var_name="KITTY_PADDING" ;;
        kitty_shrink_padding) var_name="KITTY_SHRINK_PADDING_FULLSCREEN" ;;
        rofi_font) var_name="ROFI_FONT" ;;
        rofi_font_size) var_name="ROFI_FONT_SIZE" ;;
        rofi_border) var_name="ROFI_BORDER_SIZE" ;;
        rofi_rounding) var_name="ROFI_ROUNDING" ;;
        rofi_padding) var_name="ROFI_PADDING" ;;
        scheme)
            rx_theme_apply_scheme "$value"
            return $?
            ;;
        *)
            rx_log "error" "Unknown key: ${PINK}${key}${RESET}"
            return 1
            ;;
    esac

    set_var "$var_name" "$value"
    rx_theme_refresh_apps
}

rx_theme_refresh_apps() {
    bash "$RETRO_DIR/retro.sh" app all refresh >/dev/null 2>&1
}

rx_theme_apply_mode() {
    local mode="$1"

    case "$mode" in
        dark|light) ;;
        *)
            rx_log "error" "Mode must be ${PINK}dark${RESET} or ${PINK}light${RESET}"
            return 1
            ;;
    esac

    set_var "RETRO_THEME_MODE" "$mode"

    local scheme
    scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")
    if [[ $scheme == "wallpaper" ]]; then
        local wallpaper
        wallpaper=$(get_var "WALL_CURRENT" "")
        if [[ -z $wallpaper || ! -f $wallpaper ]]; then
            return 0
        fi
    fi
    rx_theme_apply_colors
}

rx_theme_apply_scheme() {
    local scheme="$1"

    if [[ $scheme == "wallpaper" ]]; then
        set_var "RETRO_THEME_SCHEME" "wallpaper"
        local wallpaper
        wallpaper=$(get_var "WALL_CURRENT" "")
        if [[ -z $wallpaper || ! -f $wallpaper ]]; then
            return 0
        fi
        rx_theme_apply_colors
        return 0
    fi

    local def_data
    def_data=$(_load_theme_def "$scheme")
    if [[ -z $def_data ]]; then
        rx_log "error" "Unknown theme: ${PINK}${scheme}${RESET}"
        return 1
    fi

    set_var "RETRO_THEME_SCHEME" "$scheme"
    rx_theme_apply_colors
}

rx_theme_apply_colors() {
    local mode
    mode=$(get_var "RETRO_THEME_MODE" "dark")
    local scheme
    scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")

    if [[ $scheme == "wallpaper" ]]; then
        local wallpaper
        wallpaper=$(get_var "WALL_CURRENT" "")
        if [[ -z $wallpaper || ! -f $wallpaper ]]; then
            local frame="$HOME/.config/retro/wallpaper_frames"
            wallpaper=$(find "$frame" -maxdepth 1 -name '*.png' 2>/dev/null | head -1)
        fi
        if [[ -z $wallpaper || ! -f $wallpaper ]]; then
            rx_theme_refresh_apps
            return 0
        fi

        local static_source="$wallpaper"
        local cache="$HOME/.config/retro/wallpaper_frames/$(basename "$wallpaper").png"
        [[ -f $cache ]] && static_source="$cache"

        local scheme_type
        local color_cache="$HOME/.config/retro/wallpaper_frames/$(basename "$wallpaper").colors"
        if [[ -f $color_cache ]]; then
            scheme_type="scheme-$(cat "$color_cache")"
        else
            local saturation
            saturation=$(magick "$static_source" -colorspace HSL -format "%[fx:100*s]" info: 2>/dev/null)
            if [[ -n $saturation ]] && [ "$(echo "$saturation < 1.0" | bc)" -eq 1 ]; then
                scheme_type="scheme-monochrome"
                echo "monochrome" >"$color_cache"
            else
                scheme_type="scheme-vibrant"
                echo "vibrant" >"$color_cache"
            fi
        fi

        if [[ $scheme_type == "scheme-monochrome" ]]; then
            matugen image -b wal --mode "$mode" "$static_source" -t scheme-monochrome --fallback-color "#ffffff" --source-color-index 0 >/dev/null 2>&1 || return 1
            rx_grayscale_output
        else
            matugen image -b wal --mode "$mode" "$static_source" -t scheme-vibrant --source-color-index 0 >/dev/null 2>&1 || return 1
        fi
    else
        local def_data
        def_data=$(_load_theme_def "$scheme")
        local palette_rel
        palette_rel=$(echo "$def_data" | cut -d'|' -f1)
        if [[ -z $palette_rel ]]; then
            rx_log "error" "No palette image defined for theme: ${PINK}$scheme${RESET}"
            rx_theme_refresh_apps
            return 0
        fi
        local palette_path="$THEMES_DIR/$palette_rel"
        if [[ ! -f $palette_path ]]; then
            rx_log "error" "Palette image not found: ${PINK}$palette_path${RESET}"
            rx_theme_refresh_apps
            return 0
        fi
        rx_generate_colors "$palette_path" "$mode" "scheme-tonal-spot" "0" "saturation" || return 1

        local theme_file="$THEMES_DIR/${scheme}.json"
        if [[ -f $theme_file && $mode != "light" ]]; then
            rx_apply_color_map "$theme_file"
        fi
    fi

    rx_theme_refresh_apps
}

rx_theme_get_status_lines() {
    local mode
    mode=$(get_var "RETRO_THEME_MODE" "dark")
    local scheme
    scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")
    local scheme_display="$scheme"

    if [[ $scheme != "wallpaper" ]]; then
        local def_data
        def_data=$(_load_theme_def "$scheme")
        local display_name
        display_name=$(echo "$def_data" | cut -d'|' -f2)
        [[ -n $display_name ]] && scheme_display="$display_name"
    fi

    cat <<EOF
mode|${mode}
theme|${scheme_display}
font_main|$(get_var "RETRO_FONT_MAIN" "Inter")
font_nerd|$(get_var "RETRO_FONT_NERD" "JetBrainsMono Nerd Font")
font_emoji|$(get_var "RETRO_FONT_EMOJI" "Apple Color Emoji")
opacity|$(get_var "RETRO_OPACITY" "1.0")
inactive_opacity|$(get_var "RETRO_INACTIVE_OPACITY" "0.8")
rounding|$(get_var "RETRO_ROUNDING" "10")
rounding_power|$(get_var "RETRO_ROUNDING_POWER" "2")
border|$(get_var "RETRO_BORDER_SIZE" "2")
gap_in|$(get_var "RETRO_GAP_IN" "5")
gap_out|$(get_var "RETRO_GAP_OUT" "20")
shadow|$(get_var "RETRO_SHADOW" "true")
shadow_range|$(get_var "RETRO_SHADOW_RANGE" "4")
shadow_power|$(get_var "RETRO_SHADOW_RENDER_POWER" "3")
blur|$(get_var "RETRO_BLUR" "true")
blur_size|$(get_var "RETRO_BLUR_SIZE" "3")
blur_passes|$(get_var "RETRO_BLUR_PASSES" "3")
blur_vibrancy|$(get_var "RETRO_BLUR_VIBRANCY" "0.1696")
kitty_font|$(get_var "KITTY_FONT" "JetBrainsMono Nerd Font")
kitty_font_size|$(get_var "KITTY_FONT_SIZE" "9.5")
kitty_padding|$(get_var "KITTY_PADDING" "5")
rofi_font|$(get_var "ROFI_FONT" "JetBrainsMono Nerd Font")
rofi_font_size|$(get_var "ROFI_FONT_SIZE" "9.5")
rofi_border|$(get_var "ROFI_BORDER_SIZE" "2")
rofi_rounding|$(get_var "ROFI_ROUNDING" "10")
rofi_padding|$(get_var "ROFI_PADDING" "5")
EOF
}

rx_theme_get_setup_values() {
    echo "mode=$(get_var "RETRO_THEME_MODE" "dark")"
    echo "theme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")"
    echo "font_main=$(get_var "RETRO_FONT_MAIN" "Inter")"
    echo "font_nerd=$(get_var "RETRO_FONT_NERD" "JetBrainsMono Nerd Font")"
    echo "font_emoji=$(get_var "RETRO_FONT_EMOJI" "Apple Color Emoji")"
    echo "opacity=$(get_var "RETRO_OPACITY" "1.0")"
    echo "rounding=$(get_var "RETRO_ROUNDING" "10")"
    echo "gap_in=$(get_var "RETRO_GAP_IN" "5")"
    echo "gap_out=$(get_var "RETRO_GAP_OUT" "20")"
    echo "shadow=$(get_var "RETRO_SHADOW" "true")"
    echo "blur=$(get_var "RETRO_BLUR" "true")"
}

case "$1" in
    "--set")
        rx_theme_set "$2" "$3"
        ;;
    "--mode")
        rx_theme_apply_mode "$2"
        ;;
    "--theme")
        rx_theme_apply_scheme "$2"
        ;;
    "--apply-colors")
        rx_theme_apply_colors
        ;;
    "--refresh")
        rx_theme_refresh_apps
        ;;
    "--status")
        rx_theme_get_status_lines
        ;;
    "--setup-get")
        rx_theme_get_setup_values
        ;;
    "--list-themes")
        _list_themes
        ;;
    "--theme-data")
        _load_theme_def "$2"
        ;;
esac
