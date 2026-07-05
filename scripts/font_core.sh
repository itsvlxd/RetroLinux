#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "font"

rx_generate_conf() {
    local main=$(get_var "RETRO_FONT_MAIN")
    local nerd=$(get_var "RETRO_FONT_NERD")
    local emoji=$(get_var "RETRO_FONT_EMOJI")
    local conf_file="$HOME/.config/fontconfig/conf.d/99-retro-fonts.conf"

    [[ -z $main ]] && main="sans-serif"
    [[ -z $nerd ]] && nerd="monospace"
    [[ -z $emoji ]] && emoji="serif"

    mkdir -p "$(dirname "$conf_file")"

    cat <<EOF >"$conf_file"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>

  <match target="pattern">
    <test qual="any" name="family"><string>sans-serif</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>$main</string>
    </edit>
  </match>

  <match target="pattern">
    <test qual="any" name="family"><string>system-ui</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>$main</string>
    </edit>
  </match>

  <match target="pattern">
    <test qual="any" name="family"><string>Arial</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>$main</string>
    </edit>
  </match>

  <match target="pattern">
    <test qual="any" name="family"><string>Helvetica</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>$main</string>
    </edit>
  </match>

  <match target="pattern">
    <test qual="any" name="family"><string>monospace</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>$nerd</string>
    </edit>
  </match>

  <match target="pattern">
    <test name="family"><string>Noto Color Emoji</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>$emoji</string>
    </edit>
  </match>

  <match target="pattern">
    <test qual="any" name="family"><string>emoji</string></test>
    <edit name="family" mode="assign" binding="strong">
      <string>$emoji</string>
    </edit>
  </match>

  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
  </match>
  <match target="font">
    <edit name="hinting" mode="assign"><bool>false</bool></edit>
  </match>
  <match target="font">
    <edit name="hintstyle" mode="assign"><const>hintnone</const></edit>
  </match>
  <match target="font">
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
  </match>
  <match target="font">
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
  </match>

</fontconfig>
EOF

    fc-cache -f -v >/dev/null 2>&1

    gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
    gsettings set org.gnome.desktop.interface font-hinting 'none'
    bash "$RETRO_DIR/scripts/theme_core.sh" "--apply-gtk-font" 2>/dev/null
}

rx_refresh_apps() {
    pgrep -x kitty >/dev/null && kill -SIGUSR1 $(pgrep -x kitty)
}

rx_font_file_install() {
    local source_path="$1"
    local target_dir="$HOME/.local/share/fonts"
    local installed=0
    local skipped=0
    local overwritten=0
    local needs_confirm=false

    mkdir -p "$target_dir"

    if [[ -d "$source_path" ]]; then
        local files=("$source_path"/*)
        if [[ ${#files[@]} -eq 0 || ! -e "${files[0]}" ]]; then
            echo "DIRECTORY_EMPTY|$source_path"
            return 1
        fi
        for f in "$source_path"/*; do
            [[ -f "$f" ]] || continue
            local result
            result=$(rx_install_single_font "$f" "$target_dir")
            case "$result" in
                INSTALLED*) ((installed++)) ;;
                SKIPPED*) ((skipped++)) ;;
                OVERWRITTEN*) ((overwritten++)) ;;
                EXISTS*)
                    if [[ "$needs_confirm" == "false" ]]; then
                        needs_confirm=true
                    fi
                    ;;
            esac
        done
    elif [[ -f "$source_path" ]]; then
        local result
        result=$(rx_install_single_font "$source_path" "$target_dir")
        case "$result" in
            INSTALLED*) ((installed++)) ;;
            SKIPPED*) ((skipped++)) ;;
            OVERWRITTEN*) ((overwritten++)) ;;
            EXISTS*)
                needs_confirm=true
                echo "$result"
                ;;
        esac
    else
        echo "FILE_NOT_FOUND|$source_path"
        return 1
    fi

    echo "RESULT|installed=$installed|skipped=$skipped|overwritten=$overwritten|needs_confirm=$needs_confirm"
    return 0
}

rx_install_single_font() {
    local source_file="$1"
    local target_dir="$2"
    local filename=$(basename "$source_file")
    local target_path="$target_dir/$filename"

    local ext="${filename##*.}"
    ext="${ext,,}"
    case "$ext" in
        ttf|otf|woff|woff2|ttc)
            ;;
        *)
            echo "INVALID_EXT|$filename"
            return 1
            ;;
    esac

    local font_display="${filename%.*}"
    font_display=$(echo "$font_display" | sed 's/[-_]/ /g')

    if [[ -f "$target_path" ]]; then
        local existing_hash=$(md5sum "$target_path" 2>/dev/null | awk '{print $1}')
        local new_hash=$(md5sum "$source_file" 2>/dev/null | awk '{print $1}')

        echo "EXISTS|$filename|$font_display|$target_path|identical=$([ "$existing_hash" == "$new_hash" ] && echo true || echo false)"
        return 0
    fi

    cp "$source_file" "$target_path"
    echo "INSTALLED|$filename|$font_display"
    return 0
}

rx_font_file_do_overwrite() {
    local source_file="$1"
    local target_path="$2"
    local filename=$(basename "$source_file")

    local font_display="${filename%.*}"
    font_display=$(echo "$font_display" | sed 's/[-_]/ /g')

    cp "$source_file" "$target_path"
    echo "OVERWRITTEN|$filename|$font_display"
    return 0
}

rx_font_file_do_rename() {
    local source_file="$1"
    local target_dir="$2"
    local filename=$(basename "$source_file")

    local font_display="${filename%.*}"
    font_display=$(echo "$font_display" | sed 's/[-_]/ /g')

    local base="${filename%.*}"
    local ext="${filename##*.}"
    local counter=1
    local new_name="${base}_${counter}.${ext}"
    while [[ -f "$target_dir/$new_name" ]]; do
        ((counter++))
        new_name="${base}_${counter}.${ext}"
    done
    cp "$source_file" "$target_dir/$new_name"
    echo "INSTALLED|$new_name|$font_display"
    return 0
}

rx_font_file_cache() {
    fc-cache -f >/dev/null 2>&1
    echo "CACHE_UPDATED"
}

case "$1" in
    "--sync") rx_generate_conf ;;
    "--search-remote")
        helper=$(get_var "PKG_HELPER")
        query="$2"

        $helper -Ss "$query" |
            grep -E "^(aur|extra|community|multilib)/" |
            sed 's/^[^\/]*\///' |
            awk 'tolower($1) ~ /font|ttf|otf|woff|emoji|ttc|woff2/'
        ;;
    "--list-installed")
        fc-list : family | cut -d',' -f1 | sort -u | sed 's/^ //'
        ;;
    "--install-file")
        rx_font_file_install "$2"
        ;;
    "--install-file-overwrite")
        rx_font_file_do_overwrite "$2" "$3"
        ;;
    "--install-file-rename")
        rx_font_file_do_rename "$2" "$3"
        ;;
    "--install-file-skip")
        echo "SKIPPED"
        ;;
    "--install-file-cache")
        rx_font_file_cache
        ;;
    "--family-to-pkg")
        files=$(fc-list ":family=$2" file 2>/dev/null | cut -d: -f1)
        for f in $files; do
            pkg=$(pacman -Qo "$f" 2>/dev/null | grep -oP 'owned by \K\S+')
            [[ -n $pkg ]] && echo "$pkg" && exit 0
        done
        echo ""
        ;;
esac
