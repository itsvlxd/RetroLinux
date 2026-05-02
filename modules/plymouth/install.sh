#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"

install_plymouth_themes() {
    local themes_dir="/usr/share/plymouth/themes"
    local module_files="$RETRO_DIR/modules/plymouth/files"
    
    rx_log "info" "Installing Plymouth themes..."
    
    if [[ ! -d $themes_dir ]]; then
        mkdir -p "$themes_dir"
    fi
    
    for theme in "$module_files"/*; do
        if [[ -d $theme ]]; then
            local theme_name=$(basename "$theme")
            rx_log "info" "Installing theme: ${PINK}$theme_name${RESET}"
            cp -rf "$theme" "$themes_dir/"
        fi
    done
    
    rx_log "success" "Plymouth themes installed to $themes_dir"
}

set_plymouth_theme() {
    local theme_name="retrolinux"
    local plymouth_conf="/etc/plymouth/plymouthd.conf"
    
    rx_log "info" "Setting Plymouth theme to ${PINK}$theme_name${RESET}..."
    
    mkdir -p /etc/plymouth
    
    cat > "$plymouth_conf" << EOF
[Daemon]
Theme=$theme_name
ShowDelay=0
EOF
    
    if [[ -f "$plymouth_conf" ]]; then
        rx_log "success" "Plymouth config created at $plymouth_conf"
        cat "$plymouth_conf"
    else
        rx_log "error" "Failed to create Plymouth config"
        return 1
    fi
    
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        if plymouth-set-default-theme "$theme_name" >/dev/null 2>&1; then
            rx_log "success" "Plymouth theme set via command"
        else
            rx_log "info" "Theme set via config file (command unavailable)"
        fi
    fi
    
    return 0
}

add_plymouth_hook() {
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    
    rx_log "info" "Adding Plymouth hook to mkinitcpio.conf..."
    
    if [[ ! -f "$mkinitcpio_conf" ]]; then
        rx_log "error" "mkinitcpio.conf not found"
        return 1
    fi
    
    if grep -q "plymouth" "$mkinitcpio_conf"; then
        rx_log "info" "Plymouth hook already present in mkinitcpio.conf"
        return 0
    fi
    
    local hooks_line=$(grep "^HOOKS=" "$mkinitcpio_conf")
    
    if [[ -z "$hooks_line" ]]; then
        rx_log "error" "Could not find HOOKS line in mkinitcpio.conf"
        return 1
    fi
    
    rx_log "info" "Current HOOKS: $hooks_line"
    
    if [[ "$hooks_line" == *"block"* ]]; then
        sed -i 's/\(HOOKS=.*block\)/\1 plymouth/' "$mkinitcpio_conf"
        rx_log "success" "Plymouth hook added after 'block'"
    elif [[ "$hooks_line" == *"udev"* ]]; then
        sed -i 's/\(HOOKS=.*udev\)/\1 plymouth/' "$mkinitcpio_conf"
        rx_log "success" "Plymouth hook added after 'udev'"
    else
        sed -i 's/HOOKS=\(.*\)/HOOKS=\1 plymouth/' "$mkinitcpio_conf"
        rx_log "success" "Plymouth hook added to end of HOOKS"
    fi
    
    local new_hooks_line=$(grep "^HOOKS=" "$mkinitcpio_conf")
    rx_log "info" "New HOOKS: $new_hooks_line"
    
    if grep -q "plymouth" "$mkinitcpio_conf"; then
        rx_log "success" "Plymouth hook successfully added to mkinitcpio.conf"
        return 0
    else
        rx_log "error" "Failed to add Plymouth hook"
        return 1
    fi
}

rebuild_initramfs() {
    rx_log "info" "Rebuilding initramfs..."
    
    if command -v mkinitcpio >/dev/null 2>&1; then
        if mkinitcpio -P 2>&1 | tee /tmp/mkinitcpio.log; then
            rx_log "success" "Initramfs rebuilt successfully"
        else
            rx_log "error" "Initramfs rebuild failed"
            rx_log "info" "Check /tmp/mkinitcpio.log for details"
            return 1
        fi
    else
        rx_log "error" "mkinitcpio not found"
        return 1
    fi
    
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_plymouth_themes
    set_plymouth_theme
    add_plymouth_hook
    rebuild_initramfs
fi
