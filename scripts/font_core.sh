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
esac
