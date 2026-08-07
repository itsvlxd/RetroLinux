#!/bin/bash

source "$RETRO_DIR/lib/fs.sh"
source "$RETRO_DIR/lib/git.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/pkg.sh"
source "$RETRO_DIR/lib/logo.sh"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/module.sh"
source "$RETRO_DIR/lib/helpers.sh"

register_command() {
    local empty=1
}

run_postinstall() {
    SETUP_LOG="/var/log/retrolinux-setup.log"
    exec > >(tee -a "$SETUP_LOG") 2>&1

    export RETRO_SETUP=true

    rx_logo
    rx_log "info" "Running post-install setup..."
    rx_log "info" "Setup log written to: $SETUP_LOG"
    faillock --user $USER --reset

    rx_git_fix_owner
    sudo chown -R "$USER:$USER" "$HOME/.config" 2>/dev/null || true

    source "$HOME/.retro_install"

    source "$RETRO_DIR/cmds/system/setup/network.sh" && setup_network
    source "$RETRO_DIR/cmds/system/setup/modules.sh" && setup_modules
    source "$RETRO_DIR/cmds/system/setup/ricing.sh" && setup_ricing_mode
    source "$RETRO_DIR/cmds/system/setup/variables.sh" && setup_variables
    source "$RETRO_DIR/cmds/system/setup/drivers.sh" && setup_drivers

    retro wallpaper "static" "true"
    retro wallpaper "set" "Car In Neon Gas Station"

    retro keyring setup --needed

    check_dep "${EDITOR_CHOICE:-nvim}" "neovim"
    check_dep "${BROWSER_CHOICE:-firefox}" "firefox"
    check_dep "${FILEMANAGER_CHOICE:-nemo}" "nemo"
    check_dep "${FIREWALL_ENGINE:-nftables}" "nftables"
    check_dep "loupe" "loupe"
    check_dep "mpv" "mpv"

    retro xdg setup -o "editor=${EDITOR_CHOICE:-nvim},browser=${BROWSER_CHOICE:-firefox},filemanager=${FILEMANAGER_CHOICE:-nemo},image=loupe,video=mpv"

    retro wallpaper setup --needed -o "theme=retro"
    retro theme setup --needed -y
    sudo mkdir -p /root/.config
    for _dir in gtk-3.0 gtk-4.0 Kvantum qt5ct qt6ct; do
        sudo ln -snf "$HOME/.config/$_dir" "/root/.config/$_dir"
    done
    retro power setup --needed -o "profile=recommended"
    retro font setup --needed -y
    retro input setup --needed -y
    retro audio setup
    retro polkit setup --needed -y
    retro firewall setup --needed -o "engine=${FIREWALL_ENGINE:-nftables},default=drop"
    retro fans setup --needed -o "engine=lm-sensors,profile=balanced"

    [[ $FINGERPRINT_ENABLED == true ]] && retro fingerprint setup --needed
    [[ $SSH_ENABLED == true ]] && retro ssh setup --needed -o "port=${SSH_PORT:-22},password=${SSH_PASSWORD_LOGIN:-false},pubkey=${SSH_KEY_LOGIN:-true},root=${SSH_ROOT_LOGIN:-false}"

    local root_device=$(findmnt -n -o SOURCE / | grep -oP '^/dev/[^ ]+')
    if [[ -n $root_device ]]; then
        retro timeshift setup --needed -o "device=${root_device},daily=5,weekly=3,monthly=2,boot=true,filters=optimized" 2>/dev/null || true
    fi

    retro wallpaper "static" "false"

    sudo rm -f /etc/sudoers.d/retro-post-install
    rm "$HOME/.retro_install"

    rx_log "success" "Post-install complete!"
    rx_log "warn" "The installation process is now finished, rebooting in 5 seconds..."

    sleep 5

    faillock --user $USER --reset
    systemctl reboot
}
