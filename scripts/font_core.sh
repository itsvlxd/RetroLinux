#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

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

  <alias>
    <family>sans-serif</family>
    <prefer><family>$main</family><family>$nerd</family><family>$emoji</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>$main</family><family>$nerd</family><family>$emoji</family></prefer>
  </alias>

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

</fontconfig>
EOF

    fc-cache -f >/dev/null 2>&1

    cur_hint=$(gsettings get org.gnome.desktop.interface font-antialiasing | tr -d "'")

    gsettings set org.gnome.desktop.interface font-antialiasing 'none'
    sleep 0.1
    gsettings set org.gnome.desktop.interface font-antialiasing "$cur_hint"
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
            grep -iE "font|ttf|otf|woff|emoji" |
            grep -ivE "lib32-|lib64-|electron|nodejs|python-" |
            grep -E "^(aur|extra|community|multilib)/" |
            sed 's/^[^\/]*\///'
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
esac
