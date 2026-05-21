#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/scripts/grub_core.sh"

rx_log "info" "Installing GRUB themes..."
install_grub_themes

rx_log "info" "Updating GRUB configuration..."
update_grub_config

rx_log "info" "Regenerating GRUB configuration..."
regenerate_grub

rx_log "success" "GRUB module installation complete"
