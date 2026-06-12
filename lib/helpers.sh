#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/variable.sh"

rx_format_time() {
    local T=$1
    [[ -z $T || $T == "null" ]] && echo "Disabled" && return

    if ((T < 60)); then
        echo "${T} seconds"
    elif ((T < 3600)); then
        echo "$((T / 60)) minutes"
    elif ((T < 86400)); then
        echo "$((T / 3600)) hours"
    elif ((T < 604800)); then
        echo "$((T / 86400)) days"
    elif ((T < 2592000)); then
        echo "$((T / 604800)) weeks"
    else
        echo "$((T / 2592000)) months"
    fi
}

rx_format_uptime() {
    local total_seconds=$1

    [[ -z $total_seconds || $total_seconds -lt 60 ]] && echo "Just now" && return

    local minutes=$((total_seconds / 60))
    local hours=$((minutes / 60))
    local days=$((hours / 24))
    local weeks=$((days / 7))
    local months=$((weeks / 4))

    minutes=$((minutes % 60))
    hours=$((hours % 24))
    days=$((days % 7))
    weeks=$((weeks % 4))

    local result=""
    [[ $months -gt 0 ]] && result+="${months} months "
    [[ $weeks -gt 0 ]] && result+="${weeks} weeks "
    [[ $days -gt 0 ]] && result+="${days} days "
    [[ $hours -gt 0 ]] && result+="${hours} hours "
    [[ $minutes -gt 0 ]] && result+="${minutes} min"

    result="${result%" "}"
    echo "$result"
}

rx_format_size() {
    local size=$1
    [[ -z $size || $size == "0" ]] && echo "0 B" && return

    local units=('B' 'KB' 'MB' 'GB')
    local i=0

    while (($(echo "$size > 1024" | bc -l) && i < 3)); do
        size=$(echo "scale=2; $size / 1024" | bc -l)
        ((i++))
    done
    echo "${size} ${units[$i]}"
}

rx_format_string() {
    local name="$1"
    name="${name%.*}"
    name="${name//.[0-9]*x[0-9]*/}"
    name="${name//-/ }"
    name="${name//_/ }"

    echo "$name" | sed -E 's/(^| )([a-z])/\1\U\2/g'
}

get_opacity_hex() {
    local base_opacity=$(get_var "RETRO_OPACITY" "1.0")

    [[ $base_opacity == "1.0" ]] && {
        echo "FF"
        return
    }

    local multiplier="${1:-1.0}"

    local opacity_int=$(echo "($base_opacity * $multiplier * 255 + 0.5) / 1" | bc)

    ((opacity_int > 255)) && opacity_int=255
    ((opacity_int < 0)) && opacity_int=0

    printf "%02x" "$opacity_int"
}

get_battery_icon() {
    local cap=$1
    local stat=$2

    [[ $stat == *"charging"* && $stat != *"discharging"* ]] && echo "󱐋" && return

    if ((cap >= 95)); then
        echo "󰁹"
    elif ((cap >= 85)); then
        echo "󰂂"
    elif ((cap >= 75)); then
        echo "󰂁"
    elif ((cap >= 65)); then
        echo "󰂀"
    elif ((cap >= 55)); then
        echo "󰁿"
    elif ((cap >= 45)); then
        echo "󰁾"
    elif ((cap >= 35)); then
        echo "󰁽"
    elif ((cap >= 25)); then
        echo "󰁼"
    elif ((cap >= 15)); then
        echo "󰁻"
    else
        echo "󰂃"
    fi
}

rx_generate_colors() {
    local source="$1"
    local mode="${2:-dark}"
    local scheme_type="${3:-scheme-tonal-spot}"
    local source_index="${4:-0}"
    local prefer="${5:-}"
    local solid_color="${6:-}"

    if ! command -v matugen >/dev/null 2>&1; then
        rx_log "error" "matugen is not installed"
        return 1
    fi

    local matugen_output
    local matugen_exit

    if [[ -n $solid_color ]]; then
        matugen_output=$(matugen color hex "$solid_color" --mode "$mode" -t "$scheme_type" 2>&1)
        matugen_exit=$?
    else
        if [[ ! -f $source ]]; then
            rx_log "error" "Source image not found for color generation: ${PINK}$source${RESET}"
            return 1
        fi
        if [[ -n $prefer ]]; then
            matugen_output=$(matugen image --mode "$mode" "$source" -t "$scheme_type" --prefer "$prefer" 2>&1)
            matugen_exit=$?
        else
            matugen_output=$(matugen image --mode "$mode" "$source" -t "$scheme_type" --source-color-index "$source_index" 2>&1)
            matugen_exit=$?
        fi
    fi

    if [[ $matugen_exit -ne 0 ]]; then
        rx_log "error" "matugen failed with exit code ${PINK}$matugen_exit${RESET}"
        rx_log "error" "matugen output: ${GRAY}$(echo "$matugen_output" | tail -3)${RESET}"
        return 1
    fi
}

rx_apply_color_map() {
    local theme_file="$1"
    local output_dir="${RETRO_CONFIG:-$HOME/.config/retro}/themes"

    local keys
    keys=$(jq -r '.color_map | to_entries[] | "\(.key)|\(.value)"' "$theme_file" 2>/dev/null)
    [[ -z $keys ]] && return 0

    declare -A slot_map
    slot_map["black"]="color0"
    slot_map["red"]="color1"
    slot_map["green"]="color2"
    slot_map["yellow"]="color3"
    slot_map["blue"]="color4"
    slot_map["magenta"]="color5"
    slot_map["cyan"]="color6"
    slot_map["white"]="color7"
    slot_map["bright_black"]="color8"
    slot_map["bright_red"]="color9"
    slot_map["bright_green"]="color10"
    slot_map["bright_yellow"]="color11"
    slot_map["bright_blue"]="color12"
    slot_map["bright_magenta"]="color13"
    slot_map["bright_cyan"]="color14"
    slot_map["bright_white"]="color15"

    while IFS='|' read -r key value; do
        [[ -z $key || -z $value ]] && continue
        local hex="${value#\#}"
        local slot="${slot_map[$key]:-}"

        local file="$output_dir/kitty-colors.conf"
        if [[ -f $file ]]; then
            if [[ -n $slot ]]; then
                sed -i "s/^\(${slot} \+\)#[0-9a-f]*/\1#${hex}/" "$file"
            else
                sed -i "s/^\(${key} \+\)#[0-9a-f]*/\1#${hex}/" "$file"
            fi
        fi

        file="$output_dir/colors.css"
        if [[ -f $file ]]; then
            local css_key="${slot:-$key}"
            sed -i "s/\(@define-color ${css_key} *\)#[0-9a-f]*/\1#${hex}/" "$file"
        fi

        file="$output_dir/firefox.css"
        if [[ -f $file ]]; then
            local ff_key="${slot:-$key}"
            sed -i "s/^\([[:space:]]*--${ff_key}: *\)#[0-9a-f][0-9a-f]*/\1#${hex}/" "$file"
            local r=$((16#${hex:0:2}))
            local g=$((16#${hex:2:2}))
            local b=$((16#${hex:4:2}))
            sed -i "s/^\([[:space:]]*--${ff_key}_rgb: *\)[0-9][0-9]* [0-9][0-9]* [0-9][0-9]*/\1${r} ${g} ${b}/" "$file"
        fi

        file="$output_dir/rofi-colors.rasi"
        if [[ -f $file ]]; then
            local rofi_key="${key//_/-}"
            sed -i "s/^\(    ${rofi_key}: *\)#[0-9a-f]*FF/\1#${hex}FF/" "$file"
        fi

        if [[ -z $slot ]]; then
            file="$output_dir/hyprland-colors.lua"
            if [[ -f $file ]]; then
                sed -i "s/^\(    ${key} = \"\)0xff[0-9a-f]*\"/\10xff${hex}\"/" "$file"
                if [[ $key == "primary" ]]; then
                    sed -i "s/^\(    source_color = \"\)0xff[0-9a-f]*\"/\10xff${hex}\"/" "$file"
                fi
            fi
        fi

        for gtk_file in "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"; do
            [[ -f $gtk_file ]] || continue
            case "$key" in
                primary)
                    sed -i "s/^\(@define-color accent_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    sed -i "s/^\(@define-color accent_bg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    ;;
                on_primary)
                    sed -i "s/^\(@define-color accent_fg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    ;;
                surface)
                    sed -i "s/^\(@define-color window_bg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    sed -i "s/^\(@define-color headerbar_bg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    sed -i "s/^\(@define-color popover_bg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    sed -i "s/^\(@define-color view_bg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    sed -i "s/^\(@define-color card_bg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    ;;
                on_surface)
                    sed -i "s/^\(@define-color window_fg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    sed -i "s/^\(@define-color headerbar_fg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    sed -i "s/^\(@define-color popover_fg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    sed -i "s/^\(@define-color view_fg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    sed -i "s/^\(@define-color card_fg_color *\)#[0-9a-f]*/\1#${hex}/" "$gtk_file"
                    ;;
            esac
        done

        local kvantum_file="$HOME/.config/Kvantum/retro/retro.kvconfig"
        if [[ -f $kvantum_file ]]; then
            case "$key" in
                primary)
                    sed -i "s/^\(highlight\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    sed -i "s/^\(link\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    ;;
                surface)
                    sed -i "s/^\(window\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    sed -i "s/^\(dark\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    ;;
                on_surface)
                    sed -i "s/^\(text\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    sed -i "s/^\(window\.text\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    sed -i "s/^\(button\.text\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    sed -i "s/^\(tooltip\.text\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    sed -i "s/^\(progress\.indicator\.text\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    ;;
                surface_variant)
                    sed -i "s/^\(mid\.light\.color=\)#[0-9a-f]*/\1#${hex}/" "$kvantum_file"
                    ;;
            esac
        fi

        local cava_file="$HOME/.config/cava/themes/retro"
        if [[ -f $cava_file ]]; then
            case "$key" in
                on_surface)
                    sed -i "s/^foreground = '.*'/foreground = '#${hex}'/" "$cava_file"
                    ;;
                primary)
                    sed -i "s/^gradient_color_1 = '.*'/gradient_color_1 = '#${hex}'/" "$cava_file"
                    sed -i "s/^horizontal_gradient_color_1 = '.*'/horizontal_gradient_color_1 = '#${hex}'/" "$cava_file"
                    ;;
                secondary)
                    sed -i "s/^gradient_color_2 = '.*'/gradient_color_2 = '#${hex}'/" "$cava_file"
                    ;;
                tertiary)
                    sed -i "s/^gradient_color_3 = '.*'/gradient_color_3 = '#${hex}'/" "$cava_file"
                    sed -i "s/^horizontal_gradient_color_3 = '.*'/horizontal_gradient_color_3 = '#${hex}'/" "$cava_file"
                    ;;
                primary_container)
                    sed -i "s/^horizontal_gradient_color_2 = '.*'/horizontal_gradient_color_2 = '#${hex}'/" "$cava_file"
                    ;;
            esac
        fi
    done <<<"$keys"
}

check_dep() {
    local cmd="$1"
    local pkgs="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        local helper=$(get_var "PKG_HELPER")
        : "${helper:="yay"}"
        rx_log "error" "Missing required dependency: ${PINK}$cmd${RESET}"
        rx_confirm "Would you like to install [${GRAY}$pkgs${RESET}] using $helper?" "N" || {
            rx_log "info" "Dependency required. Aborting."
            return 1
        }

        rx_log "info" "Installing..."
        $helper -S $pkgs
        if ! command -v "$cmd" >/dev/null 2>&1; then
            rx_log "error" "Installation failed or aborted."
            return 1
        fi
    fi
    return 0
}

rx_grayscale_output() {
    local output_dir="${RETRO_CONFIG:-$HOME/.config/retro}/themes"

    while IFS= read -r file; do
        [[ -f $file ]] || continue

        perl -i -pe '
            s/#([0-9a-fA-F]{6})\b/ do {
                my $r = hex(substr($1,0,2));
                my $g = hex(substr($1,2,2));
                my $b = hex(substr($1,4,2));
                my $gray = sprintf("%02x", int(0.299*$r + 0.587*$g + 0.114*$b + 0.5));
                "#" . $gray x 3;
            } /ge;
            s/0x([0-9a-fA-F]{6})\b/ do {
                my $r = hex(substr($1,0,2));
                my $g = hex(substr($1,2,2));
                my $b = hex(substr($1,4,2));
                my $gray = sprintf("%02x", int(0.299*$r + 0.587*$g + 0.114*$b + 0.5));
                "0x" . $gray x 3;
            } /ge;
        ' "$file" 2>/dev/null
    done < <(find "$output_dir" -maxdepth 1 -type f 2>/dev/null)
}

rx_set_papirus_folder_color() {
    local hex="$1"
    local scheme
    scheme=$(get_var "RETRO_THEME_SCHEME" "wallpaper")

    if [[ -z $hex ]]; then
        if [[ $scheme == "wallpaper" ]]; then
            hex=$(grep -oP 'source_color = "0x[0-9a-f]{2}\K[0-9a-f]{6}' "$HOME/.config/retro/themes/hyprland-colors.lua" 2>/dev/null | head -1)
        else
            local theme_file="$RETRO_DIR/themes/${scheme}.json"
            [[ -f $theme_file ]] && hex=$(jq -r '.color_map.primary // empty' "$theme_file" 2>/dev/null | sed 's/^#//')
        fi
    fi
    [[ -z $hex ]] && return 0

    local hsl
    hsl=$(convert xc:"#${hex}" -colorspace HSL txt:- 2>/dev/null | tail -1)
    local hue=$(echo "$hsl" | grep -oP 'hsl\(\K[^,]+')
    local sat=$(echo "$hsl" | grep -oP 'hsl\([^,]+,\K[^,]+' | tr -d '%')
    local lum=$(echo "$hsl" | grep -oP ',\K[^%]+(?=%\))')

    local color="nordic"
    if [[ -n $hue && -n $sat ]]; then
        if (($(echo "$sat < 15" | bc -l))); then
            if (($(echo "$lum < 20" | bc -l))); then
                color="black"
            elif (($(echo "$lum > 80" | bc -l))); then
                color="white"
            else
                color="nordic"
            fi
        elif (($(echo "$hue < 15" | bc -l))); then
            color="red"
        elif (($(echo "$hue < 30" | bc -l))); then
            color="carmine"
        elif (($(echo "$hue < 45" | bc -l))); then
            color="deeporange"
        elif (($(echo "$hue < 55" | bc -l))); then
            color="orange"
        elif (($(echo "$hue < 70" | bc -l))); then
            color="paleorange"
        elif (($(echo "$hue < 100" | bc -l))); then
            color="yellow"
        elif (($(echo "$hue < 150" | bc -l))); then
            color="green"
        elif (($(echo "$hue < 180" | bc -l))); then
            color="teal"
        elif (($(echo "$hue < 200" | bc -l))); then
            color="cyan"
        elif (($(echo "$hue < 215" | bc -l))); then
            color="darkcyan"
        elif (($(echo "$hue < 245" | bc -l))); then
            color="blue"
        elif (($(echo "$hue < 265" | bc -l))); then
            color="indigo"
        elif (($(echo "$hue < 290" | bc -l))); then
            color="violet"
        elif (($(echo "$hue < 320" | bc -l))); then
            color="magenta"
        elif (($(echo "$hue < 335" | bc -l))); then
            color="pink"
        else
            color="red"
        fi
    fi

    command -v papirus-folders >/dev/null 2>&1 && sudo -n papirus-folders -C "$color" --theme Papirus-Dark >/dev/null 2>&1
}
