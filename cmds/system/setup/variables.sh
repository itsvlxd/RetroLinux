#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_variables() {
    rx_log "info" "Initializing system variables..."
    local filemanager_choice="${FILEMANAGER_CHOICE:-thunar}"
    local editor_choice="${EDITOR_CHOICE:-nvim}"
    local aur_helper="${AUR_HELPER:-yay}"
    
    local defaults=(
        "PKG_HELPER|$aur_helper"
        "RETRO_FILEMANAGER_CMD|$filemanager_choice"
        "RETRO_TERMINAL_CMD|kitty"
        "RETRO_EDITOR_CMD|$editor_choice"
        "RETRO_THEME|retro"
        "RETRO_OPACITY|0.9"
        "RETRO_INACTIVE_OPACITY|0.8"
        "RETRO_BORDER_SIZE|2"
        "RETRO_ROUNDING|10"
        "RETRO_GAP_IN|5"
        "RETRO_GAP_OUT|20"
        "RETRO_SHADOW|true"
        "RETRO_BLUR|true"
        "NOTIFY_ON_HIGH_BAT_USAGE|true"
        "CLIP_WARDEN_SYNC|900"
        "CLIP_WARDEN_TIMEOUT|600"
        "CLIP_WARDEN_DESTRUCT|30"
        "BAT_SAVER_THRESHOLD|50"
        "BAT_SAVER_ACTIVE|false"
        "BAT_SAVER_FORCED|false"
        "BAT_SAVER_ON_PWR_DIS|true"
        "BAT_NOTIFY_THRESHOLD|30"
        "BAT_NOTIFY_CRITICAL_THRESHOLD|15"
        "WALL_STATIC_FORCED|false"
        "WALL_STATIC_ON_BAT|true"
        "WALL_SLIDESHOW_INTERVAL|300"
        "PWR_CURRENT|balanced"
        "PWR_PREVIOUS|saver"
        "PWR_BAT_SAVER|7"
        "PWR_BAT_BALANCED|14"
        "PWR_BAT_PERFORMANCE|35"
        "PWR_AC_SAVER|15"
        "PWR_AC_BALANCED|28"
        "PWR_AC_PERFORMANCE|65"
        "KITTY_FONT|JetBrainsMono Nerd Font"
        "KITTY_FONT_SIZE|9.5"
        "KITTY_PADDING|5"
        "KITTY_SHRINK_PADDING_FULLSCREEN|true"
        "ROFI_FONT|JetBrainsMono Nerd Font"
        "ROFI_FONT_SIZE|9.5"
        "ROFI_BORDER_SIZE|2"
        "ROFI_ROUNDING|10"
        "ROFI_PADDING|5"
    )
    
    for entry in "${defaults[@]}"; do
        IFS='|' read -r key val <<< "$entry"
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
            cat > "$HOME/.local/share/applications/yazi.desktop" << 'EOF'
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
    cat > "$HOME/.config/mimeapps.list" << EOF
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