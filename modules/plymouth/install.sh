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
    
    rx_log "info" "Setting Plymouth theme to ${PINK}$theme_name${RESET}..."
    
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        if plymouth-set-default-theme "$theme_name" --rebuild-initrd >/dev/null 2>&1; then
            rx_log "success" "Plymouth theme set to $theme_name and initrd rebuilt"
        else
            rx_log "info" "Theme set via config file (command unavailable)"
            
            mkdir -p /etc/plymouth
            cat > /etc/plymouth/plymouthd.conf << EOF
[Daemon]
Theme=$theme_name
ShowDelay=0
EOF
            
            rm -f /usr/share/plymouth/themes/default.plymouth
            ln -s $theme_name/$theme_name.plymouth /usr/share/plymouth/themes/default.plymouth
            
            rx_log "success" "Plymouth theme configured via fallback method"
        fi
    else
        mkdir -p /etc/plymouth
        cat > /etc/plymouth/plymouthd.conf << EOF
[Daemon]
Theme=$theme_name
ShowDelay=0
EOF
        
        rx_log "success" "Plymouth config created at /etc/plymouth/plymouthd.conf"
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
    
    local hooks_line=$(grep "^HOOKS=" "$mkinitcpio_conf")
    
    if [[ -z "$hooks_line" ]]; then
        rx_log "error" "Could not find HOOKS line in mkinitcpio.conf"
        return 1
    fi
    
    rx_log "info" "Current HOOKS: $hooks_line"
    
    if echo "$hooks_line" | grep -q "plymouth"; then
        rx_log "info" "Plymouth hook already present in mkinitcpio.conf"
        
        if echo "$hooks_line" | grep -q "udev.*plymouth.*autodetect"; then
            rx_log "success" "Plymouth hook is in correct position (after udev, before autodetect)"
            return 0
        else
            rx_log "warn" "Plymouth hook is in wrong position, fixing..."
        fi
    fi
    
    if echo "$hooks_line" | grep -q "udev"; then
        sed -i 's/\(HOOKS=.*udev\)/\1 plymouth/' "$mkinitcpio_conf"
        rx_log "success" "Plymouth hook added after 'udev'"
    else
        sed -i 's/HOOKS=\(.*\)/HOOKS=\1 plymouth/' "$mkinitcpio_conf"
        rx_log "success" "Plymouth hook added to HOOKS"
    fi
    
    local new_hooks_line=$(grep "^HOOKS=" "$mkinitcpio_conf")
    rx_log "info" "New HOOKS: $new_hooks_line"
    
    if grep -q "plymouth" "$mkinitcpio_conf"; then
        rx_log "success" "Plymouth hook successfully configured in mkinitcpio.conf"
        return 0
    else
        rx_log "error" "Failed to add Plymouth hook"
        return 1
    fi
}

rebuild_initramfs() {
    rx_log "info" "Rebuilding initramfs..."
    
    if command -v mkinitcpio >/dev/null 2>&1; then
        if mkinitcpio -P; then
            rx_log "success" "Initramfs rebuilt successfully"
        else
            rx_log "error" "Initramfs rebuild failed"
            return 1
        fi
    else
        rx_log "error" "mkinitcpio not found"
        return 1
    fi
    
    return 0
}

install_plymouth_themes
set_plymouth_theme
add_plymouth_hook
rebuild_initramfs
