#!/bin/bash

source "$RETRO_DIR/lib/log.sh"

install_spotify() {
    if [[ ! -d /opt/spotify ]]; then
        rx_log "error" "Spotify not found at /opt/spotify"
        return 1
    fi

    rx_log "info" "Launching Spotify — please log in to generate your profile..."
    rx_log "info" "Waiting for ~/.config/spotify/prefs to appear..."

    spotify &

    local attempts=0
    while [[ ! -f "$HOME/.config/spotify/prefs" && $attempts -lt 30 ]]; do
        sleep 2
        ((attempts++))
    done

    if [[ -f "$HOME/.config/spotify/prefs" ]]; then
        rx_log "success" "Spotify preferences detected"
    else
        rx_log "warn" "Spotify preferences not detected after $((attempts * 2))s — continuing anyway"
    fi

    rx_log "info" "Granting write permissions to Spotify directory..."
    sudo chmod a+wr /opt/spotify
    sudo chmod a+wr /opt/spotify/Apps -R
    rx_log "success" "Spotify directory permissions set"

    rx_log "info" "Patching Spotify desktop entry..."
    local desktop_file="/usr/share/applications/spotify.desktop"
    if ! grep -q "^Comment=" "$desktop_file" 2>/dev/null; then
        sudo sed -i '/^Icon=/a Comment=Stream music and podcasts on Spotify' "$desktop_file"
        rx_log "success" "Desktop entry updated with description"
    else
        rx_log "info" "Desktop entry already has a description"
    fi

    rx_log "info" "Initializing Spicetify..."
    spicetify backup apply -n
    rx_log "success" "Spicetify initialized"

    rx_log "info" "Installing Spicetify Marketplace..."
    curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh
    rx_log "success" "Spicetify Marketplace installed"
}

install_spotify
