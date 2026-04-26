#!/usr/bin/env bash

export RETRO_INSTALL="/opt/retrolinux/bin"
source "$RETRO_INSTALL/lib/display.sh"
source "$RETRO_INSTALL/lib/gum.sh"
source "$RETRO_INSTALL/lib/errors.sh"
source "$RETRO_INSTALL/lib/wifi.sh"
source "$RETRO_INSTALL/lib/qr.sh"
source "$RETRO_INSTALL/lib/locale.sh"
source "$RETRO_INSTALL/lib/timezone.sh"

rx_set_retro_colors

RETROLINUX_USER=""

setup_user_config() {
    /opt/retrolinux/bin/retroinstall
    if [[ ! -f /root/user_configuration.json || ! -f /root/user_credentials.json ]]; then
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "ERROR: Configuration files not created."
        return 1
    fi
    export RETROLINUX_USER="$(jq -r '.users[0].username' /root/user_credentials.json 2>/dev/null || echo 'root')"
}

install_system() {
    rx_clear_logo
    echo
    gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Installing..."
    echo

    pacman-key --init 2>/dev/null || true
    pacman-key --populate archlinux 2>/dev/null || true

    findmnt -R /mnt >/dev/null && umount -R /mnt 2>/dev/null || true

    if ! archinstall \
        --config /root/user_configuration.json \
        --creds /root/user_credentials.json \
        --silent \
        --skip-ntp \
        --skip-wkd \
        --skip-wifi-check; then
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "ERROR: archinstall failed"
        cat /var/log/archinstall/install.log 2>/dev/null || true
        return 1
    fi

    cp /etc/pacman.conf /mnt/etc/pacman.conf 2>/dev/null || true

    mkdir -p /mnt/etc/sudoers.d
    cat >/mnt/etc/sudoers.d/99-retrolinux-installer <<EOF
root ALL=(ALL:ALL) NOPASSWD: ALL
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
$RETROLINUX_USER ALL=(ALL:ALL) NOPASSWD: ALL
EOF
    chmod 440 /mnt/etc/sudoers.d/99-retrolinux-installer 2>/dev/null || true

    if [[ -n $RETROLINUX_USER && $RETROLINUX_USER != "root" ]]; then
        mkdir -p /mnt/home/$RETROLINUX_USER
        chown -R 1000:1000 /mnt/home/$RETROLINUX_USER/.local/ 2>/dev/null || true
    fi
}

main() {
    if [[ $(tty) == "/dev/tty1" ]]; then
        plymouth quit 2>/dev/null || true
        rx_clear_logo

        if ! setup_user_config; then
            gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Configuration failed"
            exit 1
        fi

        if ! install_system; then
            gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Installation failed"
            exit 1
        fi

        rx_clear_logo
        echo
        gum style --foreground 2 --padding "1 0 1 $PADDING_LEFT" "Installation complete! Rebooting..."
        echo
        sleep 3
        reboot
    fi
}

main