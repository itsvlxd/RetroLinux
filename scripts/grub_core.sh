#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "grub"

if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

install_grub_themes() {
    local themes_dir="/boot/grub/themes"
    local module_files="$RETRO_DIR/modules/grub/files"

    rx_log_file "info" "Installing GRUB themes from $module_files to $themes_dir"

    if [[ ! -d $themes_dir ]]; then
        rx_log_file "info" "Creating themes directory: $themes_dir"
        $SUDO_CMD mkdir -p "$themes_dir"
    fi

    local theme_count=0
    for theme in "$module_files"/*; do
        if [[ -d $theme ]]; then
            local theme_name=$(basename "$theme")
            rx_log_file "info" "Installing theme: $theme_name"
            $SUDO_CMD cp -rf "$theme" "$themes_dir/"
            ((theme_count++))
        fi
    done

    rx_log_file "success" "GRUB themes installed to $themes_dir ($theme_count themes)"
}

get_grub_cmdline() {
    local base_params="quiet splash loglevel=3 net.ifnames=0"
    local hw_cmdline=$(bash "$RETRO_DIR/scripts/driver_core.sh" --grub-cmdline 2>/dev/null)

    rx_log_file "info" "Building kernel cmdline (base + hardware params)"

    local merged_cmdline=""
    declare -A seen_params

    for param in $base_params $hw_cmdline; do
        local key="${param%%=*}"
        if [[ -z ${seen_params[$key]} ]]; then
            seen_params[$key]=1
            merged_cmdline+="$param "
        fi
    done
    
    local result="${merged_cmdline% }"
    rx_log_file "info" "Kernel cmdline: $result"
    echo "$result"
}

update_grub_config() {
    local grub_defaults="/etc/default/grub"

    _get_grub_val() {
        local var_name="$1"
        local var_key="$2"
        local default_val="$3"
        local file_val=""
        if [[ -f $grub_defaults ]]; then
            file_val=$(grep "^${var_name}=" "$grub_defaults" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
        fi
        if [[ -n $file_val ]]; then
            echo "$file_val"
        else
            get_var "$var_key" "$default_val"
        fi
    }

    local gfxmode=$(_get_grub_val "GRUB_GFXMODE" "BOOT_VIDEO_GRUB" "1920x1080")
    local theme_choice=$(_get_grub_val "GRUB_THEME" "GRUB_THEME_CHOICE" "retropunk")
    local os_prober=$(_get_grub_val "GRUB_DISABLE_OS_PROBER" "GRUB_OS_PROBER" "false")
    local timeout_val=$(_get_grub_val "GRUB_TIMEOUT" "GRUB_TIMEOUT" "10")
    local cmdline=$(get_grub_cmdline)

    if [[ $theme_choice =~ /themes/([^/]+)/theme\.txt ]]; then
        theme_choice="${BASH_REMATCH[1]}"
    fi

    rx_log_file "info" "Updating GRUB config (theme=$theme_choice, timeout=${timeout_val}s, gfxmode=$gfxmode, os_prober=$os_prober)"

    if [[ -f $grub_defaults ]]; then
        rx_log_file "info" "Writing GRUB configuration..."

        if grep -q "^GRUB_DISTRIBUTOR=" "$grub_defaults"; then
            $SUDO_CMD sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="RetroLinux"|' "$grub_defaults"
        else
            echo 'GRUB_DISTRIBUTOR="RetroLinux"' | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
        fi

        if grep -q "^GRUB_TIMEOUT=" "$grub_defaults"; then
            $SUDO_CMD sed -i "s|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=$timeout_val|" "$grub_defaults"
        else
            echo "GRUB_TIMEOUT=$timeout_val" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
        fi

        if [[ -n $gfxmode && $gfxmode != "auto" ]]; then
            if grep -q "^GRUB_GFXMODE=" "$grub_defaults"; then
                $SUDO_CMD sed -i "s|^GRUB_GFXMODE=.*|GRUB_GFXMODE=\"$gfxmode\"|" "$grub_defaults"
            else
                echo "GRUB_GFXMODE=\"$gfxmode\"" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
            fi
        fi

        if ! grep -q "^GRUB_GFXPAYLOAD_LINUX=" "$grub_defaults"; then
            echo "GRUB_GFXPAYLOAD_LINUX=keep" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
        fi

        local theme_path="/boot/grub/themes/$theme_choice/theme.txt"
        if [[ -d "/boot/grub/themes/$theme_choice" ]]; then
            if grep -q "^GRUB_THEME=" "$grub_defaults"; then
                $SUDO_CMD sed -i "s|^GRUB_THEME=.*|GRUB_THEME=$theme_path|" "$grub_defaults"
            else
                echo "GRUB_THEME=$theme_path" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
            fi
        else
            rx_log_file "warn" "Theme directory not found: /boot/grub/themes/$theme_choice"
        fi

        if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_defaults"; then
            $SUDO_CMD sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"|" "$grub_defaults"
        else
            echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
        fi

        if grep -q "^GRUB_DISABLE_OS_PROBER=" "$grub_defaults"; then
            $SUDO_CMD sed -i "s|^GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=$os_prober|" "$grub_defaults"
        else
            echo "GRUB_DISABLE_OS_PROBER=$os_prober" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
        fi

        rx_log_file "success" "GRUB configuration updated"
    else
        rx_log_file "error" "GRUB defaults file not found: $grub_defaults"
    fi
}

patch_grub_cfg() {
    local grub_cfg="/boot/grub/grub.cfg"
    local theme_choice=$(get_var "GRUB_THEME_CHOICE" "retropunk")

    if [[ -f $grub_cfg ]]; then
        rx_log_file "info" "Patching GRUB cfg with theme settings (theme=$theme_choice)"

        local temp_cfg=$(mktemp)
        local found_terminal_output=false
        local patched=false

        while IFS= read -r line; do
            echo "$line" >>"$temp_cfg"

            if [[ $line =~ terminal_output.*gfxterm ]] && [[ $patched == false ]]; then
                found_terminal_output=true
            elif [[ $found_terminal_output == true ]] && [[ $patched == false ]] && [[ -n $line ]]; then
                local font_file=""

                case "$theme_choice" in
                    retrolinux) font_file="victor-pixel-24.pf2" ;;
                    retropunk | *) font_file="Rajdhani_Regular_24.pf2" ;;
                esac

                rx_log_file "info" "Injecting theme font: $font_file"
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
            rx_log_file "success" "GRUB cfg patched with theme settings"
        else
            rx_log_file "warn" "Could not patch GRUB cfg automatically (terminal_output gfxterm not found)"
        fi

        rm -f "$temp_cfg"
    else
        rx_log_file "error" "GRUB config not found: $grub_cfg"
    fi
}

remove_grub_echo_messages() {
    local grub_cfg="/boot/grub/grub.cfg"
    
    if [[ -f $grub_cfg ]]; then
        rx_log_file "info" "Removing GRUB loading messages..."
        
        local removed_count=0
        removed_count=$(grep -c "echo.*Loading Linux linux\|echo.*Loading initial ramdisk" "$grub_cfg" 2>/dev/null || echo "0")
        
        $SUDO_CMD sed -i "/echo.*Loading Linux linux/d" "$grub_cfg"
        $SUDO_CMD sed -i "/echo.*Loading initial ramdisk/d" "$grub_cfg"
        
        rx_log_file "success" "GRUB loading messages removed ($removed_count entries cleaned)"
    else
        rx_log_file "error" "GRUB config not found: $grub_cfg"
    fi
}

patch_grub_menu_entries() {
    local grub_cfg="/boot/grub/grub.cfg"

    if [[ -f $grub_cfg ]]; then
        rx_log_file "info" "Patching GRUB menu entries..."

        local arch_count=$(grep -c "Arch Linux\|GNU/Linux\|Archlinux" "$grub_cfg" 2>/dev/null || echo "0")
        rx_log_file "info" "Replacing $arch_count Arch Linux references with RetroLinux"
        
        $SUDO_CMD sed -i 's/Arch Linux/RetroLinux/g' "$grub_cfg"
        $SUDO_CMD sed -i 's/GNU\/Linux/RetroLinux/g' "$grub_cfg"
        $SUDO_CMD sed -i 's/Archlinux/RetroLinux/g' "$grub_cfg"
        $SUDO_CMD sed -i 's/RetroLinux Linux/RetroLinux/g' "$grub_cfg"

        local temp_grub=$(mktemp)
        local skip_block=0
        local brace_count=0
        local removed_entries=0

        while IFS= read -r line; do
            if [[ $skip_block -eq 0 ]] && [[ $line =~ ^submenu\ \'Advanced\ options\ for ]]; then
                skip_block=1
                brace_count=0
                ((removed_entries++))
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

        rx_log_file "success" "GRUB menu entries updated to RetroLinux ($removed_entries submenu entries removed)"
    else
        rx_log_file "error" "GRUB config not found: $grub_cfg"
    fi
}

add_shutdown_reboot_entries() {
    local grub_cfg="/boot/grub/grub.cfg"

    if [[ -f $grub_cfg ]]; then
        rx_log_file "info" "Adding shutdown and reboot entries..."

        local temp_grub=$(mktemp)
        local skip_block=0
        local skip_uefi=false
        local skip_shutdown=false
        local skip_reboot=false
        local skip_memtest=false
        local if_depth=0
        local removed_uefi=false
        local removed_shutdown=false
        local removed_reboot=false
        local removed_memtest=false

        while IFS= read -r line; do
            if [[ $line =~ ^if.*grub_platform.*efi ]] && [[ $skip_uefi == false ]]; then
                skip_uefi=true
                if_depth=1
                removed_uefi=true
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
                removed_shutdown=true
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
                removed_reboot=true
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
                removed_memtest=true
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

        local added_entries=""
        [[ $removed_uefi == true ]] && added_entries+="UEFI firmware "
        [[ $removed_shutdown == true ]] && added_entries+="shutdown "
        [[ $removed_reboot == true ]] && added_entries+="reboot "
        [[ $removed_memtest == true ]] && added_entries+="memtest86+ "

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

        rx_log_file "success" "GRUB entries refreshed: ${added_entries:-all}"
    else
        rx_log_file "error" "GRUB config not found: $grub_cfg"
    fi
}

set_default_kernel() {
    local grub_cfg="/boot/grub/grub.cfg"
    local target_kernel=$(get_var "GRUB_KERNEL" "linux")

    if [[ $target_kernel == "linux" ]]; then
        return 0
    fi

    if [[ ! -f $grub_cfg ]]; then
        rx_log_file "error" "GRUB config not found: $grub_cfg"
        return 1
    fi

    rx_log_file "info" "Setting default kernel to: $target_kernel"

    local kernel_count=$(grep -c "^menuentry 'RetroLinux'" "$grub_cfg" 2>/dev/null || echo "0")
    if [[ $kernel_count -eq 0 ]]; then
        rx_log_file "warn" "No RetroLinux menuentry found, skipping kernel patch"
        return 1
    fi

    local temp_cfg=$(mktemp)
    local patched=false
    local first_entry=true

    while IFS= read -r line; do
        if [[ $first_entry == true && $line =~ ^menuentry\ \'RetroLinux\' ]]; then
            first_entry=false
            echo "$line" >>"$temp_cfg"
            continue
        fi

        if [[ $patched == false && $first_entry == false ]]; then
            if [[ $line =~ /vmlinuz-linux[[:space:]] ]] || [[ $line =~ /vmlinuz-linux$ ]]; then
                line=$(echo "$line" | sed "s|/vmlinuz-linux[[:space:]]|/vmlinuz-${target_kernel} |g; s|/vmlinuz-linux$|/vmlinuz-${target_kernel}|g")
                patched=true
            fi
            if [[ $line =~ /initramfs-linux\.img ]]; then
                line=$(echo "$line" | sed "s|/initramfs-linux\.img|/initramfs-${target_kernel}.img|g")
            fi
        fi

        echo "$line" >>"$temp_cfg"
    done <"$grub_cfg"

    if [[ $patched == true ]]; then
        $SUDO_CMD cp "$temp_cfg" "$grub_cfg"
        rx_log_file "success" "Default kernel set to: $target_kernel"
    else
        rx_log_file "warn" "Could not patch default kernel entry"
    fi

    rm -f "$temp_cfg"
}

regenerate_grub() {
    rx_log_file "info" "Regenerating GRUB configuration..."

    if command -v grub-mkconfig >/dev/null 2>&1; then
        local grub_defaults="/etc/default/grub"
        local backup_file="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
        
        rx_log_file "info" "Backing up $grub_defaults to $backup_file"
        sudo cp "$grub_defaults" "$backup_file" 2>/dev/null

        rx_log_file "info" "Running grub-mkconfig -o /boot/grub/grub.cfg"
        if $SUDO_CMD grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1; then
            rx_log_file "info" "GRUB config regenerated, applying patches..."
            patch_grub_cfg
            patch_grub_menu_entries
            add_shutdown_reboot_entries
            remove_grub_echo_messages
            set_default_kernel
            rx_log_file "success" "GRUB configuration regenerated and patched"
        else
            rx_log_file "error" "GRUB configuration regeneration failed, restoring backup..."
            sudo cp "$backup_file" "$grub_defaults" 2>/dev/null
            rx_log_file "info" "Backup restored from $backup_file"
        fi
    else
        rx_log_file "error" "grub-mkconfig not found"
    fi
}
