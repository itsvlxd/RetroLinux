#!/bin/bash

source "$RETRO_DIR/cmds/tools/power.sh"

RETRO_CONFIG="$HOME/.config/retro"
source_bin="$RETRO_DIR/retro.sh"
bin_dir="/usr/local/bin"
cmd_name="retro"
target="$bin_dir/$cmd_name"

cmd_power "permissions"

setup_cronie() {
    rx_log "info" "Checking cronie service..."

    if systemctl is-active cronie.service &>/dev/null; then
        rx_log "info" "Cronie service is running"
    else
        rx_log "info" "Enabling cronie service..."
        sudo systemctl enable cronie.service
        sudo systemctl start cronie.service
        rx_log "success" "Cronie service enabled and started"
    fi
}

retro_fix_permissions() {
    rx_log "info" "Fixing RetroLinux permissions..."
    find "$RETRO_DIR" -name "*.sh" -type f -exec sudo chmod 755 {} \;
    git config --global --add safe.directory "$RETRO_DIR"
    rx_log "success" "Permissions and git safe.directory configured"
}

if command -v gsettings >/dev/null 2>&1; then
    if [[ $(gsettings get org.blueman.general notification-daemon 2>/dev/null) == "true" ]]; then
        gsettings set org.blueman.general notification-daemon false
    fi
fi

setup_cronie
retro_fix_permissions

if [[ ! -L $target ]] || [[ "$(readlink -f "$target")" != "$source_bin" ]]; then
    rx_log "info" "Installing ${PINK}${cmd_name}${RESET} to ${bin_dir}..."
    [[ ! -d $bin_dir ]] && sudo mkdir -p "$bin_dir"
    sudo ln -sf "$source_bin" "$target"
    sudo chmod +x "$target"
    rx_log "success" "The ${PINK}${cmd_name}${RESET} command is now global."
    sudo git config --global --add safe.directory "$RETRO_DIR"
fi

patch_env() {
    local file="$1"
    local var_name="$2"
    local var_val="$3"

    if [[ -f $file ]]; then
        if grep -q "export $var_name=" "$file"; then
            local current_val=$(grep "export $var_name=" "$file" | sed 's/.*export '"$var_name"'="\(.*\)"/\1/')
            if [[ "$current_val" != "$var_val" ]]; then
                sed -i "s|export $var_name=\".*\"|export $var_name=\"$var_val\"|" "$file"
                rx_log "success" "Updated $var_name in $(basename "$file")"
            fi
        else
            echo "export $var_name=\"$var_val\"" >>"$file"
            rx_log "success" "Added $var_name to $(basename "$file")"
        fi
    fi
}

patch_env "$HOME/.profile" "RETRO_DIR" "$RETRO_DIR"
patch_env "$HOME/.profile" "RETRO_CONFIG" "$RETRO_CONFIG"

shell_conf=""
[[ -f "$HOME/.zshrc" ]] && shell_conf="$HOME/.zshrc"
[[ -f "$HOME/.bashrc" ]] && [[ -z $shell_conf ]] && shell_conf="$HOME/.bashrc"

if [[ -n $shell_conf ]]; then
    if ! grep -q "$bin_dir" "$shell_conf"; then
        echo -e "\n# Retro PATH\nexport PATH=\"$bin_dir:\$PATH\"" >>"$shell_conf"
    fi

    patch_env "$shell_conf" "RETRO_DIR" "$RETRO_DIR"
    patch_env "$shell_conf" "RETRO_CONFIG" "$RETRO_CONFIG"
fi

[[ ! -d $RETRO_CONFIG ]] && mkdir -p "$RETRO_CONFIG"
