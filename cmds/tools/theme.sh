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
            _status_line() {
                local icon="$1" label="$2" value="$3"
                printf " ${PINK}%s${RESET} %-22s ${PINK}%s${RESET}\n" "$icon" "$label" "$value"
            }
            _lighten() {
                local h="$1" p="${2:-60}"
                local r=$((16#${h:0:2})) g=$((16#${h:2:2})) b=$((16#${h:4:2}))
                r=$((r + (255 - r) * p / 100))
                g=$((g + (255 - g) * p / 100))
                b=$((b + (255 - b) * p / 100))
                printf "%02x%02x%02x" $r $g $b
            }
            _darken() {
                local h="$1" p="${2:-75}"
                local r=$((16#${h:0:2})) g=$((16#${h:2:2})) b=$((16#${h:4:2}))
                r=$((r * (100 - p) / 100))
                g=$((g * (100 - p) / 100))
                b=$((b * (100 - p) / 100))
                printf "%02x%02x%02x" $r $g $b
            }

            local mode scheme wallpaper
            mode=$(get_var "RETRO_THEME_MODE" "dark")
            mode="${mode^}"
            scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")
            if [[ $scheme != "wallpaper" ]]; then
                local def_data display_name
                def_data=$(_theme_call "--theme-data" "$scheme")
                display_name=$(echo "$def_data" | cut -d'|' -f2)
                [[ -n $display_name ]] && scheme="$display_name"
            fi
            scheme="${scheme^}"

            echo -e "\n ${PINK}󰏘 Theme Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

            _status_line "󰊪" "Environment:" "$mode / $scheme"

            wallpaper=$(get_var "WALL_CURRENT" "")
            if [[ -n $wallpaper ]]; then
                wallpaper="${wallpaper##*/}"
                wallpaper="${wallpaper%.*}"
            else
                wallpaper="(none)"
            fi
            _status_line "󰸉" "Wallpaper:" "$wallpaper"

            local lua_file="$HOME/.config/retro/themes/hyprland-colors.lua"
            local primary_hex=""
            if [[ -f $lua_file ]]; then
                primary_hex=$(grep -oP '^\s*primary\s*=\s*"0x\K[0-9a-fA-F]{6}' "$lua_file" | head -1)
            fi
            if [[ -n $primary_hex ]]; then
                local light_hex dark_hex
                light_hex=$(_lighten "$primary_hex" 60)
                dark_hex=$(_darken "$primary_hex" 75)
                _status_line "󰏘" "Accent Palette:" \
                    "${GRAY}Primary:${PINK} #${primary_hex}  ${GRAY}Light:${PINK} #${light_hex}  ${GRAY}Dark:${PINK} #${dark_hex}"
            else
                _status_line "󰏘" "Accent Palette:" "(not generated yet)"
            fi

            local gtk_theme qt_theme
            gtk_theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo "N/A")
            gtk_theme="${gtk_theme//\'/}"
            qt_theme=$(grep '^theme=' "$HOME/.config/Kvantum/kvantum.kvconfig" 2>/dev/null | cut -d= -f2 || echo "N/A")
            _status_line "󰉋" "Toolkits:" "${GRAY}GTK:${PINK} ${gtk_theme}  ${GRAY}Qt:${PINK} Kvantum (${qt_theme})"

            local icon_theme cursor_theme
            icon_theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || echo "N/A")
            icon_theme="${icon_theme//\'/}"
            cursor_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || echo "N/A")
            cursor_theme="${cursor_theme//\'/}"
            local browser_state
            if [[ $(get_var "RETRO_BROWSER_THEME" "true") == "true" ]]; then
                browser_state="${SUCCESS}● Enabled"
            else
                browser_state="${MUTE}○ Disabled"
            fi
            _status_line "󰉏" "Asset Themes:" "${GRAY}Icons:${PINK} ${icon_theme}  ${GRAY}Cursor:${PINK} ${cursor_theme}  ${GRAY}Browser:${browser_state}"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

            _status_line "󰃠" "Window Opacity:" \
                "$(get_var RETRO_OPACITY 1.0) ${GRAY}active${PINK}  $(get_var RETRO_INACTIVE_OPACITY 0.8) ${GRAY}inactive"
            _status_line "󰋙" "Layout Geometry:" \
                "${GRAY}Borders:${PINK} $(get_var RETRO_BORDER_SIZE 2)px  ${GRAY}Rounding:${PINK} $(get_var RETRO_ROUNDING 10)px (pwr: $(get_var RETRO_ROUNDING_POWER 2))"
            _status_line "󰢤" "Workspace Gaps:" \
                "$(get_var RETRO_GAP_IN 5) ${GRAY}inner${PINK}  $(get_var RETRO_GAP_OUT 20) ${GRAY}outer"
            _status_line "󰏗" "Compositor FX:" \
                "${GRAY}Shadows:${PINK} $(get_var RETRO_SHADOW true)  ${GRAY}Blur:${PINK} $(get_var RETRO_BLUR true)"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

            _status_line "󰛖" "Kitty Terminal:" \
                "$(get_var KITTY_FONT "JetBrainsMono Nerd Font") ($(get_var KITTY_FONT_SIZE 9.5)pt)  ${GRAY}Padding:${PINK} $(get_var KITTY_PADDING 15)"
            _status_line "󰏗" "Rofi Launcher:" \
                "$(get_var ROFI_FONT "JetBrainsMono Nerd Font") ($(get_var ROFI_FONT_SIZE 9.5)pt)  ${GRAY}Border:${PINK} $(get_var ROFI_BORDER_SIZE 2)  ${GRAY}Round:${PINK} $(get_var ROFI_ROUNDING 10)"

            rx_table_separator
            rx_table_spacer
            ;;

        "browsers")
            local subcmd="${1:-toggle}"
            case "$subcmd" in
                "enable")
                    result=$(_theme_call "--browsers-enable")
                    if [[ $result == "enabled" ]]; then
                        rx_log "success" "Browser theme integration Enabled"
                    fi
                    ;;
                "disable")
                    _theme_call "--browsers-disable"
                    rx_log "success" "Browser theme integration Disabled"
                    ;;
                "refresh")
                    _theme_call "--deploy-browsers"
                    rx_log "success" "Browser chrome deployed"
                    ;;
                toggle | *)
                    local result
                    result=$(_theme_call "--toggle-browsers")
                    if [[ $result == "enabled" ]]; then
                        rx_log "success" "Browser theme integration Enabled"
                    elif [[ $result == "disabled" ]]; then
                        rx_log "success" "Browser theme integration Disabled"
                    fi
                    ;;
            esac
            ;;

        "setup")
            rx_setup_parse "$@"
            _theme_call "--papirus-setup"

            local theme_exists=false
            [[ $(get_var "RETRO_THEME_SCHEME" "") != "" ]] && theme_exists=true
            rx_setup_check_needed "$theme_exists" && return 0

            local mode_conf
            mode_conf=$(get_var "RETRO_THEME_MODE" "dark")
            local scheme_conf
            scheme_conf=$(get_var "RETRO_THEME_SCHEME" "wallpaper")

            if [[ $RX_SETUP_YES == "true" ]]; then
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

            new_opacity=$(rx_input "Window opacity" "$(get_var RETRO_OPACITY 1.0)" \
                '^[0-9]+(\.[0-9]+)?$' "Must be a number (e.g. 0.9)")

            new_inactive_opacity=$(rx_input "Inactive window opacity" "$(get_var RETRO_INACTIVE_OPACITY 0.8)" \
                '^[0-9]+(\.[0-9]+)?$' "Must be a number (e.g. 0.8)")

            new_rounding=$(rx_input_numeric "Window rounding (px)" "$(get_var RETRO_ROUNDING 10)" 0 50)
            new_rounding_power=$(rx_input_numeric "Rounding power" "$(get_var RETRO_ROUNDING_POWER 2)" 1 10)

            new_border=$(rx_input_numeric "Border size (px)" "$(get_var RETRO_BORDER_SIZE 2)" 0 20)

            new_gap_in=$(rx_input_numeric "Gaps between windows (px)" "$(get_var RETRO_GAP_IN 5)" 0 50)
            new_gap_out=$(rx_input_numeric "Gaps around workspace (px)" "$(get_var RETRO_GAP_OUT 20)" 0 100)

            new_shadow=false
            rx_confirm "Enable shadows?" "$(get_var RETRO_SHADOW true)" && new_shadow=true
            if [[ $new_shadow == "true" ]]; then
                new_shadow_range=$(rx_input_numeric "Shadow range (px)" "$(get_var RETRO_SHADOW_RANGE 4)" 0 50)
                new_shadow_power=$(rx_input_numeric "Shadow render power" "$(get_var RETRO_SHADOW_RENDER_POWER 3)" 1 10)
            else
                new_shadow_range=$(get_var RETRO_SHADOW_RANGE 4)
                new_shadow_power=$(get_var RETRO_SHADOW_RENDER_POWER 3)
            fi

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

            new_kitty_font=$(_pick_font "Select Kitty font" "$(get_var KITTY_FONT "JetBrainsMono Nerd Font")")
            new_kitty_font_size=$(rx_input "Kitty font size" "$(get_var KITTY_FONT_SIZE 9.5)" \
                '^[0-9]+(\.[0-9]+)?$' "Must be a number (e.g. 9.5)")
            new_kitty_padding=$(rx_input_numeric "Kitty padding (px)" "$(get_var KITTY_PADDING 5)" 0 50)

            new_rofi_font=$(_pick_font "Select Rofi font" "$(get_var ROFI_FONT "JetBrainsMono Nerd Font")")
            new_rofi_font_size=$(rx_input "Rofi font size" "$(get_var ROFI_FONT_SIZE 9.5)" \
                '^[0-9]+(\.[0-9]+)?$' "Must be a number (e.g. 9.5)")
            new_rofi_border=$(rx_input_numeric "Rofi border (px)" "$(get_var ROFI_BORDER_SIZE 2)" 0 20)
            new_rofi_rounding=$(rx_input_numeric "Rofi rounding (px)" "$(get_var ROFI_ROUNDING 10)" 0 50)
            new_rofi_padding=$(rx_input_numeric "Rofi padding (px)" "$(get_var ROFI_PADDING 5)" 0 50)

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
            _color_dot() {
                local hex="$1"
                if [[ -z $hex ]]; then
                    echo -ne "${MUTE}●${RESET}"
                    return
                fi
                hex="${hex#\#}"
                local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
                echo -ne "\e[38;2;${r};${g};${b}m●\e[0m"
            }
            _color_text() {
                local hex="$1" text="$2"
                if [[ -z $hex ]]; then
                    echo -ne "${PINK}${text}${RESET}"
                    return
                fi
                hex="${hex#\#}"
                local r=$((16#${hex:0:2})) g=$((16#${hex:2:2})) b=$((16#${hex:4:2}))
                echo -ne "\e[38;2;${r};${g};${b}m${text}\e[0m"
            }

            echo -e "\n ${PINK}󰄈 Available Color Schemes${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────────────────────────────────${RESET}"

            local lua_file="$HOME/.config/retro/themes/hyprland-colors.lua"
            local css_file="$HOME/.config/retro/themes/colors.css"
            local wall_primary=""
            local -a wall_dots=()
            if [[ -f $lua_file ]]; then
                wall_primary=$(grep -oP '^\s*primary\s*=\s*"0x\K[0-9a-fA-F]{6}' "$lua_file" | head -1)
            fi
            if [[ -f $css_file ]]; then
                for i in 0 1 2 3 4 5 6 7; do
                    local c
                    c=$(grep -oP "@define-color color${i}\s+\K#[0-9a-fA-F]+" "$css_file" | head -1)
                    c="${c#\#}"
                    wall_dots+=("$c")
                done
            fi

            echo -n " ${PINK}󰊪${RESET} "
            _color_text "$wall_primary" "wallpaper"
            local pad=$((22 - 9))
            printf "%${pad}s" ""
            echo -ne "${GRAY}-${RESET}"
            local auth_pad=$((24 - 1))
            printf "%${auth_pad}s" ""
            for dot in "${wall_dots[@]:-}"; do
                _color_dot "$dot"
                echo -n " "
            done
            echo

            while IFS='|' read -r display internal author primary red green yellow blue magenta cyan white black; do
                [[ -z $internal ]] && continue
                echo -n " ${PINK}󰊪${RESET} "
                _color_text "$primary" "$display"
                local name_len=${#display}
                local name_pad=$((22 - name_len))
                [[ $name_pad -lt 1 ]] && name_pad=1
                printf "%${name_pad}s" ""
                echo -ne "${GRAY}${author}${RESET}"
                local auth_len=${#author}
                local auth_pad=$((24 - auth_len))
                [[ $auth_pad -lt 1 ]] && auth_pad=1
                printf "%${auth_pad}s" ""
                for c in "$red" "$green" "$yellow" "$blue" "$magenta" "$cyan" "$white" "$black"; do
                    _color_dot "$c"
                    echo -n " "
                done
                echo
            done < <(_theme_call "--list-display")

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────────────────────────────────${RESET}"
            echo
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

        "refresh")
            local mode
            mode=$(get_var "RETRO_THEME_MODE" "dark")
            local theme="adw-gtk3"
            [[ $mode == "dark" ]] && theme="adw-gtk3-dark"
            gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" 2>/dev/null
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null
            if command -v xsettingsd >/dev/null 2>&1; then
                mkdir -p "$HOME/.config/xsettingsd"
                cat >"$HOME/.config/xsettingsd/xsettingsd.conf" <<EOF
Net/ThemeName "Adwaita"
EOF
                timeout 0.1s xsettingsd 2>/dev/null
                cat >"$HOME/.config/xsettingsd/xsettingsd.conf" <<EOF
Net/ThemeName "$theme"
EOF
                timeout 0.1s xsettingsd 2>/dev/null
            fi
            if command -v kvantummanager >/dev/null 2>&1; then
                kvantummanager --set matugen >/dev/null 2>&1 &
            fi
            rx_log "success" "GTK/Qt theme reloaded into all open apps"
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
            rx_help_cmd "browsers" "Deploy colors and website themes to Firefox/Zen profiles"
            rx_help_cmd "refresh" "Live-reload GTK3/GTK4 theme into running apps"
            rx_help_examples
            rx_help_example "retro theme status" "Show current configuration"
            rx_help_example "retro theme setup" "Interactive configuration wizard"
            rx_help_example "retro theme mode dark" "Switch to dark mode"
            rx_help_example "retro theme set catppuccin" "Apply Catppuccin color scheme"
            rx_help_example "retro theme set opacity 0.95" "Set window opacity"
            rx_help_example "retro theme browsers" "Deploy colors + website themes to browsers"
            rx_help_example "retro theme font set" "Set font for an app"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "theme" "Centralized theme management — fonts, colors, appearance" "cmd_theme"
