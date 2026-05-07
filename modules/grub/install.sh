#!/bin/bash

# TODO: remove the echos of boot and ramdisk

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"

if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

install_grub_themes() {
    local themes_dir="/boot/grub/themes"
    local module_files="$RETRO_DIR/modules/grub/files"

    rx_log "info" "Installing GRUB themes..."

    if [[ ! -d $themes_dir ]]; then
        $SUDO_CMD mkdir -p "$themes_dir"
    fi

    for theme in "$module_files"/*; do
        if [[ -d $theme ]]; then
            local theme_name=$(basename "$theme")
            rx_log "info" "Installing theme: ${PINK}$theme_name${RESET}"
            $SUDO_CMD cp -rf "$theme" "$themes_dir/"
        fi
    done

    rx_log "success" "GRUB themes installed to $themes_dir"
}

update_grub_config() {
    local grub_defaults="/etc/default/grub"
    local gfxmode="${BOOT_VIDEO_GRUB:-1920x1080}"

    if [[ -f $grub_defaults ]]; then
        rx_log "info" "Updating GRUB configuration..."

        if grep -q "^GRUB_DISTRIBUTOR=" "$grub_defaults"; then
            $SUDO_CMD sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="RetroLinux"|' "$grub_defaults"
        else
            echo 'GRUB_DISTRIBUTOR="RetroLinux"' | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
        fi

        if [[ -n $gfxmode && $gfxmode != "auto" ]]; then
            if grep -q "^GRUB_GFXMODE=" "$grub_defaults"; then
                $SUDO_CMD sed -i "s|^GRUB_GFXMODE=.*|GRUB_GFXMODE=\"$gfxmode\"|" "$grub_defaults"
            else
                echo "GRUB_GFXMODE=\"$gfxmode\"" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
            fi
        fi

        local theme_choice="${GRUB_THEME_CHOICE:-retropunk}"
        local theme_path="/boot/grub/themes/$theme_choice/theme.txt"

        if [[ -d "/boot/grub/themes/$theme_choice" ]]; then
            if ! grep -q "^GRUB_THEME=" "$grub_defaults"; then
                echo "GRUB_THEME=$theme_path" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
            else
                $SUDO_CMD sed -i "s|^GRUB_THEME=.*|GRUB_THEME=$theme_path|" "$grub_defaults"
            fi
        fi

        if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_defaults"; then
            if ! grep -q "splash" "$grub_defaults"; then
                $SUDO_CMD sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 splash"/' "$grub_defaults"
            fi
        fi

        if [[ ${GRUB_OS_PROBER:-false} == "true" ]]; then
            $SUDO_CMD sed -i 's|^#*GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|' "$grub_defaults"
        else
            $SUDO_CMD sed -i 's|^#*GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=true|' "$grub_defaults"
        fi

        rx_log "success" "GRUB configuration updated"
    fi
}

patch_grub_cfg() {
    local grub_cfg="/boot/grub/grub.cfg"

    if [[ -f $grub_cfg ]]; then
        rx_log "info" "Patching GRUB cfg with theme settings..."

        local temp_cfg=$(mktemp)
        local found_terminal_output=false
        local patched=false

        while IFS= read -r line; do
            echo "$line" >>"$temp_cfg"

            if [[ $line =~ terminal_output.*gfxterm ]] && [[ $patched == false ]]; then
                found_terminal_output=true
            elif [[ $found_terminal_output == true ]] && [[ $patched == false ]] && [[ -n $line ]]; then
                local theme_choice="${GRUB_THEME_CHOICE:-retropunk}"
                local font_file=""

                case "$theme_choice" in
                    retrolinux) font_file="victor-pixel-24.pf2" ;;
                    retropunk | *) font_file="Rajdhani_Regular_24.pf2" ;;
                esac

                cat >>"$temp_cfg" <<GRUB_SETTINGS

if [ -f /boot/grub/themes/$theme_choice/theme.txt ]; then
    loadfont /boot/grub/themes/$theme_choice/$font_file
    set theme=/boot/grub/themes/$theme_choice/theme.txt
fi
GRUB_SETTINGS
                patched=true
            fi
        done <"$grub_cfg"

        if [[ $patched == true ]]; then
            $SUDO_CMD cp "$temp_cfg" "$grub_cfg"
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

        $SUDO_CMD sed -i 's/Arch Linux/RetroLinux/g' "$grub_cfg"
        $SUDO_CMD sed -i 's/GNU\/Linux/RetroLinux/g' "$grub_cfg"
        $SUDO_CMD sed -i 's/Archlinux/RetroLinux/g' "$grub_cfg"
        $SUDO_CMD sed -i 's/RetroLinux Linux/RetroLinux/g' "$grub_cfg"

        local temp_grub=$(mktemp)
        local skip_block=0
        local brace_count=0

        while IFS= read -r line; do
            if [[ $skip_block -eq 0 ]] && [[ $line =~ ^submenu\ \'Advanced\ options\ for ]]; then
                skip_block=1
                brace_count=0
                continue
            fi

            if [[ $skip_block -eq 1 ]]; then
                local open_braces=$(echo "$line" | tr -cd '{' | wc -c)
                local close_braces=$(echo "$line" | tr -cd '}' | wc -c)
                brace_count=$((brace_count + open_braces - close_braces))

                if [[ $brace_count -le 0 ]]; then
                    skip_block=0
                fi
                continue
            fi

            echo "$line" >>"$temp_grub"
        done <"$grub_cfg"

        $SUDO_CMD cp "$temp_grub" "$grub_cfg"
        rm -f "$temp_grub"

        rx_log "success" "GRUB menu entries updated to RetroLinux"
    fi
}

add_shutdown_reboot_entries() {
    local grub_cfg="/boot/grub/grub.cfg"

    if [[ -f $grub_cfg ]]; then
        rx_log "info" "Adding shutdown and reboot entries..."

        local temp_grub=$(mktemp)
        local skip_block=0
        local skip_uefi=false
        local skip_shutdown=false
        local skip_reboot=false
        local skip_memtest=false
        local if_depth=0

        while IFS= read -r line; do
            if [[ $line =~ ^if.*grub_platform.*efi ]] && [[ $skip_uefi == false ]]; then
                skip_uefi=true
                if_depth=1
                continue
            fi

            if [[ $skip_uefi == true ]]; then
                if [[ $line =~ ^if ]]; then
                    ((if_depth++))
                fi
                if [[ $line =~ ^fi$ ]]; then
                    ((if_depth--))
                    if [[ $if_depth -le 0 ]]; then
                        skip_uefi=false
                    fi
                fi
                continue
            fi

            if [[ $line =~ ^menuentry.*System\ shutdown ]]; then
                skip_shutdown=true
                skip_block=0
                continue
            fi

            if [[ $skip_shutdown == true ]]; then
                local open_braces=$(echo "$line" | tr -cd '{' | wc -c)
                local close_braces=$(echo "$line" | tr -cd '}' | wc -c)
                skip_block=$((skip_block + open_braces - close_braces))

                if [[ $skip_block -le 0 ]]; then
                    skip_shutdown=false
                fi
                continue
            fi

            if [[ $line =~ ^menuentry.*System\ restart ]]; then
                skip_reboot=true
                skip_block=0
                continue
            fi

            if [[ $skip_reboot == true ]]; then
                local open_braces=$(echo "$line" | tr -cd '{' | wc -c)
                local close_braces=$(echo "$line" | tr -cd '}' | wc -c)
                skip_block=$((skip_block + open_braces - close_braces))

                if [[ $skip_block -le 0 ]]; then
                    skip_reboot=false
                fi
                continue
            fi

            if [[ $line =~ ^if.*memtest ]] || [[ $line =~ ^menuentry.*Memtest ]]; then
                skip_memtest=true
                skip_block=0
                continue
            fi

            if [[ $skip_memtest == true ]]; then
                local open_braces=$(echo "$line" | tr -cd '{' | wc -c)
                local close_braces=$(echo "$line" | tr -cd '}' | wc -c)
                skip_block=$((skip_block + open_braces - close_braces))

                if [[ $skip_block -le 0 ]]; then
                    skip_memtest=false
                fi
                continue
            fi

            echo "$line" >>"$temp_grub"
        done <"$grub_cfg"

        cat >>"$temp_grub" <<'UEFI_ENTRY'

if [ "${grub_platform}" == "efi" ]; then
    menuentry 'UEFI Firmware Settings' --class efi --id 'uefi-firmware' {
        fwsetup
    }
fi

menuentry 'System shutdown' --class shutdown --class poweroff {
    echo 'System shutting down...'
    halt
}

menuentry 'System restart' --class reboot --class restart {
    echo 'System rebooting...'
    reboot
}

if [ -f "/boot/memtest86+/memtest.efi" ]; then
    menuentry "Run Memtest86+ (RAM test)" --class memtest86 --class memtest --class gnu --class tool {
        set gfxpayload=1920x1080,1024x768
        linux /boot/memtest86+/memtest.efi
    }
elif [ -f "/boot/memtest86+/memtest" ]; then
    menuentry "Run Memtest86+ (RAM test)" --class memtest86 --class memtest --class gnu --class tool {
        set gfxpayload=1920x1080,1024x768
        linux /boot/memtest86+/memtest
    }
fi
UEFI_ENTRY

        $SUDO_CMD cp "$temp_grub" "$grub_cfg"
        rm -f "$temp_grub"

        rx_log "success" "UEFI, shutdown, reboot, and memtest entries added"
    fi
}

regenerate_grub() {
    rx_log "info" "Regenerating GRUB configuration..."

    if command -v grub-mkconfig >/dev/null 2>&1; then
        if $SUDO_CMD grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
            patch_grub_cfg
            patch_grub_menu_entries
            add_shutdown_reboot_entries
            rx_log "success" "GRUB configuration regenerated and patched"
        else
            rx_log "warn" "GRUB configuration regeneration had issues"
        fi
    fi
}

install_grub_themes
update_grub_config
regenerate_grub
