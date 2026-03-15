#!/bin/bash

source "$RETRO_DIR/cmds/system/setup/directories.sh"
source "$RETRO_DIR/cmds/system/setup/fingerprint.sh"
source "$RETRO_DIR/cmds/system/setup/wallpapers.sh"
source "$RETRO_DIR/cmds/system/setup/variables.sh"
source "$RETRO_DIR/cmds/system/setup/bitwarden.sh"
source "$RETRO_DIR/cmds/system/setup/editor.sh"
source "$RETRO_DIR/cmds/system/setup/pacman.sh"
source "$RETRO_DIR/cmds/system/setup/system.sh"
source "$RETRO_DIR/cmds/system/setup/emojis.sh"
source "$RETRO_DIR/cmds/system/setup/power.sh"

cmd_setup() {
    rx_logo
    rx_log "info" "Setting up RetroArch..."

    setup_system
    setup_editors

    SKIP_PROMPT=true

    execute_logic "install" "retro"
    run_task "install"

    rx_default_directories

    rx_vars_defaults "$2"

    rx_optimize_cpu
    rx_optimize_pacman

    rx_bootstrap_pkg_manager

    rx_setup_wallpapers

    rx_setup_emojis "$2"
    rx_setup_bitwarden
    rx_setup_fingerprint

    rx_log "success" "Setup complete!"

    sleep 1
    exec $SHELL
}

register_command "SYSTEM" "-s|--setup" "Install dependencies and CLI" "cmd_setup"
