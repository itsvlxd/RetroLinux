#!/bin/bash

RETRO_CACHE="$HOME/.cache/retro"
source_bin="$RETRO_DIR/retro.sh"
bin_dir="/usr/local/bin"
cmd_name="retro"
target="$bin_dir/$cmd_name"

rx_log "info" "Installing ${PINK}${cmd_name}${RESET} to ${bin_dir}..."

if [[ ! -d $bin_dir ]]; then
    sudo mkdir -p "$bin_dir"
fi

sudo ln -sf "$source_bin" "$target"
sudo chmod +x "$target"

patch_env() {
    local file="$1"
    local var_name="$2"
    local var_val="$3"

    if [[ -f $file ]]; then
        if ! grep -q "export $var_name=" "$file"; then
            echo "export $var_name=\"$var_val\"" >>"$file"
            rx_log "success" "Exported $var_name to $(basename "$file")"
        fi
    fi
}

patch_env "$HOME/.profile" "RETRO_DIR" "$RETRO_DIR"
patch_env "$HOME/.profile" "RETRO_CACHE" "$RETRO_CACHE"

if [[ -f "$HOME/.zshrc" ]]; then
    shell_conf="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
    shell_conf="$HOME/.bashrc"
fi

if [[ -n $shell_conf ]]; then
    if ! grep -q "$bin_dir" "$shell_conf"; then
        echo -e "\n# RetroArch PATH\nexport PATH=\"$bin_dir:\$PATH\"" >>"$shell_conf"
    fi

    patch_env "$shell_conf" "RETRO_DIR" "$RETRO_DIR"
    patch_env "$shell_conf" "RETRO_CACHE" "$RETRO_CACHE"
fi

[[ ! -d $RETRO_CACHE ]] && mkdir -p "$RETRO_CACHE"

rx_log "success" "Command ${PINK}${cmd_name}${RESET} is now system-wide."
rx_log "warn" "For Hyprland to see the new variables, you MUST log out and back in."
rx_log "info" "Current session: ${PINK}source $shell_conf${RESET}"
