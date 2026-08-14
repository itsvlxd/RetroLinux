#!/bin/bash

source "$RETRO_DIR/cmds/tools/power.sh"

: "${RETRO_CONFIG:=$HOME/.config/retro}"
SECONDARY_INSTALL=${RETRO_SECONDARY_INSTALL:-false}
source_bin="$RETRO_DIR/retro.sh"
bin_dir="/usr/local/bin"
cmd_name="retro"
target="$bin_dir/$cmd_name"

if [[ $SECONDARY_INSTALL != "true" ]]; then
    cmd_power "permissions"
fi

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

remove_conflicts() {
    local -A conflicts=(
        [dolphin]=""
        [dunst]="dunst.service"
    )

    local pkg svc
    for pkg in "${!conflicts[@]}"; do
        if pacman -Qq "$pkg" >/dev/null 2>&1; then
            rx_log "info" "Removing conflicting package: $pkg"
            if [[ $EUID -eq 0 ]]; then
                pacman -Rns --noconfirm "$pkg" >/dev/null 2>&1
            else
                sudo pacman -Rns --noconfirm "$pkg" >/dev/null 2>&1
            fi
        fi

        if pgrep -x "$pkg" >/dev/null 2>&1; then
            pkill -9 -x "$pkg" >/dev/null 2>&1
        fi

        svc="${conflicts[$pkg]}"
        if [[ -n $svc ]]; then
            systemctl --user stop "$svc" >/dev/null 2>&1
            systemctl --user disable "$svc" >/dev/null 2>&1
            systemctl --user mask "$svc" >/dev/null 2>&1
            if [[ $EUID -eq 0 ]]; then
                systemctl stop "$svc" >/dev/null 2>&1
                systemctl disable "$svc" >/dev/null 2>&1
                systemctl mask "$svc" >/dev/null 2>&1
            else
                sudo systemctl stop "$svc" >/dev/null 2>&1
                sudo systemctl disable "$svc" >/dev/null 2>&1
                sudo systemctl mask "$svc" >/dev/null 2>&1
            fi
        fi
    done
}

if command -v gsettings >/dev/null 2>&1; then
    if [[ $(gsettings get org.blueman.general notification-daemon 2>/dev/null) == "true" ]]; then
        gsettings set org.blueman.general notification-daemon false
    fi
fi

hide_nm_applet() {
    local found=""
    local dir
    for dir in /etc/xdg/autostart "$HOME/.config/autostart" /usr/share/autostart; do
        if [[ -f "$dir/nm-applet.desktop" ]]; then
            found="$dir/nm-applet.desktop"
            break
        fi
    done

    if [[ -z $found ]]; then
        rx_log "info" "nm-applet.desktop not found; nothing to hide"
        return 0
    fi

    if grep -q '^Hidden=true' "$found" 2>/dev/null; then
        rx_log "success" "nm-applet.desktop already hidden ($found)"
        return 0
    fi

    mkdir -p "$HOME/.config/autostart"
    cat >"$HOME/.config/autostart/nm-applet.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=NetworkManager
Hidden=true
EOF
    rx_log "success" "nm-applet hidden via user autostart override"

    if pgrep -x nm-applet >/dev/null 2>&1; then
        pkill -x nm-applet 2>/dev/null || true
        rx_log "info" "Stopped running nm-applet"
    fi
}
hide_nm_applet

hide_bluetooth_applet() {
    local found=""
    local dir
    for dir in /etc/xdg/autostart "$HOME/.config/autostart" /usr/share/autostart; do
        if [[ -f "$dir/blueman.desktop" ]]; then
            found="$dir/blueman.desktop"
            break
        fi
    done

    if [[ -z $found ]]; then
        rx_log "info" "blueman.desktop not found; nothing to hide"
        return 0
    fi

    if grep -q '^Hidden=true' "$found" 2>/dev/null; then
        rx_log "success" "blueman.desktop already hidden ($found)"
        return 0
    fi

    mkdir -p "$HOME/.config/autostart"
    cat >"$HOME/.config/autostart/blueman.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Bluetooth Manager
Hidden=true
EOF
    rx_log "success" "blueman applet hidden via user autostart override"

    if pgrep -x blueman-applet >/dev/null 2>&1; then
        pkill -x blueman-applet 2>/dev/null || true
        rx_log "info" "Stopped running blueman-applet"
    fi
}
hide_bluetooth_applet

remove_conflicts

if [[ $SECONDARY_INSTALL != "true" ]]; then
    setup_cronie
    retro_fix_permissions
fi

if [[ $SECONDARY_INSTALL != "true" && (! -L $target || "$(readlink "$target")" != "$source_bin") ]]; then
    rx_log "info" "Installing ${PINK}${cmd_name}${RESET} to ${bin_dir}..."
    [[ ! -d $bin_dir ]] && sudo mkdir -p "$bin_dir"

    if [[ -e $target && ! -L $target ]]; then
        rx_log "warn" "Removing non-symlink $target before linking retro"
        sudo rm -f "$target"
    fi

    if sudo ln -sf "$source_bin" "$target"; then
        sudo chmod +x "$source_bin"
        rx_log "success" "The ${PINK}${cmd_name}${RESET} command is now global."
    else
        rx_log "error" "Failed to install ${cmd_name}. ${bin_dir} is not writable."
        return 1
    fi

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

    mkdir -p "$RETRO_CONFIG" || return 0

    if [[ ! -w $RETRO_CONFIG ]] || ([[ -e $user_vars ]] && [[ ! -w $user_vars ]]); then
        rx_log "warn" "$RETRO_CONFIG is not writable. Attempting to fix ownership..."
        if sudo -n chown -R "$(id -u):$(id -g)" "$RETRO_CONFIG" 2>/dev/null; then
            rx_log "success" "Ownership fixed for $RETRO_CONFIG"
        else
            rx_log "error" "Cannot write to $RETRO_CONFIG. Variable sync skipped"
            return 1
        fi
    fi

    local added=0
    while IFS= read -r line; do
        if [[ $line =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)= ]]; then
            local key="${BASH_REMATCH[1]}"
            if [[ -f $user_vars ]] && grep -q "^export $key=" "$user_vars" 2>/dev/null; then
                continue
            fi
            if ! echo "$line" 2>/dev/null >>"$user_vars"; then
                rx_log "warn" "Skipped $key. Cannot write to $user_vars"
                continue
            fi
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

HYPRIDLE_SRC="$RETRO_DIR/modules/hyprland/files/hypridle.conf"
HYPRIDLE_DST="$RETRO_CONFIG/hypridle.conf"
if [[ ! -f $HYPRIDLE_DST ]] || cmp -s "$HYPRIDLE_SRC" "$HYPRIDLE_DST"; then
    cp "$HYPRIDLE_SRC" "$HYPRIDLE_DST"
    rx_log "success" "Copied default hypridle.conf"
fi

if command -v glib-compile-schemas >/dev/null 2>&1; then
    schema_dir="$RETRO_DIR/cmds/tools/settings/data"
    if [[ -d $schema_dir ]]; then
        glib-compile-schemas "$schema_dir" 2>/dev/null || true
        rx_log "info" "GSettings schema compiled for Retro Settings"
    fi
fi

install_settings_desktop() {
    local svg="$RETRO_DIR/cmds/tools/settings/data/icons/hicolor/scalable/apps/io.github.retrolinux.settings.svg"
    local desktop="$RETRO_DIR/cmds/tools/settings/data/applications/io.github.retrolinux.settings.desktop"

    [[ -f $svg ]] || return 0
    [[ -f $desktop ]] || return 0

    sudo mkdir -p /usr/share/applications /usr/share/icons/hicolor/scalable/apps || return 0
    sudo cp -f "$svg" /usr/share/icons/hicolor/scalable/apps/ || return 0
    sudo cp -f "$desktop" /usr/share/applications/ || return 0

    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        sudo gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi
    if command -v update-desktop-database >/dev/null 2>&1; then
        sudo update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi

    rx_log "success" "Retro Settings desktop entry and icon installed"
}

# Only the primary user runs the system-wide sudoers/ownership setup; secondary
# users just get their per-user config (env, variables, hypridle). Otherwise a
# new user's retro module install would re-chown the SDDM dir to themselves and
# steal it from the primary user.
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
    if [[ -d $sddm_dir && $(stat -c %U "$sddm_dir" 2>/dev/null) == "$USER" ]]; then
        sudo chown -R "$USER:$USER" "$sddm_dir" 2>/dev/null || true
        rx_log "success" "SDDM theme dir made writable for $USER"
    fi

    local sddm_conf_d="/etc/sddm.conf.d"
    if [[ -d $sddm_conf_d && $(stat -c %U "$sddm_conf_d" 2>/dev/null) == "$USER" ]]; then
        sudo chown -R "$USER:$USER" "$sddm_conf_d" 2>/dev/null || true
        rx_log "success" "SDDM config dir made writable for $USER"
    fi
}

setup_sddm_sudoers() {
    # Passwordless rules for rx_sddm_refresh (theme_core.sh) so the background
    # theme apply never prompts for a sudo password. Scoped to the retro SDDM
    # theme path and the exact commands it runs.
    local sddm_dir="/usr/share/sddm/themes/retro"
    [[ -d $sddm_dir ]] || return 0

    sudo rm -f /etc/sudoers.d/99-retro-sddm
    cat <<EOF | sudo tee /etc/sudoers.d/99-retro-sddm >/dev/null
%wheel ALL=(ALL) NOPASSWD: /usr/bin/mkdir -p /usr/share/sddm/themes/retro/backgrounds /usr/share/sddm/themes/retro/configs
%wheel ALL=(ALL) NOPASSWD: /usr/bin/magick * -resize 1920x1080^ -gravity center -extent 1920x1080 /usr/share/sddm/themes/retro/backgrounds/retro-wallpaper.jpg
%wheel ALL=(ALL) NOPASSWD: /usr/bin/cp /home/*/.config/retro/themes/sddm.conf /usr/share/sddm/themes/retro/configs/retro.conf
%wheel ALL=(ALL) NOPASSWD: /usr/bin/sed -i * /usr/share/sddm/themes/retro/metadata.desktop
EOF
    sudo chmod 440 /etc/sudoers.d/99-retro-sddm
    rx_log "success" "Sudoers rule added for SDDM theme refresh"
}

setup_smartctl_sudoers() {
    if command -v smartctl &>/dev/null; then
        local smartctl_path
        smartctl_path="$(command -v smartctl)"
        sudo rm -f /etc/sudoers.d/99-smartctl
        echo "%wheel ALL=(ALL) NOPASSWD: ${smartctl_path}" | sudo tee /etc/sudoers.d/99-smartctl >/dev/null
        sudo chmod 440 /etc/sudoers.d/99-smartctl
        rx_log "success" "Sudoers rule added for smartctl"
    else
        rx_log "info" "smartctl not found. Install smartmontools for SMART data"
    fi
}

patch_os_release() {
    local src="$RETRO_DIR/iso/profile/airootfs/etc/os-release"
    local dst="/etc/os-release"

    if [[ ! -f $src ]]; then
        rx_log "info" "os-release template not found; skipping"
        return 0
    fi

    if sudo cp -f "$src" "$dst"; then
        rx_log "success" "Applied Retro Linux os-release"
    else
        rx_log "warn" "Failed to write $dst — keeping existing os-release"
    fi
}

setup_nopasswd_tools() {
    # Any user can run these three tools passwordless. They're invoked
    # non-interactively in the background (settings sysinfo, disk health,
    # papirus theme recolor) — without NOPASSWD they trip pam_faillock.
    local smartctl_path
    smartctl_path="$(command -v smartctl 2>/dev/null || echo /usr/bin/smartctl)"

    sudo rm -f /etc/sudoers.d/99-retro-tools
    cat <<EOF | sudo tee /etc/sudoers.d/99-retro-tools >/dev/null
ALL ALL=(ALL) NOPASSWD: /opt/retrolinux/scripts/system_core.sh
ALL ALL=(ALL) NOPASSWD: ${smartctl_path}
ALL ALL=(ALL) NOPASSWD: /usr/bin/papirus-folders
EOF
    sudo chmod 440 /etc/sudoers.d/99-retro-tools
    rx_log "success" "Sudoers rule added for retro background tools"
}

if [[ $SECONDARY_INSTALL != "true" ]]; then
    install_settings_desktop
    setup_theme_sudoers
    setup_sddm_sudoers
    setup_smartctl_sudoers
    setup_nopasswd_tools
    patch_os_release

    SYSTEM_SCRIPT="$RETRO_DIR/scripts/system_core.sh"
    if [[ -f $SYSTEM_SCRIPT ]]; then
        sudo rm -f /etc/sudoers.d/99-retro-system /etc/sudoers.d/99-retro-logind
        echo "%wheel ALL=(ALL) NOPASSWD: ${SYSTEM_SCRIPT}" | sudo tee /etc/sudoers.d/99-retro-system >/dev/null
        sudo chmod 440 /etc/sudoers.d/99-retro-system
        rx_log "success" "Sudoers rule added for retro system (power, lid, zram, swap)"
    fi

    if [[ ! -f /swapfile ]]; then
        rx_log "info" "Setting up swap + hibernation (auto-calculated from RAM)..."
        bash "$SYSTEM_SCRIPT" --apply
    fi
fi
