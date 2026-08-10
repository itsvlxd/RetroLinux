#!/bin/bash

rx_get_disk_info() {
    local device="$1"
    local size vendor model label

    size=$(lsblk -dno SIZE "$device" 2>/dev/null | tr -d ' ')
    vendor=$(lsblk -dno VENDOR "$device" 2>/dev/null | xargs 2>/dev/null)
    model=$(lsblk -dno MODEL "$device" 2>/dev/null | xargs 2>/dev/null)

    label=""
    if [[ -n $vendor && -n $model ]]; then
        if [[ $model == *$vendor* ]]; then
            label="$model"
        else
            label="$vendor $model"
        fi
    elif [[ -n $model ]]; then
        label="$model"
    elif [[ -n $vendor ]]; then
        label="$vendor"
    fi

    local part_count=0
    part_count=$(lsblk -nro PARTNAME "$device" 2>/dev/null | grep -c '[a-zA-Z0-9]' || true)
    part_count=${part_count:-0}
    part_count=$((part_count + 0))

    local display="$device"
    [[ -n $size ]] && display="$display ($size)"
    [[ -n $label ]] && display="$display - $label"

    if [[ $part_count -gt 0 ]]; then
        local part_summary
        part_summary=$(lsblk -nro TYPE,FSTYPE,MOUNTPOINT "$device" 2>/dev/null |
            awk '$1=="part" && $2!="" { printf "%s%s%s", s, ($3==""?"?":$3), ($4==""?"":"("$4")"); s=", " }')
        [[ -n $part_summary ]] && display+=" [$part_summary]"
    fi

    echo "$display"
}

rx_get_available_disks() {
    local exclude_disk
    exclude_disk=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)

    local available_disks
    available_disks=$(
        lsblk -dpno NAME,TYPE 2>/dev/null |
            awk '$2=="disk"{print $1}' |
            grep -E '/dev/(sd|hd|vd|nvme|mmcblk|xv)' |
            { if [[ -n $exclude_disk ]]; then grep -Fvx "$exclude_disk"; else cat; fi; }
    ) || return 1

    echo "$available_disks"
}

rx_is_laptop() {
    local battery_path
    battery_path=$(find /sys/class/power_supply/ -name "BAT*" -type l 2>/dev/null | head -n 1)
    [[ -n $battery_path && -d $battery_path ]]
}

rx_disk_has_partitions() {
    local device="$1"
    local partitions
    partitions=$(lsblk -nro TYPE "$device" 2>/dev/null | grep -c "part" || echo "0")
    [[ "$partitions" -gt 0 ]]
}

rx_confirm_disk_wipe() {
    rx_clear_logo
    echo
    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Warning: This will erase ALL data on $DISK_SELECTED"
    gum style --padding "0 0 0 $PADDING_LEFT" "There is no going back from this point."
    echo

    if gum confirm --affirmative "Yes, wipe disk" --negative "No, go back" "Confirm disk wipe" --padding "$GUM_CONFIRM_PADDING"; then
        return 0
    else
        return 1
    fi
}

