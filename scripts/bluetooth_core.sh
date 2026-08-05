#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/icons.sh"
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "bluetooth"

bt_power_on() {
    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock bluetooth
    fi

    if bluetoothctl power on >/dev/null 2>&1; then
        rx_log_file "info" "Bluetooth radio powered ON"
        echo "OK|on"
    else
        rx_log_file "error" "Bluetooth power ON failed"
        echo "ERR|power_on_failed"
    fi
}

bt_power_off() {
    if bluetoothctl power off >/dev/null 2>&1; then
        rx_log_file "info" "Bluetooth radio powered OFF"
        echo "OK|off"
    else
        rx_log_file "error" "Bluetooth power OFF failed"
        echo "ERR|power_off_failed"
    fi
}

get_bt_status() {
    local controller_mac=$(bluetoothctl show | grep "Controller" | awk '{print $2}')

    local adapter="unknown"
    if [[ -n $controller_mac ]]; then
        for d in /sys/class/bluetooth/hci*; do
            if [[ -d $d ]] && grep -qi "$controller_mac" "$d/address" 2>/dev/null; then
                adapter=$(basename "$d")
                break
            fi
        done
    fi

    [[ $adapter == "unknown" && -d /sys/class/bluetooth/hci0 ]] && adapter="hci0"

    local bt_info=$(bluetoothctl show)
    local radio_on=$(echo "$bt_info" | grep -i "Powered:" | awk '{print $2}' | xargs)
    local disc=$(echo "$bt_info" | grep -i "Discoverable:" | awk '{print $2}' | xargs)
    local pair=$(echo "$bt_info" | grep -i "Pairable:" | awk '{print $2}' | xargs)

    local hw_mode="OFFLINE"
    if [[ $adapter != "unknown" ]]; then
        local hci_path="/sys/class/bluetooth/$adapter/device/power"
        local pwr_ctrl=$(cat "$hci_path/control" 2>/dev/null || echo "on")
        local pwr_stat=$(cat "$hci_path/runtime_status" 2>/dev/null || echo "active")

        hw_mode="NORMAL"
        [[ $pwr_ctrl == "auto" || $pwr_stat == "suspended" ]] && hw_mode="SAVER"
    fi

    local chip_name="Unknown Adapter"
    if [[ $adapter != "unknown" ]]; then
        chip_name=$(lsusb -d $(cat /sys/class/bluetooth/$adapter/device/uevent | grep "PRODUCT" | cut -d= -f2 | tr '/' ':') 2>/dev/null | cut -d' ' -f7-)
        [[ -z $chip_name ]] && chip_name="Bluetooth Adapter ($adapter)"
    fi

    local ver="5.x"
    if command -v btmgmt >/dev/null 2>&1; then
        local lmp=$(timeout 2 btmgmt info 2>/dev/null | grep -i "ver" | awk '{print $4}' | head -n 1)
        case "$lmp" in 13) ver="5.4" ;; 12) ver="5.3" ;; 11) ver="5.2" ;; 10) ver="5.1" ;; 9) ver="5.0" ;; esac
    fi

    local conns=$(bluetoothctl devices Connected | wc -l)

    echo "${radio_on:-no}|${hw_mode}|${disc:-no}|${pair:-no}|${chip_name}|${ver}|${conns}|${adapter}|${controller_mac}"
}

get_nearby() {
    local check_count=0
    local is_scanning="no"

    while [[ $check_count -lt 3 ]]; do
        is_scanning=$(bluetoothctl show 2>/dev/null | grep -i "Discovering:" | awk '{print $2}' | xargs)
        [[ $is_scanning == "yes" ]] && break
        sleep 0.2
        ((check_count++))
    done

    if [[ $is_scanning != "yes" ]]; then
        echo "ERR_SCAN_OFF"
        return 1
    fi

    local paired_macs
    paired_macs=$(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}')

    bluetoothctl devices 2>/dev/null | while read -r line; do
        [[ -z $line ]] && continue
        local mac=$(echo "$line" | awk '{print $2}')
        if [[ ! $paired_macs =~ $mac ]]; then
            echo "$line"
        fi
    done
}

toggle_discovery() {
    local info=$(bluetoothctl show)
    local current=$(echo "$info" | grep -i "Discoverable:" | awk '{print $2}' | xargs)

    if [[ $current == "yes" ]]; then
        bluetoothctl discoverable off >/dev/null 2>&1
        bluetoothctl pairable off >/dev/null 2>&1
        echo "off"
    else
        bluetoothctl discoverable on >/dev/null 2>&1
        bluetoothctl pairable on >/dev/null 2>&1
        bluetoothctl discoverable-timeout 180 >/dev/null 2>&1
        echo "on"
    fi
}

is_device_phone() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    local uuids
    uuids=$(bluetoothctl info "$mac" 2>/dev/null | grep "UUID:" | sed 's/.*(//; s/).*//')
    echo "$uuids" | grep -qi "^0000112f\|^0000112d\|^00001132" && echo "true" || echo "false"
}

is_device_computer() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    local class_hex
    class_hex=$(bluetoothctl info "$mac" 2>/dev/null | grep "Class:" | awk '{print $2}' | xargs)
    [[ -z $class_hex ]] && echo "false" && return

    local class_dec
    class_dec=$(printf '%d\n' "$class_hex" 2>/dev/null || echo "0")
    local major=$(((class_dec >> 8) & 0x1F))
    [[ $major -eq 1 ]] && echo "true" || echo "false"
}

is_device_audio_capable() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    local uuids
    uuids=$(bluetoothctl info "$mac" 2>/dev/null | grep "UUID:" | sed 's/.*(//; s/).*//')
    echo "$uuids" | grep -qi "^0000110b\|^0000110a\|^00001108\|^0000111e\|^0000111f" && echo "true" || echo "false"
}

is_device_input_capable() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    local uuids
    uuids=$(bluetoothctl info "$mac" 2>/dev/null | grep "UUID:" | sed 's/.*(//; s/).*//')
    echo "$uuids" | grep -qi "^00001124\|^00001126\|^00001812\|^00001813\|^00001816\|^00001805\|^00001806\|^0000180a" && echo "true" || echo "false"
}

is_device_gamepad() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    local class_hex
    class_hex=$(bluetoothctl info "$mac" 2>/dev/null | grep "Class:" | awk '{print $2}' | xargs)
    [[ -z $class_hex ]] && class_hex=$(bluetoothctl info "$mac" 2>/dev/null | grep "^[[:space:]]*Class:" | awk '{print $3}' | tr -d '()' | xargs)

    local icon_val
    icon_val=$(bluetoothctl info "$mac" 2>/dev/null | grep "Icon:" | awk '{print $2}' | xargs)

    if [[ $icon_val == *"gamepad"* || $icon_val == *"input-gaming"* || $icon_val == *"joystick"* ]]; then
        echo "true"
        return
    fi

    [[ -z $class_hex ]] && echo "false" && return

    local class_dec
    class_dec=$(printf '%d\n' "$class_hex" 2>/dev/null || echo "0")
    local major=$(((class_dec >> 8) & 0x1F))
    local minor=$(((class_dec >> 2) & 0x3F))

    if [[ $major -eq 5 ]] && [[ $minor -ge 1 && $minor -le 15 ]]; then
        echo "true"
    else
        echo "false"
    fi
}

get_device_category() {
    local mac="$1"
    [[ -z $mac ]] && echo "other" && return

    local is_phone is_computer is_audio is_input is_gamepad
    is_phone=$(is_device_phone "$mac")
    is_computer=$(is_device_computer "$mac")
    is_audio=$(is_device_audio_capable "$mac")
    is_input=$(is_device_input_capable "$mac")
    is_gamepad=$(is_device_gamepad "$mac")

    if [[ $is_phone == "true" ]]; then
        echo "phone"
    elif [[ $is_computer == "true" ]]; then
        echo "computer"
    elif [[ $is_gamepad == "true" ]]; then
        echo "controller"
    elif [[ $is_audio == "true" && $is_input == "true" ]]; then
        echo "audio+input"
    elif [[ $is_audio == "true" ]]; then
        echo "audio"
    elif [[ $is_input == "true" ]]; then
        echo "input"
    else
        echo "other"
    fi
}

decode_type_icon() {
    local type="$1"
    case "$type" in
        phone) echo "pho" ;;
        computer) echo "pc" ;;
        audio) echo "aud" ;;
        audio+input) echo "aud+in" ;;
        controller) echo "ctrl" ;;
        input) echo "in" ;;
        *) echo "unk" ;;
    esac
}

get_bt_device_class_decoded() {
    local mac="$1"
    [[ -z $mac ]] && echo "unknown" && return

    local class_hex
    class_hex=$(bluetoothctl info "$mac" 2>/dev/null | grep "Class:" | awk '{print $2}' | xargs)
    [[ -z $class_hex ]] && echo "unknown" && return

    local class_dec
    class_dec=$(printf '%d\n' "$class_hex" 2>/dev/null || echo "0")
    local major=$(((class_dec >> 8) & 0x1F))
    local minor=$(((class_dec >> 2) & 0x3F))

    if [[ $major -eq 4 ]]; then
        case $minor in
            4) echo "Wearable Headset" ;;
            5) echo "Hands-free" ;;
            6 | 10) echo "Headphones" ;;
            7 | 13) echo "HiFi Audio" ;;
            8) echo "Microphone" ;;
            9) echo "Loudspeaker" ;;
            11) echo "Portable Audio" ;;
            20) echo "Gaming/Toy" ;;
            21) echo "Gaming Controller" ;;
            *) echo "Audio Device" ;;
        esac
    elif [[ $major -eq 5 ]]; then
        case $minor in
            1) echo "Keyboard" ;;
            2) echo "Pointing Device" ;;
            3) echo "Combo Keyboard/Mouse" ;;
            *) echo "Input Device" ;;
        esac
    elif [[ $major -eq 7 ]]; then
        echo "Wearable"
    elif [[ $major -eq 2 ]]; then
        echo "Phone"
    elif [[ $major -eq 1 ]]; then
        echo "Computer"
    else
        echo "Unknown"
    fi
}

get_nearby_detailed() {
    local check_count=0
    local is_scanning="no"

    while [[ $check_count -lt 3 ]]; do
        is_scanning=$(bluetoothctl show 2>/dev/null | grep -i "Discovering:" | awk '{print $2}' | xargs)
        [[ $is_scanning == "yes" ]] && break
        sleep 0.2
        ((check_count++))
    done

    if [[ $is_scanning != "yes" ]]; then
        echo "ERR_SCAN_OFF"
        return 1
    fi

    local paired_macs
    paired_macs=$(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}')

    bluetoothctl devices 2>/dev/null | while read -r line; do
        [[ -z $line ]] && continue
        local mac=$(echo "$line" | awk '{print $2}')
        [[ $paired_macs =~ $mac ]] && continue

        local device_type type_code class_name name
        device_type=$(get_device_category "$mac")
        type_code=$(decode_type_icon "$device_type")
        class_name=$(get_bt_device_class_decoded "$mac")
        name=$(echo "$line" | cut -d' ' -f3-)

        echo "$type_code|$class_name|$device_type|$mac|$name"
    done
}

get_paired_detailed() {
    bluetoothctl devices Paired 2>/dev/null | while read -r line; do
        [[ -z $line ]] && continue
        local mac=$(echo "$line" | awk '{print $2}')

        local device_type type_code class_name name connected
        device_type=$(get_device_category "$mac")
        type_code=$(decode_type_icon "$device_type")
        class_name=$(get_bt_device_class_decoded "$mac")
        name=$(echo "$line" | cut -d' ' -f3-)
        bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes" && connected="yes" || connected="no"

        echo "$type_code|$class_name|$device_type|$mac|$name|$connected"
    done
}

get_device_battery() {
    local mac="$1"
    [[ -z $mac ]] && echo "" && return
    bluetoothctl info "$mac" 2>/dev/null \
        | grep "Battery Percentage:" \
        | grep -o '([0-9]*)' \
        | tr -d '()'
}

get_audio_card_for_mac() {
    local mac="$1"
    [[ -z $mac ]] && return

    local mac_underscored="${mac//:/_}"
    pactl list cards short 2>/dev/null | awk '{print $2}' | grep -i "${mac_underscored}" | head -1
}

get_audio_profile() {
    local card="$1"
    [[ -z $card ]] && return

    pactl list cards 2>/dev/null | sed -n '/Name: .*'"$card"'/,/Ports:/p' | grep "Active Profile:" | awk '{print $3}' | tr -d '\n' | xargs
}

get_audio_codec() {
    local card="$1"
    [[ -z $card ]] && return

    local active
    active=$(pactl list cards 2>/dev/null | sed -n '/Name: .*'"$card"'/,/Ports:/p' | grep "Active Profile:" | awk '{print $3}' | tr -d '\n' | xargs)

    case "$active" in
        *sbc_xq*) echo "SBC-XQ" ;;
        *msbc*) echo "MSBC" ;;
        *cvsd*) echo "CVSD" ;;
        *ldac*) echo "LDAC" ;;
        *aptx_hd* | *aptx-hd*) echo "aptX HD" ;;
        *aptx*) echo "aptX" ;;
        *aac*) echo "AAC" ;;
        *opus*) echo "Opus" ;;
        *sbc*) echo "SBC" ;;
        *headset*) echo "MSBC" ;;
        *a2dp*) echo "SBC" ;;
        *off*) echo "off" ;;
        *) echo "${active:-unknown}" ;;
    esac
}

get_available_profiles() {
    local card="$1"
    [[ -z $card ]] && return

    pactl list cards 2>/dev/null | sed -n '/Name: .*'"$card"'/,/Ports:/p' | grep -vE "^\s+(device|api|spa|bluez|factory|client|object|media)" | grep -E "^\s+[a-z].*:" | head -20
}

profile_display_name() {
    local profile="$1"
    case "$profile" in
        *a2dp-sink*aac*) echo "High Fidelity Playback (A2DP Sink, codec AAC)" ;;
        *a2dp-sink*ldac*) echo "High Fidelity Playback (A2DP Sink, codec LDAC)" ;;
        *a2dp-sink*aptx_hd* | *a2dp-sink*aptx-hd*) echo "High Fidelity Playback (A2DP Sink, codec aptX HD)" ;;
        *a2dp-sink*aptx*) echo "High Fidelity Playback (A2DP Sink, codec aptX)" ;;
        *a2dp-sink*opus*) echo "High Fidelity Playback (A2DP Sink, codec Opus)" ;;
        *a2dp-sink*sbc_xq*) echo "High Fidelity Playback (A2DP Sink, codec SBC-XQ)" ;;
        *a2dp-sink*sbc*) echo "High Fidelity Playback (A2DP Sink, codec SBC)" ;;
        *a2dp-sink*) echo "High Fidelity Playback (A2DP Sink)" ;;
        *headset-head-unit*msbc*) echo "Headset Head Unit (HSP/HFP, codec MSBC)" ;;
        *headset-head-unit-cvsd*) echo "Headset Head Unit (HSP/HFP, codec CVSD)" ;;
        *headset-head-unit*) echo "Headset Head Unit (HSP/HFP)" ;;
        *off*) echo "Off" ;;
        *) echo "$profile" ;;
    esac
}

get_profile_info() {
    local mac="$1"
    [[ -z $mac ]] && return

    local card
    card=$(get_audio_card_for_mac "$mac")

    if [[ -z $card ]]; then
        echo "NO_CARD"
        return
    fi

    local active_profile codec profiles_raw
    active_profile=$(get_audio_profile "$card")
    codec=$(get_audio_codec "$card")
    profiles_raw=$(get_available_profiles "$card")

    echo "CARD|$card"
    echo "ACTIVE|$active_profile"
    echo "CODEC|${codec:-unknown}"

    if [[ -n $profiles_raw ]]; then
        echo "$profiles_raw" | while IFS=: read -r profile _; do
            [[ -z $profile ]] && continue
            profile=$(echo "$profile" | xargs)
            [[ -z $profile ]] && continue
            local name is_active=0
            name=$(profile_display_name "$profile")
            [[ $profile == "$active_profile" ]] && is_active=1
            echo "PROFILE|$profile|$is_active|$name"
        done
    fi
}

set_audio_profile() {
    local mac="$1"
    local profile="$2"

    [[ -z $mac || -z $profile ]] && echo "ERR_MISSING_ARGS" && return 1

    local card
    card=$(get_audio_card_for_mac "$mac")

    if [[ -z $card ]]; then
        echo "ERR_NO_CARD"
        return 1
    fi

    local available_profiles
    available_profiles=$(get_available_profiles "$card" | awk -F: '{print $1}' | xargs)
    local found=0
    for p in $available_profiles; do
        [[ "$p" == "$profile" ]] && found=1 && break
    done

    if [[ $found -eq 0 ]]; then
        rx_log_file "error" "Profile $profile not available for $mac"
        echo "ERR_PROFILE_NOT_FOUND"
        return 1
    fi

    if pactl set-card-profile "$card" "$profile" 2>/dev/null; then
        rx_log_file "info" "Audio profile set to $profile for $mac"
        echo "OK|$profile"
    else
        rx_log_file "error" "Failed to set audio profile $profile for $mac"
        echo "ERR_SET_FAILED"
        return 1
    fi
}

normalize_profile() {
    local profile="$1"
    local codec="$2"

    case "$profile" in
        a2dp | a2dp-sink)
            case "$codec" in
                aac | AAC) echo "a2dp-sink" ;;
                ldac | LDAC) echo "a2dp-sink-ldac" ;;
                aptx | aptX) echo "a2dp-sink-aptx" ;;
                sbc-xq | SBC-XQ | sbc_xq) echo "a2dp-sink-sbc_xq" ;;
                sbc | SBC) echo "a2dp-sink-sbc" ;;
                *) echo "a2dp-sink" ;;
            esac
            ;;
        headset | hfp | hsp)
            case "$codec" in
                msbc | MSBC) echo "headset-head-unit" ;;
                cvsd | CVSD) echo "headset-head-unit-cvsd" ;;
                *) echo "headset-head-unit" ;;
            esac
            ;;
        off) echo "off" ;;
        *) echo "$profile" ;;
    esac
}

bt_pair_with_agent() {
    local mac="$1"
    local name="${2:-unknown}"
    [[ -z $mac ]] && echo "ERR_NO_MAC" && return 1

    local is_paired
    is_paired=$(bluetoothctl info "$mac" 2>/dev/null | grep "Paired:" | awk '{print $2}' | xargs)

    bt-agent -c NoInputNoOutput -d >/dev/null 2>&1
    local agent_pid=$!
    sleep 0.5

    if [[ $is_paired != "yes" ]]; then
        bluetoothctl pair "$mac" >/dev/null 2>&1
        local pair_result=$?
        if [[ $pair_result -ne 0 ]]; then
            kill "$agent_pid" 2>/dev/null
            rx_log_file "error" "Pairing failed for $name ($mac)"
            echo "ERR_PAIR_FAILED|$pair_result"
            return 1
        fi
    fi

    bluetoothctl connect "$mac" >/dev/null 2>&1
    local connect_result=$?

    kill "$agent_pid" 2>/dev/null

    if [[ $connect_result -eq 0 ]]; then
        rx_log_file "info" "Connected to $name ($mac)"
        echo "OK|$mac|$name"
        return 0
    else
        rx_log_file "error" "Connection failed for $name ($mac)"
        echo "ERR_CONNECT_FAILED|$connect_result"
        return 1
    fi
}

bt_disconnect() {
    local mac="$1"
    [[ -z $mac ]] && return 1
    bluetoothctl disconnect "$mac" >/dev/null 2>&1
    rx_log_file "info" "Disconnected $mac"
}

bt_reconnect_with_agent() {
    local mac="$1"
    local name="${2:-unknown}"
    [[ -z $mac ]] && echo "ERR_NO_MAC" && return 1

    bt-agent -c NoInputNoOutput -d >/dev/null 2>&1
    local agent_pid=$!
    sleep 0.5

    bluetoothctl connect "$mac" >/dev/null 2>&1
    local connect_result=$?

    kill "$agent_pid" 2>/dev/null

    if [[ $connect_result -eq 0 ]]; then
        rx_log_file "info" "Reconnected to $name ($mac)"
        echo "OK|$mac|$name"
        return 0
    else
        rx_log_file "error" "Reconnection failed for $name ($mac)"
        echo "ERR_CONNECT_FAILED|$connect_result"
        return 1
    fi
}

bt_remove_device() {
    local mac="$1"
    [[ -z $mac ]] && return 1
    bluetoothctl remove "$mac" >/dev/null 2>&1
    rx_log_file "info" "Removed device $mac"
}

_rx_notif_id() {
    local mac="$1"
    [[ -z $mac || $mac == "Unknown" || ! $mac =~ ^[0-9A-Fa-f:]+$ ]] && echo "48923" && return
    local mac_clean=$(echo "$mac" | tr -d ':')
    local notif_id=$((0x$mac_clean % 1000000))
    [[ $notif_id -lt 10000 ]] && notif_id=$((notif_id + 10000))
    echo "$notif_id"
}

_rx_device_name() {
    local mac="$1"
    [[ -z $mac || $mac == "Unknown" || ! $mac =~ ^[0-9A-Fa-f:]+$ ]] && echo "Unknown Device" && return
    local name
    name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Name:" | cut -d' ' -f2-)
    [[ -z $name ]] && name="Unknown Device"
    echo "$name"
}

bt_obex_ask() {
    local filename="$1"
    local size="$2"
    local source="$3"

    local device_name
    device_name=$(_rx_device_name "$source")

    local icon_path=$(rx_get_icon "$device_name")
    [[ $icon_path != /* ]] && icon_path="bluetooth-active-symbolic"

    local human_size
    human_size=$(numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "${size} bytes")

    rx_log_file "info" "Incoming file: $filename ($human_size) from $device_name ($source)"

    local action
    action=$(
        notify-send \
            --wait \
            -r 48923 \
            -u critical \
            -i "$icon_path" \
            -a "RetroLink" \
            -A "accept=Accept" \
            -A "deny=Deny" \
            "Incoming Bluetooth File" \
            "From: <b>${device_name}</b> (${source})\nFile: $filename ($human_size)"
    )

    if [[ $action == "accept" ]]; then
        exit 0
    else
        rx_log_file "warn" "File transfer denied: $filename from $device_name ($source)"
        exit 1
    fi
}

_bt_dismiss_notif() {
    local id="$1"
    [[ -z $id || $id -eq 0 ]] && return
    gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.CloseNotification \
        "$id" >/dev/null 2>&1
}

bt_obex_notify_progress() {
    local source="$1"
    local filename="$2"
    local pct="$3"
    local transferred="$4"
    local total="$5"

    [[ -z $source || -z $filename || -z $pct ]] && return 1

    local device_name
    device_name=$(_rx_device_name "$source")

    local icon_path
    icon_path=$(rx_get_icon "$device_name")
    [[ $icon_path != /* ]] && icon_path="bluetooth-active-symbolic"

    local notif_id
    notif_id=$(_rx_notif_id "$source")

    local cancel_flag="/tmp/.bt_receive_${notif_id}_cancel"

    local cur_human total_human
    if command -v numfmt >/dev/null 2>&1; then
        cur_human=$(numfmt --to=iec-i --suffix=B "$transferred" 2>/dev/null || echo "${transferred}B")
        total_human=$(numfmt --to=iec-i --suffix=B "$total" 2>/dev/null || echo "${total}B")
    else
        cur_human="${transferred}B"
        total_human="${total}B"
    fi

    if [[ $pct -eq 100 ]]; then
        rx_log_file "info" "Transfer progress: $filename from $device_name - 100%"
    fi

    (
        local action
        action=$(notify-send \
            -r "$notif_id" \
            -a "RetroTransfer" \
            -i "$icon_path" \
            -t 20000 \
            -h "string:x-canonical-private-synchronous:bt-transfer" \
            -h "int:value:${pct}" \
            -A "cancel=Cancel Transfer" \
            "Receiving: ${filename}" \
            "From: <b>${device_name}</b> (${source})\nProgress: <b>${pct}%</b> (${cur_human} / ${total_human})")

        [[ $action == "cancel" ]] && touch "$cancel_flag"
    ) &
}

bt_obex_receive_cancel_monitor() {
    local source="$1"
    local filename="$2"
    local total="$3"

    local device_name
    device_name=$(_rx_device_name "$source")

    local icon_path
    icon_path=$(rx_get_icon "$device_name")
    [[ $icon_path != /* ]] && icon_path="bluetooth-active-symbolic"

    local notif_id
    notif_id=$(_rx_notif_id "$source")

    local cancel_flag="/tmp/.bt_receive_${notif_id}_cancel"
    rm -f "$cancel_flag"

    local action
    action=$(notify-send \
        --wait \
        -r "$notif_id" \
        -a "RetroTransfer" \
        -i "$icon_path" \
        -t 60000 \
        -h "string:x-canonical-private-synchronous:bt-transfer" \
        -A "cancel=Cancel Transfer" \
        "Receiving: ${filename}" \
        "From: <b>${device_name}</b> (${source})\nTap Cancel to abort.")

    [[ $action == "cancel" ]] && touch "$cancel_flag"
}

bt_obex_notify_done() {
    local source="$1"
    local filename="$2"
    local status="$3"
    local elapsed="$4"

    [[ -z $source || -z $filename || -z $status ]] && return 1

    local device_name
    device_name=$(_rx_device_name "$source")

    local icon_path
    icon_path=$(rx_get_icon "$device_name")
    [[ $icon_path != /* ]] && icon_path="bluetooth-active-symbolic"

    local notif_id
    notif_id=$(_rx_notif_id "$source")

    local cancel_flag="/tmp/.bt_receive_${notif_id}_cancel"
    rm -f "$cancel_flag"

    _bt_dismiss_notif "$notif_id"

    if [[ $status == "complete" ]]; then
        notify-send \
            -r "$notif_id" \
            -a "RetroTransfer" \
            -i "$icon_path" \
            -u normal \
            "Transfer Complete" \
            "<b>${filename}</b> received from <b>${device_name}</b> in ${elapsed} seconds."
        rx_log_file "success" "File $filename received from $device_name ($source) in ${elapsed}s"
    elif [[ $status == "cancelled" ]]; then
        notify-send \
            -r "$notif_id" \
            -a "RetroTransfer" \
            -i "$icon_path" \
            -u normal \
            "Transfer Aborted" \
            "Connection to <b>${device_name}</b> severed."
        rx_log_file "warn" "File transfer cancelled: $filename from $device_name ($source)"
    else
        notify-send \
            -r "$notif_id" \
            -a "RetroTransfer" \
            -i "$icon_path" \
            -u normal \
            "Transfer Failed" \
            "Receiving <b>${filename}</b> from <b>${device_name}</b> was interrupted."
        rx_log_file "error" "File transfer failed: $filename from $device_name ($source)"
    fi
}

bt_obex_send_cancel_monitor() {
    local mac="$1"
    local filename="$2"
    local total="$3"
    local file_size="$4"

    local device_name
    device_name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Name:" | cut -d' ' -f2-)
    [[ -z $device_name ]] && device_name="Unknown Device"

    local icon_path
    icon_path=$(rx_get_icon "$device_name")
    [[ $icon_path != /* ]] && icon_path="bluetooth-active-symbolic"

    local mac_clean=$(echo "$mac" | tr -d ':')
    local notif_id=$((0x$mac_clean % 1000000))
    [[ $notif_id -lt 10000 ]] && notif_id=$((notif_id + 10000))

    local cancel_flag="/tmp/.bt_send_${notif_id}_cancel"
    rm -f "$cancel_flag"

    local action
    action=$(notify-send \
        --wait \
        -r "$notif_id" \
        -a "RetroTransfer" \
        -i "$icon_path" \
        -t 120000 \
        -h "string:x-canonical-private-synchronous:bt-transfer" \
        -A "cancel=Cancel Transfer" \
        "Sending: ${filename}" \
        "To: <b>${device_name}</b> (${mac})\nWaiting for device to accept... ($file_size)")

    [[ $action == "cancel" ]] && touch "$cancel_flag"
}

bt_send_file() {
    local mac="$1"
    local file_path="$2"
    [[ -z $mac || -z $file_path ]] && echo "ERR_MISSING_ARGS" && return 1
    [[ ! -f $file_path ]] && echo "ERR_FILE_NOT_FOUND" && return 1

    local file_name=$(basename "$file_path")
    local total_bytes=$(stat -c%s "$file_path")
    local file_size=$(du -h "$file_path" | awk '{print $1}')

    local device_name=$(bluetoothctl info "$mac" | grep "Name:" | cut -d' ' -f2-)
    [[ -z $device_name ]] && device_name="Unknown Device"

    local icon_path=$(rx_get_icon "$device_name")
    [[ $icon_path != /* ]] && icon_path="bluetooth-active-symbolic"

    local mac_clean=$(echo "$mac" | tr -d ':')
    local notif_id=$((0x$mac_clean % 1000000))
    [[ $notif_id -lt 10000 ]] && notif_id=$((notif_id + 10000))

    local log_file="/tmp/.bt_send_${notif_id}.log"
    local cancel_flag="/tmp/.bt_send_${notif_id}_cancel"
    local result_file="/tmp/.bt_send_${notif_id}_result.txt"
    rm -f "$log_file" "$cancel_flag" "$result_file"

    rx_log_file "info" "Sending $file_name to $device_name ($mac)"

    stdbuf -oL bt-obex -p "$mac" "$file_path" >"$log_file" 2>&1 &
    local obex_pid=$!

    (
        export DISPLAY="$DISPLAY"
        export DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
        export XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
        export RETRO_DIR="$RETRO_DIR"
        bash "$RETRO_DIR/scripts/bluetooth_core.sh" --obex-send-cancel-monitor "$mac" "$file_name" "$total_bytes" "$file_size" </dev/null >/dev/null 2>&1 &
    )

    _format_bytes() {
        local b=${1:-0}
        if ((b < 1024)); then
            echo "${b}B"
        elif ((b < 1048576)); then
            echo "$((b / 1024))K"
        else
            echo "$((b / 1048576))M"
        fi
    }

    _send_notif_with_cancel() {
        local pct="$1"
        local status_msg="$2"
        local ACTION

        ACTION=$(notify-send -r "$notif_id" -a "RetroTransfer" \
            -i "$icon_path" \
            -t 20000 \
            -h "string:x-canonical-private-synchronous:bt-transfer" \
            -h "int:value:$pct" \
            -A "cancel=Cancel Transfer" \
            "Sending: $file_name" \
            "To: <b>$device_name</b> ($mac)\n$status_msg")

        [[ $ACTION == "cancel" ]] && touch "$cancel_flag"
    }

    _send_notif_with_cancel 0 "Waiting for device to accept... ($file_size)" &

    (
        local result_file="/tmp/.bt_send_${notif_id}_result.txt"
        local last_pct=-1
        local send_start=$(date +%s)

        while kill -0 "$obex_pid" 2>/dev/null; do
            sleep 1

            if [[ -f $cancel_flag ]]; then
                kill "$obex_pid" 2>/dev/null
                source "$RETRO_DIR/scripts/bluetooth_core.sh" 2>/dev/null
                bt_disconnect "$mac"

                _bt_dismiss_notif "$notif_id"
                notify-send -r "$notif_id" -a "RetroTransfer" -i "$icon_path" -u normal \
                    "Transfer Aborted" "Connection to <b>$device_name</b> severed."
                echo "ERR|cancelled" >"$result_file"
                rm -f "$log_file" "$cancel_flag"
                return
            fi

            local pct=$(LC_ALL=C tr -dc '[:print:]\n' <"$log_file" 2>/dev/null | grep -oP '\d+(?=%$)' | tail -1)
            pct=${pct:-0}

            if ((pct > last_pct && pct > 0)); then
                last_pct=$pct

                local cur_bytes=$((total_bytes * pct / 100))
                local cur_human=$(_format_bytes "$cur_bytes")

                _send_notif_with_cancel "$pct" "Progress: <b>${pct}%</b> ($cur_human / $file_size)" &
            fi
        done

        wait "$obex_pid"
        local elapsed=$(($(date +%s) - send_start))

        if grep -qi "Completed" "$log_file"; then
            _bt_dismiss_notif "$notif_id"
            notify-send -r "$notif_id" -a "RetroTransfer" -u normal \
                -i "$icon_path" \
                "Transfer Complete" "<b>$file_name</b> sent to <b>$device_name</b> in ${elapsed} seconds."
            echo "OK|$elapsed" >"$result_file"
            source "$RETRO_DIR/scripts/bluetooth_core.sh" 2>/dev/null
            rx_log_file "success" "File $file_name sent to $device_name ($mac) in ${elapsed}s"
        else
            _bt_dismiss_notif "$notif_id"
            notify-send -r "$notif_id" -a "RetroTransfer" -u normal -i "$icon_path" \
                "Transfer Failed" "<b>$device_name</b> rejected the request."
            echo "ERR|rejected" >"$result_file"
            source "$RETRO_DIR/scripts/bluetooth_core.sh" 2>/dev/null
            rx_log_file "error" "Failed to send $file_name to $device_name ($mac) - rejected"
        fi

        rm -f "$log_file" "$cancel_flag"
    ) &

    echo "OK|$file_path"
}

bt_cancel_send() {
    local mac="$1"
    [[ -z $mac ]] && return 1
    local mac_clean=$(echo "$mac" | tr -d ':')
    local notif_id=$((0x$mac_clean % 1000000))
    [[ $notif_id -lt 10000 ]] && notif_id=$((notif_id + 10000))
    touch "/tmp/.bt_send_${notif_id}_cancel"
    rx_log_file "warn" "Send transfer cancelled for $mac"
}

rx_handle_profile_set() {
    local mac="$1"
    local profile="$2"
    local codec="$3"
    local normalized
    normalized=$(normalize_profile "$profile" "$codec")
    rx_log_file "info" "Setting audio profile for $mac: $profile ($codec) -> $normalized"
    set_audio_profile "$mac" "$normalized"
}

rx_handle_can_send() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return
    local is_phone is_computer
    is_phone=$(is_device_phone "$mac")
    is_computer=$(is_device_computer "$mac")
    [[ $is_phone == "true" || $is_computer == "true" ]] && echo "true" || echo "false"
}

bt_obex_ensure_download_dir() {
    local dl_dir
    dl_dir=$(get_var "BT_DOWNLOAD_DIR" 2>/dev/null)
    if [[ -n $dl_dir ]]; then
        echo "$dl_dir"
        return 0
    fi

    local result_file="/tmp/.bt_zenity_dir_$$"
    rm -f "$result_file"

    zenity --file-selection --directory --title="Select Download Folder" >"$result_file" 2>/dev/null &
    local zenity_pid=$!

    local tries=0
    local addr=""
    while [[ $tries -lt 20 && -z $addr ]]; do
        sleep 0.05
        addr=$(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "xdg-desktop-portal-gtk") | .address' | head -1)
        ((tries++))
    done

    if [[ -n $addr ]]; then
        hyprctl dispatch setfloating "address:$addr" 2>/dev/null
        hyprctl dispatch centerwindow "address:$addr" 2>/dev/null
    fi

    wait $zenity_pid
    local dir_path
    dir_path=$(cat "$result_file" 2>/dev/null)
    rm -f "$result_file"

    if [[ -z $dir_path ]]; then
        dir_path="$HOME/Downloads"
        mkdir -p "$dir_path"
    fi

    set_var "BT_DOWNLOAD_DIR" "$dir_path"
    rx_log_file "info" "Download directory set to: $dir_path"
    echo "$dir_path"
}

bt_obex_move_received_file() {
    local filename="$1"
    local source="$2"

    local dl_dir
    dl_dir=$(get_var "BT_DOWNLOAD_DIR" 2>/dev/null)
    if [[ -z $dl_dir ]]; then
        dl_dir="$HOME/Downloads"
    fi

    if [[ -f "$dl_dir/$filename" ]]; then
        rx_log_file "info" "File already in $dl_dir: $filename"
        xdg-open "$dl_dir/$filename" >/dev/null 2>&1 &
        return 0
    fi

    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
    local cache_file="$cache_dir/$filename"

    if [[ -f $cache_file ]]; then
        mv "$cache_file" "$dl_dir/" 2>/dev/null && {
            rx_log_file "info" "Moved $filename to $dl_dir"
            xdg-open "$dl_dir/$filename" >/dev/null 2>&1 &
            return 0
        }
    fi

    local found
    found=$(find "$cache_dir" -maxdepth 2 -name "$filename" -newer /tmp/.bt_obex_receive.pid 2>/dev/null | head -1)
    if [[ -n $found ]]; then
        mv "$found" "$dl_dir/" 2>/dev/null && {
            rx_log_file "info" "Moved $filename to $dl_dir"
            xdg-open "$dl_dir/$filename" >/dev/null 2>&1 &
            return 0
        }
    fi

    return 1
}

bt_obex_restart_with_root() {
    local dl_dir
    dl_dir=$(get_var "BT_DOWNLOAD_DIR" 2>/dev/null)
    if [[ -z $dl_dir ]]; then
        dl_dir="$HOME/Downloads"
    fi

    sleep 1

    pkill obexd 2>/dev/null
    sleep 0.5

    nohup /usr/lib/bluetooth/obexd --root="$dl_dir" >/dev/null 2>&1 &
    sleep 1.5

    rx_log_file "info" "OBEX daemon restarted with root: $dl_dir"
    bt_obex_receive_restart
}

bt_obex_receive_start() {
    local pid_file="/tmp/.bt_obex_receive.pid"
    if [[ -f $pid_file ]] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
        echo "OK|already_running|$(cat "$pid_file")"
        return 0
    fi

    local script_dir="$RETRO_DIR/scripts"

    pkill -f 'bluetooth_receive.py' 2>/dev/null
    sleep 0.5

    local dl_dir
    dl_dir=$(get_var "BT_DOWNLOAD_DIR" 2>/dev/null)
    if [[ -z $dl_dir ]]; then
        dl_dir="$HOME/Downloads"
        mkdir -p "$dl_dir"
    fi

    pkill obexd 2>/dev/null
    sleep 0.5

    nohup /usr/lib/bluetooth/obexd --root="$dl_dir" >/dev/null 2>&1 &
    sleep 1.5

    pid_file="/tmp/.bt_obex_receive.pid"
    if [[ -f $pid_file ]]; then
        local old_pid
        old_pid=$(cat "$pid_file" 2>/dev/null)
        [[ -n $old_pid ]] && kill "$old_pid" 2>/dev/null
        rm -f "$pid_file"
    fi

    nohup env \
        DISPLAY="$DISPLAY" \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        RETRO_DIR="$RETRO_DIR" \
        python3 "$script_dir/python/bluetooth_receive.py" "$RETRO_DIR/scripts/bluetooth_core.sh" \
        >/tmp/.bt_obex_receive.log 2>&1 &
    local pid=$!
    echo "$pid" >"$pid_file"

    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        set_var "BT_RECEIVE_ACTIVE" "true"
        rx_log_file "info" "OBEX receive agent started (PID: $pid)"
        echo "OK|$pid"
    else
        local err
        err=$(cat /tmp/.bt_obex_receive.log 2>/dev/null | head -1)
        [[ -z $err ]] && err="start_failed"
        rm -f "$pid_file"
        rx_log_file "error" "OBEX receive agent failed to start: $err"
        echo "ERR|$err"
    fi
}

bt_obex_receive_stop() {
    local pid_file="/tmp/.bt_obex_receive.pid"
    if [[ ! -f $pid_file ]] || ! kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
        rm -f "$pid_file"
        set_var "BT_RECEIVE_ACTIVE" "false"
        echo "OK|already_stopped"
        return 0
    fi

    pkill -f 'bluetooth_receive.py' 2>/dev/null
    rm -f /tmp/.bt_obex_receive.log
    set_var "BT_RECEIVE_ACTIVE" "false"
    rx_log_file "info" "OBEX receive agent stopped"
    echo "OK|stopped"
}

bt_obex_receive_restart() {
    bt_obex_receive_stop >/dev/null 2>&1
    sleep 1
    bt_obex_receive_start
}

bt_obex_receive_status() {
    local pid_file="/tmp/.bt_obex_receive.pid"
    local dl_dir
    dl_dir=$(get_var "BT_DOWNLOAD_DIR" 2>/dev/null)
    [[ -z $dl_dir ]] && dl_dir="$HOME/Downloads"

    if [[ -f $pid_file ]] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
        echo "running|${dl_dir}"
    else
        echo "stopped|${dl_dir}"
    fi
}

bt_mic_suspend() {
    local mac="$1"
    [[ -z $mac ]] && echo "ERR_NO_MAC" && return 1

    local card
    card=$(get_audio_card_for_mac "$mac")
    [[ -z $card ]] && echo "ERR_NO_CARD" && return 1

    local current_profile
    current_profile=$(get_audio_profile "$card")
    [[ -z $current_profile ]] && echo "ERR_NO_PROFILE" && return 1

    if [[ $current_profile == a2dp-sink* ]]; then
        echo "OK|already_output_only"
        return 0
    fi

    set_var "BT_MIC_PREV_PROFILE_${mac//:/_}" "$current_profile"

    if pactl set-card-profile "$card" "a2dp-sink" 2>/dev/null; then
        rx_log_file "info" "Mic disabled for $mac (switched to a2dp-sink)"
        echo "OK|a2dp-sink"
    else
        rx_log_file "error" "Failed to switch profile for $mac"
        echo "ERR_SWITCH_FAILED"
        return 1
    fi
}

bt_mic_resume() {
    local mac="$1"
    [[ -z $mac ]] && echo "ERR_NO_MAC" && return 1

    local card
    card=$(get_audio_card_for_mac "$mac")
    [[ -z $card ]] && echo "ERR_NO_CARD" && return 1

    local prev_profile
    prev_profile=$(get_var "BT_MIC_PREV_PROFILE_${mac//:/_}" "")

    if [[ -z $prev_profile ]]; then
        prev_profile="headset-head-unit"
    fi

    if pactl set-card-profile "$card" "$prev_profile" 2>/dev/null; then
        rx_log_file "info" "Mic enabled for $mac (switched to $prev_profile)"
        echo "OK|$prev_profile"
    else
        rx_log_file "error" "Failed to switch profile for $mac"
        echo "ERR_SWITCH_FAILED"
        return 1
    fi
}

bt_mic_status() {
    local mac="$1"
    [[ -z $mac ]] && echo "ERR_NO_MAC" && return 1

    local card
    card=$(get_audio_card_for_mac "$mac")
    [[ -z $card ]] && echo "ERR_NO_CARD" && return 1

    local current_profile
    current_profile=$(get_audio_profile "$card")

    if [[ $current_profile == a2dp-sink* ]]; then
        echo "disabled|a2dp-sink"
    else
        echo "enabled|$current_profile"
    fi
}

rx_handle_can_send() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return
    local is_phone is_computer
    is_phone=$(is_device_phone "$mac")
    is_computer=$(is_device_computer "$mac")
    [[ $is_phone == "true" || $is_computer == "true" ]] && echo "true" || echo "false"
}

case "$1" in
    "--power-on") bt_power_on ;;
    "--power-off") bt_power_off ;;
    "--status") get_bt_status ;;
    "--toggle-discovery") toggle_discovery ;;
    "--scan-on")
        (
            echo "power on"
            echo "scan on"
            sleep 180
        ) | bluetoothctl >/dev/null 2>&1 &
        ;;
    "--scan-off")
        pkill -f "bluetoothctl"
        ;;
    "--list") bluetoothctl devices Paired ;;
    "--nearby") get_nearby ;;
    "--nearby-detailed") get_nearby_detailed ;;
    "--paired-detailed") get_paired_detailed ;;
    "--battery") get_device_battery "$2" ;;
    "--device-type")
        get_device_category "$2"
        ;;
    "--device-class")
        get_bt_device_class_decoded "$2"
        ;;
    "--profile-info")
        get_profile_info "$2"
        ;;
    "--profile-set")
        rx_handle_profile_set "$2" "$3" "$4"
        ;;
    "--connect")
        bt_pair_with_agent "$2" "${3:-unknown}"
        ;;
    "--disconnect") bt_disconnect "$2" ;;
    "--reconnect")
        bt_reconnect_with_agent "$2" "${3:-unknown}"
        ;;
    "--remove") bt_remove_device "$2" ;;
    "--forget") bt_remove_device "$2" ;;
    "--can-send")
        rx_handle_can_send "$2"
        ;;
    "--send")
        bt_send_file "$2" "$3"
        ;;
    "--cancel-send")
        bt_cancel_send "$2"
        ;;
    "--receive-start")
        bt_obex_receive_start
        ;;
    "--receive-restart")
        bt_obex_receive_restart
        ;;
    "--receive-stop")
        bt_obex_receive_stop
        ;;
    "--receive-status")
        bt_obex_receive_status
        ;;
    "--obex-ensure-download-dir")
        bt_obex_ensure_download_dir
        ;;
    "--obex-move-and-restart")
        bt_obex_move_received_file "$2" "$3" && bt_obex_restart_with_root
        ;;
    "--obex-ask")
        bt_obex_ask "$2" "$3" "$4"
        ;;
    "--obex-notify-progress")
        bt_obex_notify_progress "$2" "$3" "$4" "$5" "$6"
        ;;
    "--obex-notify-done")
        bt_obex_notify_done "$2" "$3" "$4" "$5"
        ;;
    "--obex-receive-cancel-monitor")
        bt_obex_receive_cancel_monitor "$2" "$3" "$4"
        ;;
    "--obex-send-cancel-monitor")
        bt_obex_send_cancel_monitor "$2" "$3" "$4" "$5"
        ;;
    "--trust")
        mac=$2
        [[ -z $mac ]] && echo "ERR_NO_MAC" && exit 1
        bluetoothctl trust "$mac" >/dev/null 2>&1 && echo "OK|trusted" || echo "ERR|trust_failed"
        ;;
    "--untrust")
        mac=$2
        [[ -z $mac ]] && echo "ERR_NO_MAC" && exit 1
        bluetoothctl untrust "$mac" >/dev/null 2>&1 && echo "OK|untrusted" || echo "ERR|untrust_failed"
        ;;
    "--mic-suspend") bt_mic_suspend "$2" ;;
    "--mic-resume") bt_mic_resume "$2" ;;
    "--mic-status") bt_mic_status "$2" ;;
esac
