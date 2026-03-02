#!/bin/bash

RETRO_DIR="$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")"

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/fs.sh"

target="$HOME/.local/bin/retro"

if [[ -L "$target" ]]; then
    rm "$target"
    rx_log "success" "Global command 'retro' unlinked."
fi

shell_conf="$HOME/.zshrc"
[[ "$SHELL" == *"bash"* ]] && shell_conf="$HOME/.bashrc"

if [[ -f "$shell_conf" ]]; then
    if grep -q "# RetroArch PATH" "$shell_conf"; then
        sed -i '/# RetroArch PATH/,+1d' "$shell_conf"

        if grep -q "export RETRO_DIR=" "$shell_conf"; then
            rx_log "success" "Cleaned RETRO_DIR from $shell_conf"

            sed -i '/export RETRO_DIR=/d' "$shell_conf"
        fi

    fi
fi
