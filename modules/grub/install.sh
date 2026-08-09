#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/scripts/grub_core.sh"

setup_grub_menu_sudoers() {
    local spliter="$RETRO_DIR/scripts/python/grub_manual_entries.py"
    if [[ -x $spliter ]]; then
        sudo rm -f /etc/sudoers.d/99-retro-grub-menu
        echo "%wheel ALL=(ALL) NOPASSWD: ${spliter}" | sudo tee /etc/sudoers.d/99-retro-grub-menu >/dev/null
        sudo chmod 440 /etc/sudoers.d/99-retro-grub-menu
        rx_log "success" "Sudoers rule added for GRUB menu parser"
    fi
}
setup_grub_menu_sudoers

setup_grub_core_sudoers() {
    # Commands used by scripts/grub_core.sh so `retro grub` and the settings
    # UI can run them without a password prompt. Only binaries actually present
    # on the system are whitelisted; sudoers rejects entries for missing paths.
    local cmds=(
        grub-mkconfig
        grub-install
        grub-script-check
        grub-mkstandalone
        mkinitcpio
        btrfs
        filefrag
        mkswap
        swapon
        swapoff
        fallocate
        truncate
        chattr
        dd
        pacman
        systemctl
        timeshift
    )

    local keep=()
    local cmd
    for cmd in "${cmds[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            keep+=("$(command -v "$cmd")")
        fi
    done

    local spliter="$RETRO_DIR/scripts/python/grub_manual_entries.py"
    if [[ -x $spliter ]]; then
        keep+=("$spliter")
    fi

    if [[ ${#keep[@]} -eq 0 ]]; then
        rx_log "warn" "No GRUB core commands found, skipping sudoers setup"
        return 0
    fi

    sudo rm -f /etc/sudoers.d/99-retro-grub-core
    {
        echo "%wheel ALL=(ALL) NOPASSWD: $(IFS=', '; echo "${keep[*]}")"
    } | sudo tee /etc/sudoers.d/99-retro-grub-core >/dev/null
    sudo chmod 440 /etc/sudoers.d/99-retro-grub-core

    if sudo visudo -cf /etc/sudoers.d/99-retro-grub-core >/dev/null 2>&1; then
        rx_log "success" "Sudoers rule added for GRUB core commands"
    else
        rx_log "error" "GRUB core sudoers file failed validation, removing it"
        sudo rm -f /etc/sudoers.d/99-retro-grub-core
        return 1
    fi
}
setup_grub_core_sudoers

rx_log "info" "Installing GRUB themes..."
install_grub_themes

rx_log "info" "Updating GRUB configuration..."
update_grub_config

rx_log "info" "Regenerating GRUB configuration..."
regenerate_grub

rx_log "success" "GRUB module installation complete"
