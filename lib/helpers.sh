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

_dark_to_light() {
    local hex="$1"
    local key="$2"
    python3 -c "
import sys, colorsys

hx = sys.argv[1]
key = sys.argv[2]
r = int(hx[0:2], 16) / 255.0
g = int(hx[2:4], 16) / 255.0
b = int(hx[4:6], 16) / 255.0
h, l, s = colorsys.rgb_to_hls(r, g, b)
l = max(0.001, min(0.999, l))
s = max(0.001, min(0.999, s))

bg_keys = {'background', 'surface', 'surface_variant', 'shadow', 'black', 'bright_black'}
fg_keys = {'on_surface', 'on_background', 'white', 'bright_white', 'on_primary', 'on_secondary', 'on_error'}

if key in bg_keys:
    new_l = max(0.88, min(0.97, 1.0 - l * 0.85))
elif key in fg_keys:
    new_l = min(0.15, max(0.05, 1.0 - l))
elif key == 'outline':
    new_l = min(0.55, max(0.25, 1.0 - l * 0.8))
else:
    new_l = min(0.72, max(0.38, 1.0 - l * 0.5))
    s = max(0.15, s * 0.85)

rr, gg, bb = colorsys.hls_to_rgb(h, new_l, s)
print(f'{int(rr*255):02x}{int(gg*255):02x}{int(bb*255):02x}')
" "$hex" "$key"
}


rx_apply_color_map() {
    local theme_file="$1"
    local output_dir="${RETRO_CONFIG:-$HOME/.config/retro}/themes"
    local mode
    mode=$(get_var "RETRO_THEME_MODE" "dark")

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

    local keys
    keys=$(jq -r --arg cm "$cm_key" '.[$cm] | if has("highlight") then .highlight = .primary else . end | if has("cursor") then .cursor = .primary else . end | to_entries[] | "\(.key)|\(.value)"' "$theme_file" 2>/dev/null)
    [[ -z $keys ]] && return 0

    local override_file="${output_dir}/overrides/$(basename "$theme_file" .json).json"
    local override_keys=""
    if [[ -f $override_file ]]; then
        local override_cm="$cm_key"
        if [[ ! $(jq -r ".${cm_key} | type" "$override_file" 2>/dev/null) == "object" ]]; then
            override_cm="color_map"
        fi
        [[ $(jq -r ".${override_cm} | type" "$override_file" 2>/dev/null) == "object" ]] && \
            override_keys=$(jq -r --arg cm "$override_cm" '.[$cm] | to_entries[] | "\(.key)|\(.value)"' "$override_file" 2>/dev/null)
    fi
    if [[ -n $override_keys ]]; then
        keys=$(printf "%s\n%s" "$override_keys" "$keys" | awk -F'|' '!seen[$1]++')
    fi

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
        [[ $computed == true ]] && hex=$(_dark_to_light "$hex" "$key")
        local slot="${slot_map[$key]:-}"

        local file="$output_dir/kitty-colors.conf"
        if [[ -f $file ]]; then
            if [[ -n $slot ]]; then
                sed -i "s/^\(${slot} \+\)#[0-9a-f]*/\1#${hex}/" "$file"
            else
                sed -i "s/^\(${key} \+\)#[0-9a-f]*/\1#${hex}/" "$file"
            fi

            case "$key" in
                primary)
                    sed -i "s/^\(cursor \+\)#[0-9a-f]*/\1#${hex}/" "$file"
                    sed -i "s/^\(url_color \+\)#[0-9a-f]*/\1#${hex}/" "$file"
                    ;;
                secondary)
                    sed -i "s/^\(selection_background \+\)#[0-9a-f]*/\1#${hex}/" "$file"
                    ;;
            esac
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

            if [[ $key == "primary" ]]; then
                sed -i "s/^\(    selected: *\)#[0-9a-f]*FF/\1#${hex}FF/" "$file"
                sed -i "s/^\(    highlight: *\)#[0-9a-f]*FF/\1#${hex}FF/" "$file"
            fi
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

        if [[ -z $slot ]]; then
            file="$output_dir/hyprland-colors.conf"
            if [[ -f $file ]]; then
                sed -i "s/^\$${key} = .*$/\$${key} = #${hex}/" "$file"
            fi
        fi

        file="$output_dir/shell-colors.json"
        if [[ -f $file ]]; then
            local shell_key=""
            case "$key" in
                primary)               shell_key="primary" ;;
                on_primary)            shell_key="overPrimary" ;;
                primary_container)     shell_key="primaryContainer" ;;
                on_primary_container)  shell_key="overPrimaryContainer" ;;
                on_primary_fixed)      shell_key="overPrimaryFixed" ;;
                on_primary_fixed_variant) shell_key="overPrimaryFixedVariant" ;;
                secondary)             shell_key="secondary" ;;
                on_secondary)          shell_key="overSecondary" ;;
                secondary_container)   shell_key="secondaryContainer" ;;
                on_secondary_container) shell_key="overSecondaryContainer" ;;
                on_secondary_fixed)    shell_key="overSecondaryFixed" ;;
                on_secondary_fixed_variant) shell_key="overSecondaryFixedVariant" ;;
                tertiary)              shell_key="tertiary" ;;
                on_tertiary)           shell_key="overTertiary" ;;
                tertiary_container)    shell_key="tertiaryContainer" ;;
                on_tertiary_container) shell_key="overTertiaryContainer" ;;
                on_tertiary_fixed)     shell_key="overTertiaryFixed" ;;
                on_tertiary_fixed_variant) shell_key="overTertiaryFixedVariant" ;;
                error)                 shell_key="error" ;;
                on_error)              shell_key="overError" ;;
                error_container)       shell_key="errorContainer" ;;
                on_error_container)    shell_key="overErrorContainer" ;;
                surface)               shell_key="surface" ;;
                on_surface)            shell_key="overSurface" ;;
                surface_variant)       shell_key="surfaceVariant" ;;
                on_surface_variant)    shell_key="overSurfaceVariant" ;;
                surface_bright)        shell_key="surfaceBright" ;;
                surface_container)     shell_key="surfaceContainer" ;;
                surface_container_high) shell_key="surfaceContainerHigh" ;;
                surface_container_highest) shell_key="surfaceContainerHighest" ;;
                surface_container_low) shell_key="surfaceContainerLow" ;;
                surface_container_lowest) shell_key="surfaceContainerLowest" ;;
                surface_dim)           shell_key="surfaceDim" ;;
                background)            shell_key="background" ;;
                on_background)         shell_key="overBackground" ;;
                outline)               shell_key="outline" ;;
                outline_variant)       shell_key="outlineVariant" ;;
                inverse_primary)       shell_key="inversePrimary" ;;
                inverse_surface)       shell_key="inverseSurface" ;;
                inverse_on_surface)    shell_key="inverseOnSurface" ;;
                shadow)                shell_key="shadow" ;;
                scrim)                 shell_key="scrim" ;;
            esac
            if [[ -n $shell_key ]]; then
                sed -i "s/\"${shell_key}\": *\"#[0-9a-f]*\"/\"${shell_key}\": \"#${hex}\"/" "$file"
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
