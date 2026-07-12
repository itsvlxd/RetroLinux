#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "system_core"

DROPIN_DIR="/etc/systemd/logind.conf.d"
DROPIN_FILE="$DROPIN_DIR/retro-power.conf"

write_logind() {
    local power="${1:-suspend}"
    local power_long="${2:-poweroff}"
    local lid="${3:-suspend}"
    sudo mkdir -p "$DROPIN_DIR"
    sudo tee "$DROPIN_FILE" >/dev/null <<EOF
[Login]
HandlePowerKey=$power
HandlePowerKeyLongPress=$power_long
HandleLidSwitch=$lid
HandleLidSwitchExternalPower=$lid
HandleLidSwitchDocked=ignore
LidSwitchIgnoreInhibited=yes
EOF
    sudo systemctl reload systemd-logind 2>/dev/null || true
}

print_status() {
    local power="suspend" power_long="poweroff" lid="suspend"
    if [[ -f $DROPIN_FILE ]]; then
        power=$(grep "^HandlePowerKey=" "$DROPIN_FILE" | cut -d= -f2)
        power_long=$(grep "^HandlePowerKeyLongPress=" "$DROPIN_FILE" | cut -d= -f2)
        lid=$(grep "^HandleLidSwitch=" "$DROPIN_FILE" | cut -d= -f2 | head -1)
    fi

    echo "POWER|${power:-suspend}"
    echo "LONG|${power_long:-poweroff}"
    echo "LID|${lid:-suspend}"

    local swap_path=""
    [[ -f /swap/swapfile ]] && swap_path="/swap/swapfile"
    [[ -z $swap_path && -f /swapfile ]] && swap_path="/swapfile"

    if [[ -n $swap_path ]]; then
        local swap_gib=$(stat -c%s "$swap_path" 2>/dev/null | awk '{printf "%.0f", $1/1024/1024/1024}')
        local swap_prio=$(grep -F "$swap_path" /etc/fstab 2>/dev/null | grep -oP 'pri=\K[0-9]+' || echo "0")
        echo "SWAP|${swap_gib:-0}|${swap_prio}"
    else
        echo "SWAP|0|0"
    fi

    local zram_raw=$(zramctl 2>/dev/null | grep "^/dev/zram")
    local zram_alg=$(echo "$zram_raw" | awk '{print $2}')
    local zram_disk=$(echo "$zram_raw" | awk '{print $3}')
    local zram_prio=$(swapon --show 2>/dev/null | grep "/dev/zram" | awk '{print $4}')
    local zram_conf_size=$(grep "^zram-size" /etc/systemd/zram-generator.conf 2>/dev/null | cut -d= -f2 | xargs)
    echo "ZRAM|${zram_alg:-zstd}|${zram_disk:-0}|${zram_prio:-80}|${zram_conf_size:-ram / 2}"

    local resume_status=$(bash "$RETRO_DIR/scripts/grub_core.sh" --resume-status 2>/dev/null)
    if [[ $resume_status == "configured" ]]; then
        echo "RESUME|ready"
    else
        echo "RESUME|missing"
    fi
}

configure_zram() {
    local raw_size="$1" priority="${2:-80}"
    local parsed_size="$raw_size"
    local conf="/etc/systemd/zram-generator.conf"

    if [[ $raw_size =~ ^([0-9]+)[gG][bB]?$ ]]; then
        parsed_size=$((${BASH_REMATCH[1]} * 1024))
    fi

    if [[ -f $conf ]] && grep -q "zram-size = $parsed_size" "$conf" && grep -q "swap-priority = $priority" "$conf"; then
        return 0
    fi

    sudo tee "$conf" >/dev/null <<EOF
[zram0]
zram-size = $parsed_size
compression-algorithm = zstd
swap-priority = $priority
EOF
    sudo swapoff /dev/zram0 2>/dev/null || true
    sudo systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
}



apply_all() {
    if [[ -n $SUDO_USER ]]; then
        local real_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        if [[ -n $real_home ]]; then
            export RETRO_CONFIG="${RETRO_CONFIG:-$real_home/.config/retro}"
        fi
    fi

    local power=$(get_var "PWR_POWER_BTN" "suspend")
    local power_long=$(get_var "PWR_POWER_BTN_LONG" "poweroff")
    local lid=$(get_var "PWR_LID_CLOSE" "suspend")
    write_logind "$power" "$power_long" "$lid"

    bash "$RETRO_DIR/scripts/grub_core.sh" --setup-hibernation

    local zram_size=$(get_var "SYSTEM_ZRAM_SIZE" "ram / 2")
    local zram_prio=$(get_var "SYSTEM_ZRAM_PRIO" "80")
    configure_zram "$zram_size" "$zram_prio"

    set_var "SYSTEM_ZRAM_SIZE" "$zram_size" 2>/dev/null || true
    set_var "SYSTEM_ZRAM_PRIO" "$zram_prio" 2>/dev/null || true
}

_smart_suspend() {
    if [[ -f /sys/power/resume && -f /sys/power/resume_offset ]]; then
        local r=$(cat /sys/power/resume)
        local o=$(cat /sys/power/resume_offset)
        if [[ $r != "0:0" && -n $r && -n $o && $o != "0" ]]; then
            exec systemctl suspend-then-hibernate
        fi
    fi
    exec systemctl suspend
}

case "${1:-}" in
    --hibernate-available)
        if [[ -f /sys/power/resume && -f /sys/power/resume_offset ]]; then
            local r=$(cat /sys/power/resume)
            local o=$(cat /sys/power/resume_offset)
            if [[ $r != "0:0" && -n $r && -n $o && $o != "0" ]]; then
                echo "available"
            else
                echo "unavailable"
            fi
        else
            echo "unavailable"
        fi
        ;;
    --status | -s)
        print_status
        ;;
    --set-power)
        write_logind "${2:-suspend}" "$(get_var PWR_POWER_BTN_LONG poweroff)" "$(get_var PWR_LID_CLOSE suspend)"
        ;;
    --set-long)
        write_logind "$(get_var PWR_POWER_BTN suspend)" "${2:-poweroff}" "$(get_var PWR_LID_CLOSE suspend)"
        ;;
    --set-lid)
        write_logind "$(get_var PWR_POWER_BTN suspend)" "$(get_var PWR_POWER_BTN_LONG poweroff)" "${2:-suspend}"
        ;;
    --sleep | --set-sleep)
        bash "$RETRO_DIR/scripts/grub_core.sh" --configure-sleep
        ;;
    --set-zram)
        configure_zram "$2" "${3:-80}"
        set_var "SYSTEM_ZRAM_SIZE" "$2" 2>/dev/null || true
        set_var "SYSTEM_ZRAM_PRIO" "${3:-80}" 2>/dev/null || true
        ;;
    --set-swap)
        bash "$RETRO_DIR/scripts/grub_core.sh" --create-swap "$2" "$3"
        set_var "SYSTEM_SWAP_SIZE" "$2" 2>/dev/null || true
        set_var "SYSTEM_SWAP_PRIO" "${3:-20}" 2>/dev/null || true
        ;;
    --apply)
        apply_all
        ;;
    --smart-suspend)
        _smart_suspend
        ;;
    *)
        write_logind "${1:-suspend}" "${2:-poweroff}" "${3:-suspend}"
        ;;
esac
