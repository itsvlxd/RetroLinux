#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/timeshift.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "grub"

if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

_detect_bootloader() {
    if [[ -f /boot/grub/grub.cfg ]]; then
        echo "grub|/etc/default/grub|GRUB_CMDLINE_LINUX_DEFAULT|grub-mkconfig -o /boot/grub/grub.cfg"
    elif [[ -d /boot/loader/entries ]]; then
        local entry=$(ls /boot/loader/entries/*.conf 2>/dev/null | head -1)
        echo "systemd-boot|${entry}|options|systemctl reboot"
    elif [[ -f /boot/refind_linux.conf ]]; then
        echo 'refind|/boot/refind_linux.conf|"Boot with standard options"|refind-install'
    else
        echo "unknown|||"
    fi
}

_get_kernel_params() {
    local bl_info=$(_detect_bootloader)
    IFS='|' read -r bl_type bl_file bl_key bl_update_cmd <<<"$bl_info"
    if [[ $bl_type == "grub" && -f $bl_file ]]; then
        grep "^${bl_key}=" "$bl_file" | cut -d'"' -f2
    elif [[ $bl_type == "systemd-boot" && -n $bl_file ]]; then
        grep "^options " "$bl_file" | sed 's/^options //'
    elif [[ $bl_type == "refind" && -f $bl_file ]]; then
        grep '^"' "$bl_file" | head -1 | sed 's/^[^"]*"\([^"]*\)".*/\1/'
    fi
}

_compute_resume_params() {
    local swap_path=""
    [[ -f /swap/swapfile ]] && swap_path="/swap/swapfile"
    [[ -z $swap_path && -f /swapfile ]] && swap_path="/swapfile"

    if [[ -n $swap_path ]] && swapon --show 2>/dev/null | grep -q "$swap_path"; then
        local swap_dev=$(findmnt -no SOURCE -T "$swap_path" 2>/dev/null | sed 's/\[.*\]//')
        local resume_dev=""
        if [[ $swap_dev == /dev/mapper/* ]]; then
            resume_dev="$swap_dev"
        else
            resume_dev="UUID=$(findmnt -no UUID -T "$swap_path" 2>/dev/null)"
        fi
        local resume_offset=""
        if command -v btrfs &>/dev/null; then
            resume_offset=$(sudo btrfs inspect-internal map-swapfile -r "$swap_path" 2>/dev/null)
        fi
        if [[ -z $resume_offset ]]; then
            resume_offset=$(sudo filefrag -v "$swap_path" 2>/dev/null | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')
        fi
        if [[ -n $resume_dev && -n $resume_offset ]]; then
            echo "${resume_dev}|${resume_offset}"
            return 0
        fi
    fi
    return 1
}

_check_resume_status() {
    if grep -q "resume=" /boot/grub/grub.cfg 2>/dev/null; then
        echo "configured"
    else
        echo "missing"
    fi
}

configure_swap() {
    local size_gib="$1" priority="${2:-20}"
    local swap_file="/swap/swapfile"
    local is_btrfs=false

    [[ -z $size_gib || $size_gib -eq 0 ]] && return 0

    if command -v btrfs &>/dev/null && [[ $(stat -f --format=%T / 2>/dev/null) == "btrfs" ]]; then
        is_btrfs=true
        if [[ ! -d /swap ]]; then
            $SUDO_CMD btrfs subvolume create /swap
        fi
    fi
    $SUDO_CMD mkdir -p /swap 2>/dev/null || true
    $SUDO_CMD chattr +C /swap 2>/dev/null || true

    if [[ -f /swapfile ]] && [[ ! -f $swap_file ]]; then
        $SUDO_CMD swapoff /swapfile 2>/dev/null || true
        $SUDO_CMD rm -f /swapfile
        $SUDO_CMD sed -i '/\/swapfile/d' /etc/fstab
        $SUDO_CMD sed -i '/\/swap\/swapfile/d' /etc/fstab
    fi

    if [[ -f $swap_file ]]; then
        local current_bytes=$(stat -c%s "$swap_file" 2>/dev/null || echo 0)
        local target_bytes=$((size_gib * 1024 * 1024 * 1024))
        if [[ $current_bytes -eq $target_bytes ]]; then
            local fstab_line="$swap_file none swap defaults,pri=$priority 0 0"
            if ! grep -qF "$fstab_line" /etc/fstab 2>/dev/null; then
                $SUDO_CMD sed -i '\|'"$swap_file"'|d' /etc/fstab
                echo "$fstab_line" | $SUDO_CMD tee -a /etc/fstab >/dev/null
            fi
            if ! swapon --show 2>/dev/null | grep -qF "$swap_file"; then
                $SUDO_CMD swapon "$swap_file" 2>/dev/null || true
            fi
            return 0
        fi
        $SUDO_CMD swapoff "$swap_file" 2>/dev/null || true
    fi

    $SUDO_CMD truncate -s 0 "$swap_file"
    $SUDO_CMD chattr +C "$swap_file" 2>/dev/null || true
    if $is_btrfs; then
        local count_64m=$((size_gib * 16))
        $SUDO_CMD dd if=/dev/zero of="$swap_file" bs=64M count="$count_64m" status=none
    else
        $SUDO_CMD fallocate -l "${size_gib}G" "$swap_file"
    fi
    $SUDO_CMD chmod 600 "$swap_file"
    $SUDO_CMD mkswap "$swap_file" >/dev/null

    $SUDO_CMD sed -i '\|'$swap_file'|d' /etc/fstab
    echo "$swap_file none swap defaults,pri=$priority 0 0" | $SUDO_CMD tee -a /etc/fstab >/dev/null
    $SUDO_CMD swapon "$swap_file" 2>/dev/null || true
}

configure_sleep() {
    local sleep_dropin="/etc/systemd/sleep.conf.d/99-retro-hibernate.conf"
    $SUDO_CMD mkdir -p /etc/systemd/sleep.conf.d
    if ! grep -q "HibernateMode=platform shutdown" "$sleep_dropin" 2>/dev/null; then
        $SUDO_CMD tee "$sleep_dropin" >/dev/null <<EOF
[Sleep]
HibernateMode=platform shutdown
EOF
    fi
}

_add_resume_hook() {
    local mkinitcpio_conf="/etc/mkinitcpio.conf"
    [[ ! -f $mkinitcpio_conf ]] && return 1

    if ! grep "^HOOKS=" "$mkinitcpio_conf" 2>/dev/null | grep -q "resume"; then
        rx_log_file "info" "Adding resume hook to mkinitcpio.conf"

        local hook_line=$(grep "^HOOKS=" "$mkinitcpio_conf" 2>/dev/null | head -1)
        [[ -z $hook_line ]] && return 1

        local insert_after="filesystems"
        for hook in encrypt lvm2; do
            if echo "$hook_line" | grep -q "$hook"; then
                insert_after="$hook"
            fi
        done

        $SUDO_CMD sed -i "s|^HOOKS=(\(.*\)${insert_after}\(.*\)|HOOKS=(\1${insert_after} resume\2|" "$mkinitcpio_conf"
    fi

    rx_log_file "info" "Regenerating initramfs..."
    $SUDO_CMD mkinitcpio -P
    rx_log_file "success" "Initramfs regenerated with resume support"
}

setup_hibernation() {
    rx_log_file "info" "Setting up hibernation..."

    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gib=$(awk "BEGIN { printf \"%.0f\", $mem_kb / 1024 / 1024 }")
    local default_swap=$(( mem_gib + 3 ))
    local swap_size=$(get_var "SYSTEM_SWAP_SIZE" "${default_swap:-18}")
    local swap_prio=$(get_var "SYSTEM_SWAP_PRIO" "20")

    configure_swap "$swap_size" "$swap_prio"
    configure_sleep

    _add_resume_hook

    local current_driver_params=$(get_var "DRIVER_KERNEL_PARAMS" "")
    if ! echo "$current_driver_params" | grep -q "hibernate.compressor"; then
        current_driver_params+=" hibernate.compressor=lz4"
        set_var "DRIVER_KERNEL_PARAMS" "$(echo "$current_driver_params" | xargs)"
    fi

    set_var "SYSTEM_SWAP_SIZE" "$swap_size" 2>/dev/null || true
    set_var "SYSTEM_SWAP_PRIO" "$swap_prio" 2>/dev/null || true

    local resume_params=$(_compute_resume_params)
    if [[ -n $resume_params ]]; then
        IFS='|' read -r resume_dev resume_offset <<<"$resume_params"
        if [[ -n $resume_dev && -n $resume_offset ]]; then
            local resolve_dev=""
            if [[ $resume_dev == UUID=* ]]; then
                local uuid="${resume_dev#UUID=}"
                resolve_dev=$(blkid -t UUID="$uuid" -o device 2>/dev/null)
            else
                resolve_dev="$resume_dev"
            fi
            local maj_min=$(lsblk -ndo MAJ:MIN "$resolve_dev" 2>/dev/null)
            if [[ -n $maj_min ]]; then
                echo "$maj_min" | $SUDO_CMD tee /sys/power/resume >/dev/null 2>&1 || true
                echo "$resume_offset" | $SUDO_CMD tee /sys/power/resume_offset >/dev/null 2>&1 || true
                rx_log_file "info" "Resume params written to sysfs (${maj_min} / ${resume_offset})"
            fi
        fi
    fi

    rx_log_file "success" "Hibernation setup complete (swap=${swap_size}G)"
}

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

install_grub_template() {
    local module_template="$RETRO_DIR/modules/grub/files/10_linux"
    local state_dir="/usr/local/share/retrolinux/grub.d"
    local kernel=$(get_var "GRUB_KERNEL" "linux")

    rx_log_file "info" "Installing GRUB template (kernel=$kernel)"

    if [[ ! -f $module_template ]]; then
        rx_log_file "error" "GRUB template not found: $module_template"
        return 1
    fi

    $SUDO_CMD mkdir -p "$state_dir"
    $SUDO_CMD sed "s|@RETRO_KERNEL@|$kernel|" "$module_template" | $SUDO_CMD tee "$state_dir/10_linux" >/dev/null
    $SUDO_CMD install -m 755 "$state_dir/10_linux" /etc/grub.d/10_linux
    rx_log_file "success" "GRUB template installed to /etc/grub.d/10_linux"

    install_grub_restore_script
}

install_grub_restore_script() {
    local state_dir="/usr/local/share/retrolinux"
    local restore="$state_dir/grub-restore.sh"
    $SUDO_CMD mkdir -p "$state_dir"

    $SUDO_CMD tee "$restore" >/dev/null <<'RESTORE'
#!/bin/sh
set -e
# Restore the RetroLinux GRUB template after grub package updates so the boot
# menu is always generated deterministically.
if [ -f /usr/local/share/retrolinux/grub.d/10_linux ]; then
    install -m 755 /usr/local/share/retrolinux/grub.d/10_linux /etc/grub.d/10_linux
fi
for script in 30_uefi-firmware 41_snapshots-btrfs 60_memtest86+; do
    chmod -x "/etc/grub.d/$script" 2>/dev/null || true
done
exit 0
RESTORE
    $SUDO_CMD chmod +x "$restore"

    local hook="/etc/pacman.d/hooks/99-retrolinux-grub.hook"
    $SUDO_CMD mkdir -p /etc/pacman.d/hooks
    $SUDO_CMD tee "$hook" >/dev/null <<'HOOK'
[Trigger]
Operation = Upgrade
Operation = Install
Type = File
Target = usr/bin/grub-mkconfig

[Action]
Description = Restoring RetroLinux GRUB template...
When = PostTransaction
Exec = /usr/local/share/retrolinux/grub-restore.sh
HOOK
    rx_log_file "success" "GRUB restore hook installed"
}

disable_grub_d_scripts() {
    # Scripts absorbed into the RetroLinux template are disabled so grub-mkconfig
    # doesn't emit duplicate entries. 41_snapshots-btrfs still regenerates the
    # snapshot list via grub-btrfsd; 60_memtest86+ is replaced by the template's
    # single memtest entry.
    for script in 30_uefi-firmware 41_snapshots-btrfs 60_memtest86+; do
        $SUDO_CMD chmod -x "/etc/grub.d/$script" 2>/dev/null || true
    done
}

verify_grub_cfg() {
    local grub_cfg="/boot/grub/grub.cfg"
    if command -v grub-script-check >/dev/null 2>&1 && [[ -f $grub_cfg ]]; then
        if grub-script-check "$grub_cfg" 2>/dev/null; then
            rx_log_file "success" "grub.cfg passed grub-script-check"
        else
            rx_log_file "error" "grub.cfg FAILED grub-script-check - the boot menu may be broken!"
            return 1
        fi
    fi
}

apply_manual_entries() {
    local store="${RETRO_CONFIG:-$HOME/.config/retro}/grub/manual-entries.cfg"
    if [[ ! -f $store ]]; then
        return 0
    fi

    local grub_cfg="/boot/grub/grub.cfg"
    local out
    out=$("$RETRO_DIR/scripts/python/grub_manual_entries.py" --apply "$grub_cfg" "$store") || {
        rx_log_file "error" "Failed to apply manual GRUB menu entries"
        return 1
    }

    rx_log_file "info" "Applying manual GRUB menu entries from $store"
    printf '%s\n' "$out" | $SUDO_CMD tee "$grub_cfg" >/dev/null
}

apply_menu_order() {
    local store="${RETRO_CONFIG:-$HOME/.config/retro}/grub/manual-entries.cfg"
    if [[ ! -f $store ]]; then
        return 0
    fi

    local grub_cfg="/boot/grub/grub.cfg"
    local out
    out=$("$RETRO_DIR/scripts/python/grub_manual_entries.py" --reorder "$grub_cfg" "$store") || {
        rx_log_file "error" "Failed to reorder GRUB menu entries"
        return 1
    }

    rx_log_file "info" "Applying GRUB menu entry order from $store"
    printf '%s\n' "$out" | $SUDO_CMD tee "$grub_cfg" >/dev/null
}

get_grub_cmdline() {
    local base_params="quiet splash loglevel=3 net.ifnames=0"
    local hw_cmdline=$(RETRO_CONFIG="$RETRO_CONFIG" bash "$RETRO_DIR/scripts/driver_core.sh" --hw-cmdline 2>/dev/null)

    rx_log_file "info" "Building kernel cmdline (base + hardware params)"

    local extra_params=""
    local running=$(cat /proc/cmdline 2>/dev/null)
    for p in $running; do
        case "$p" in
            i915.force_probe=*|xe.force_probe=*) extra_params+="$p " ;;
        esac
    done

    local merged_cmdline=""
    declare -A seen_params

    for param in $base_params $hw_cmdline $extra_params; do
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

    if [[ -n $SUDO_USER ]]; then
        local real_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        if [[ -n $real_home ]]; then
            export RETRO_CONFIG="${RETRO_CONFIG:-$real_home/.config/retro}"
        fi
    fi

    # Make sure the selected theme is on disk before we reference it in
    # GRUB_THEME; otherwise GRUB falls back to the default theme silently.
    install_grub_themes

    local gfxmode=$(get_var "BOOT_VIDEO_GRUB" "1920x1080")
    local theme_choice=$(get_var "GRUB_THEME_CHOICE" "retropunk")
    [[ -z $theme_choice ]] && theme_choice="retropunk"
    local os_prober=$(get_var "GRUB_OS_PROBER" "false")
    local timeout_val=$(get_var "GRUB_TIMEOUT" "10")
    local cmdline=$(get_grub_cmdline)

    local driver_params=$(get_var "DRIVER_KERNEL_PARAMS" "")
    [[ -n $driver_params ]] && cmdline="$cmdline $driver_params"

    local resume_params=$(_compute_resume_params)
    if [[ -n $resume_params ]]; then
        IFS='|' read -r resume_dev resume_offset <<<"$resume_params"
        if [[ -n $resume_dev && -n $resume_offset ]]; then
            cmdline="$cmdline resume=$resume_dev resume_offset=$resume_offset"
        fi
    fi
    cmdline=$(echo "$cmdline" | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ' | xargs)

    local snapshots=$(get_var "GRUB_SNAPSHOTS_ENABLED" "true")
    rx_log_file "info" "Updating GRUB config (theme=$theme_choice, timeout=${timeout_val}s, gfxmode=$gfxmode, os_prober=$os_prober, snapshots=$snapshots)"

    if [[ $snapshots == "true" ]]; then
        $SUDO_CMD systemctl enable --now grub-btrfsd 2>/dev/null || true
    else
        $SUDO_CMD systemctl disable --now grub-btrfsd 2>/dev/null || true
    fi

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

        if grep -q "^GRUB_DEFAULT=" "$grub_defaults"; then
            $SUDO_CMD sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=0|' "$grub_defaults"
        else
            echo "GRUB_DEFAULT=0" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
        fi

        if grep -q "^GRUB_DISABLE_RECOVERY=" "$grub_defaults"; then
            $SUDO_CMD sed -i 's|^GRUB_DISABLE_RECOVERY=.*|GRUB_DISABLE_RECOVERY=true|' "$grub_defaults"
        else
            echo "GRUB_DISABLE_RECOVERY=true" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
        fi

        if grep -q "^GRUB_PRELOAD_MODULES=" "$grub_defaults"; then
            $SUDO_CMD sed -i 's|^GRUB_PRELOAD_MODULES=.*|GRUB_PRELOAD_MODULES="part_gpt part_msdos"|' "$grub_defaults"
        else
            echo 'GRUB_PRELOAD_MODULES="part_gpt part_msdos"' | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
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

        local grub_disable="true"
        [[ $os_prober == "true" ]] && grub_disable="false"
        if grep -q "^GRUB_DISABLE_OS_PROBER=" "$grub_defaults"; then
            $SUDO_CMD sed -i "s|^GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=$grub_disable|" "$grub_defaults"
        else
            echo "GRUB_DISABLE_OS_PROBER=$grub_disable" | $SUDO_CMD tee -a "$grub_defaults" >/dev/null
        fi

        rx_log_file "success" "GRUB configuration updated"
    else
        rx_log_file "error" "GRUB defaults file not found: $grub_defaults"
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

    local temp_cfg=$(mktemp)
    local in_first_entry=false
    local brace_depth=0
    local patched_vmlinuz=false
    local patched_initrd=false

    while IFS= read -r line; do
        if [[ $in_first_entry == false && $line =~ ^menuentry\ \'RetroLinux ]]; then
            in_first_entry=true
            brace_depth=0
        fi

        if [[ $in_first_entry == true ]]; then
            local open_b=$(echo "$line" | tr -cd '{' | wc -c)
            local close_b=$(echo "$line" | tr -cd '}' | wc -c)
            brace_depth=$((brace_depth + open_b - close_b))

            if [[ $patched_vmlinuz == false && $line =~ /vmlinuz-[^[:space:]]+ ]]; then
                line=$(echo "$line" | sed 's|/vmlinuz-[^[:space:]]*|/vmlinuz-'"${target_kernel}"'|')
                patched_vmlinuz=true
            fi
            if [[ $patched_initrd == false && $line =~ /initramfs-[^[:space:]]+\.img ]]; then
                line=$(echo "$line" | sed 's|/initramfs-[^[:space:]]*\.img|/initramfs-'"${target_kernel}"'.img|')
                patched_initrd=true
            fi

            if [[ $brace_depth -le 0 ]]; then
                in_first_entry=false
            fi
        fi

        echo "$line" >>"$temp_cfg"
    done <"$grub_cfg"

    if [[ $patched_vmlinuz == true || $patched_initrd == true ]]; then
        $SUDO_CMD cp "$temp_cfg" "$grub_cfg"
        rx_log_file "success" "Default kernel set to: $target_kernel"
    else
        rx_log_file "warn" "Could not patch default kernel entry"
    fi

    rm -f "$temp_cfg"
}

create_timeshift_backup() {
    local comment="${1:-"Grub Changes $(date '+%Y-%m-%d %H:%M')"}"

    if ! command -v timeshift &>/dev/null; then
        rx_log_file "warn" "Timeshift not installed, skipping backup"
        return 0
    fi

    rx_log_file "info" "Creating Timeshift backup: $comment"
    if sudo timeshift --create --comments "$comment" --tags O >/dev/null 2>&1; then
        rx_log_file "success" "Timeshift backup created"
        rx_timeshift_limit_by_description "Grub Changes" 3
    else
        rx_log_file "warn" "Timeshift backup failed, continuing anyway"
    fi
}

patch_snapshot_entry() {
    local grub_cfg="/boot/grub/grub.cfg"

    if [[ ! -f $grub_cfg ]]; then
        rx_log_file "error" "GRUB config not found: $grub_cfg"
        return 1
    fi

    # Safety net: the template emits the snapshots submenu with the right title
    # and --class, so this only normalizes a stock grub-btrfs submenu when the
    # user regenerates with a plain `grub-mkconfig` (which would otherwise
    # produce "RetroLinux snapshots"). Memtest/os-prober entries are emitted by
    # the template / 30_os-prober and must NOT be injected here.
    rx_log_file "info" "Patching snapshot submenu entry..."

    local patched=false
    local temp_cfg=$(mktemp)

    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*submenu\ \'Retro[[:space:]]*Linux\ [Ss]napshots ]]; then
            line="${line//\'Retro Linux snapshots\'/\'RetroLinux Snapshots\'}"
            line="${line//\'RetroLinux snapshots\'/\'RetroLinux Snapshots\'}"
            if [[ $line != *--class*retrolinux* ]]; then
                line="${line/\{/--class retrolinux \{}"
            fi
            patched=true
        fi
        echo "$line" >>"$temp_cfg"
    done <"$grub_cfg"

    if [[ $patched == true ]]; then
        $SUDO_CMD cp "$temp_cfg" "$grub_cfg"
        rx_log_file "success" "Snapshot submenu entry patched"
    else
        rx_log_file "info" "No snapshot submenu entry found to patch"
    fi

    rm -f "$temp_cfg"
}

remove_snapshot_entry() {
    local grub_cfg="/boot/grub/grub.cfg"

    if [[ ! -f $grub_cfg ]]; then
        rx_log_file "error" "GRUB config not found: $grub_cfg"
        return 1
    fi

    rx_log_file "info" "Removing snapshot submenu entry..."

    local temp_cfg=$(mktemp)
    local skip=false
    local brace_depth=0
    local removed=false

    while IFS= read -r line; do
        if [[ $skip == false && $line =~ submenu\ \'Retro[^\']*[Ss]napshot ]]; then
            skip=true
            brace_depth=$(echo "$line" | tr -cd '{' | wc -c)
            brace_depth=$((brace_depth - $(echo "$line" | tr -cd '}' | wc -c)))
            removed=true
            continue
        fi

        if [[ $skip == true ]]; then
            local open_b=$(echo "$line" | tr -cd '{' | wc -c)
            local close_b=$(echo "$line" | tr -cd '}' | wc -c)
            brace_depth=$((brace_depth + open_b - close_b))
            if [[ $brace_depth -le 0 ]]; then
                skip=false
            fi
            continue
        fi

        echo "$line" >>"$temp_cfg"
    done <"$grub_cfg"

    if [[ $removed == true ]]; then
        $SUDO_CMD cp "$temp_cfg" "$grub_cfg"
        rx_log_file "success" "Snapshot submenu entry removed"
    else
        rx_log_file "info" "No snapshot submenu entry found to remove"
    fi

    rm -f "$temp_cfg"
}

_grub_ensure_kernel() {
    local kernel="$1"
    [[ -z $kernel || $kernel == "linux" ]] && return 0

    local img="/boot/vmlinuz-${kernel}"
    local initrd="/boot/initramfs-${kernel}.img"

    if [[ -f $img && -f $initrd ]]; then
        rx_log_file "info" "Kernel ${kernel} already present"
        return 0
    fi

    rx_log_file "info" "Kernel ${kernel} missing, installing..."
    $SUDO_CMD pacman -S --needed --noconfirm "${kernel}" "${kernel}-headers" || {
        rx_log_file "error" "Failed to install kernel ${kernel}"
        return 1
    }
    $SUDO_CMD mkinitcpio -P 2>/dev/null || true

    if [[ -f $img && -f $initrd ]]; then
        rx_log_file "success" "Kernel ${kernel} installed and initramfs rebuilt"
        return 0
    fi
    rx_log_file "error" "Kernel ${kernel} files still missing after install"
    return 1
}

add_resume_params() {
    local device="$1" offset="$2"
    [[ -z $device || -z $offset ]] && { rx_log_file "error" "Missing device or offset for resume"; return 1; }

    rx_log_file "info" "Adding resume parameters (device=$device offset=$offset)"

    if [[ -f /etc/default/grub ]]; then
        $SUDO_CMD sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/s| resume=[^ ]*||g; /^GRUB_CMDLINE_LINUX_DEFAULT=/s| resume_offset=[^ ]*||g' /etc/default/grub
        if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub 2>/dev/null; then
            $SUDO_CMD sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 resume=$device resume_offset=$offset\"|" /etc/default/grub
        else
            echo "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet resume=$device resume_offset=$offset\"" | $SUDO_CMD tee -a /etc/default/grub >/dev/null
        fi
    fi

    if [[ -f /boot/grub/grub.cfg ]]; then
        $SUDO_CMD sed -i '/^\s*linux\s/s| resume=[^ ]*||g; /^\s*linux\s/s| resume_offset=[^ ]*||g' /boot/grub/grub.cfg
        $SUDO_CMD sed -i "s|^\(\s*linux.*\)|\1 resume=$device resume_offset=$offset|" /boot/grub/grub.cfg
    fi

    rx_log_file "success" "Resume parameters added"
}

apply_kernel_params() {
    local params="$1"
    local bl_info=$(_detect_bootloader)
    IFS='|' read -r bl_type bl_file bl_key bl_update_cmd <<<"$bl_info"

    rx_log_file "info" "Applying kernel params to $bl_type bootloader: ${params:-none}"

    case "$bl_type" in
        grub)
            if [[ -n $params ]]; then
                patch_kernel_cmdline "$params"
            else
                local grub_cfg="/boot/grub/grub.cfg"
                local grub_defaults="/etc/default/grub"
                if [[ -f $grub_cfg ]]; then
                    $SUDO_CMD sed -i '/^\s*linux\s/s/ i915\.force_probe=[^ ]*//g; /^\s*linux\s/s/ xe\.force_probe=[^ ]*//g' "$grub_cfg"
                fi
                if [[ -f $grub_defaults ]]; then
                    $SUDO_CMD sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/s/ i915\.force_probe=[^ ]*//g; /^GRUB_CMDLINE_LINUX_DEFAULT=/s/ xe\.force_probe=[^ ]*//g' "$grub_defaults"
                fi
            fi
            ;;
        systemd-boot)
            for f in /boot/loader/entries/*.conf; do
                [[ -f $f ]] || continue
                local existing_opts=$(grep "^options " "$f" | sed 's/^options //')
                if [[ -n $params ]]; then
                    local cleaned=$(echo "$existing_opts" | sed 's/ i915\.force_probe=[^ ]*//g; s/ xe\.force_probe=[^ ]*//g' | xargs)
                    $SUDO_CMD sed -i "s|^options .*|options ${cleaned} ${params}|" "$f"
                else
                    $SUDO_CMD sed -i 's/ i915\.force_probe=[^ ]*//g; s/ xe\.force_probe=[^ ]*//g' "$f"
                fi
            done
            ;;
        refind)
            if [[ -f $bl_file ]]; then
                local existing_opts=$(grep '^"' "$bl_file" | head -1 | sed 's/^[^"]*"\([^"]*\)".*/\1/')
                if [[ -n $params ]]; then
                    local cleaned=$(echo "$existing_opts" | sed 's/ i915\.force_probe=[^ ]*//g; s/ xe\.force_probe=[^ ]*//g' | xargs)
                    $SUDO_CMD sed -i "s|^\"[^\"]*\"|\"Boot with standard options\" \"${cleaned} ${params}\"|" "$bl_file"
                else
                    $SUDO_CMD sed -i 's/ i915\.force_probe=[^ ]*//g; s/ xe\.force_probe=[^ ]*//g' "$bl_file"
                fi
            fi
            ;;
    esac

    rx_log_file "success" "Kernel params applied to $bl_type bootloader"
    echo "SUCCESS|${bl_type}"
}

patch_kernel_cmdline() {
    local grub_cfg="/boot/grub/grub.cfg"
    local grub_defaults="/etc/default/grub"
    local params="$1"
    [[ -z $params ]] && { rx_log_file "error" "No kernel params provided"; return 1; }

    rx_log_file "info" "Patching kernel cmdline in RetroLinux entry"

    local temp_cfg=$(mktemp)
    local in_entry=false
    local patched=false

    while IFS= read -r line; do
        if [[ $in_entry == false && $line =~ ^menuentry\ \'RetroLinux ]]; then
            in_entry=true
            echo "$line" >>"$temp_cfg"
        elif [[ $in_entry == true && $line =~ ^[[:space:]]*linux[[:space:]] ]]; then
            local kernel_path=$(echo "$line" | awk '{print $2}')
            local existing=$(echo "$line" | sed 's/^\s*linux\s\+[^ ]\+\s\+//')
            existing=$(echo "$existing" | sed 's/i915\.force_probe=[^ ]*//g; s/xe\.force_probe=[^ ]*//g' | xargs)
            existing=$(echo "$existing" | tr ' ' '\n' | awk '!seen[$0]++' | tr '\n' ' ' | xargs)
            echo -e "\tlinux\t${kernel_path} ${existing} ${params}" >>"$temp_cfg"
            patched=true
            in_entry=false
        else
            echo "$line" >>"$temp_cfg"
        fi
    done <"$grub_cfg"

    if [[ $patched == true ]]; then
        $SUDO_CMD cp "$temp_cfg" "$grub_cfg"

        if [[ -f $grub_defaults ]]; then
            $SUDO_CMD sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/s| i915\.force_probe=[^ ]*||g; /^GRUB_CMDLINE_LINUX_DEFAULT=/s| xe\.force_probe=[^ ]*||g' "$grub_defaults"
            $SUDO_CMD sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${params}\"|" "$grub_defaults"
        fi

        rx_log_file "success" "Kernel cmdline patched in RetroLinux entry"
    else
        rx_log_file "warn" "Could not find RetroLinux entry to patch"
    fi
    rm -f "$temp_cfg"
}

regenerate_grub() {
    local remove_snapshots="${1:-false}"
    local grub_defaults="/etc/default/grub"

    if [[ -n $SUDO_USER ]]; then
        local real_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        if [[ -n $real_home ]]; then
            export RETRO_CONFIG="${RETRO_CONFIG:-$real_home/.config/retro}"
        fi
    fi

    rx_log_file "info" "Regenerating GRUB configuration..."

    # Themes + the RetroLinux menu template must be in place before we write
    # /etc/default/grub and run grub-mkconfig, so every regeneration produces
    # the same deterministic menu.
    install_grub_themes
    install_grub_template
    disable_grub_d_scripts

    setup_hibernation

    update_grub_config

    if ! command -v grub-mkconfig >/dev/null 2>&1; then
        rx_log_file "error" "grub-mkconfig not found"
        return 1
    fi

    local target_kernel=$(get_var "GRUB_KERNEL" "linux")
    _grub_ensure_kernel "$target_kernel" || return 1

    local backup_file="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
    rx_log_file "info" "Backing up $grub_defaults to $backup_file"
    sudo cp "$grub_defaults" "$backup_file" 2>/dev/null

    local os_prober=$(get_var "GRUB_OS_PROBER" "false")
    if [[ $os_prober == "true" ]]; then
        check_dep os-prober os-prober
        local os_prober_path
        os_prober_path=$(command -v os-prober 2>/dev/null)
        if [[ -n $os_prober_path ]]; then
            local sudoers_file="/etc/sudoers.d/99-os-prober"
            local rule="%wheel ALL=(ALL) NOPASSWD: ${os_prober_path}"
            if [[ ! -f $sudoers_file ]]; then
                export RULE="$rule" SUDO_CMD
                timeout 10 bash -c 'echo "$RULE" | $SUDO_CMD tee "$1" >/dev/null 2>&1 && $SUDO_CMD chmod 0440 "$1"' _ "$sudoers_file" 2>/dev/null || true
            fi
        fi
    fi

    rx_log_file "info" "Running grub-mkconfig -o /boot/grub/grub.cfg"
    if ! $SUDO_CMD grub-mkconfig -o /boot/grub/grub.cfg >/dev/null; then
        rx_log_file "error" "GRUB regeneration failed"
        return 1
    fi

    # The snapshot submenu is generated dynamically by grub-btrfsd and the main
    # entry's kernel comes from the template; only patch those two parts.
    remove_grub_echo_messages
    if [[ $remove_snapshots == true ]]; then
        remove_snapshot_entry
    else
        patch_snapshot_entry
    fi
    set_default_kernel

    # Re-apply the user's manually edited menu entries (from the settings
    # boot menu editor) so they survive the deterministic regeneration.
    apply_manual_entries
    # Then apply the drag-and-drop order the user picked in the settings GUI.
    apply_menu_order

    verify_grub_cfg

    rx_log_file "success" "GRUB configuration regenerated"
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        "--detect-bootloader") _detect_bootloader ;;
        "--get-kernel-params") _get_kernel_params ;;
        "--get-cmdline") get_grub_cmdline ;;
        "--compute-resume-params") _compute_resume_params ;;
        "--resume-status") _check_resume_status ;;
        "--apply-resume") add_resume_params "$2" "$3" ;;
        "--apply-kernel-params") apply_kernel_params "$2" ;;
        "--regenerate") regenerate_grub "$2" ;;
        "--apply-manual-entries") apply_manual_entries ;;
        "--apply-menu-order") apply_menu_order ;;
        "--update-config") update_grub_config ;;
        "--themes") install_grub_themes ;;
        "--ensure-kernel") _grub_ensure_kernel "$2" ;;
        "--create-swap") configure_swap "$2" "$3" ;;
        "--configure-sleep") configure_sleep ;;
        "--setup-hibernation") setup_hibernation ;;
    esac
fi
