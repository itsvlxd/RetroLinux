#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"

install_grub_themes() {
    local themes_dir="/boot/grub/themes"
    local module_files="$RETRO_DIR/modules/grub/files"

    rx_log "info" "Installing GRUB themes..."

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

    rx_log "success" "GRUB themes installed to $themes_dir"
}

update_grub_config() {
    local grub_defaults="/etc/default/grub"

    if [[ -f $grub_defaults ]]; then
        rx_log "info" "Updating GRUB configuration..."

        if grep -q "^GRUB_DISTRIBUTOR=" "$grub_defaults"; then
            sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="RetroLinux"|' "$grub_defaults"
        else
            echo 'GRUB_DISTRIBUTOR="RetroLinux"' >>"$grub_defaults"
        fi

        if [[ -d "/boot/grub/themes/retropunk" ]]; then
            if ! grep -q "^GRUB_THEME=" "$grub_defaults"; then
                echo 'GRUB_THEME=/boot/grub/themes/retropunk/theme.txt' >>"$grub_defaults"
            else
                sed -i 's|^GRUB_THEME=.*|GRUB_THEME=/boot/grub/themes/retropunk/theme.txt|' "$grub_defaults"
            fi
        fi

        rx_log "success" "GRUB configuration updated"
    fi
}

patch_grub_cfg() {
    local grub_cfg="/boot/grub/grub.cfg"

    if [[ -f $grub_cfg ]]; then
        rx_log "info" "Patching GRUB cfg with theme settings..."

        local temp_cfg=$(mktemp)
        local found_insmod=false
        local patched=false

        while IFS= read -r line; do
            echo "$line" >>"$temp_cfg"

            if [[ $line =~ ^insmod.* ]] && [[ $patched == false ]]; then
                found_insmod=true
            elif [[ $found_insmod == true ]] && [[ $patched == false ]]; then
                if [[ ! $line =~ ^insmod.* ]] && [[ -n $line ]]; then
                    cat >>"$temp_cfg" <<'GRUB_SETTINGS'

insmod png
set gfxmode="1920x1080"
set gfxpayload=keep

if terminal_output gfxterm; then
    true
else
    terminal_input console
    terminal_output console
fi

if [ -f /boot/grub/themes/retropunk/theme.txt ]; then
    loadfont /boot/grub/themes/retropunk/Rajdhani_Regular_24.pf2
    set theme=/boot/grub/themes/retropunk/theme.txt
fi
GRUB_SETTINGS
                    patched=true
                fi
            fi
        done <"$grub_cfg"

        if [[ $patched == true ]]; then
            cp "$temp_cfg" "$grub_cfg"
            rx_log "success" "GRUB cfg patched with theme settings"
        else
            rx_log "warn" "Could not patch GRUB cfg automatically"
        fi

        rm -f "$temp_cfg"
    fi
}

patch_grub_menu_entries() {
    local grub_cfg="/boot/grub/grub.cfg"

    if [[ -f $grub_cfg ]]; then
        rx_log "info" "Patching GRUB menu entries..."

        sed -i 's/Arch Linux/RetroLinux/g' "$grub_cfg"
        sed -i 's/GNU\/Linux/RetroLinux/g' "$grub_cfg"
        sed -i 's/Archlinux/RetroLinux/g' "$grub_cfg"

        rx_log "success" "GRUB menu entries updated to RetroLinux"
    fi
}

regenerate_grub() {
    rx_log "info" "Regenerating GRUB configuration..."

    if command -v grub-mkconfig >/dev/null 2>&1; then
        if grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
            patch_grub_cfg
            patch_grub_menu_entries
            rx_log "success" "GRUB configuration regenerated and patched"
        else
            rx_log "warn" "GRUB configuration regeneration had issues"
        fi
    fi
}

install_grub_themes
update_grub_config
regenerate_grub
