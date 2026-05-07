#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_power() {
    rx_log "info" "Applying power optimizations..."
    "$RETRO_DIR/retro.sh" power "permissions" 2>&1
    "$RETRO_DIR/retro.sh" power "optimize" -y 2>&1
    rx_log "success" "Power optimizations applied"
}