#!/bin/bash

# TODO: Make a proper font manager where u can install multiple fonts
# and install emojis and changee the current emoji
#
# also there is a bug in which all the numbers transfom in emojis
# and we need to also find a way to refresh kitty and add the emojis
# to kitty also and any custom theme and font we use

rx_generate_emoji_config() {
    local style_key="${1,,}"
    local conf_file="$HOME/.config/fontconfig/conf.d/99-retro-emoji.conf"

    local real_font_name=""
    case "$style_key" in
        "apple") real_font_name="Apple Color Emoji" ;;
        "google") real_font_name="Noto Color Emoji" ;;
        "twemoji") local real_font_name="Twemoji" ;;
        "fluent") local real_font_name="Fluent UI Emoji" ;;
        "joypixels") local real_font_name="JoyPixels" ;;
        "samsung") local real_font_name="Samsung Color Emoji" ;;
        "openmoji") local real_font_name="OpenMoji" ;;
        "blob") local real_font_name="Blobmoji" ;;
        *) real_font_name="Noto Color Emoji" ;;
    esac

    mkdir -p "$(dirname "$conf_file")"
    rm -f "$HOME/.config/fontconfig/conf.d/"*emoji.conf

    rx_log "info" "Enforcing ${PINK}$real_font_name${RESET} as the absolute priority..."

    cat <<EOF >"$conf_file"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test qual="any" name="family"><string>emoji</string></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>$real_font_name</string>
    </edit>
  </match>

  <match target="pattern">
    <test name="family"><string>Noto Color Emoji</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>$real_font_name</string>
    </edit>
  </match>

  <alias binding="strong">
    <family>sans-serif</family>
    <prefer><family>$real_font_name</family></prefer>
  </alias>
  <alias binding="strong">
    <family>serif</family>
    <prefer><family>$real_font_name</family></prefer>
  </alias>
  <alias binding="strong">
    <family>monospace</family>
    <prefer><family>$real_font_name</family></prefer>
  </alias>
</fontconfig>
EOF

    rx_log "info" "Nuking font cache..."
    fc-cache -rf >/dev/null 2>&1
}

rx_install_emoji_pkg() {
    local pkg="$1"
    local name="$2"

    rx_log "info" "Installing $name Emoji set..."

    if pacman -Ss "^$pkg$" >/dev/null 2>&1; then
        sudo pacman -S "$pkg" --noconfirm
        return $?
    fi

    local aur_helper=""
    command -v yay >/dev/null && aur_helper="yay"
    command -v paru >/dev/null && aur_helper="paru"

    if [[ -n $aur_helper ]]; then
        if ! $aur_helper -S "$pkg" --noconfirm; then
            rx_log "warn" "$pkg not found. Searching for alternatives..."

            local alt_pkg=$($aur_helper -Ss "$name" | grep "emoji" | awk '{print $1}' | head -n 1 | cut -d'/' -f2)

            if [[ -n $alt_pkg ]]; then
                rx_log "info" "Found alternative: $alt_pkg. Installing..."
                $aur_helper -S "$alt_pkg" --noconfirm
            else
                rx_log "error" "No emoji package found for '$name' in AUR."
                return 1
            fi
        fi
    else
        rx_log "error" "No AUR helper (yay/paru) found. Cannot install $name."
        return 1
    fi
}

rx_setup_emojis() {
    local var_script="$RETRO_DIR/scripts/variable_core.sh"
    local force_flag="$1"

    local current_style=$(bash "$var_script" --get "EMOJI_STYLE")
    local should_run=false

    if [[ -z $current_style || $current_style == "null" ]]; then
        should_run=true
    elif [[ $force_flag == "-f" || $force_flag == "--force" ]]; then
        rx_log "warn" "Force flag detected. Reconfiguring emojis..."
        should_run=true
    else
        rx_log "info" "Current Emoji Style:${RESET} ${current_style^^}"
        rx_log "info" "Would you like to change your current style? ${PINK}[y/N]${RESET}: "
        read -r change
        [[ $change =~ ^[Yy]$ ]] && should_run=true
    fi

    [[ $should_run == "false" ]] && return 0

    local styles=(
        "apple|ttf-apple-emoji|Apple|Glossy, high-detail, premium (iOS vibe)"
        "google|noto-fonts-emoji|Google|Flat, clean, highly compatible (Android vibe)"
        "twemoji|ttf-twemoji|Twitter|The classic Discord/Web look"
        "fluent|ttf-fluentui-emoji|Microsoft|3D Fluent style"
        "joypixels|ttf-joypixels|JoyPixels|Very vibrant and expressive"
        "samsung|ttf-samsung-emojis|Samsung|Clean, bubbly lines"
        "openmoji|ttf-openmoji|OpenMoji|Artistic with black outlines"
        "blob|noto-fonts-emoji-blob|Blobs|The legendary Android 'Noodle' blobs"
    )

    echo -e "\n ${PINK}󰞅 Select your Emoji Aesthetic:${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

    for i in "${!styles[@]}"; do
        IFS='|' read -r key pkg name vibe <<<"${styles[$i]}"
        local marker=" "
        [[ $key == "$current_style" ]] && marker="${PINK}󰄾${RESET}"
        printf " %b ${PINK}%2d)${RESET} %-12s ${GRAY}»${RESET} %s\n" "$marker" $((i + 1)) "$name" "$vibe"
    done

    echo -ne "\n ${PINK}󰄾 ${RESET}Select a style (1-${#styles[@]}) or [Enter] to skip: "
    read -r choice

    if [[ ! $choice =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#styles[@]})); then
        rx_log "info" "Emoji setup skipped."
        return 0
    fi

    local selected="${styles[$((choice - 1))]}"
    IFS='|' read -r key pkg name vibe <<<"$selected"

    bash "$var_script" --set "EMOJI_STYLE" "$key"
    rx_log "success" "EMOJI_STYLE updated to: ${PINK}$key${RESET}"

    rx_install_emoji_pkg "$pkg" "$key"

    rx_generate_emoji_config "$key"
}
