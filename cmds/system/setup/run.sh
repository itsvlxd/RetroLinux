#!/bin/bash

source "$RETRO_DIR/lib/fs.sh"
source "$RETRO_DIR/lib/git.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/pkg.sh"
source "$RETRO_DIR/lib/logo.sh"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/module.sh"
source "$RETRO_DIR/lib/helpers.sh"

RETRO_COMPLETE="$HOME/.retro"

register_command() {
    local empty=1
}

run_postinstall() {
    rx_logo
    rx_log "info" "Running post-install setup..."
    faillock --user $USER --reset

    rx_git_fix_owner

    source "$HOME/.retro_install"

    source "$RETRO_DIR/cmds/system/setup/network.sh" && setup_network
    source "$RETRO_DIR/cmds/system/setup/ricing.sh" && setup_ricing_mode
    source "$RETRO_DIR/cmds/system/setup/variables.sh" && setup_variables
    source "$RETRO_DIR/cmds/system/setup/modules.sh" && setup_modules

    retro wallpaper "static" "true"
    retro wallpaper "set" "car-in-neon-gas-station.mp4"

    source "$RETRO_DIR/cmds/system/setup/drivers.sh" && setup_drivers
    source "$RETRO_DIR/cmds/system/setup/grub.sh" && setup_grub
    source "$RETRO_DIR/cmds/system/setup/xdg.sh" && setup_xdg
    source "$RETRO_DIR/cmds/system/setup/keyring.sh" && setup_keyring

    retro xdg setup -o "${EDITOR_CHOICE:-nvim},${BROWSER_CHOICE:-firefox},${FILEMANAGER_CHOICE:-thunar},loupe,mpv"

    source "$RETRO_DIR/cmds/system/setup/ssh.sh" && setup_ssh
    source "$RETRO_DIR/cmds/system/setup/terminal.sh" && setup_terminal
    source "$RETRO_DIR/cmds/system/setup/wallpaper.sh" && setup_wallpaper
    source "$RETRO_DIR/cmds/system/setup/fonts.sh" && setup_fonts
    source "$RETRO_DIR/cmds/system/setup/fingerprint.sh" && setup_fingerprint
    source "$RETRO_DIR/cmds/system/setup/power.sh" && setup_power
    source "$RETRO_DIR/cmds/system/setup/browser.sh" && setup_browser
    source "$RETRO_DIR/cmds/system/setup/audio.sh" && setup_audio

    retro wallpaper "static" "false"

    rm "$HOME/.retro_install"

    rx_log "success" "Post-install complete!"
    rx_log "warn" "The installation process is now finished, rebooting in 5 seconds..."

    sleep 5

    faillock --user $USER --reset
    systemctl reboot
}
