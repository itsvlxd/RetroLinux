#!/bin/bash

# TODO: Add a default text editor variable

source "$RETRO_DIR/lib/setup/directories.sh"
source "$RETRO_DIR/lib/setup/fingerprint.sh"
source "$RETRO_DIR/lib/setup/wallpapers.sh"
source "$RETRO_DIR/lib/setup/variables.sh"
source "$RETRO_DIR/lib/setup/pacman.sh"
source "$RETRO_DIR/lib/setup/emojis.sh"
source "$RETRO_DIR/lib/setup/power.sh"

cmd_setup() {
    rx_logo
    rx_log "info" "Setting up RetroArch..."

    SKIP_PROMPT=true

    execute_logic "install" "retro"

    rx_default_directories

    rx_vars_defaults "$2"
    rx_optimize_cpu_defaults

    rx_optimize_pacman
    rx_bootstrap_pkg_manager

    rx_setup_emojis "$2"
    rx_setup_wallpapers
    rx_setup_fingerprint

    rx_log "success" "Setup complete!"

    sleep 1
    exec $SHELL
}

register_command "SYSTEM" "-s|--setup" "Install dependencies and CLI" "cmd_setup"
