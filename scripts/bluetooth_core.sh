#!/bin/bash

get_bt_status() {
    local bt_info=$(bluetoothctl show)
    local radio_on=$(echo "$bt_info" | grep -i "Powered:" | awk '{print $2}' | xargs)
    local disc=$(echo "$bt_info" | grep -i "Discoverable:" | awk '{print $2}' | xargs)
    local pair=$(echo "$bt_info" | grep -i "Pairable:" | awk '{print $2}' | xargs)

    local hci_path="/sys/class/bluetooth/hci0/device/power"
    local pwr_ctrl=$(cat "$hci_path/control" 2>/dev/null || echo "on")
    local pwr_stat=$(cat "$hci_path/runtime_status" 2>/dev/null || echo "active")

    local hw_mode="NORMAL"
    [[ $pwr_ctrl == "auto" || $pwr_stat == "suspended" ]] && hw_mode="SAVER"

    local chip_name="Intel Meteor Lake BT"
    if [[ -f "/sys/class/bluetooth/hci0/device/uevent" ]]; then
        chip_name="Intel Wireless Bluetooth"
    fi

    local ver="5.4"
    if command -v btmgmt >/dev/null 2>&1; then
        local lmp
        lmp=$(timeout 3 btmgmt info 2>/dev/null | grep -i "ver" | awk '{print $4}' | head -n 1)
        case "$lmp" in 13) ver="5.4" ;; 12) ver="5.3" ;; 11) ver="5.2" ;; esac
    fi

    local conns=$(bluetoothctl devices Connected | wc -l)

    echo "${radio_on:-no}|${hw_mode}|${disc:-no}|${pair:-no}|${chip_name}|${ver}|${conns}"
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

    if [[ "$icon_val" == *"gamepad"* || "$icon_val" == *"input-gaming"* || "$icon_val" == *"joystick"* ]]; then
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
        phone)        echo "pho" ;;
        computer)     echo "pc" ;;
        audio)        echo "aud" ;;
        audio+input)  echo "aud+in" ;;
        controller)   echo "ctrl" ;;
        input)        echo "in" ;;
        *)            echo "unk" ;;
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
            6|10) echo "Headphones" ;;
            7|13) echo "HiFi Audio" ;;
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
        *aptx_hd*|*aptx-hd*) echo "aptX HD" ;;
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
        *a2dp-sink*aptx_hd*|*a2dp-sink*aptx-hd*) echo "High Fidelity Playback (A2DP Sink, codec aptX HD)" ;;
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
            [[ "$profile" == "$active_profile" ]] && is_active=1
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

    if pactl set-card-profile "$card" "$profile" 2>/dev/null; then
        echo "OK|$profile"
    else
        echo "ERR_SET_FAILED"
        return 1
    fi
}

normalize_profile() {
    local profile="$1"
    local codec="$2"

    case "$profile" in
        a2dp|a2dp-sink)
            case "$codec" in
                aac|AAC) echo "a2dp-sink" ;;
                ldac|LDAC) echo "a2dp-sink-ldac" ;;
                aptx|aptX) echo "a2dp-sink-aptx" ;;
                sbc-xq|SBC-XQ|sbc_xq) echo "a2dp-sink-sbc_xq" ;;
                sbc|SBC) echo "a2dp-sink-sbc" ;;
                *) echo "a2dp-sink" ;;
            esac
            ;;
        headset|hfp|hsp)
            case "$codec" in
                msbc|MSBC) echo "headset-head-unit" ;;
                cvsd|CVSD) echo "headset-head-unit-cvsd" ;;
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

    bluetoothctl trust "$mac" >/dev/null 2>&1

    if [[ $is_paired != "yes" ]]; then
        bluetoothctl pair "$mac" >/dev/null 2>&1
        local pair_result=$?
        if [[ $pair_result -ne 0 ]]; then
            kill "$agent_pid" 2>/dev/null
            echo "ERR_PAIR_FAILED|$pair_result"
            return 1
        fi
    fi

    bluetoothctl connect "$mac" >/dev/null 2>&1
    local connect_result=$?

    kill "$agent_pid" 2>/dev/null

    if [[ $connect_result -eq 0 ]]; then
        echo "OK|$mac|$name"
        return 0
    else
        echo "ERR_CONNECT_FAILED|$connect_result"
        return 1
    fi
}

bt_disconnect() {
    local mac="$1"
    [[ -z $mac ]] && return 1
    bluetoothctl disconnect "$mac" >/dev/null 2>&1
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
        echo "OK|$mac|$name"
        return 0
    else
        echo "ERR_CONNECT_FAILED|$connect_result"
        return 1
    fi
}

bt_remove_device() {
    local mac="$1"
    [[ -z $mac ]] && return 1
    bluetoothctl remove "$mac" >/dev/null 2>&1
}

bt_send_file() {
    local mac="$1"
    local file_path="$2"
    [[ -z $mac || -z $file_path ]] && echo "ERR_MISSING_ARGS" && return 1
    [[ ! -f "$file_path" ]] && echo "ERR_FILE_NOT_FOUND" && return 1
    if ! command -v bt-obex >/dev/null 2>&1; then
        echo "ERR_NO_BT_OBEX"
        return 1
    fi

    rm -f /tmp/.bt_send_log.txt

    bt-obex -p "$mac" "$file_path" >/tmp/.bt_send_log.txt 2>&1 &
    local obex_pid=$!
    local start_time=$SECONDS

    while kill -0 "$obex_pid" 2>/dev/null; do
        sleep 0.3
        local elapsed=$((SECONDS - start_time))
        if [[ $elapsed -gt 150 ]]; then
            kill "$obex_pid" 2>/dev/null
            echo "ERR_SEND_FAILED|timeout after 150s"
            return 1
        fi
    done

    wait "$obex_pid" 2>/dev/null

    local log_content
    log_content=$(cat /tmp/.bt_send_log.txt 2>/dev/null)

    echo "$log_content" | grep -qi "Completed" && echo "OK|$file_path" && return 0

    local err_msg
    err_msg=$(echo "$log_content" | grep -iE "Failed|Error|failed" | grep -v "GLib\|g_atomic" | tail -1 | xargs | cut -c1-100)
    [[ -z $err_msg ]] && err_msg="transfer failed"
    echo "ERR_SEND_FAILED|$err_msg"
    return 1
}

rx_handle_profile_set() {
    local mac="$1"
    local profile="$2"
    local codec="$3"
    local normalized
    normalized=$(normalize_profile "$profile" "$codec")
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

case "$1" in
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
esac
