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

    local sys_lang="${SYS_LANG:-en_US}"
    local sys_enc="UTF-8"
    if [[ "$sys_lang" == *.* ]]; then
        sys_enc="${sys_lang##*.}"
        sys_lang="${sys_lang%%.*}"
    fi

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

    local luks_password_json="null"
    local luks_iter_time="null"
    local luks_enc_type="null"
    if [[ "$LUKS_ENABLED" == "true" && -n "$LUKS_PASSWORD" ]]; then
        local luks_pw_escaped
        luks_pw_escaped=$(echo -n "$LUKS_PASSWORD" | jq -Rsa)
        luks_password_json="$luks_pw_escaped"
        luks_iter_time="${LUKS_ITER_TIME:-2000}"
        luks_enc_type="luks"
    fi

    local root_pw_escaped
    if ! root_pw_escaped=$(echo -n "$ROOT_PASSWORD" | jq -Rsa 2>/dev/null); then
        rx_clear_logo; echo; gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process root password"; echo; rx_retry_or_exit "JSON processing failed" || rx_abort; return 1; fi

    local user_pw_escaped
    if ! user_pw_escaped=$(echo -n "$USER_PASSWORD" | jq -Rsa 2>/dev/null); then
        rx_clear_logo; echo; gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process user password"; echo; rx_retry_or_exit "JSON processing failed" || rx_abort; return 1; fi

    local username_escaped
    if ! username_escaped=$(echo -n "$USER_NAME" | jq -Rsa 2>/dev/null); then
        rx_clear_logo; echo; gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process username"; echo; rx_retry_or_exit "JSON processing failed" || rx_abort; return 1; fi

    local bluetooth_json="false"
    if [[ "$BLUETOOTH_ENABLED" == "true" ]]; then
        bluetooth_json="true"
    fi

    local print_json="false"
    if [[ "$PRINT_SERVICE_ENABLED" == "true" ]]; then
        print_json="true"
    fi

    local encryption_password_escaped="null"
    if [[ "$LUKS_ENABLED" == "true" && -n "$LUKS_PASSWORD" ]]; then
        if ! encryption_password_escaped=$(echo -n "$LUKS_PASSWORD" | jq -Rsa 2>/dev/null); then
            rx_clear_logo; echo; gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Could not process LUKS password"; echo; rx_retry_or_exit "JSON processing failed" || rx_abort; return 1; fi
    fi

    local sudo_json="false"
    if [[ "$USER_SUDO" == "true" ]]; then
        sudo_json="true"
    fi

    cat >user_credentials.json <<EOF
{
    "encryption_password": $encryption_password_escaped,
    "!root_password": $root_pw_escaped,
    "users": [
        {
            "!password": $user_pw_escaped,
            "groups": [],
            "sudo": $sudo_json,
            "username": $username_escaped
        }
    ]
}
EOF

    local luks_block="null"
    if [[ "$LUKS_ENABLED" == "true" && -n "$LUKS_PASSWORD" ]]; then
        luks_block=$(jq -n \
            --arg enc "$luks_enc_type" \
            --argjson iter "$luks_iter_time" \
            --argjson parts '["6c6490d5-7399-4bc1-b32b-fe527ccd75bf"]' \
            '{
                encryption_type: $enc,
                lvm_volumes: [],
                iter_time: $iter,
                partitions: $parts
            }')
    fi

    local user_config_json
    user_config_json=$(jq -n \
        --arg device "$DISK_SELECTED" \
        --argjson boot_size "$boot_partition_size" \
        --argjson boot_start "$boot_partition_start" \
        --argjson main_size "$main_partition_size" \
        --argjson main_start "$main_partition_start" \
        --arg hostname "$USER_HOSTNAME" \
        --arg kernel "$KERNEL_SELECTION" \
        --arg kb "$KEYBOARD" \
        --arg sys_lang "$sys_lang" \
        --arg sys_enc "$sys_enc" \
        --arg timezone "$USER_TIMEZONE" \
        --argjson bluetooth "$bluetooth_json" \
        --argjson printing "$print_json" \
        --arg mirrors "$MIRROR_REGIONS" \
        --arg custom_mirror "$CUSTOM_MIRRORS" \
        --argjson luks "$luks_block" \
        '{
            app_config: {
                audio_config: { audio: "pipewire" },
                bluetooth_config: { enabled: $bluetooth },
                firewall_config: { firewall: "ufw" },
                print_service_config: { enabled: $printing }
            },
            "archinstall-language": "English",
            auth_config: {},
            bootloader_config: {
                bootloader: "Grub",
                removable: true,
                uki: true
            },
            custom_commands: [],
            disk_config: {
                btrfs_options: {
                    snapshot_config: {
                        type: "Timeshift"
                    }
                },
                config_type: "default_layout",
                device_modifications: [{
                    device: $device,
                    partitions: [
                        {
                            btrfs: [],
                            dev_path: null,
                            flags: ["boot", "esp"],
                            fs_type: "fat32",
                            mount_options: [],
                            mountpoint: "/boot",
                            obj_id: "5e886548-4794-4b97-9535-7c3e34e744ce",
                            size: { sector_size: { unit: "B", value: 512 }, unit: "GiB", value: 1 },
                            start: { sector_size: { unit: "B", value: 512 }, unit: "MiB", value: 1 },
                            status: "create",
                            type: "primary"
                        },
                        {
                            btrfs: [
                                { mountpoint: "/", name: "@" },
                                { mountpoint: "/home", name: "@home" },
                                { mountpoint: "/var/log", name: "@log" },
                                { mountpoint: "/var/cache/pacman/pkg", name: "@pkg" }
                            ],
                            dev_path: null,
                            flags: [],
                            fs_type: "btrfs",
                            mount_options: ["compress=zstd"],
                            mountpoint: null,
                            obj_id: "6c6490d5-7399-4bc1-b32b-fe527ccd75bf",
                            size: { sector_size: { unit: "B", value: 512 }, unit: "B", value: $main_size },
                            start: { sector_size: { unit: "B", value: 512 }, unit: "B", value: $main_start },
                            status: "create",
                            type: "primary"
                        }
                    ],
                    wipe: true
                }]
            } + (if $luks != null then { disk_encryption: $luks } else {} end),
            hostname: $hostname,
            kernels: [$kernel],
            locale_config: {
                kb_layout: $kb,
                sys_enc: $sys_enc,
                sys_lang: $sys_lang
            },
            mirror_config: {
                custom_repositories: [],
                custom_servers: (if $custom_mirror != "" then [{ url: $custom_mirror }] else [] end),
                mirror_regions: (if $mirrors != "" then { ($mirrors): [] } else {} end),
                optional_repositories: []
            },
            network_config: { type: "nm_iwd" },
            ntp: true,
            pacman_config: {
                color: true,
                parallel_downloads: 5
            },
            packages: [],
            profile_config: {
                gfx_driver: "All open-source",
                greeter: "sddm",
                profile: {
                    custom_settings: {
                        Hyprland: {
                            seat_access: "polkit"
                        }
                    },
                    details: ["Hyprland"],
                    main: "Desktop"
                }
            },
            script: null,
            services: [],
            swap: {
                algorithm: "zstd",
                enabled: true
            },
            timezone: $timezone,
            version: "4.3"
        }')

    echo "$user_config_json" >user_configuration.json

    if ! jq empty user_configuration.json 2>/dev/null; then
        rx_clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Error: Generated invalid JSON"
        echo
        rx_retry_or_exit "JSON validation failed" || rx_abort
        return 1
    fi

    return 0
}

if ! setup_config; then
    rx_setup_fail "Config"
fi