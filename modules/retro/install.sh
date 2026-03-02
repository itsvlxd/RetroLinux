#!/bin/bash

source_bin="$RETRO_DIR/retro.sh"
bin_dir="$HOME/.local/bin"
cmd_name="retro"
target="$bin_dir/$cmd_name"

mkdir -p "$bin_dir"
chmod +x "$source_bin"
rx_link "$source_bin" "$target"

if [[ -f "$HOME/.zshrc" ]]; then
    shell_conf="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
    shell_conf="$HOME/.bashrc"
else
    rx_log "error" "No supported shell config (.zshrc or .bashrc) found."
    return 1
fi

if [[ -f "$shell_conf" ]]; then
    if ! grep -q "export RETRO_DIR=" "$shell_conf"; then
        echo "export RETRO_DIR=\"$RETRO_DIR\"" >>"$shell_conf"
        rx_log "success" "RETRO_DIR exported to $(basename "$shell_conf")"
    fi

    if ! grep -q "# RetroArch PATH" "$shell_conf"; then
        echo -e '\n# RetroArch PATH' >>"$shell_conf"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$shell_conf"
        rx_log "success" "Patched PATH in $(basename "$shell_conf")"
    fi
fi

rx_log "success" "Global command ${PINK}${cmd_name}${RESET} is ready."
rx_log "warn" "RESTART your terminal or run: ${PINK}source $shell_conf${RESET}"
