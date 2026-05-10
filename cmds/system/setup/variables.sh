#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_variables() {
    rx_log "info" "Initializing system variables..."
    local filemanager_choice="${FILEMANAGER_CHOICE:-thunar}"
    local editor_choice="${EDITOR_CHOICE:-nvim}"
    local install_type="${INSTALL_TYPE:-complete}"
    local aur_helper="${AUR_HELPER:-yay}"

    local defaults=(
        "PKG_HELPER|$aur_helper"
        "RETRO_FILEMANAGER_CMD|$filemanager_choice"
        "RETRO_EDITOR_CMD|$editor_choice"
        "RETRO_INSTALL|$install_type"
    )

    for entry in "${defaults[@]}"; do
        IFS='|' read -r key val <<<"$entry"
        "$RETRO_DIR/retro.sh" variable set "$key" "$val" 2>/dev/null
    done
    rx_log "success" "System variables initialized"

    local desktop_file
    case "$filemanager_choice" in
        thunar) desktop_file="thunar.desktop" ;;
        nemo) desktop_file="nemo.desktop" ;;
        nautilus) desktop_file="org.gnome.Nautilus.desktop" ;;
        yazi)
            desktop_file="yazi.desktop"
            mkdir -p "$HOME/.local/share/applications"
            cat >"$HOME/.local/share/applications/yazi.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Yazi
Exec=kitty -e yazi %u
Icon=yazi
Terminal=true
Categories=System;FileManagement;
MimeType=inode/directory;application/x-directory;
EOF
            ;;
        *) desktop_file="thunar.desktop" ;;
    esac

    local browser_choice="${BROWSER_CHOICE:-firefox}"
    local browser_file
    case "$browser_choice" in
        zen-browser-bin) browser_file="zen.desktop" ;;
        chromium) browser_file="chromium.desktop" ;;
        firefox) browser_file="firefox.desktop" ;;
        floorp) browser_file="floorp.desktop" ;;
        thorium) browser_file="thorium.desktop" ;;
        nyxt) browser_file="nyxt.desktop" ;;
        *) browser_file="firefox.desktop" ;;
    esac

    mkdir -p "$HOME/.config"
    cat >"$HOME/.config/mimeapps.list" <<EOF
[Default Applications]
text/plain=${editor_choice}.desktop
inode/directory=$desktop_file
application/x-directory=$desktop_file
x-scheme-handler/file=$desktop_file
x-scheme-handler/trash=$desktop_file
x-scheme-handler/http=$browser_file
x-scheme-handler/https=$browser_file
EOF
    update-desktop-database "$HOME/.local/share/applications" 2>&1
    rx_log "success" "File manager configured: $filemanager_choice"

    command -v gsettings &>/dev/null && gsettings set org.gnome.desktop.default-applications.terminal exec 'kitty'
}
