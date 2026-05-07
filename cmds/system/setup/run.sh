#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

RETRO_COMPLETE="$HOME/.retro"

run_postinstall() {
    rx_logo
    rx_log "info" "Running post-install setup..."

    source "$HOME/.retro_install"

    source "$RETRO_DIR/cmds/system/setup/network.sh" && setup_network
    source "$RETRO_DIR/cmds/system/setup/packages.sh" && setup_packages
    source "$RETRO_DIR/cmds/system/setup/aur.sh" && setup_aur
    source "$RETRO_DIR/cmds/system/setup/drivers.sh" && setup_drivers
    source "$RETRO_DIR/cmds/system/setup/xdg.sh" && setup_xdg
    source "$RETRO_DIR/cmds/system/setup/keyring.sh" && setup_keyring
    source "$RETRO_DIR/cmds/system/setup/mimeapps.sh" && setup_mimeapps
    source "$RETRO_DIR/cmds/system/setup/editor.sh" && setup_editor
    source "$RETRO_DIR/cmds/system/setup/ssh.sh" && setup_ssh
    source "$RETRO_DIR/cmds/system/setup/modules.sh" && setup_modules

    source "$RETRO_DIR/cmds/system/setup/terminal.sh" && setup_terminal
    source "$RETRO_DIR/cmds/system/setup/variables.sh" && setup_variables
    source "$RETRO_DIR/cmds/system/setup/wallpaper.sh" && setup_wallpaper
    source "$RETRO_DIR/cmds/system/setup/fonts.sh" && setup_fonts
    source "$RETRO_DIR/cmds/system/setup/fingerprint.sh" && setup_fingerprint
    source "$RETRO_DIR/cmds/system/setup/power.sh" && setup_power
    source "$RETRO_DIR/cmds/system/setup/browser.sh" && setup_browser

    touch "$RETRO_COMPLETE"
    rx_log "success" "Post-install complete!"
}

