#!/bin/bash

cmd_setup() {
    rx_logo
    rx_log "info" "Setting up RetroArch..."

    rx_optimize_pacman
    rx_bootstrap_pkg_manager

    local source_bin=$(readlink -f "$0")
    local bin_dir="$HOME/.local/bin"
    local cmd_name=$(basename "$0" .sh)
    local target="$bin_dir/$cmd_name"

    chmod +x "$source_bin"

    rx_link "$source_bin" "$target"

    rx_log "success" "Command ${PINK}${cmd_name}${RESET} is now available globally."

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        rx_log "warn" "Detecting missing PATH entry for ~/.local/bin"

        shell_conf="$HOME/.zshrc"
        [[ "$SHELL" == *"bash"* ]] && shell_conf="$HOME/.bashrc"

        if ! grep -q ".local/bin" "$shell_conf"; then
            echo -e '\n# RetroArch PATH' >>"$shell_conf"

            echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$shell_conf"

            rx_log "success" "Patched $shell_conf with ~/.local/bin"
        fi
    fi

    rx_log "success" "Setup complete! Restarting shell..."

    sleep 1
    exec $SHELL
}

register_command "SYSTEM" "-s|--setup" "Install dependencies and CLI" "cmd_setup"
