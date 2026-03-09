#!/bin/bash

# TODO: Add a default text editor variable
# TODO: Make also a fingerprint setup if it detects that the device has
# fingerprint capabilities

source "$RETRO_DIR/lib/setup/directories.sh"
source "$RETRO_DIR/lib/setup/wallpapers.sh"
source "$RETRO_DIR/lib/setup/variables.sh"
source "$RETRO_DIR/lib/setup/pacman.sh"
source "$RETRO_DIR/lib/setup/power.sh"

cmd_setup() {
    rx_logo
    rx_log "info" "Setting up RetroArch..."

    SKIP_PROMPT=true

    execute_logic "install" "retro"

    rx_default_directories

    rx_vars_defaults "$1"
    rx_optimize_cpu_defaults

    rx_optimize_pacman
    rx_bootstrap_pkg_manager

    rx_setup_wallpapers

    rx_log "success" "Setup complete!"

    sleep 1
    exec $SHELL
}

register_command "SYSTEM" "-s|--setup" "Install dependencies and CLI" "cmd_setup"
