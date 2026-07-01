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
        [[ $EUID -eq 0 ]] && systemctl enable cronie.service || sudo systemctl enable cronie.service
        [[ $EUID -eq 0 ]] && systemctl start cronie.service || sudo systemctl start cronie.service
        rx_log "success" "Cronie service enabled and started"
    fi
}

retro_fix_permissions() {
    rx_log "info" "Fixing RetroLinux permissions..."
    find "$RETRO_DIR" -path "*/iso/work" -prune -o -name "*.sh" -type f -exec chmod 755 {} \;
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
    [[ ! -d $bin_dir ]] && mkdir -p "$bin_dir"
    ln -sf "$source_bin" "$target"
    chmod +x "$target"
    rx_log "success" "The ${PINK}${cmd_name}${RESET} command is now global."
    git config --global --add safe.directory "$RETRO_DIR"
fi

patch_env() {
    local file="$1"
    local var_name="$2"
    local var_val="$3"

    if [[ -f $file ]]; then
        if grep -q "export $var_name=" "$file"; then
            local current_val=$(grep "export $var_name=" "$file" | sed 's/.*export '"$var_name"'="\(.*\)"/\1/')
            if [[ $current_val != "$var_val" ]]; then
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

ENV_DIR="$HOME/.config/environment.d"
mkdir -p "$ENV_DIR"
ENV_FILE="$ENV_DIR/retro.conf"
for entry in "RETRO_DIR=$RETRO_DIR" "RETRO_CONFIG=$RETRO_CONFIG"; do
    var="${entry%%=*}"
    if grep -q "^${var}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${var}=.*|${entry}|" "$ENV_FILE"
    else
        echo "$entry" >>"$ENV_FILE"
    fi
done

systemctl --user set-environment RETRO_DIR="$RETRO_DIR" RETRO_CONFIG="$RETRO_CONFIG" 2>/dev/null || true

[[ ! -d $RETRO_CONFIG ]] && mkdir -p "$RETRO_CONFIG"

sync_missing_variables() {
    local template_vars="$RETRO_DIR/modules/retro/files/variables.sh"
    local user_vars="$RETRO_CONFIG/variables.sh"

    [[ ! -f $template_vars ]] && return 0

    local added=0
    while IFS= read -r line; do
        if [[ $line =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)= ]]; then
            local key="${BASH_REMATCH[1]}"
            if [[ -f $user_vars ]] && grep -q "^export $key=" "$user_vars" 2>/dev/null; then
                continue
            fi
            echo "$line" >>"$user_vars"
            rx_log "success" "Added missing variable: $key"
            added=1
        fi
    done <"$template_vars"

    if [[ $added -eq 0 ]]; then
        rx_log "info" "All variables are up to date"
    else
        rx_log "success" "Variable sync complete ($added new variables added)"
    fi
}

sync_missing_variables

if command -v glib-compile-schemas >/dev/null 2>&1; then
    schema_dir="$RETRO_DIR/cmds/tools/settings/data"
    if [[ -d $schema_dir ]]; then
        glib-compile-schemas "$schema_dir" 2>/dev/null || true
        rx_log "info" "GSettings schema compiled for Retro Settings"
    fi
fi

setup_theme_sudoers() {
    if command -v papirus-folders >/dev/null 2>&1; then
        sudo rm -f /etc/sudoers.d/papirus-folders
        cat <<EOF | sudo tee /etc/sudoers.d/papirus-folders >/dev/null
%wheel ALL=(ALL) NOPASSWD: SETENV: /usr/bin/papirus-folders
Defaults!/usr/bin/papirus-folders !env_reset
EOF
        sudo chmod 440 /etc/sudoers.d/papirus-folders
        rx_log "success" "Sudoers rule added for papirus-folders"
    fi

    local sddm_dir="/usr/share/sddm/themes/retro"
    if [[ -d $sddm_dir ]]; then
        sudo chown -R "$USER:$USER" "$sddm_dir" 2>/dev/null || true
        rx_log "success" "SDDM theme dir made writable for $USER"
    fi

    local sddm_hidpi_conf="/etc/sddm.conf.d/hidpi.conf"
    sudo rm -f /etc/sudoers.d/retro-sddm-hidpi
    cat <<EOF | sudo tee /etc/sudoers.d/retro-sddm-hidpi >/dev/null
%wheel ALL=(ALL) NOPASSWD: /usr/bin/tee $sddm_hidpi_conf
EOF
    sudo chmod 440 /etc/sudoers.d/retro-sddm-hidpi
    rx_log "success" "Sudoers rule added for SDDM HiDPI config"
}
setup_theme_sudoers
