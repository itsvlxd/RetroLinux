#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_config() {
    rx_load_state

    if [[ $RX_DEBUG == 1 ]]; then
        gum style --foreground 3 --padding "1 0 1 $PADDING_LEFT" "[DEBUG] DISK_SELECTED='$DISK_SELECTED'"
        sleep 2
    fi

    rx_step "Writing configuration..."

    if [[ -z $DISK_SELECTED ]]; then
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: No disk selected"
        gum style --padding "0 0 0 $PADDING_LEFT" "Please go back and select a disk"
        echo
        rx_retry_or_exit "No disk selected" || rx_abort
        return 1
    fi

    local disk_size
    local retry=0
    local max_retries=3
    while ((retry < max_retries)); do
        disk_size=$(lsblk -bdno SIZE "$DISK_SELECTED" 2>/dev/null)
        if [[ -n $disk_size ]]; then
            break
        fi
        ((retry++))
        if ((retry < max_retries)); then
            gum style --foreground 3 --padding "1 0 1 $PADDING_LEFT" "Retrying disk read ($retry/$max_retries)..."
            sleep 1
        fi
    done

    if [[ -z $disk_size ]]; then
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not read disk size"
        gum style --padding "0 0 0 $PADDING_LEFT" "Selected: $DISK_SELECTED"
        echo
        rx_retry_or_exit "Cannot read disk" || rx_abort
        return 1
    fi

    local sys_lang="${SYS_LANG:-en_US.UTF-8}"
    local sys_enc="UTF-8"
    if [[ "$sys_lang" == *.* ]]; then
        sys_enc="${sys_lang##*.}"
        sys_lang="${sys_lang%.*}.${sys_enc}"
    fi

    local password_escaped
    if ! password_escaped=$(echo -n "$USER_PASSWORD" | jq -Rsa); then
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process password"
        echo
        rx_retry_or_exit "JSON processing failed" || rx_abort
        return 1
    fi

    local password_hash_escaped
    if ! password_hash_escaped=$(echo -n "$USER_PASSWORD_HASH" | jq -Rsa); then
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process password hash"
        echo
        rx_retry_or_exit "JSON processing failed" || rx_abort
        return 1
    fi

    local username_escaped
    if ! username_escaped=$(echo -n "$USER_NAME" | jq -Rsa); then
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process username"
        echo
        rx_retry_or_exit "JSON processing failed" || rx_abort
        return 1
    fi

    cat <<EOF >user_credentials.json
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
EOF

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

    cat <<EOF >user_configuration.json
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
    "hostname": "$USER_HOSTNAME",
    "kernels": [ "linux" ],
    "network_config": { "type": "iso" },
    "ntp": true,
    "parallel_downloads": 8,
    "script": null,
    "services": [],
    "swap": true,
    "timezone": "$USER_TIMEZONE",
    "locale_config": {
        "kb_layout": "$KEYBOARD",
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
EOF

    return 0
}

if ! setup_config; then
    rx_setup_fail "Config"
fi