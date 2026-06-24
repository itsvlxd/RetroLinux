#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"

install_silent_sddm() {
    local theme_src="$RETRO_DIR/modules/sddm/files"
    local theme_dst="/usr/share/sddm/themes/retro"

    rx_log "info" "Installing SilentSDDM theme..."

    mkdir -p /usr/share/sddm/themes
    rsync -a --delete "$theme_src/" "$theme_dst/"
    chmod -R 755 "$theme_dst"
    chown -R "${SUDO_USER:-$USER}":"${SUDO_USER:-$USER}" "$theme_dst"

    if [[ -d $theme_dst/fonts ]]; then
        rx_log "info" "Installing SDDM fonts..."
        cp -r "$theme_dst/fonts/"* /usr/share/fonts/ 2>/dev/null
        fc-cache -f 2>/dev/null
    fi

    rx_log "success" "SilentSDDM theme installed to $theme_dst"
}

configure_sddm() {
    rx_log "info" "Configuring /etc/sddm.conf..."

    mkdir -p /etc

    cat > /etc/sddm.conf <<'EOF'
[Theme]
Current=retro

[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=QML2_IMPORT_PATH=/usr/share/sddm/themes/retro/components/,QT_IM_MODULE=qtvirtualkeyboard
EOF

    rx_log "success" "SDDM configured to use Silent theme"
}

install_silent_sddm
configure_sddm
