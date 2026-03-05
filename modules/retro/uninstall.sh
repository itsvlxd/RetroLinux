#!/bin/bash

target="/usr/local/bin/retro"

if [[ -L $target || -f $target ]]; then
    rx_log "info" "Removing system-wide binary: $target"
    sudo rm "$target"
    rx_log "success" "Global command ${PINK}retro${RESET} unlinked."
fi

files_to_clean=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile")

for shell_conf in "${files_to_clean[@]}"; do
    [[ ! -f $shell_conf ]] && continue

    if grep -q "RETRO_DIR\|RETRO_CACHE\|# RetroArch PATH" "$shell_conf"; then
        rx_log "info" "Cleaning up $(basename "$shell_conf")..."

        # Remove the PATH patch (the header + the next line)
        sed -i '/# RetroArch PATH/,+1d' "$shell_conf"

        # Remove individual exports
        sed -i '/export RETRO_DIR=/d' "$shell_conf"
        # Remove RETRO_CACHE as well
        sed -i '/export RETRO_CACHE=/d' "$shell_conf"

        rx_log "success" "Sanitized $(basename "$shell_conf")"
    fi
done

# --- 4. OPTIONAL: CACHE REMOVAL ---
# Use 'retro --uninstall --purge' logic if you want to kill the cache too
if [[ $1 == "--purge" ]]; then
    rx_log "warn" "Purging cache directory..."
    rm -rf "$HOME/.cache/retro"
    rx_log "success" "Cache cleared."
fi

rx_log "success" "Uninstall complete. ${PINK}retro${RESET} is no longer global."
rx_log "info" "Note: Environment changes require a logout/login to fully clear from Hyprland."
