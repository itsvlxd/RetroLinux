#!/bin/bash

source "$RETRO_DIR/lib/icons.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/cmds/tools/app.sh"

on_power_disconnect() {
    local cap="$1"
    notify-send -u normal -i battery-caution \
        "Power Disconnected" "Now on battery power (${cap}%)"
}

on_power_connect() {
    local cap="$1"
    if [[ $cap -eq 100 ]]; then
        notify-send -u normal -i battery-full-charging \
            "Power Connected" "Running on AC (Battery bypassed)"
    else
        notify-send -u normal -i battery-charging \
            "Power Connected" "Charging up (${cap}%)"
    fi
}

on_battery_saver_enabled() {
    notify-send -u normal -i power-profile-saver \
        "Battery Saver" "Power draw capped to extend runtime"
}

on_battery_saver_disabled() {
    notify-send -u normal -i power-profile-balanced \
        "Battery Saver" "Standard power limits restored"
}

on_battery_usage_high() {
    local app="$1"
    local watts="$2"
    local cpu="$3"
    local pid="$4"

    ACTION=$(notify-send -a "retro_battery_usage_$app" -u normal -i dialog-warning-symbolic -t 15000 \
        "Battery Usage" \
        "High battery usage detected.\n<b>$app ($pid)</b> is pulling ${watts}W and ${cpu}% CPU" \
        -A "terminate=Terminate Process" \
        -A "ignore=Ignore $app")

    case "$ACTION" in
        "terminate")
            kill -15 "$pid" 2>/dev/null
            ;;
        "ignore")
            local current_list=$(get_var "BAT_IGNORE_APPS")
            if [[ $current_list == "null" || -z $current_list ]]; then
                set_var "BAT_IGNORE_APPS" "$app"
            else
                set_var "BAT_IGNORE_APPS" "${current_list}|$app"
            fi
            ;;
    esac
}

on_battery_low() {
    local cap="$1"

    if [[ $cap == "30" ]]; then
        notify-send -u normal -i battery-low \
            "Battery Low" "${cap}% remaining — find a plug soon"

    fi
}

on_battery_critical() {
    local cap="$1"

    if [[ $cap == "15" ]]; then
        notify-send -u critical -i battery-empty \
            "Battery Critical" "Only ${cap}% left. Connect power now."

    fi
}

on_usb_connected() {
    local label="$1"
    local mount_path="$2"

    local fm_name=$(get_var "RETRO_FILEMANAGER_CMD")
    local fm_display="${fm_name^}"

    (
        ACTION=$(
            notify-send -a "retro_usb_con_$label" -u normal -i drive-removable-media-symbolic -t 10000 -w \
                "USB Drive Detected" \
                "<b>$label</b> has been mounted.\nLocation: $mount_path" \
                -A "open=Open in $fm_display" \
                -A "ignore=Ignore $label"
        )

        case "$ACTION" in
            "open")
                cmd_apps "filemanager" "open" "$mount_path"
                ;;
            "ignore")
                local current_list=$(get_var "USB_IGNORE_DRIVES")
                if [[ $current_list == "null" || -z $current_list ]]; then
                    set_var "USB_IGNORE_DRIVES" "$label"
                else
                    set_var "USB_IGNORE_DRIVES" "${current_list}|$label"
                fi
                rx_log "info" "Drive '$label' added to ignore list."
                ;;
        esac
    ) &
}

on_usb_disconnected() {
    local dev_name="$1"
    local mount_root="$2"
    local ignore_list=$(get_var "USB_IGNORE_DRIVES")

    for link in "$mount_root"/*; do
        if [[ -L $link ]]; then
            local target=$(readlink "$link")

            if [[ ! -e $target ]]; then
                local label=$(basename "$link")

                if [[ "|$ignore_list|" != *"|$label|"* ]]; then
                    notify-send -a "retro_usb_dis_$dev_name" -u normal -i drive-removable-media-symbolic -t 10000 \
                        "USB Drive Removed" \
                        "Drive <b>$label</b> ($dev_name) has been disconnected."
                fi

                rm "$link"
            fi
        fi
    done
}

on_bluetooth_connected() {
    local name="$1"
    local mac="$2"

    local icon_path=$(rx_get_icon "$name")

    (
        local ACTION=$(notify-send -a "retro_bluetooth_con_$mac" -u normal -i "$icon_path" -t 10000 \
            "Connection Established" \
            "<b>$name</b> ($mac) has been connected successfully." \
            -A "disconnect=Disconnect" \
            -A "forget=Forget Device")

        case "$ACTION" in
            "disconnect")
                rx_log "info" "User requested disconnect for $name ($mac)."
                source "$RETRO_DIR/scripts/bluetooth_core.sh" 2>/dev/null
                bt_disconnect "$mac"
                ;;
            "forget")
                rx_log "info" "User requested to forget device: $name."
                source "$RETRO_DIR/scripts/bluetooth_core.sh" 2>/dev/null
                bt_remove_device "$mac"
                notify-send -u low -i "edit-delete" "Device Forgotten" "$name has been removed from trusted devices."
                ;;
        esac
    ) &
}

on_bluetooth_disconnected() {
    local name="$1"
    local mac="$2"
    local icon_path=$(rx_get_icon "$name")

    notify-send -a "retro_bluetooth_con_$mac" -u normal -i "$icon_path" -t 5000 \
        "Connection Closed" \
        "<b>$name</b> ($mac) is no longer active."
}

on_bluetooth_pairing_request() {
    local name="$1"
    local mac="$2"

    local icon_path=$(rx_get_icon "$name")

    local ACTION=$(notify-send -a "retro_bluetooth_con_$mac" -u critical -i "$icon_path" -w \
        "Bluetooth Pairing Request" \
        "Device <b>$name</b> sent a bluetooth pairing request.\nAddress: $mac" \
        -A "pair=Pair" \
        -A "ignore=Ignore")

    case "$ACTION" in
        "pair")
            local current_locks=$(get_var "BT_PAIRING_IN_PROGRESS")
            set_var "BT_PAIRING_IN_PROGRESS" "$current_locks|$mac"

            rx_log "info" "Starting bt-agent for $name..."

            (
                source "$RETRO_DIR/scripts/bluetooth_core.sh"
                local result
                result=$(bt_pair_with_agent "$mac" "$name")

                local new_locks=$(get_var "BT_PAIRING_IN_PROGRESS" | sed "s/|$mac//g")
                set_var "BT_PAIRING_IN_PROGRESS" "$new_locks"

                if [[ $result == OK* ]]; then
                    rx_log "success" "Pairing complete for $name."
                else
                    rx_log "error" "Pairing failed for $name (${result})."
                fi
            ) &
            ;;

        "ignore")
            local current_ignored=$(get_var "BT_MAC_IGNORE")
            if [[ -z $current_ignored || $current_ignored == "null" ]]; then
                set_var "BT_MAC_IGNORE" "$mac"
            else
                [[ "|$current_ignored|" != *"|$mac|"* ]] && set_var "BT_MAC_IGNORE" "$current_ignored|$mac"
            fi
            rx_log "info" "Added $mac to ignore list."
            ;;
    esac
}

on_pkg_updates_available() {
    local count="$1"
    local sample="$2"

    local ACTION=$(notify-send -u normal -i software-update-available-symbolic -t 20000 \
        "System Updates Available" \
        "<b>$count</b> packages have pending updates.\nIncluding: <i>$sample</i>" \
        -A "update=Update Now" \
        -A "later=Remind Later")

    if [[ $ACTION == "update" ]]; then
        hyprctl dispatch exec "[float; size 1000 700; center] kitty -- bash $RETRO_DIR/scripts/lib/system_update.sh $count $sample" &
    fi
}

on_retro_update_available() {
    local commits="$1"

    local ACTION=$(notify-send -u normal -i software-update-available-symbolic -t 20000 \
        "Retro Update Available" \
        "RetroLinux has some new updates. \n<b>$commits</b> new commits have been added." \
        -A "update=Update" \
        -A "later=Remind me later")

    if [[ $ACTION == "update" ]]; then
        hyprctl dispatch exec "[float; size 1000 700; center] kitty -- bash -c 'cd $RETRO_DIR && bash retro.sh --update; echo; echo Press Enter to close.; read'" &
    fi
}
