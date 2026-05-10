#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_mimeapps() {
    rx_log "info" "Configuring default applications..."

    local editor_choice="${EDITOR_CHOICE:-nvim}"
    local filemanager_choice="${FILEMANAGER_CHOICE:-thunar}"
    local browser_choice="${BROWSER_CHOICE:-firefox}"

    local desktop_file
    case "$filemanager_choice" in
        thunar) desktop_file="thunar.desktop" ;;
        nemo) desktop_file="nemo.desktop" ;;
        nautilus) desktop_file="org.gnome.Nautilus.desktop" ;;
        *) desktop_file="thunar.desktop" ;;
    esac

    local browser_file
    case "$browser_choice" in
        zen-browser-bin) browser_file="zen.desktop" ;;
        chromium) browser_file="chromium.desktop" ;;
        firefox) browser_file="firefox.desktop" ;;
        *) browser_file="firefox.desktop" ;;
    esac

    mkdir -p "$HOME/.config"
    cat >"$HOME/.config/mimeapps.list" <<EOF
[Default Applications]
text/plain=${editor_choice}.desktop
inode/directory=$desktop_file
application/x-directory=$desktop_file
x-scheme-handler/http=$browser_file
x-scheme-handler/https=$browser_file
x-scheme-handler/file=$desktop_file
EOF
    update-desktop-database "$HOME/.local/share/applications" 2>&1
    rx_log "success" "Default applications configured"
}

