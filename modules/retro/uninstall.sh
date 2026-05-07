#!/bin/bash

remove_power_permissions() {
    local tmp_file="/etc/tmpfiles.d/retro-power.conf"

    if [[ -f $tmp_file ]]; then
        rx_log "info" "Revoking system-wide CPU power permissions..."

        if sudo rm "$tmp_file"; then
            rx_log "success" "Power management configuration file removed."
        else
            rx_log "error" "Failed to remove the power permissions file."
            return 1
        fi

        rx_log "warn" "System permissions will revert to default on next reboot."
        rx_log "success" "Power management configuration removed."
    else
        rx_log "info" "No power management configuration found. Skipping."
    fi
}

remove_retro_command() {
    local target="/usr/local/bin/retro"

    if [[ -L $target || -f $target ]]; then
        rx_log "info" "Removing system-wide binary: $target"
        sudo rm "$target"
        rx_log "success" "Global command ${PINK}retro${RESET} unlinked."
    fi

    local files_to_clean=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile")

    for shell_conf in "${files_to_clean[@]}"; do
        [[ ! -f $shell_conf ]] && continue

        if grep -q "RETRO_DIR\|RETRO_CONFIG\|# Retro Linux PATH" "$shell_conf"; then
            rx_log "info" "Cleaning up $(basename "$shell_conf")..."

            # Remove the PATH patch (the header + the next line)
            sed -i '/# Retro Linux PATH/,+1d' "$shell_conf"

            # Remove individual exports
            sed -i '/export RETRO_DIR=/d' "$shell_conf"
            # Remove RETRO_CONFIG as well
            sed -i '/export RETRO_CONFIG=/d' "$shell_conf"

            rx_log "success" "Sanitized $(basename "$shell_conf")"
        fi
    done

    #if [[ $1 == "--purge" ]]; then
    #    rx_log "warn" "Purging cache directory..."
    #    rm -rf "$HOME/.cache/retro"
    #    rx_log "success" "Cache cleared."
    #fi

    rx_log "success" "Uninstall complete. ${PINK}retro${RESET} is no longer global."
    rx_log "info" "Note: Environment changes require a logout/login to fully clear from Hyprland."
}

retro fingerprint uninstall

remove_power_permissions
remove_retro_command
