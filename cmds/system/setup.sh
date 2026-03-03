#!/bin/bash

cmd_setup() {
    rx_logo
    rx_log "info" "Setting up RetroArch..."

    rx_vars_defaults "$1"
    rx_optimize_pacman
    rx_bootstrap_pkg_manager

    rx_log "success" "Setup complete!"

    sleep 1
    exec $SHELL
}

register_command "SYSTEM" "-s|--setup" "Install dependencies and CLI" "cmd_setup"
