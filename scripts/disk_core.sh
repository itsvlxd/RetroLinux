#!/bin/bash

source "$RETRO_DIR/lib/variable.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "disk"

if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

_smartctl() {
    [[ $EUID -eq 0 ]] && { smartctl "$@" 2>/dev/null; return; }
    timeout 5 sudo -n smartctl "$@" 2>/dev/null
}

_get_disks() {
    while IFS= read -r line; do
        local NAME="" SIZE="" MODEL="" TYPE="" ROTA=""
        eval "$line" 2>/dev/null
        [[ -z $NAME ]] && continue
        [[ $NAME == zram* ]] && continue
        echo "${NAME}|${SIZE}|${MODEL:-?}|${TYPE}|${ROTA}"
    done < <(lsblk -Pdno NAME,SIZE,MODEL,TYPE,ROTA 2>/dev/null)
}

_get_disk_type() {
    local name="$1" rota="$2" model="$3"
    if [[ $name == nvme* ]]; then
        echo "NVMe M.2 SSD"
    elif [[ $name == mmcblk* ]]; then
        echo "eMMC Storage"
    elif [[ $name == sd* ]]; then
        local syspath
        syspath=$(readlink -f "/sys/block/${name}" 2>/dev/null)
        if [[ $syspath == *"/usb"* ]]; then
            echo "USB Flash Storage"
        elif [[ $rota -eq 1 ]]; then
            echo "SATA HDD"
        else
            echo "SATA SSD"
        fi
    else
        echo "Storage Device"
    fi
}

_get_wear_level() {
    local dev="$1"
    command -v smartctl &>/dev/null || { echo "N/A"; return; }
    local data
    data=$(_smartctl -A "/dev/${dev}" 2>/dev/null)
    [[ -z $data ]] && { echo "N/A"; return; }

    local pct
    pct=$(echo "$data" | grep -oP 'Percentage Used:\s+\K[0-9]+' | head -1)
    if [[ -n $pct ]]; then
        local remaining=$((100 - pct))
        echo "${remaining}%"
        return
    fi

    pct=$(echo "$data" | awk '$1 == "231" {print $NF; exit}')
    if [[ -n $pct && $pct =~ ^[0-9]+$ && $pct -gt 0 && $pct -le 100 ]]; then
        local remaining=$((100 - pct))
        echo "${remaining}%"
        return
    fi

    local wear
    wear=$(echo "$data" | awk '$1 == "177" {print $4; exit}')
    if [[ -z $wear ]]; then
        wear=$(echo "$data" | awk '$1 == "173" {print $4; exit}')
    fi
    if [[ -n $wear && $wear =~ ^[0-9]+$ && $wear -le 100 ]]; then
        echo "${wear}%"
        return
    fi

    echo "N/A"
}

_get_smart_health() {
    local dev="$1"
    command -v smartctl &>/dev/null || { echo "N/A"; return; }
    local result
    result=$(_smartctl -H "/dev/${dev}" | grep -oP '(PASSED|FAILED|OK)' | head -1)
    echo "${result:-UNKNOWN}"
}

_get_smart_temp() {
    local dev="$1"
    command -v smartctl &>/dev/null || { echo "N/A"; return; }
    local result
    result=$(_smartctl -A "/dev/${dev}" | awk '/^Temperature:/ {print $2; exit} /Temperature_Celsius/ {print $10; exit}')
    echo "${result:-N/A}"
}

_get_smart_attributes() {
    local dev="$1"
    command -v smartctl &>/dev/null || return
    _smartctl -A "/dev/${dev}" | while IFS= read -r line; do
        local id=$(echo "$line" | awk '{print $1}')
        local name=$(echo "$line" | awk '{print $2}')
        local value=$(echo "$line" | awk '{print $NF}')
        if [[ $id =~ ^[0-9]+$ ]]; then
            echo "${id}|${name}|${value}"
        fi
    done
}

_get_disk_usage() {
    local dev="$1"
    local parts mounts="" used="?"
    parts=$(lsblk -nlo NAME "/dev/${dev}" 2>/dev/null | tail -n +2)
    while IFS= read -r part; do
        local mount
        mount=$(findmnt -nlo TARGET "/dev/${part}" 2>/dev/null | head -1)
        if [[ -n $mount ]]; then
            [[ -n $mounts ]] && mounts="${mounts}, "
            mounts="${mounts}${mount}"
            [[ $used == "?" ]] && used=$(df -h "$mount" 2>/dev/null | awk 'NR==2 {print $5}')
        fi
    done <<<"$parts"
    [[ -z $mounts ]] && mounts=""
    echo "${used:-?}|${mounts}"
}

_mount_device() {
    local dev="$1"
    local path="$2"
    local label
    label=$(blkid -s LABEL -o value "/dev/${dev}" 2>/dev/null || echo "")
    [[ -z $label ]] && label="${dev}"

    if command -v udisksctl &>/dev/null; then
        result=$(udisksctl mount -b "/dev/${dev}" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            local mnt=$(echo "$result" | grep -oP 'at \K.*')
            echo "OK|mounted=${mnt}"
            rx_log_file "info" "Mounted ${dev} at ${mnt} (udisks)"
            return 0
        fi
    fi

    if [[ -n $path ]]; then
        $SUDO_CMD mkdir -p "$path" 2>/dev/null
        $SUDO_CMD mount "/dev/${dev}" "$path" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            echo "OK|mounted=${path}"
            rx_log_file "info" "Mounted ${dev} at ${path}"
            return 0
        fi
    else
        local default_path="/mnt/${label// /_}"
        $SUDO_CMD mkdir -p "$default_path" 2>/dev/null
        $SUDO_CMD mount "/dev/${dev}" "$default_path" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            echo "OK|mounted=${default_path}"
            rx_log_file "info" "Mounted ${dev} at ${default_path}"
            return 0
        fi
    fi

    echo "ERR|mount_failed"
    return 1
}

_umount_device() {
    local path="$1"
    if [[ $path == "/" || $path == "/home" || $path == "/boot" ]]; then
        echo "ERR|cannot_umount_system"
        return 1
    fi

    if command -v udisksctl &>/dev/null; then
        udisksctl unmount -b "$(findmnt -nlo SOURCE "$path" 2>/dev/null)" 2>/dev/null && {
            echo "OK|unmounted=${path}"
            rx_log_file "info" "Unmounted ${path} (udisks)"
            return 0
        }
    fi

    $SUDO_CMD umount "$path" 2>/dev/null && {
        echo "OK|unmounted=${path}"
        rx_log_file "info" "Unmounted ${path}"
        return 0
    }
    echo "ERR|umount_failed"
    return 1
}

_btrfs_subvol_list() {
    local path="${1:-/}"
    $SUDO_CMD btrfs subvolume list "$path" 2>/dev/null | while IFS= read -r line; do
        local id=$(echo "$line" | grep -oP 'ID \K[0-9]+')
        local gen=$(echo "$line" | grep -oP 'gen \K[0-9]+')
        local level=$(echo "$line" | grep -oP 'top level \K[0-9]+')
        local subpath=$(echo "$line" | grep -oP 'path \K.*')
        echo "${id}|${subpath}|${gen}|${level}"
    done
}

_btrfs_quota_show() {
    local path="${1:-/}"
    $SUDO_CMD btrfs qgroup show "$path" 2>/dev/null | tail -n +3 | while IFS= read -r line; do
        local id=$(echo "$line" | awk '{print $1}')
        local rfer=$(echo "$line" | awk '{print $2}')
        local excl=$(echo "$line" | awk '{print $3}')
        [[ -n $id ]] && echo "${id}|${rfer}|${excl}"
    done
}

_is_btrfs() {
    local path="${1:-/}"
    local fstype
    fstype=$(findmnt -nlo FSTYPE "$path" 2>/dev/null)
    [[ $fstype == "btrfs" ]] && return 0
    return 1
}

case "$1" in
    "--status")
        while IFS='|' read -r name size model dtype rota; do
            [[ -z $name ]] && continue
            human_type=$(_get_disk_type "$name" "$rota" "$model")
            health=$(_get_smart_health "$name")
            temp=$(_get_smart_temp "$name")
            wear=$(_get_wear_level "$name")
            IFS='|' read -r used mounts <<< "$(_get_disk_usage "$name")"
            echo "${name}|${human_type}|${model}|${size}|${used:-0}|${health}|${temp}|${mounts}|${wear}"
        done < <(_get_disks)
        ;;

    "--health")
        target="$2"
        if [[ -n $target ]]; then
            echo "device|${target}"
            echo "status|$(_get_smart_health "$target")"
            echo "temp|$(_get_smart_temp "$target")"
            _get_smart_attributes "$target"
        else
            while IFS='|' read -r name size model dtype rota; do
                [[ -z $name ]] && continue
                health=$(_get_smart_health "$name")
                echo "${name}|${size}|${model}|${dtype}|${health}|$(_get_smart_temp "$name")"
            done < <(_get_disks)
        fi
        ;;

    "--list")
        _get_disks
        ;;

    "--mount")
        dev="$2"
        path="$3"
        [[ -z $dev ]] && echo "ERR|missing_device" && exit 1
        _mount_device "$dev" "$path"
        ;;

    "--umount")
        path="$2"
        [[ -z $path ]] && echo "ERR|missing_path" && exit 1
        _umount_device "$path"
        ;;

    "--btrfs-list")
        btrfs_path="${2:-/}"
        _is_btrfs "$btrfs_path" || { echo "ERR|not_btrfs"; exit 1; }
        _btrfs_subvol_list "$btrfs_path"
        ;;

    "--btrfs-quota")
        btrfs_path="${2:-/}"
        _is_btrfs "$btrfs_path" || { echo "ERR|not_btrfs"; exit 1; }
        _btrfs_quota_show "$btrfs_path"
        ;;

    "--btrfs-check")
        _is_btrfs "$2" && echo "yes" || echo "no"
        ;;

    "--setup-get")
        automount=$(get_var "DISK_AUTOMOUNT" "true")
        btrfs_quota=$(get_var "DISK_BTRFS_QUOTA" "false")
        echo "automount=${automount}"
        echo "btrfs_quota=${btrfs_quota}"
        ;;

    "--setup-apply")
        automount="true"
        btrfs_quota="false"
        for arg in "$@"; do
            case "$arg" in
                automount=*) automount="${arg#automount=}" ;;
                btrfs_quota=*) btrfs_quota="${arg#btrfs_quota=}" ;;
            esac
        done
        set_var "DISK_AUTOMOUNT" "$automount"
        set_var "DISK_BTRFS_QUOTA" "$btrfs_quota"
        if [[ $btrfs_quota == "true" ]]; then
            _is_btrfs "/" && $SUDO_CMD btrfs quota enable / 2>/dev/null
        fi

        if command -v smartctl &>/dev/null; then
            smartctl_path=$(command -v smartctl)
            sudoers_file="/etc/sudoers.d/99-smartctl"
            rule="%wheel ALL=(ALL) NOPASSWD: ${smartctl_path}"
            if [[ ! -f $sudoers_file ]]; then
                export RULE="$rule" SUDO_CMD
                if timeout 10 bash -c 'echo "$RULE" | $SUDO_CMD tee "$1" >/dev/null 2>&1 && $SUDO_CMD chmod 0440 "$1"' _ "$sudoers_file"; then
                    rx_log_file "success" "Created ${sudoers_file} — passwordless smartctl enabled"
                else
                    rx_log_file "warn" "Could not create ${sudoers_file} (sudo not available in non-TTY context)."
                    rx_log_file "warn" "Run: echo '${rule}' | sudo tee ${sudoers_file} && sudo chmod 0440 ${sudoers_file}"
                fi
            else
                rx_log_file "info" "${sudoers_file} already exists — skipping"
            fi
        else
            rx_log_file "warn" "smartctl not found — install smartmontools for SMART data"
        fi

        echo "OK|automount=${automount}|btrfs_quota=${btrfs_quota}"
        rx_log_file "success" "Disk setup: automount=${automount}, btrfs_quota=${btrfs_quota}"
        ;;

    *)
        echo "Usage: $0 --{status|health|list|mount|umount|btrfs-list|btrfs-quota|btrfs-check|setup-get|setup-apply} [args]"
        exit 1
        ;;
esac
