#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/menu.sh"
source "$RETRO_DIR/lib/setup.sh"

_THEME_CORE="$RETRO_DIR/scripts/theme_core.sh"

_theme_call() {
    bash "$_THEME_CORE" "$@"
}

_theme_set() {
    local key="$1"
    local value="$2"
    if _theme_call "--set" "$key" "$value"; then
        rx_log "success" "${PINK}$key${RESET} set to ${PINK}$value${RESET}"
    fi
}

_pick_font() {
    local label="$1"
    local default="$2"
    local fonts=()
    mapfile -t fonts < <(bash "$RETRO_DIR/scripts/font_core.sh" --list-installed 2>/dev/null)
    if [[ ${#fonts[@]} -eq 0 ]]; then
        echo "$default"
        return
    fi
    rx_menu "󰄾" "$label" "${fonts[@]}"
}

cmd_theme() {
    local action="${1,,}"
    shift 2>/dev/null || true

    case "$action" in
        "status")
            rx_table_header "󰄈" "Theme Configuration"
            local mode
            mode=$(get_var "RETRO_THEME_MODE" "dark")
            local scheme
            scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")
            if [[ $scheme != "wallpaper" ]]; then
                local def_data
                def_data=$(_theme_call "--theme-data" "$scheme")
                local display_name
                display_name=$(echo "$def_data" | cut -d'|' -f2)
                [[ -n $display_name ]] && scheme="$display_name"
            fi
            rx_table_row "󰊪" "Mode:" "$mode" "$PINK" "22"
            rx_table_row "󰊪" "Color Scheme:" "$scheme" "$PINK" "22"
            rx_table_separator
            rx_table_spacer

            rx_table_header "󰄈" "Hyprland Look"
            rx_table_row "󰊪" "Opacity:" "$(get_var RETRO_OPACITY 1.0)" "$PINK" "22"
            rx_table_row "󰊪" "Inactive Opacity:" "$(get_var RETRO_INACTIVE_OPACITY 0.8)" "$PINK" "22"
            rx_table_row "󰊪" "Rounding:" "$(get_var RETRO_ROUNDING 10)" "$PINK" "22"
            rx_table_row "󰊪" "Rounding Power:" "$(get_var RETRO_ROUNDING_POWER 2)" "$PINK" "22"
            rx_table_row "󰊪" "Border:" "$(get_var RETRO_BORDER_SIZE 2)" "$PINK" "22"
            rx_table_row "󰊪" "Gap In/Out:" "$(get_var RETRO_GAP_IN 5) / $(get_var RETRO_GAP_OUT 20)" "$PINK" "22"
            rx_table_row "󰊪" "Shadow:" "$(get_var RETRO_SHADOW true) (range: $(get_var RETRO_SHADOW_RANGE 4), power: $(get_var RETRO_SHADOW_RENDER_POWER 3))" "$PINK" "22"
            rx_table_row "󰊪" "Blur:" "$(get_var RETRO_BLUR true) (size: $(get_var RETRO_BLUR_SIZE 3), passes: $(get_var RETRO_BLUR_PASSES 3))" "$PINK" "22"
            rx_table_separator
            rx_table_spacer

            rx_table_header "󰄈" "Kitty"
            rx_table_row "󰊪" "Font:" "$(get_var KITTY_FONT "JetBrainsMono Nerd Font")" "$PINK" "22"
            rx_table_row "󰊪" "Font Size:" "$(get_var KITTY_FONT_SIZE 9.5)" "$PINK" "22"
            rx_table_row "󰊪" "Padding:" "$(get_var KITTY_PADDING 5)" "$PINK" "22"
            rx_table_separator
            rx_table_spacer

            rx_table_header "󰄈" "Rofi"
            rx_table_row "󰊪" "Font:" "$(get_var ROFI_FONT "JetBrainsMono Nerd Font")" "$PINK" "22"
            rx_table_row "󰊪" "Font Size:" "$(get_var ROFI_FONT_SIZE 9.5)" "$PINK" "22"
            rx_table_row "󰊪" "Border:" "$(get_var ROFI_BORDER_SIZE 2)" "$PINK" "22"
            rx_table_row "󰊪" "Rounding:" "$(get_var ROFI_ROUNDING 10)" "$PINK" "22"
            rx_table_row "󰊪" "Padding:" "$(get_var ROFI_PADDING 5)" "$PINK" "22"
            rx_table_separator
            rx_table_spacer
            ;;

        "setup")
            rx_setup_parse "$@"

            local mode_conf
            mode_conf=$(get_var "RETRO_THEME_MODE" "dark")
            local scheme_conf
            scheme_conf=$(get_var "RETRO_THEME_SCHEME" "wallpaper")

            if [[ $SKIP_PROMPT == "true" ]]; then
                _theme_call "--mode" "$mode_conf"
                _theme_call "--theme" "$scheme_conf"
                rx_log "success" "Theme configuration applied with current defaults"
                return 0
            fi

            local new_mode new_scheme
            local new_opacity new_inactive_opacity new_rounding new_rounding_power
            local new_border new_gap_in new_gap_out
            local new_shadow new_shadow_range new_shadow_power
            local new_blur new_blur_size new_blur_passes new_blur_vibrancy
            local new_kitty_font new_kitty_font_size new_kitty_padding
            local new_rofi_font new_rofi_font_size new_rofi_border new_rofi_rounding new_rofi_padding

            # --- Mode ---
            new_mode=$(rx_input_choice "󰄾" "Color Mode" "$mode_conf" "dark" "light")

            # --- Theme ---
            local -a theme_options=("wallpaper")
            local -a theme_internal=("wallpaper")
            while IFS='|' read -r display_name internal_name description; do
                [[ -z $internal_name ]] && continue
                theme_options+=("$internal_name — $description")
                theme_internal+=("$internal_name")
            done < <(_theme_call "--list-themes")

            local theme_default_idx=0
            for i in "${!theme_internal[@]}"; do
                [[ ${theme_internal[$i]} == "$scheme_conf" ]] && theme_default_idx=$i && break
            done
            local theme_default_display="${theme_options[$theme_default_idx]:-wallpaper}"

            local selected_theme
            selected_theme=$(rx_input_choice "󰄾" "Color Scheme" "$theme_default_display" "${theme_options[@]}")
            new_scheme="$selected_theme"
            if [[ $selected_theme == *" — "* ]]; then
                new_scheme="${selected_theme%% — *}"
            fi

            # --- Opacity (float) ---
            new_opacity=$(rx_input "Window opacity" "$(get_var RETRO_OPACITY 1.0)" \
                '^[0-9]+(\.[0-9]+)?$' "Must be a number (e.g. 0.9)")

            # --- Inactive Opacity (float) ---
            new_inactive_opacity=$(rx_input "Inactive window opacity" "$(get_var RETRO_INACTIVE_OPACITY 0.8)" \
                '^[0-9]+(\.[0-9]+)?$' "Must be a number (e.g. 0.8)")

            # --- Rounding ---
            new_rounding=$(rx_input_numeric "Window rounding (px)" "$(get_var RETRO_ROUNDING 10)" 0 50)
            new_rounding_power=$(rx_input_numeric "Rounding power" "$(get_var RETRO_ROUNDING_POWER 2)" 1 10)

            # --- Border ---
            new_border=$(rx_input_numeric "Border size (px)" "$(get_var RETRO_BORDER_SIZE 2)" 0 20)

            # --- Gaps ---
            new_gap_in=$(rx_input_numeric "Gaps between windows (px)" "$(get_var RETRO_GAP_IN 5)" 0 50)
            new_gap_out=$(rx_input_numeric "Gaps around workspace (px)" "$(get_var RETRO_GAP_OUT 20)" 0 100)

            # --- Shadow ---
            new_shadow=false
            rx_confirm "Enable shadows?" "$(get_var RETRO_SHADOW true)" && new_shadow=true
            if [[ $new_shadow == "true" ]]; then
                new_shadow_range=$(rx_input_numeric "Shadow range (px)" "$(get_var RETRO_SHADOW_RANGE 4)" 0 50)
                new_shadow_power=$(rx_input_numeric "Shadow render power" "$(get_var RETRO_SHADOW_RENDER_POWER 3)" 1 10)
            else
                new_shadow_range=$(get_var RETRO_SHADOW_RANGE 4)
                new_shadow_power=$(get_var RETRO_SHADOW_RENDER_POWER 3)
            fi

            # --- Blur ---
            new_blur=false
            rx_confirm "Enable blur?" "$(get_var RETRO_BLUR true)" && new_blur=true
            if [[ $new_blur == "true" ]]; then
                new_blur_size=$(rx_input_numeric "Blur size" "$(get_var RETRO_BLUR_SIZE 3)" 1 20)
                new_blur_passes=$(rx_input_numeric "Blur passes" "$(get_var RETRO_BLUR_PASSES 3)" 1 10)
                new_blur_vibrancy=$(rx_input "Blur vibrancy" "$(get_var RETRO_BLUR_VIBRANCY 0.1696)" \
                    '^[0-9]+(\.[0-9]+)?$' "Must be a number (e.g. 0.1696)")
            else
                new_blur_size=$(get_var RETRO_BLUR_SIZE 3)
                new_blur_passes=$(get_var RETRO_BLUR_PASSES 3)
                new_blur_vibrancy=$(get_var RETRO_BLUR_VIBRANCY 0.1696)
            fi

            # --- Kitty ---
            new_kitty_font=$(_pick_font "Select Kitty font" "$(get_var KITTY_FONT "JetBrainsMono Nerd Font")")
            new_kitty_font_size=$(rx_input "Kitty font size" "$(get_var KITTY_FONT_SIZE 9.5)" \
                '^[0-9]+(\.[0-9]+)?$' "Must be a number (e.g. 9.5)")
            new_kitty_padding=$(rx_input_numeric "Kitty padding (px)" "$(get_var KITTY_PADDING 5)" 0 50)

            # --- Rofi ---
            new_rofi_font=$(_pick_font "Select Rofi font" "$(get_var ROFI_FONT "JetBrainsMono Nerd Font")")
            new_rofi_font_size=$(rx_input "Rofi font size" "$(get_var ROFI_FONT_SIZE 9.5)" \
                '^[0-9]+(\.[0-9]+)?$' "Must be a number (e.g. 9.5)")
            new_rofi_border=$(rx_input_numeric "Rofi border (px)" "$(get_var ROFI_BORDER_SIZE 2)" 0 20)
            new_rofi_rounding=$(rx_input_numeric "Rofi rounding (px)" "$(get_var ROFI_ROUNDING 10)" 0 50)
            new_rofi_padding=$(rx_input_numeric "Rofi padding (px)" "$(get_var ROFI_PADDING 5)" 0 50)

            # --- Summary ---
            rx_setup_summary "󰄈" "Theme Configuration Summary" \
                "Mode" "$new_mode" \
                "Color Scheme" "$new_scheme" \
                "Opacity" "$new_opacity" \
                "Inactive Opacity" "$new_inactive_opacity" \
                "Rounding" "$new_rounding" \
                "Border" "$new_border" \
                "Gap In/Out" "${new_gap_in} / ${new_gap_out}" \
                "Shadow" "$new_shadow" \
                "Blur" "$new_blur" \
                "Kitty Font" "$new_kitty_font" \
                "Rofi Font" "$new_rofi_font"

            rx_setup_confirm || return 0

            # --- Apply ---
            set_var "RETRO_THEME_MODE" "$new_mode"
            set_var "RETRO_THEME_SCHEME" "$new_scheme"

            _theme_call "--apply-colors"

            _theme_call "--set" "opacity" "$new_opacity"
            _theme_call "--set" "inactive_opacity" "$new_inactive_opacity"
            _theme_call "--set" "rounding" "$new_rounding"
            _theme_call "--set" "rounding_power" "$new_rounding_power"
            _theme_call "--set" "border" "$new_border"
            _theme_call "--set" "gap_in" "$new_gap_in"
            _theme_call "--set" "gap_out" "$new_gap_out"
            _theme_call "--set" "shadow" "$new_shadow"
            _theme_call "--set" "shadow_range" "$new_shadow_range"
            _theme_call "--set" "shadow_power" "$new_shadow_power"
            _theme_call "--set" "blur" "$new_blur"
            _theme_call "--set" "blur_size" "$new_blur_size"
            _theme_call "--set" "blur_passes" "$new_blur_passes"
            _theme_call "--set" "blur_vibrancy" "$new_blur_vibrancy"
            _theme_call "--set" "kitty_font" "$new_kitty_font"
            _theme_call "--set" "kitty_font_size" "$new_kitty_font_size"
            _theme_call "--set" "kitty_padding" "$new_kitty_padding"
            _theme_call "--set" "rofi_font" "$new_rofi_font"
            _theme_call "--set" "rofi_font_size" "$new_rofi_font_size"
            _theme_call "--set" "rofi_border" "$new_rofi_border"
            _theme_call "--set" "rofi_rounding" "$new_rofi_rounding"
            _theme_call "--set" "rofi_padding" "$new_rofi_padding"

            rx_setup_success "󰄈" "Theme Configured" \
                "Mode" "$new_mode" \
                "Color Scheme" "$new_scheme" \
                "Opacity" "$new_opacity" \
                "Rounding" "$new_rounding" \
                "Border" "$new_border" \
                "Gap In/Out" "${new_gap_in} / ${new_gap_out}"
            ;;

        "set")
            local key="$1"
            local value="$2"
            if [[ -z $key ]]; then
                rx_log "error" "Usage: retro theme set <name>    — apply a color scheme"
                rx_log "error" "       retro theme set <key> <value> — set a value"
                return 1
            fi
            if [[ -z $value ]]; then
                if bash "$_THEME_CORE" "--theme" "$key"; then
                    rx_log "success" "Color scheme set to ${PINK}$key${RESET}"
                fi
            else
                _theme_set "$key" "$value"
            fi
            ;;

        "mode")
            local mode="$1"
            [[ -z $mode ]] && rx_log "error" "Usage: retro theme mode <dark|light>" && return 1
            _theme_call "--mode" "$mode" && rx_log "success" "Mode set to ${PINK}$mode${RESET}"
            ;;

        "list")
            rx_table_header "󰄈" "Available Color Schemes"
            local wallpaper_desc="Sync with current wallpaper (matugen)"
            [[ ${#wallpaper_desc} -gt 20 ]] && wallpaper_desc="${wallpaper_desc:0:20}.."
            printf " ${PINK}󰊪 ${RESET}%-16s${PINK}%-22s${RESET}${MUTE}%s${RESET}\n" "wallpaper" "—" "$wallpaper_desc"
            while IFS='|' read -r display_name internal_name description; do
                [[ -z $internal_name ]] && continue
                local def_data
                def_data=$(_theme_call "--theme-data" "$internal_name")
                local author
                author=$(echo "$def_data" | cut -d'|' -f3)
                local desc_short="${description:0:20}"
                [[ ${#description} -gt 20 ]] && desc_short="${desc_short}.."
                printf " ${PINK}󰊪 ${RESET}%-16s${PINK}%-20s${RESET}${MUTE}%s${RESET}\n" "$internal_name" "$author" "$desc_short"
            done < <(_theme_call "--list-themes")
            rx_table_separator
            rx_table_spacer
            ;;

        "font")
            local font_action="${1,,}"
            shift 2>/dev/null || true

            case "$font_action" in
                "set")
                    local apps=("kitty" "rofi")
                    local app
                    app=$(rx_menu "󰄾" "Select target app:" "${apps[@]}")
                    [[ -z $app ]] && return 1

                    local font_name
                    font_name=$(_pick_font "Select font for ${app}" "$(get_var "${app^^}_FONT" "")")
                    [[ -z $font_name ]] && return 1

                    if _theme_call "--set" "${app}_font" "$font_name"; then
                        rx_log "success" "${PINK}$app${RESET} font set to ${PINK}$font_name${RESET}"
                    fi
                    ;;
                "size")
                    local apps=("system" "kitty" "rofi")
                    local app
                    app=$(rx_menu "󰄾" "Select target app:" "${apps[@]}")
                    [[ -z $app ]] && return 1

                    local size
                    size=$(rx_input_numeric "Font size for ${app}" "" 1 100)
                    [[ -z $size ]] && return 1

                    case "$app" in
                        "system")
                            rx_log "warn" "System font size is managed by fontconfig/GNOME settings, not Retro"
                            return 1
                            ;;
                        "kitty")
                            if _theme_call "--set" "kitty_font_size" "$size"; then
                                rx_log "success" "${PINK}$app${RESET} font size set to ${PINK}$size${RESET}"
                            fi
                            ;;
                        "rofi")
                            if _theme_call "--set" "rofi_font_size" "$size"; then
                                rx_log "success" "${PINK}$app${RESET} font size set to ${PINK}$size${RESET}"
                            fi
                            ;;
                    esac
                    ;;
                *)
                    rx_log "error" "Usage: retro theme font {set|size}"
                    return 1
                    ;;
            esac
            ;;

        "apply-colors")
            if _theme_call "--apply-colors"; then
                rx_log "success" "Colors regenerated and applied"
            fi
            ;;

        *)
            rx_help_usage "retro theme <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show current theme configuration"
            rx_help_cmd "setup [--yes|-y]" "Interactive theme setup wizard"
            rx_help_cmd "mode <dark|light>" "Set color mode"
            rx_help_cmd "list" "List available color schemes"
            rx_help_cmd "set <name>" "Apply a predefined color scheme (e.g. 'set catppuccin')"
            rx_help_cmd "set <key> <value>" "Set an individual aesthetic value (e.g. 'set opacity 0.95')"
            rx_help_cmd "font {set|size}" "Set font family or size (interactive app picker)"
            rx_help_cmd "apply-colors" "Regenerate colors from wallpaper"
            rx_help_examples
            rx_help_example "retro theme status" "Show current configuration"
            rx_help_example "retro theme setup" "Interactive configuration wizard"
            rx_help_example "retro theme mode dark" "Switch to dark mode"
            rx_help_example "retro theme set catppuccin" "Apply Catppuccin color scheme"
            rx_help_example "retro theme set opacity 0.95" "Set window opacity"
            rx_help_example "retro theme font set" "Set font for an app"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "theme" "Centralized theme management — fonts, colors, appearance" "cmd_theme"
