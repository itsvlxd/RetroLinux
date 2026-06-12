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

_list_displays() {
    local files=("$THEMES_DIR"/*.json)
    if [[ ! -e ${files[0]} ]]; then
        return
    fi
    for f in "${files[@]}"; do
        local base display author primary
        local red green yellow blue magenta cyan white black
        base=$(basename "$f" .json)
        display=$(jq -r '.name // empty' "$f" 2>/dev/null)
        author=$(jq -r '.author // empty' "$f" 2>/dev/null | sed 's/ *([^)]* variant) *//')
        primary=$(jq -r '.color_map.primary // empty' "$f" 2>/dev/null)

        if [[ -n $primary ]]; then
            red=$(jq -r '.color_map.red // empty' "$f" 2>/dev/null)
            green=$(jq -r '.color_map.green // empty' "$f" 2>/dev/null)
            yellow=$(jq -r '.color_map.yellow // empty' "$f" 2>/dev/null)
            blue=$(jq -r '.color_map.blue // empty' "$f" 2>/dev/null)
            magenta=$(jq -r '.color_map.magenta // empty' "$f" 2>/dev/null)
            cyan=$(jq -r '.color_map.cyan // empty' "$f" 2>/dev/null)
            white=$(jq -r '.color_map.white // empty' "$f" 2>/dev/null)
            black=$(jq -r '.color_map.black // empty' "$f" 2>/dev/null)
        else
            local palette_path palette_file
            palette_path=$(jq -r '.palette // empty' "$f" 2>/dev/null)
            if [[ -n $palette_path ]]; then
                palette_file="$THEMES_DIR/$palette_path"
                if command -v convert >/dev/null 2>&1 && [[ -f $palette_file ]]; then
                    local -a sampled
                    mapfile -t sampled < <(convert "$palette_file" -sample 8x1! -depth 8 txt:- 2>/dev/null | grep -oP '#[0-9A-Fa-f]{6}')
                    if [[ ${#sampled[@]} -ge 1 ]]; then
                        primary="${sampled[0]#\#}"
                        red="${sampled[0]#\#}"
                        green="${sampled[1]#\#}"
                        yellow="${sampled[2]#\#}"
                        blue="${sampled[3]#\#}"
                        magenta="${sampled[4]#\#}"
                        cyan="${sampled[5]#\#}"
                        white="${sampled[6]#\#}"
                        black="${sampled[7]#\#}"
                    fi
                fi
            fi
        fi

        echo "${display:-$base}|$base|${author:--}|$primary|$red|$green|$yellow|$blue|$magenta|$cyan|$white|$black"
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
    bash "$RETRO_DIR/retro.sh" theme refresh >/dev/null 2>&1
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

    local theme_name="adw-gtk3"
    local portal_theme="prefer-light"
    local gtk3_prefer="0"
    [[ $mode == "dark" ]] && theme_name="adw-gtk3-dark" && portal_theme="prefer-dark" && gtk3_prefer="1"

    gsettings set org.gnome.desktop.interface color-scheme "$portal_theme" 2>/dev/null
    gsettings set org.gnome.desktop.interface gtk-theme "$theme_name" 2>/dev/null
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" 2>/dev/null

    mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
    cat >"$HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=$theme_name
gtk-icon-theme-name=Papirus-Dark
gtk-application-prefer-dark-theme=$gtk3_prefer
EOF
    cat >"$HOME/.config/gtk-4.0/settings.ini" <<EOF
[Settings]
gtk-icon-theme-name=Papirus-Dark
EOF

    mkdir -p "$HOME/.config/Kvantum"
    cat >"$HOME/.config/Kvantum/kvantum.kvconfig" <<EOF
[General]
theme=matugen
EOF
    command -v kvantummanager >/dev/null 2>&1 && kvantummanager --set matugen >/dev/null 2>&1 &

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

_detect_browser_profiles() {
    local zen_ini="$HOME/.zen/profiles.ini"
    local ff_ini="$HOME/.mozilla/firefox/profiles.ini"

    # Zen browser
    if [[ -f $zen_ini ]]; then
        local install_default=""
        install_default=$(awk '
            BEGIN { RS=""; FS="\n" }
            /^\[Install/ {
                for (i=1; i<=NF; i++)
                    if ($i ~ /^Default=/) { print substr($i,9); exit }
            }
        ' "$zen_ini")

        while IFS='|' read -r name path rel is_def; do
            local abs="$path"
            [[ $rel == "1" ]] && abs="$HOME/.zen/$path"
            [[ -d $abs ]] && echo "zen|$abs"
        done < <(awk '
            BEGIN { RS=""; FS="\n" }
            /^\[Profile/ {
                n=""; p=""; r=0; d=0
                for (i=1; i<=NF; i++) {
                    if ($i ~ /^Name=/) n=substr($i,6)
                    if ($i ~ /^Path=/) p=substr($i,6)
                    if ($i ~ /^IsRelative=1/) r=1
                    if ($i ~ /^Default=1/) d=1
                }
                print n "|" p "|" r "|" d
            }
        ' "$zen_ini")

        if [[ -n $install_default ]]; then
            _resolve_install_default "$install_default" "$HOME/.zen" "zen"
        fi
    fi

    # Firefox
    if [[ -f $ff_ini ]]; then
        local install_default=""
        install_default=$(awk '
            BEGIN { RS=""; FS="\n" }
            /^\[Install/ {
                for (i=1; i<=NF; i++)
                    if ($i ~ /^Default=/) { print substr($i,9); exit }
            }
        ' "$ff_ini")

        while IFS='|' read -r name path rel is_def; do
            local abs="$path"
            [[ $rel == "1" ]] && abs="$HOME/.mozilla/firefox/$path"
            [[ -d $abs ]] && echo "firefox|$abs"
        done < <(awk '
            BEGIN { RS=""; FS="\n" }
            /^\[Profile/ {
                n=""; p=""; r=0; d=0
                for (i=1; i<=NF; i++) {
                    if ($i ~ /^Name=/) n=substr($i,6)
                    if ($i ~ /^Path=/) p=substr($i,6)
                    if ($i ~ /^IsRelative=1/) r=1
                    if ($i ~ /^Default=1/) d=1
                }
                print n "|" p "|" r "|" d
            }
        ' "$ff_ini")

        if [[ -n $install_default ]]; then
            _resolve_install_default "$install_default" "$HOME/.mozilla/firefox" "firefox"
        fi
    fi
}

_resolve_install_default() {
    local val="$1" base="$2" browser="$3"
    if [[ -d $val ]]; then
        echo "${browser}|$val"
    elif [[ -d "$base/$val" ]]; then
        echo "${browser}|$base/$val"
    else
        awk -v b="$base" -v t="$val" -v br="$browser" '
            BEGIN { RS=""; FS="\n" }
            /^\[Profile/ {
                n=""; p=""; r=0
                for (i=1; i<=NF; i++) {
                    if ($i ~ /^Name=/) n=substr($i,6)
                    if ($i ~ /^Path=/) p=substr($i,6)
                    if ($i ~ /^IsRelative=1/) r=1
                }
                if (n == t || p == t) {
                    if (r) print br "|" b "/" p; else print br "|" p
                }
            }
        ' "$base/profiles.ini" 2>/dev/null
    fi
}

rx_theme_deploy_browsers() {
    local firefox_css="$HOME/.config/retro/themes/firefox.css"
    local src_websites="$HOME/.config/matugen/websites"
    local deployed=0

    while IFS='|' read -r browser profile_dir; do
        [[ -z $profile_dir || ! -d $profile_dir ]] && continue

        local chrome_dir="$profile_dir/chrome"
        local dst_websites="$chrome_dir/websites"
        mkdir -p "$dst_websites"

        if [[ -d $src_websites ]]; then
            for site_css in "$src_websites"/*.css; do
                [[ -f $site_css ]] && cp -u "$site_css" "$dst_websites/"
            done
            for dst_file in "$dst_websites"/*.css; do
                [[ -f $dst_file ]] || continue
                local base
                base=$(basename "$dst_file")
                if [[ ! -f "$src_websites/$base" ]]; then
                    rm -f "$dst_file"
                fi
            done
        fi

        if [[ -f $firefox_css ]]; then
            ln -sf "$firefox_css" "$chrome_dir/colors.css"
        fi

        if [[ -f $chrome_dir/userContent.css ]]; then
            if ! grep -q "Generated by retro" "$chrome_dir/userContent.css" 2>/dev/null; then
                cp "$chrome_dir/userContent.css" "$chrome_dir/userContent.css.bak"
            fi
        fi

        {
            printf '/* Generated by retro theme engine — do not edit */\n'
            printf '@import url("%s/colors.css");\n' "$chrome_dir"
            printf '\n'
            if [[ -d $src_websites ]]; then
                local site_files=("$src_websites"/*.css)
                if [[ -e ${site_files[0]} ]]; then
                    for wc in "${site_files[@]}"; do
                        local base
                        base=$(basename "$wc")
                        printf '@import url("%s/websites/%s");\n' "$chrome_dir" "$base"
                    done
                fi
            fi
        } > "$chrome_dir/userContent.css"

        local user_js="$profile_dir/user.js"
        local pref_line='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
        if [[ -f $user_js ]]; then
            grep -qF "$pref_line" "$user_js" 2>/dev/null || echo "$pref_line" >> "$user_js"
        else
            echo "$pref_line" > "$user_js"
        fi

        rx_log "info" "Browser chrome deployed: ${PINK}${browser}${RESET} → ${GRAY}$profile_dir${RESET}"
        deployed=1
    done < <(_detect_browser_profiles | sort -u)

    [[ $deployed -eq 0 ]] && rx_log "warn" "No browser profiles found to deploy"
}

rx_theme_browser_status() {
    local profiles
    profiles=$(_detect_browser_profiles | sort -u)
    if [[ -z $profiles ]]; then
        return
    fi
    while IFS='|' read -r browser path; do
        local chrome_dir="$path/chrome"
        local status=""
        if [[ -d $chrome_dir ]]; then
            local site_count=0
            if [[ -d $chrome_dir/websites ]]; then
                site_count=$(find "$chrome_dir/websites" -maxdepth 1 -name '*.css' 2>/dev/null | wc -l)
            fi
            if [[ -L $chrome_dir/colors.css ]] && readlink "$chrome_dir/colors.css" | grep -q 'firefox.css'; then
                status="${GREEN}deployed${RESET}"
                [[ $site_count -gt 0 ]] && status+=" / ${CYAN}${site_count} sites${RESET}"
            else
                status="${MUTE}no colors${RESET}"
                [[ $site_count -gt 0 ]] && status+=" / ${CYAN}${site_count} sites${RESET}"
            fi
        else
            status="${MUTE}no chrome${RESET}"
        fi
        echo "${browser}|${path}|${status}"
    done <<< "$profiles"
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
    rx_set_papirus_folder_color
    rx_theme_deploy_browsers
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
    "--list-display")
        _list_displays
        ;;
    "--theme-data")
        _load_theme_def "$2"
        ;;
    "--deploy-browsers")
        rx_theme_deploy_browsers
        ;;
    "--browser-status")
        rx_theme_browser_status
        ;;
    "--papirus-setup")
        command -v papirus-folders >/dev/null 2>&1 || return 0
        sudo rm -f /etc/sudoers.d/papirus-folders
        cat <<EOF | sudo tee /etc/sudoers.d/papirus-folders >/dev/null
%wheel ALL=(ALL) NOPASSWD: SETENV: /usr/bin/papirus-folders
Defaults!/usr/bin/papirus-folders !env_reset
EOF
        sudo chmod 440 /etc/sudoers.d/papirus-folders
        sudo mkdir -p /usr/share/icons/default /etc/gtk-3.0 /etc/gtk-4.0
        cat <<EOF | sudo tee /usr/share/icons/default/index.theme >/dev/null
[Icon Theme]
Inherits=Papirus-Dark
EOF
        cat <<EOF | sudo tee /etc/gtk-3.0/settings.ini >/dev/null
[Settings]
gtk-icon-theme-name = Papirus-Dark
EOF
        cat <<EOF | sudo tee /etc/gtk-4.0/settings.ini >/dev/null
[Settings]
gtk-icon-theme-name = Papirus-Dark
EOF
        ;;
esac
