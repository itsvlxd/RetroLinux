#!/bin/bash

source "$RETRO_DIR/cmds/system/setup/directories.sh"
source "$RETRO_DIR/cmds/system/setup/fingerprint.sh"
source "$RETRO_DIR/cmds/system/setup/filemanager.sh"
source "$RETRO_DIR/cmds/system/setup/wallpapers.sh"
source "$RETRO_DIR/cmds/system/setup/variables.sh"
source "$RETRO_DIR/cmds/system/setup/auto-save.sh"
source "$RETRO_DIR/cmds/system/setup/bitwarden.sh"
source "$RETRO_DIR/cmds/system/setup/editor.sh"
source "$RETRO_DIR/cmds/system/setup/pacman.sh"
source "$RETRO_DIR/cmds/system/setup/system.sh"
source "$RETRO_DIR/cmds/system/setup/emojis.sh"
source "$RETRO_DIR/cmds/system/setup/power.sh"

# TODO: Improve installing logs
# TODO: If a module path already exists warn the user first
# that we detected a different config then the retro one
# and bypass SKIP_PROMPT and ask the user if he would like
# to install the specific module but still ensure him that
# before installing we backup their local config

cmd_setup() {
    rx_logo
    rx_log "info" "Setting up Retro Linux..."

    setup_system
    setup_editors

    SKIP_PROMPT=true

    execute_logic "install" "retro"
    run_task "install"

    rx_default_directories

    rx_vars_defaults "$2"

    setup_file_manager

    rx_optimize_cpu
    rx_optimize_pacman
    rx_bootstrap_pkg_manager

    rx_setup_session_service
    rx_setup_wallpapers

    rx_setup_emojis "$2"
    rx_setup_bitwarden
    rx_setup_fingerprint

    rx_log "success" "Setup complete!"

    sleep 1
    exec $SHELL
}

register_command "SYSTEM" "-s|--setup" "Install dependencies and CLI" "cmd_setup"
