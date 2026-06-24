#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"

rx_log "info" "Removing SilentSDDM theme..."

rm -rf /usr/share/sddm/themes/retro

if [[ -f /etc/sddm.conf ]]; then
    sed -i '/^Current=retro$/d' /etc/sddm.conf
    sed -i '/^InputMethod=qtvirtualkeyboard$/d' /etc/sddm.conf
    sed -i '/^GreeterEnvironment=/d' /etc/sddm.conf
fi

rx_log "success" "SilentSDDM theme removed"
