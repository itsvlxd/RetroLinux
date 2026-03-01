#!/bin/bash

cmd_setup() {
    rx_logo
    rx_log "info" "Setting up retroArch core"

    rx_bootstrap_yay
    rx_link_bin "$0"

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        rx_log "warn" "Detecting missing PATH entry for ~/.local/bin"

        shell_conf="$HOME/.zshrc"
        [[ "$SHELL" == *"bash"* ]] && shell_conf="$HOME/.bashrc"

        if ! grep -q ".local/bin" "$shell_conf"; then
            echo -e '\n# retroArch PATH' >>"$shell_conf"

            echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$shell_conf"

            rx_log "success" "Patched $shell_conf with ~/.local/bin"
        fi
    fi

    rx_log "success" "Setup complete! Restarting shell..."

    sleep 1
    exec $SHELL
}

register_command "SYSTEM" "-s|--setup" "Install dependencies and CLI" "cmd_setup"
