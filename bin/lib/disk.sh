#!/bin/bash

rx_get_disk_info() {
    local device="$1"
    local size vendor model label

    size=$(lsblk -dno SIZE "$device" 2>/dev/null)
    vendor=$(lsblk -dno VENDOR "$device" 2>/dev/null | sed 's/ *$//')
    model=$(lsblk -dno MODEL "$device" 2>/dev/null | sed 's/ *$//')

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

    local display="$device"
    [[ -n $size ]] && display="$display ($size)"
    [[ -n $label ]] && display="$display - $label"

    local part_summary
    part_summary=$(lsblk -nro TYPE,NAME,FSTYPE,MOUNTPOINT "$device" 2>/dev/null |
        awk '$1=="part" { printf "%s%s%s", s, ($3==""?"?":$3), ($4==""?"":"("$4")"); s=", " }')
    [[ -n $part_summary ]] && display+=" [$part_summary]"

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

rx_write_configuration() {
    local password="$1"
    local username="$2"
    local hostname="$3"
    local timezone="$4"
    local keyboard="$5"
    local sys_lang="$6"
    local sys_enc="$7"

    local password_escaped
    password_escaped=$(echo -n "$password" | jq -Rsa) || {
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process password"
        echo
        rx_retry_or_exit "JSON processing failed" || rx_abort
        return 1
    }

    local password_hash_escaped
    password_hash_escaped=$(echo -n "$USER_PASSWORD_HASH" | jq -Rsa) || {
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process password hash"
        echo
        rx_retry_or_exit "JSON processing failed" || rx_abort
        return 1
    }

    local username_escaped
    username_escaped=$(echo -n "$username" | jq -Rsa) || {
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process username"
        echo
        rx_retry_or_exit "JSON processing failed" || rx_abort
        return 1
    }

    cat <<-_EOF_ >user_credentials.json
{
    "encryption_password": $password_escaped,
    "root_enc_password": $password_hash_escaped,
    "users": [
        {
            "enc_password": $password_hash_escaped,
            "groups": [],
            "sudo": true,
            "username": $username_escaped
        }
    ]
}
_EOF_

    local disk_size
    disk_size=$(lsblk -bdno SIZE "$DISK_SELECTED" 2>/dev/null) || {
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not read disk size"
        echo
        rx_retry_or_exit "Cannot read disk" || rx_abort
        return 1
    }

    local mib=$((1024 * 1024))
    local gib=$((mib * 1024))
    local disk_size_in_mib=$((disk_size / mib * mib))

    local gpt_backup_reserve=$((mib))
    local boot_partition_start=$((mib))
    local boot_partition_size=$((2 * gib))

    local main_partition_start=$((boot_partition_size + boot_partition_start))
    local main_partition_size=$((disk_size_in_mib - main_partition_start - gpt_backup_reserve))

    if [[ $main_partition_size -le 0 ]]; then
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Disk is too small"
        gum style --padding "0 0 0 $PADDING_LEFT" "Minimum 2GB required"
        echo
        rx_retry_or_exit "Disk too small" || rx_abort
        return 1
    fi

    cat <<-_EOF_ >user_configuration.json
{
    "app_config": null,
    "archinstall-language": "English",
    "auth_config": {},
    "audio_config": { "audio": "pipewire" },
    "bootloader": "grub",
    "custom_commands": [],
    "disk_config": {
        "btrfs_options": {},
        "config_type": "default_layout",
        "device_modifications": [
            {
                "device": "$DISK_SELECTED",
                "partitions": [
                    {
                        "btrfs": [],
                        "dev_path": null,
                        "flags": [ "boot", "esp" ],
                        "fs_type": "fat32",
                        "mount_options": [],
                        "mountpoint": "/boot",
                        "obj_id": "ea21d3f2-82bb-49cc-ab5d-6f81ae94e18d",
                        "size": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $boot_partition_size
                        },
                        "start": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $boot_partition_start
                        },
                        "status": "create",
                        "type": "primary"
                    },
                    {
                        "btrfs": [
                            { "mountpoint": "/", "name": "@" },
                            { "mountpoint": "/home", "name": "@home" },
                            { "mountpoint": "/var/log", "name": "@log" },
                            { "mountpoint": "/var/cache/pacman/pkg", "name": "@pkg" }
                        ],
                        "dev_path": null,
                        "flags": [],
                        "fs_type": "btrfs",
                        "mount_options": [ "compress=zstd" ],
                        "mountpoint": null,
                        "obj_id": "8c2c2b92-1070-455d-b76a-56263bab24aa",
                        "size": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $main_partition_size
                        },
                        "start": {
                            "sector_size": { "unit": "B", "value": 512 },
                            "unit": "B",
                            "value": $main_partition_start
                        },
                        "status": "create",
                        "type": "primary"
                    }
                ],
                "wipe": true
            }
        ],
        "disk_encryption": {
            "encryption_type": "luks",
            "lvm_volumes": [],
            "iter_time": 2000,
            "partitions": [ "8c2c2b92-1070-455d-b76a-56263bab24aa" ],
            "encryption_password": $password_escaped
        }
    },
    "hostname": "$hostname",
    "kernels": [ "linux" ],
    "network_config": { "type": "iso" },
    "ntp": true,
    "parallel_downloads": 8,
    "script": null,
    "services": [],
    "swap": true,
    "timezone": "$timezone",
    "locale_config": {
        "kb_layout": "$keyboard",
        "sys_enc": "$sys_enc",
        "sys_lang": "$sys_lang"
    },
    "mirror_config": {
        "custom_repositories": [],
        "custom_servers": [
            {"url": "https://geo.mirror.pkgbuild.com/\$repo/os/\$arch"}
        ],
        "mirror_regions": {},
        "optional_repositories": []
    },
    "packages": [
        "base-devel",
        "git",
        "neovim"
    ],
    "profile_config": {
        "gfx_driver": null,
        "greeter": null,
        "profile": {}
    },
    "version": "3.0.9"
}
_EOF_
    return 0
}