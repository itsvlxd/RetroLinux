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

_ensure_aur_helper() {
    local helper="${AUR_HELPER:-yay}"
    [[ $helper == "paru" ]] && helper="paru"
    [[ $helper == "yay" ]] && helper="yay"
    [[ $helper != "yay" && $helper != "paru" ]] && helper="yay"

    if ! command -v "$helper" >/dev/null 2>&1; then
        rx_log "info" "AUR helper ${PINK}${helper}${RESET} not found, installing..."
        sudo pacman -S --needed --noconfirm base-devel git >/dev/null 2>&1
        local repo=""
        [[ $helper == "yay" ]] && repo="https://aur.archlinux.org/yay-bin.git"
        [[ $helper == "paru" ]] && repo="https://aur.archlinux.org/paru.git"
        local tmpdir
        tmpdir=$(mktemp -d)
        git clone --depth 1 "$repo" "$tmpdir/$helper" >/dev/null 2>&1 &&
            (cd "$tmpdir/$helper" && makepkg -si --noconfirm >/dev/null 2>&1)
        rm -rf "$tmpdir" 2>/dev/null
    fi

    if command -v "$helper" >/dev/null 2>&1; then
        "$RETRO_DIR/retro.sh" variable set PKG_HELPER "$helper" >/dev/null 2>&1 || true
        rx_log "success" "AUR helper ready: ${PINK}${helper}${RESET}"
    else
        rx_log "warn" "Could not install AUR helper, AUR packages may be skipped"
    fi
}

run_postinstall() {
    SETUP_LOG="/var/log/retrolinux-setup.log"
    if ! sudo mkdir -p /var/log 2>/dev/null || ! sudo touch "$SETUP_LOG" 2>/dev/null; then
        SETUP_LOG="$HOME/.retrolinux-setup.log"
    else
        sudo chown "$USER:$USER" "$SETUP_LOG" 2>/dev/null || true
    fi
    exec > >(tee -a "$SETUP_LOG") 2>&1

    export RETRO_SETUP=true

    rx_logo
    rx_log "info" "Running post-install setup..."
    rx_log "info" "Setup log written to: $SETUP_LOG"
    faillock --user "$USER" --reset 2>/dev/null || true

    rx_git_fix_owner
    sudo chown -R "$USER:$USER" "$HOME/.config" 2>/dev/null || true

    source "$HOME/.retro_install"

    source "$RETRO_DIR/cmds/system/setup/network.sh" && setup_network
    _ensure_aur_helper
    source "$RETRO_DIR/cmds/system/setup/modules.sh" && setup_modules

    hash -r
    source "$HOME/.profile" 2>/dev/null || true
    rx_log "info" "Shell refreshed, 'retro' command is now available."

    source "$RETRO_DIR/cmds/system/setup/ricing.sh" && setup_ricing_mode
    source "$RETRO_DIR/cmds/system/setup/variables.sh" && setup_variables
    source "$RETRO_DIR/cmds/system/setup/drivers.sh" && setup_drivers

    retro wallpaper "static" "true"
    retro wallpaper "set" "Retrowave Gtr Wallpaper"

    retro keyring setup --needed

    ensure_pkg "${EDITOR_CHOICE:-nvim}" "neovim"
    if [[ ${BROWSER_CHOICE:-firefox} != "none" ]]; then
        local browser_pkg="${BROWSER_CHOICE:-firefox}"
        local browser_bin="$browser_pkg"
        [[ $browser_bin == "zen-browser-bin" ]] && browser_bin="zen"
        ensure_pkg "$browser_bin" "$browser_pkg"
    fi
    ensure_pkg "${FILEMANAGER_CHOICE:-nemo}" "nemo"
    ensure_pkg "${FIREWALL_ENGINE:-nftables}" "nftables"
    ensure_pkg "loupe" "loupe"
    ensure_pkg "mpv" "mpv"

    local xdg_browser="${BROWSER_CHOICE:-firefox}"
    [[ $xdg_browser == "zen-browser-bin" ]] && xdg_browser="zen"
    retro xdg setup -o "editor=${EDITOR_CHOICE:-nvim},browser=${xdg_browser},filemanager=${FILEMANAGER_CHOICE:-nemo},image=loupe,video=mpv"

    retro wallpaper setup --needed -y -o "theme=retro"

    retro wallpaper pull retro

    retro theme setup --needed -y
    retro theme mode dark

    bash "$RETRO_DIR/scripts/users_core.sh" --gen-face "$USER"
    bash "$RETRO_DIR/scripts/theme_core.sh" --sddm-refresh

    sudo mkdir -p /root/.config
    for _dir in gtk-3.0 gtk-4.0 Kvantum qt5ct qt6ct; do
        sudo ln -snf "$HOME/.config/$_dir" "/root/.config/$_dir"
    done

    retro grub setup --needed -y -o "theme=${GRUB_THEME_CHOICE:-retropunk},resolution=${BOOT_VIDEO_GRUB:-1920x1080},timeout=${GRUB_TIMEOUT:-10},os-prober=${GRUB_OS_PROBER:-false},snapshots=${GRUB_SNAPSHOTS_ENABLED:-true},kernel=${GRUB_KERNEL:-linux}"

    retro power setup --needed -o "profile=recommended"
    retro font setup --needed -y
    retro input setup --needed -y

    retro audio eq download JackHack96

    retro polkit setup --needed -y
    if [[ ${FIREWALL_ENABLED:-true} == "true" ]]; then
        sudo systemctl enable nftables 2>/dev/null || true
    fi

    [[ $FINGERPRINT_ENABLED == true ]] && retro fingerprint setup --needed
    [[ $SSH_ENABLED == true ]] && retro ssh setup --needed -o "port=${SSH_PORT:-22},password=${SSH_PASSWORD_LOGIN:-false},pubkey=${SSH_KEY_LOGIN:-true},root=${SSH_ROOT_LOGIN:-false}"

    local root_device=$(findmnt -n -o SOURCE / | grep -oP '^/dev/[^ ]+')
    if [[ -n $root_device ]]; then
        retro timeshift setup --needed -o "device=${root_device},daily=5,weekly=3,monthly=2,boot=true,filters=optimized" 2>/dev/null || true
    fi

    retro shell start

    sudo rm -f /etc/sudoers.d/retro-post-install
    rm "$HOME/.retro_install"

    rx_log "success" "Post-install complete!"
    rx_log "warn" "The installation process is now finished, rebooting in 5 seconds..."

    sleep 5

    faillock --user "$USER" --reset 2>/dev/null || true
    systemctl reboot
}
