#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "theme"

THEMES_DIR="$RETRO_DIR/themes"
USER_THEMES_DIR="${RETRO_CONFIG:-$HOME/.config/retro}/themes"
OVERRIDE_DIR="${USER_THEMES_DIR}/overrides"

_resolve_theme_file() {
    local name="$1"
    local file="$THEMES_DIR/${name}.json"
    [[ -f $file ]] && echo "$file" && return
    local normalized=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
    file="$THEMES_DIR/${normalized}.json"
    [[ -f $file ]] && echo "$file" && return
    file="$USER_THEMES_DIR/${name}.json"
    [[ -f $file ]] && echo "$file" && return
    file="$USER_THEMES_DIR/${normalized}.json"
    [[ -f $file ]] && echo "$file" && return
    for f in "$THEMES_DIR"/*.json "$USER_THEMES_DIR"/*.json; do
        [[ $(jq -r '.name // empty' "$f" 2>/dev/null) == "$name" ]] && echo "$f" && return
    done
    return 1
}

_load_theme_def() {
    local name="$1"
    local file=$(_resolve_theme_file "$name")
    [[ -z $file ]] && return 1
    local resolved=$(basename "$file" .json)
    local palette_path
    palette_path=$(jq -r '.palette // empty' "$file" 2>/dev/null)
    local display_name
    display_name=$(jq -r '.name // empty' "$file" 2>/dev/null)
    local author
    author=$(jq -r '.author // empty' "$file" 2>/dev/null)
    local description
    description=$(jq -r '.description // empty' "$file" 2>/dev/null)
    echo "$palette_path|${display_name:-$name}|${author:--}|$description|$resolved"
}

_list_themes() {
    local dirs=("$THEMES_DIR" "$USER_THEMES_DIR")
    for dir in "${dirs[@]}"; do
        [[ ! -d $dir ]] && continue
        for f in "$dir"/*.json; do
            [[ ! -f $f ]] && continue
            local base
            base=$(basename "$f" .json)
            local display
            display=$(jq -r '.name // empty' "$f" 2>/dev/null)
            local description
            description=$(jq -r '.description // empty' "$f" 2>/dev/null)
            echo "${display:-$base}|$base|$description"
        done
    done
}

_list_displays() {
    local all_files=()
    for dir in "$THEMES_DIR" "$USER_THEMES_DIR"; do
        [[ ! -d $dir ]] && continue
        for f in "$dir"/*.json; do
            [[ -f $f ]] && all_files+=("$f")
        done
    done
    [[ ${#all_files[@]} -eq 0 ]] && return
    for f in "${all_files[@]}"; do
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
        gtk_font) var_name="GTK_FONT" ;;
        gtk_font_size) var_name="GTK_FONT_SIZE" ;;
        scheme)
            rx_theme_apply_scheme "$value"
            return $?
            ;;
        *)
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

rx_theme_apply_gtk_font() {
    local gtk_font
    gtk_font=$(get_var "GTK_FONT" "Inter")
    local gtk_font_size
    gtk_font_size=$(get_var "GTK_FONT_SIZE" "10")
    local font_line="gtk-font-name=${gtk_font} ${gtk_font_size}"

    mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
    for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        [[ -f $f ]] && sed -i "/^gtk-font-name=/d" "$f"
        echo "$font_line" >>"$f"
    done

    for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        [[ -f $f ]] || continue
        for key in "gtk-xft-antialias" "gtk-xft-hinting" "gtk-xft-hintstyle" "gtk-xft-rgba"; do
            sed -i "/^${key}=/d" "$f"
        done
        cat >>"$f" <<'EOF'
gtk-xft-antialias=1
gtk-xft-hinting=0
gtk-xft-hintstyle=hintnone
gtk-xft-rgba=rgb
EOF
    done

    local gtk2rc="$HOME/.gtkrc-2.0"
    for key in "gtk-xft-antialias" "gtk-xft-hinting" "gtk-xft-hintstyle" "gtk-xft-rgba"; do
        [[ -f $gtk2rc ]] && sed -i "/^${key}/d" "$gtk2rc"
    done
    cat >>"$gtk2rc" <<'EOF'
gtk-xft-antialias=1
gtk-xft-hinting=0
gtk-xft-hintstyle="hintnone"
gtk-xft-rgba="rgb"
EOF

    local css_files=(
        "${RETRO_CONFIG:-$HOME/.config/retro}/themes/colors.css"
        "$HOME/.config/gtk-3.0/gtk.css"
        "$HOME/.config/gtk-4.0/gtk.css"
    )
    for f in "${css_files[@]}"; do
        [[ -f $f ]] || continue
        sed -i "s|REPLACE_RETRO_FONT|${gtk_font}|g" "$f"
        sed -i "s|REPLACE_RETRO_SIZE|${gtk_font_size}|g" "$f"
    done
}

rx_theme_apply_mode() {
    local mode="$1"

    case "$mode" in
        dark | light) ;;
        *)
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
    gsettings set org.gnome.desktop.interface font-antialiasing 'rgba' 2>/dev/null
    gsettings set org.gnome.desktop.interface font-hinting 'none' 2>/dev/null

    mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
    cat >"$HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=$theme_name
gtk-icon-theme-name=Papirus-Dark
gtk-application-prefer-dark-theme=$gtk3_prefer
gtk-font-name=$(get_var "GTK_FONT" "Inter") $(get_var "GTK_FONT_SIZE" "10")
gtk-xft-antialias=1
gtk-xft-hinting=0
gtk-xft-hintstyle=hintnone
gtk-xft-rgba=rgb
EOF
    cat >"$HOME/.config/gtk-4.0/settings.ini" <<EOF
[Settings]
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=$(get_var "GTK_FONT" "Inter") $(get_var "GTK_FONT_SIZE" "10")
gtk-xft-antialias=1
gtk-xft-hinting=0
gtk-xft-hintstyle=hintnone
gtk-xft-rgba=rgb
EOF

    mkdir -p "$HOME/.config/Kvantum"
    cat >"$HOME/.config/Kvantum/kvantum.kvconfig" <<EOF
[General]
theme=retro
EOF
    command -v kvantummanager >/dev/null 2>&1 && kvantummanager --set retro >/dev/null 2>&1 &

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
    rx_theme_deploy_root_config
    local cursor cursor_size
    cursor=$(get_var "RETRO_CURSOR_THEME" "auto")
    cursor_size=$(get_var "RETRO_CURSOR_SIZE" "24")
    rx_cursor_set "$cursor" "$cursor_size" >/dev/null
}

rx_theme_apply_scheme() {
    local scheme="$1"

    if [[ $scheme == "wallpaper" ]]; then
        set_var "RETRO_THEME_SCHEME" "wallpaper"
        rx_log_file "debug" "rx_theme_apply_scheme: RETRO_CONFIG=$RETRO_CONFIG"
        local wallpaper
        wallpaper=$(get_var "WALL_CURRENT" "")
        rx_log_file "debug" "rx_theme_apply_scheme: scheme=wallpaper, WALL_CURRENT=$wallpaper"
        if [[ -z $wallpaper ]]; then
            rx_log_file "warn" "rx_theme_apply_scheme: WALL_CURRENT is empty"
            return 0
        fi
        if [[ ! -f $wallpaper ]]; then
            rx_log_file "error" "rx_theme_apply_scheme: file not found: $wallpaper"
            return 0
        fi
        rx_log_file "info" "rx_theme_apply_scheme: calling rx_theme_apply_colors"
        rx_theme_apply_colors
        return 0
    fi

    local def_data
    def_data=$(_load_theme_def "$scheme")
    if [[ -z $def_data ]]; then
        return 1
    fi

    local resolved
    resolved=$(echo "$def_data" | cut -d'|' -f5)
    set_var "RETRO_THEME_SCHEME" "$resolved"
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
    if [[ $val == /* && -d $val ]]; then
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

rx_theme_clean_browsers() {
    while IFS='|' read -r browser profile_dir; do
        [[ -z $profile_dir || ! -d $profile_dir ]] && continue

        local chrome_dir="$profile_dir/chrome"
        [[ ! -d $chrome_dir ]] && continue

        [[ -L $chrome_dir/colors.css ]] && rm -f "$chrome_dir/colors.css"

        if [[ -f $chrome_dir/userContent.css ]] && grep -q "Generated by retro" "$chrome_dir/userContent.css" 2>/dev/null; then
            rm -f "$chrome_dir/userContent.css"
            if [[ -f $chrome_dir/userContent.css.bak ]]; then
                mv "$chrome_dir/userContent.css.bak" "$chrome_dir/userContent.css"
            fi
        fi

        rm -rf "$chrome_dir/websites" 2>/dev/null

        if [[ -z $(ls -A "$chrome_dir" 2>/dev/null) ]]; then
            rmdir "$chrome_dir" 2>/dev/null
        fi
    done < <(_detect_browser_profiles | sort -u)
}

rx_theme_deploy_browsers() {
    local verbose=${1:-0}

    if [[ $(get_var "RETRO_BROWSER_THEME" "true") != "true" ]]; then
        [[ $verbose -eq 1 ]] && rx_log_file "warn" "Browser theme integration is disabled (enable via 'retro theme browsers enable')"
        return 0
    fi

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
        } >"$chrome_dir/userContent.css"

        local user_js="$profile_dir/user.js"
        local pref_line='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
        if [[ -f $user_js ]]; then
            grep -qF "$pref_line" "$user_js" 2>/dev/null || echo "$pref_line" >>"$user_js"
        else
            echo "$pref_line" >"$user_js"
        fi

        [[ $verbose -eq 1 ]] && rx_log_file "info" "Browser chrome deployed: ${PINK}${browser}${RESET} → ${GRAY}$profile_dir${RESET}"
        ((deployed++))
    done < <(_detect_browser_profiles | sort -u)

    if [[ $deployed -eq 0 ]]; then
        rx_log_file "warn" "No browser profiles found to deploy"
    elif [[ $verbose -eq 0 ]]; then
        rx_log_file "info" "Browser chrome deployed to ${PINK}${deployed}${RESET} profile(s)"
    fi
}

rx_theme_browser_status() {
    if [[ $(get_var "RETRO_BROWSER_THEME" "true") != "true" ]]; then
        return
    fi

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
    done <<<"$profiles"
}

rx_theme_apply_colors() {
    local mode
    mode=$(get_var "RETRO_THEME_MODE" "dark")
    local scheme
    scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")

    local matugen_scheme=$(get_var "THEME_SCHEME" "scheme-tonal-spot")
    local matugen_index=$(get_var "THEME_SOURCE_INDEX" "0")

    if [[ $scheme == "wallpaper" ]]; then
        local wallpaper
        wallpaper=$(get_var "WALL_CURRENT" "")
        rx_log_file "debug" "rx_theme_apply_colors: WALL_CURRENT=$wallpaper"
        if [[ -z $wallpaper || ! -f $wallpaper ]]; then
            local frame="$HOME/.config/retro/wallpaper_frames"
            wallpaper=$(find "$frame" -maxdepth 1 -name '*.png' 2>/dev/null | head -1)
            rx_log_file "debug" "rx_theme_apply_colors: fallback frame=$wallpaper"
        fi
        if [[ -z $wallpaper || ! -f $wallpaper ]]; then
            rx_log_file "warn" "rx_theme_apply_colors: no wallpaper or frame found, skipping color gen"
            rx_theme_refresh_apps
            return 0
        fi

        local static_source="$wallpaper"
        local cache="$HOME/.config/retro/wallpaper_frames/$(basename "$wallpaper").png"
        if [[ -f $cache ]]; then
            static_source="$cache"
            rx_log_file "debug" "rx_theme_apply_colors: using cached frame $cache"
        fi
        rx_log_file "debug" "rx_theme_apply_colors: static_source=$static_source"

        # Auto-detect desaturated wallpapers → use monochrome scheme
        if command -v magick &>/dev/null && [[ -f $static_source ]]; then
            local sat=$(magick "$static_source" -colorspace HSL -format "%[fx:100*s]" info: 2>/dev/null)
            if [[ -n $sat ]] && [ "$(echo "$sat < 1.0" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
                matugen_scheme="scheme-monochrome"
                rx_log_file "debug" "rx_theme_apply_colors: low saturation ($sat%), forcing monochrome with white fallback"
            fi
        fi

        rx_log_file "debug" "rx_theme_apply_colors: matugen scheme=$matugen_scheme, index=$matugen_index, mode=$mode"
        local fallback_args=()
        [[ $matugen_scheme == "scheme-monochrome" ]] && fallback_args=(--fallback-color '#ffffff')
        rx_log_file "info" "rx_theme_apply_colors: running matugen on $static_source"
        matugen image -b wal --mode "$mode" "$static_source" -t "$matugen_scheme" --source-color-index "$matugen_index" "${fallback_args[@]}" >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            rx_log_file "error" "rx_theme_apply_colors: matugen failed on $static_source"
            return 1
        fi
        [[ $matugen_scheme == "scheme-monochrome" ]] && rx_grayscale_output
    else
        local theme_file="$THEMES_DIR/${scheme}.json"
        rx_log_file "debug" "rx_theme_apply_colors: theme scheme=$scheme, file=$theme_file"
        local palette_path
        palette_path=$(jq -r '.palette // empty' "$theme_file" 2>/dev/null)

        if [[ -n $palette_path && -f "$THEMES_DIR/$palette_path" ]]; then
            rx_log_file "info" "rx_theme_apply_colors: using palette PNG for $scheme"
            rx_generate_colors "$THEMES_DIR/$palette_path" "$mode" "$matugen_scheme" "$matugen_index" "saturation" || return 1
        else
            local source_color
            source_color=$(jq -r '.source_color // .color_map.primary // ""' "$theme_file" 2>/dev/null)
            if [[ -n $source_color ]]; then
                rx_log_file "info" "rx_theme_apply_colors: using source_color=$source_color for $scheme"
                rx_generate_colors "" "$mode" "$matugen_scheme" "$matugen_index" "" "$source_color" || return 1
            else
                rx_log_file "error" "rx_theme_apply_colors: no palette or source_color for $scheme"
                return 1
            fi
        fi

        if [[ -f $theme_file ]]; then
            local has_cm
            has_cm=$(jq -r '.color_map | type' "$theme_file" 2>/dev/null)
            rx_log_file "debug" "rx_theme_apply_colors: color_map type=$has_cm for $scheme"
            [[ $has_cm == "object" ]] && rx_apply_color_map "$theme_file"
        fi
    fi

    # GTK / Qt hot-reload: toggle color-scheme to force apps to pick up new colors
    local adw_scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)
    if [[ $adw_scheme == "'prefer-dark'" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-light 2>/dev/null
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null
    elif [[ $adw_scheme == "'prefer-light'" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null
        gsettings set org.gnome.desktop.interface color-scheme prefer-light 2>/dev/null
    fi
    touch "$HOME/.config/qt6ct/qt6ct.conf" 2>/dev/null || true

    rx_theme_refresh_apps
    rx_theme_apply_gtk_font
    rx_set_papirus_folder_color
    rx_theme_deploy_browsers
    rx_sddm_refresh

    local wc=$(get_var "WALL_CURRENT" "")
    if [[ -f $wc ]]; then
        mkdir -p "$HOME/.config/retro/wallpaper"
        cp "$wc" "$HOME/.config/retro/wallpaper/current.png"
    fi
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
gtk_font|$(get_var "GTK_FONT" "Inter")
gtk_font_size|$(get_var "GTK_FONT_SIZE" "10")
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


rx_theme_deploy_root_config() {
    local dirs=("gtk-3.0" "gtk-4.0" "Kvantum" "qt5ct" "qt6ct")
    sudo -n mkdir -p /root/.config 2>/dev/null || return 0
    for dir in "${dirs[@]}"; do
        local src="$HOME/.config/$dir"
        mkdir -p "$src"
        sudo -n ln -snf "$src" "/root/.config/$dir" 2>/dev/null
    done
    rx_log_file "info" "Root config symlinks deployed ($(get_var "RETRO_THEME_MODE" "dark"), $(get_var "GTK_FONT" "Inter") $(get_var "GTK_FONT_SIZE" "10"))"
}

_cursor_resolve() {
    local name="$1"
    if [[ $name == "auto" ]]; then
        local mode
        mode=$(get_var "RETRO_THEME_MODE" "dark")
        if [[ $mode == "light" ]]; then
            echo "Moga-White"
        else
            echo "Moga-Black"
        fi
    else
        echo "$name"
    fi
}

rx_cursor_set() {
    local input="$1"
    local size="${2:-24}"
    local name
    name=$(_cursor_resolve "$input")

    local src_dir="$RETRO_DIR/themes/cursors/$name"
    if [[ ! -d $src_dir ]]; then
        rx_log_file "error" "Cursor theme '$name' not found in $RETRO_DIR/themes/cursors/"
        return 1
    fi

    mkdir -p "$HOME/.local/share/icons" "$HOME/.icons" "$HOME/.icons/default"
    ln -snf "$src_dir" "$HOME/.local/share/icons/$name"
    ln -snf "$HOME/.local/share/icons/$name" "$HOME/.icons/$name"
    cat >"$HOME/.icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=$name
EOF
    mkdir -p "$HOME/.local/share/icons/default"
    cat >"$HOME/.local/share/icons/default/index.theme" <<EOF
[Icon Theme]
Inherits=$name
EOF

    local xresources="$HOME/.Xresources"
    if grep -q '^Xcursor\.theme' "$xresources" 2>/dev/null; then
        sed -i "s/^Xcursor\.theme:.*/Xcursor.theme: $name/" "$xresources"
    else
        echo "Xcursor.theme: $name" >> "$xresources"
    fi
    if grep -q '^Xcursor\.size' "$xresources" 2>/dev/null; then
        sed -i "s/^Xcursor\.size:.*/Xcursor.size: $size/" "$xresources"
    else
        echo "Xcursor.size: $size" >> "$xresources"
    fi
    command -v xrdb >/dev/null 2>&1 && DISPLAY="${DISPLAY:-:0}" xrdb -merge "$xresources" 2>/dev/null

    for gtk_file in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
        [[ -f $gtk_file ]] || continue
        if grep -q '^gtk-cursor-theme-name' "$gtk_file" 2>/dev/null; then
            sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$name/" "$gtk_file"
        else
            echo "gtk-cursor-theme-name=$name" >> "$gtk_file"
        fi
    done

    local env_file="$HOME/.config/retro/env.lua"
    mkdir -p "$(dirname "$env_file")"
    [[ ! -f $env_file ]] && touch "$env_file"
    if grep -q 'XCURSOR_THEME' "$env_file" 2>/dev/null; then
        sed -i "s/hl\.env(\"XCURSOR_THEME\", \"[^\"]*\")/hl.env(\"XCURSOR_THEME\", \"$name\")/" "$env_file"
    else
        echo "hl.env(\"XCURSOR_THEME\", \"$name\")" >> "$env_file"
    fi
    for var in XCURSOR_SIZE HYPRCURSOR_THEME HYPRCURSOR_SIZE; do
        local val="$size"
        [[ $var == HYPRCURSOR_THEME ]] && val="$name"
        if grep -q "$var" "$env_file" 2>/dev/null; then
            sed -i "s/hl\.env(\"$var\", \"[^\"]*\")/hl.env(\"$var\", \"$val\")/" "$env_file"
        else
            echo "hl.env(\"$var\", \"$val\")" >> "$env_file"
        fi
    done

    gsettings set org.gnome.desktop.interface cursor-theme "$name" 2>/dev/null
    gsettings set org.gnome.desktop.interface cursor-size "$size" 2>/dev/null

    command -v hyprctl >/dev/null 2>&1 && hyprctl setcursor "$name" "$size" 2>/dev/null

    local xsettingsd_conf="$HOME/.config/xsettingsd/xsettingsd.conf"
    if [[ -f $xsettingsd_conf ]]; then
        if grep -q 'Net/CursorTheme' "$xsettingsd_conf" 2>/dev/null; then
            sed -i "s/Net\/CursorTheme.*/Net\/CursorTheme \"$name\"/" "$xsettingsd_conf"
        else
            echo "Net/CursorTheme \"$name\"" >> "$xsettingsd_conf"
        fi
        if grep -q 'Net/CursorSize' "$xsettingsd_conf" 2>/dev/null; then
            sed -i "s/Net\/CursorSize.*/Net\/CursorSize $size/" "$xsettingsd_conf"
        else
            echo "Net/CursorSize $size" >> "$xsettingsd_conf"
        fi
        command -v xsettingsd >/dev/null 2>&1 && timeout 0.1s xsettingsd 2>/dev/null
    fi

    local css_files=(
        "${RETRO_CONFIG:-$HOME/.config/retro}/themes/colors.css"
        "$HOME/.config/gtk-3.0/gtk.css"
        "$HOME/.config/gtk-4.0/gtk.css"
    )
    for f in "${css_files[@]}"; do
        [[ -f $f ]] || continue
        sed -i "s|REPLACE_CURSOR|${name}|g" "$f"
    done

    set_var "RETRO_CURSOR_THEME" "$input"
    set_var "RETRO_CURSOR_SIZE" "$size"
    echo "$name"
}

rx_cursor_list() {
    local dir
    for dir in "$RETRO_DIR/themes/cursors"/*/; do
        [[ -d $dir ]] || continue
        local name
        name=$(grep -m1 '^Name=' "$dir/index.theme" 2>/dev/null | cut -d= -f2)
        echo "${name:-$(basename "$dir")}"
    done
}

_sddm_css() {
    sed -n "s/@define-color $1 *\(#[^;]*\);.*/\1/p" "${2:?}"
}

rx_sddm_refresh() {
    local sddm_dir="/usr/share/sddm/themes/retro"
    [[ ! -d $sddm_dir ]] && return 0

    local sudo_cmd=""
    [[ ! -w $sddm_dir ]] && sudo_cmd="sudo"

    local config_src="${RETRO_CONFIG:-$HOME/.config/retro}/themes/sddm.conf"
    local wallpaper
    wallpaper=$(get_var "WALL_CURRENT" "")
    local frame="$HOME/.config/retro/wallpaper_frames/$(basename "$wallpaper").png"

    $sudo_cmd mkdir -p "$sddm_dir/backgrounds" "$sddm_dir/configs"

    if [[ -f $frame ]]; then
        $sudo_cmd magick "$frame" -resize "1920x1080^" -gravity center -extent 1920x1080 \
            "$sddm_dir/backgrounds/retro-wallpaper.jpg" 2>/dev/null
    elif [[ -f $wallpaper ]]; then
        $sudo_cmd magick "$wallpaper" -resize "1920x1080^" -gravity center -extent 1920x1080 \
            "$sddm_dir/backgrounds/retro-wallpaper.jpg" 2>/dev/null
    fi

    local mode scheme
    mode=$(get_var "RETRO_THEME_MODE" "dark")
    scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")

    local surface on_surface primary on_primary surface_variant outline
    local primary_container error tertiary
    local on_surface_variant on_primary_container

    if [[ $scheme != "wallpaper" ]]; then
        local theme_file="$THEMES_DIR/${scheme}.json"
        local cm_key="color_map"
        local computed=false
        if [[ $mode == "light" ]]; then
            local has_light
            has_light=$(jq -r '.color_map_light | type' "$theme_file" 2>/dev/null)
            if [[ $has_light == "object" ]]; then
                cm_key="color_map_light"
            else
                computed=true
            fi
        fi

        local val
        val=$(jq -r ".[\"$cm_key\"].surface // \"\"" "$theme_file" 2>/dev/null)
        surface="${val:-#070514}"
        val=$(jq -r ".[\"$cm_key\"].on_surface // \"\"" "$theme_file" 2>/dev/null)
        on_surface="${val:-#e5e9f0}"
        val=$(jq -r ".[\"$cm_key\"].primary // \"\"" "$theme_file" 2>/dev/null)
        primary="${val:-#b24bf3}"
        val=$(jq -r ".[\"$cm_key\"].on_primary // \"\"" "$theme_file" 2>/dev/null)
        on_primary="${val:-#ffffff}"
        val=$(jq -r ".[\"$cm_key\"].surface_variant // \"\"" "$theme_file" 2>/dev/null)
        surface_variant="${val:-#0a091a}"
        val=$(jq -r ".[\"$cm_key\"].outline // \"\"" "$theme_file" 2>/dev/null)
        outline="${val:-#323c58}"
        val=$(jq -r ".[\"$cm_key\"].primary_container // \"\"" "$theme_file" 2>/dev/null)
        primary_container="${val:-#12102e}"
        val=$(jq -r ".[\"$cm_key\"].error // \"\"" "$theme_file" 2>/dev/null)
        error="${val:-#ff2a6d}"
        val=$(jq -r ".[\"$cm_key\"].tertiary // \"\"" "$theme_file" 2>/dev/null)
        tertiary="${val:-#ffcc33}"

        if [[ $computed == true ]]; then
            surface="#$(_dark_to_light "${surface#\#}" "surface")"
            on_surface="#$(_dark_to_light "${on_surface#\#}" "on_surface")"
            primary="#$(_dark_to_light "${primary#\#}" "primary")"
            on_primary="#$(_dark_to_light "${on_primary#\#}" "on_primary")"
            surface_variant="#$(_dark_to_light "${surface_variant#\#}" "surface_variant")"
            outline="#$(_dark_to_light "${outline#\#}" "outline")"
            primary_container="#$(_dark_to_light "${primary_container#\#}" "primary_container")"
            error="#$(_dark_to_light "${error#\#}" "error")"
            tertiary="#$(_dark_to_light "${tertiary#\#}" "tertiary")"
        fi
    else
        local css_file="${RETRO_CONFIG:-$HOME/.config/retro}/themes/colors.css"
        if [[ -f $css_file ]]; then
            surface=$(_sddm_css "surface" "$css_file")
            on_surface=$(_sddm_css "on_surface" "$css_file")
            primary=$(_sddm_css "primary" "$css_file")
            on_primary=$(_sddm_css "on_primary" "$css_file")
            surface_variant=$(_sddm_css "surface_variant" "$css_file")
            outline=$(_sddm_css "outline" "$css_file")
            primary_container=$(_sddm_css "primary_container" "$css_file")
            error=$(_sddm_css "error" "$css_file")
            tertiary=$(_sddm_css "tertiary" "$css_file")
        fi
    fi

    : "${surface:=#070514}"
    : "${on_surface:=#e5e9f0}"
    : "${primary:=#b24bf3}"
    : "${on_primary:=#ffffff}"
    : "${surface_variant:=#0a091a}"
    : "${outline:=#323c58}"
    : "${primary_container:=#12102e}"
    : "${error:=#ff2a6d}"
    : "${tertiary:=#ffcc33}"
    : "${on_surface_variant:=$on_surface}"
    : "${on_primary_container:=$on_primary}"

    mkdir -p "$(dirname "$config_src")"
    cat > "$config_src" << SDDMEOF
; Auto-generated by retro theme engine — do not edit

[General]
scale = 1.0
enable-animations = true
animated-background-placeholder = "retro-wallpaper.jpg"
background-fill-mode = "fill"

[LockScreen]
display = true
padding-top = 0
padding-right = 0
padding-bottom = 0
padding-left = 0
background = "retro-wallpaper.jpg"
use-background-color = false
background-color = ${surface}
blur = 32
brightness = 0.0
saturation = 0.0

[LockScreen.Clock]
display = true
position = "top-center"
align = "center"
format = "hh:mm"
font-family = "RedHatDisplay"
font-size = 70
font-weight = 900
color = ${on_surface}

[LockScreen.Date]
display = true
format = "dddd, MMMM dd, yyyy"
locale = "en_US"
font-family = "RedHatDisplay"
font-size = 14
font-weight = 600
color = ${on_surface}
margin-top = -15

[LockScreen.Message]
display = true
position = "bottom-center"
align = "center"
text = "Press any key"
font-family = "RedHatDisplay"
font-size = 12
font-weight = 400
display-icon = true
icon = "enter.svg"
icon-size = 16
color = ${on_surface}
paint-icon = true
spacing = 0

[LoginScreen]
background = "retro-wallpaper.jpg"
use-background-color = false
background-color = ${surface}
blur = 0
brightness = 0.0
saturation = 0.0

[LoginScreen.LoginArea]
position = "center"
margin = -1

[LoginScreen.LoginArea.Avatar]
shape = "circle"
border-radius = 35
active-size = 120
inactive-size = 80
inactive-opacity = 0.35
active-border-size = 0
inactive-border-size = 0
active-border-color = ${primary}
inactive-border-color = ${outline}
always-active = false

[LoginScreen.LoginArea.Username]
font-family = "RedHatDisplay"
font-size = 16
font-weight = 700
color = ${on_surface}
margin = 10

[LoginScreen.LoginArea.PasswordInput]
width = 200
height = 30
display-icon = true
font-family = "RedHatDisplay"
font-size = 12
icon = "password.svg"
icon-size = 16
content-color = ${on_surface}
background-color = ${surface_variant}
background-opacity = 1.0
border-size = 1
border-color = ${outline}
border-radius-left = 10
border-radius-right = 10
margin-top = 10
masked-character = "●"

[LoginScreen.LoginArea.LoginButton]
background-color = ${primary}
background-opacity = 1.0
active-background-color = ${primary}
active-background-opacity = 0.80
icon = "arrow-right.svg"
icon-size = 18
content-color = ${on_primary}
active-content-color = ${on_primary}
border-size = 0
border-color = ${primary}
border-radius-left = 10
border-radius-right = 10
margin-left = 5
show-text-if-no-password = true
hide-if-not-needed = false
font-family = "RedHatDisplay"
font-size = 12
font-weight = 600

[LoginScreen.LoginArea.Spinner]
display-text = true
text = "Logging in"
font-family = "RedHatDisplay"
font-weight = 600
font-size = 14
icon-size = 30
icon = "spinner.svg"
color = ${primary}
spacing = 5

[LoginScreen.LoginArea.WarningMessage]
font-family = "RedHatDisplay"
font-size = 11
font-weight = 400
normal-color = ${on_surface_variant}
warning-color = ${tertiary}
error-color = ${error}
margin-top = 10

[LoginScreen.MenuArea.Buttons]
margin-top = 50
margin-right = 50
margin-bottom = 50
margin-left = 50
size = 30
border-radius = 5
spacing = 10
font-family = "RedHatDisplay"

[LoginScreen.MenuArea.Popups]
max-height = 300
item-height = 30
item-spacing = 2
padding = 5
display-scrollbar = true
margin = 5
background-color = ${surface_variant}
background-opacity = 1.0
active-option-background-color = ${primary_container}
active-option-background-opacity = 1.0
content-color = ${on_surface}
active-content-color = ${on_primary_container}
font-family = "RedHatDisplay"
border-size = 1
border-color = ${outline}
font-size = 11
icon-size = 16

[LoginScreen.MenuArea.Session]
display = true
position = "bottom-left"
index = 0
popup-direction = "up"
popup-align = "center"
display-session-name = true
button-width = 200
popup-width = 200
background-color = ${surface}
background-opacity = 0.0
active-background-opacity = 0.30
content-color = ${on_surface}
active-content-color = ${primary}
border-size = 0
font-size = 10
icon-size = 16

[LoginScreen.MenuArea.Layout]
display = true
position = "bottom-right"
index = 0
popup-direction = "up"
popup-align = "center"
popup-width = 180
display-layout-name = true
background-color = ${surface}
background-opacity = 0.0
active-background-opacity = 0.30
content-color = ${on_surface}
active-content-color = ${primary}
border-size = 0
font-size = 10
icon = "language.svg"
icon-size = 16

[LoginScreen.MenuArea.Keyboard]
display = true
position = "bottom-right"
index = 0
background-color = ${surface}
background-opacity = 0.0
active-background-opacity = 0.30
content-color = ${on_surface}
active-content-color = ${primary}
border-size = 0
icon = "keyboard.svg"
icon-size = 16

[LoginScreen.MenuArea.Power]
display = true
position = "bottom-right"
index = 0
popup-direction = "up"
popup-align = "center"
popup-width = 100
background-color = ${surface}
background-opacity = 0.0
active-background-opacity = 0.30
content-color = ${on_surface}
active-content-color = ${primary}
border-size = 0
icon = "power.svg"
icon-size = 16

[LoginScreen.VirtualKeyboard]
scale = 1.0
position = "login"
start-hidden = true
background-color = ${surface_variant}
background-opacity = 1.0
key-content-color = ${on_surface}
key-color = ${surface}
key-opacity = 1.0
key-active-background-color = ${primary_container}
key-active-opacity = 1.0
selection-background-color = ${primary}
selection-content-color = ${on_primary}
primary-color = ${primary}
border-size = 0
border-color = ${outline}
restrict-input = "none"

[Tooltips]
enable = true
font-family = "RedHatDisplay"
font-size = 11
content-color = ${on_surface}
background-color = ${surface_variant}
background-opacity = 1.0
border-radius = 5
disable-user = false
disable-login-button = false
SDDMEOF

    $sudo_cmd cp "$config_src" "$sddm_dir/configs/retro.conf"
    $sudo_cmd sed -i "s|^ConfigFile=.*|ConfigFile=configs/retro.conf|" "$sddm_dir/metadata.desktop"

    rx_log_file "info" "SDDM theme refreshed (wallpaper + colors deployed)"
}

_override_set() {
    local slug="$1" key="$2" value="$3"
    [[ -z $slug || -z $key || -z $value ]] && { echo "error|missing_args"; return 1; }
    mkdir -p "$OVERRIDE_DIR"
    local file="$OVERRIDE_DIR/${slug}.json"
    if [[ -f $file ]]; then
        local tmp=$(mktemp)
        jq --arg k "$key" --arg v "$value" '.color_map[$k] = $v' "$file" > "$tmp" && mv "$tmp" "$file"
    else
        echo "{\"color_map\": {\"$key\": \"$value\"}}" > "$file"
    fi
    echo "success|${slug}|${key}|${value}"
}

_override_get() {
    local slug="$1"
    [[ -z $slug ]] && { echo "error|missing_slug"; return 1; }
    local file="$OVERRIDE_DIR/${slug}.json"
    if [[ -f $file ]]; then
        jq -r '.color_map // empty | to_entries[] | "\(.key)|\(.value)"' "$file" 2>/dev/null
    fi
}

_override_clear() {
    local slug="$1"
    [[ -z $slug ]] && { echo "error|missing_slug"; return 1; }
    local file="$OVERRIDE_DIR/${slug}.json"
    if [[ -f $file ]]; then
        rm -f "$file"
        echo "success|cleared|${slug}"
    else
        echo "success|no_overrides|${slug}"
    fi
}

_override_list() {
    if [[ ! -d $OVERRIDE_DIR ]]; then
        return
    fi
    for f in "$OVERRIDE_DIR"/*.json; do
        [[ ! -f $f ]] && continue
        local slug=$(basename "$f" .json)
        local count=$(jq -r '.color_map | length' "$f" 2>/dev/null || echo 0)
        echo "${slug}|${count} overrides"
    done
}

_custom_theme_create() {
    local json_payload="$1"
    [[ -z $json_payload ]] && { echo "error|missing_json"; return 1; }
    local slug=$(echo "$json_payload" | jq -r '.name // empty' 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
    [[ -z $slug ]] && { echo "error|invalid_name"; return 1; }
    mkdir -p "$USER_THEMES_DIR"
    echo "$json_payload" > "$USER_THEMES_DIR/${slug}.json"
    echo "success|${slug}"
}

_custom_theme_delete() {
    local slug="$1"
    [[ -z $slug ]] && { echo "error|missing_slug"; return 1; }
    local file="$USER_THEMES_DIR/${slug}.json"
    if [[ -f $file ]]; then
        rm -f "$file"
        echo "success|deleted|${slug}"
    else
        echo "error|not_found|${slug}"
    fi
}

_custom_theme_list() {
    if [[ ! -d $USER_THEMES_DIR ]]; then
        return
    fi
    for f in "$USER_THEMES_DIR"/*.json; do
        [[ ! -f $f ]] && continue
        local slug=$(basename "$f" .json)
        local display=$(jq -r '.name // empty' "$f" 2>/dev/null)
        echo "${slug}|${display:-$slug}"
    done
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
    "--browsers-enable")
        if rx_confirm "Would you like to enable theming for web pages? Requires a Firefox-based browser (Firefox/Zen)."; then
            set_var "RETRO_BROWSER_THEME" "true"
            rx_theme_deploy_browsers 1
            echo "enabled"
        else
            echo "cancelled"
        fi
        ;;
    "--browsers-disable")
        rx_theme_clean_browsers
        set_var "RETRO_BROWSER_THEME" "false"
        ;;
    "--toggle-browsers")
        current=$(get_var "RETRO_BROWSER_THEME" "true")
        if [[ $current == "true" ]]; then
            rx_theme_clean_browsers
            set_var "RETRO_BROWSER_THEME" "false"
            echo "disabled"
        else
            if rx_confirm "Would you like to enable theming for web pages? Requires a Firefox-based browser (Firefox/Zen)."; then
                set_var "RETRO_BROWSER_THEME" "true"
                rx_theme_deploy_browsers 1
                echo "enabled"
            else
                echo "disabled"
            fi
        fi
        ;;
    "--deploy-browsers")
        rx_theme_deploy_browsers 1
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
gtk-xft-antialias=1
gtk-xft-hinting=0
gtk-xft-hintstyle=hintnone
gtk-xft-rgba=rgb
EOF
        cat <<EOF | sudo tee /etc/gtk-4.0/settings.ini >/dev/null
[Settings]
gtk-icon-theme-name = Papirus-Dark
gtk-xft-antialias=1
gtk-xft-hinting=0
gtk-xft-hintstyle=hintnone
gtk-xft-rgba=rgb
EOF
        ;;
    "--apply-gtk-font")
        rx_theme_apply_gtk_font
        ;;
    "--cursor-set")
        rx_cursor_set "$2" "$3"
        ;;
    "--cursor-list")
        rx_cursor_list
        ;;
    "--sddm-refresh")
        rx_sddm_refresh
        ;;
    "--override-set")
        _override_set "$2" "$3" "$4"
        ;;
    "--override-get")
        _override_get "$2"
        ;;
    "--override-clear")
        _override_clear "$2"
        ;;
    "--override-list")
        _override_list
        ;;
    "--custom-theme-create")
        _custom_theme_create "$2"
        ;;
    "--custom-theme-delete")
        _custom_theme_delete "$2"
        ;;
    "--custom-theme-list")
        _custom_theme_list
        ;;
    "--scheme-get")
        get_var "THEME_SCHEME" "scheme-tonal-spot"
        ;;
    "--scheme-set")
        set_var "THEME_SCHEME" "$2"
        rx_theme_refresh_apps
        ;;
    "--index-get")
        get_var "THEME_SOURCE_INDEX" "0"
        ;;
    "--index-set")
        set_var "THEME_SOURCE_INDEX" "$2"
        rx_theme_refresh_apps
        ;;
esac
