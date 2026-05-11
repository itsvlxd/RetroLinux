#!/bin/bash

BT_ADAPTER_PATH="/sys/class/bluetooth/hci0"

has_bluetooth() {
    [[ -d "$BT_ADAPTER_PATH" ]] && echo "true" || echo "false"
}

get_bt_connected_devices() {
    bluetoothctl devices Connected 2>/dev/null | awk '{print $2}' | xargs
}

get_bt_device_info() {
    local mac="$1"
    [[ -z $mac ]] && return

    local name
    name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Name:" | sed 's/.*Name: //' | xargs)
    [[ -z $name ]] && name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Alias:" | sed 's.*Alias: .' | xargs)

    echo "$name"
}

is_bt_device_paired() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    bluetoothctl info "$mac" 2>/dev/null | grep -q "Paired: yes" && echo "true" || echo "false"
}

is_bt_device_audio_capable() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    local uuids
    uuids=$(bluetoothctl info "$mac" 2>/dev/null | grep "UUID:" | sed 's/.*(//; s/).*//')

    echo "$uuids" | grep -qi "^0000110b\|^0000110a\|^00001108\|^0000111e\|^0000111f" && echo "true" || echo "false"
}

is_bt_device_input_capable() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    local uuids
    uuids=$(bluetoothctl info "$mac" 2>/dev/null | grep "UUID:" | sed 's/.*(//; s/).*//')

    echo "$uuids" | grep -qi "^00001124\|^00001126\|^00001812\|^00001813\|^00001816\|^00001805\|^00001806\|^0000180a" && echo "true" || echo "false"
}

is_bt_device_phone() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    local uuids
    uuids=$(bluetoothctl info "$mac" 2>/dev/null | grep "UUID:" | sed 's/.*(//; s/).*//')

    echo "$uuids" | grep -qi "^0000112f\|^0000112d\|^00001132" && echo "true" || echo "false"
}

is_bt_device_computer() {
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

get_bt_device_category() {
    local mac="$1"
    [[ -z $mac ]] && echo "other" && return

    local is_phone is_computer is_audio is_input is_controller
    is_phone=$(is_bt_device_phone "$mac")
    is_computer=$(is_bt_device_computer "$mac")
    is_audio=$(is_bt_device_audio_capable "$mac")
    is_input=$(is_bt_device_input_capable "$mac")
    is_controller=$(is_bt_device_gamepad "$mac")

    if [[ $is_phone == "true" ]]; then
        echo "phone"
    elif [[ $is_computer == "true" ]]; then
        echo "computer"
    elif [[ $is_controller == "true" ]]; then
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

is_bt_device_gamepad() {
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

declare -A BT_DEVICE_TYPE_ICONS
BT_DEVICE_TYPE_ICONS=(
    ["phone"]="󰏊"
    ["computer"]=" PC"
    ["audio"]="󰍺"
    ["audio+input"]="󰋎"
    ["controller"]=""
    ["input-keyboard"]=""
    ["input-mouse"]=""
    ["input-audio"]=""
    ["input"]="󰎽"
    ["other"]="󰦔"
)

declare -A BT_DEVICE_TYPE_LABELS
BT_DEVICE_TYPE_LABELS=(
    ["phone"]="PHONE"
    ["computer"]="PC"
    ["audio"]="AUDIO"
    ["audio+input"]="AUDIO+INPUT"
    ["controller"]="CONTROLLER"
    ["input-keyboard"]="KEYBOARD"
    ["input-mouse"]="MOUSE"
    ["input-audio"]="INPUT AUDIO"
    ["input"]="INPUT"
    ["other"]="OTHER"
)

get_bt_device_type_icon() {
    local type="${1:-other}"
    echo "${BT_DEVICE_TYPE_ICONS[$type]:-${BT_DEVICE_TYPE_ICONS[other]:-󰦔}}"
}

get_bt_device_type_label() {
    local type="${1:-other}"
    echo "${BT_DEVICE_TYPE_LABELS[$type]:-${BT_DEVICE_TYPE_LABELS[other]:-OTHER}}"
}

can_bt_send_file() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    local is_phone is_computer
    is_phone=$(is_bt_device_phone "$mac")
    is_computer=$(is_bt_device_computer "$mac")

    if [[ $is_phone == "true" || $is_computer == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

get_bt_audio_card() {
    local mac="$1"
    [[ -z $mac ]] && return

    local mac_underscored="${mac//:/_}"
    pactl list cards short 2>/dev/null | awk '{print $2}' | grep -i "${mac_underscored}" | head -1
}

get_bt_audio_profile() {
    local card="$1"
    [[ -z $card ]] && return

    pactl list cards 2>/dev/null | sed -n '/Name: .*'"$card"'/,/Ports:/p' | grep "Active Profile:" | awk '{print $3}' | tr -d '\n' | xargs
}

get_bt_audio_codec() {
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

get_bt_codec_from_profile() {
    local profile="$1"
    [[ -z $profile ]] && echo "unknown" && return
    case "$profile" in
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
        *) echo "unknown" ;;
    esac
}

get_bt_profile_display_name() {
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

get_bt_codec_display_name() {
    local codec="$1"
    case "$codec" in
        sbc) echo "SBC" ;;
        sbc_xq) echo "SBC-XQ" ;;
        aac) echo "AAC" ;;
        ldac) echo "LDAC" ;;
        aptx) echo "aptX" ;;
        aptx_hd) echo "aptX HD" ;;
        opus) echo "Opus" ;;
        cvsd) echo "CVSD" ;;
        msbc) echo "MSBC" ;;
        *) echo "${codec:-unknown}" ;;
    esac
}

set_bt_audio_profile() {
    local card="$1"
    local profile="$2"

    if pactl set-card-profile "$card" "$profile" 2>/dev/null; then
        echo "OK"
    else
        echo "ERR"
    fi
}

is_bt_device_connected() {
    local mac="$1"
    [[ -z $mac ]] && echo "false" && return

    bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes" && echo "true" || echo "false"
}

get_bt_nearby_devices() {
    local check_count=0
    local is_scanning="no"

    while [[ $check_count -lt 3 ]]; do
        is_scanning=$(bluetoothctl show 2>/dev/null | grep -i "Discovering:" | awk '{print $2}' | xargs)
        [[ $is_scanning == "yes" ]] && break
        sleep 0.2
        ((check_count++))
    done

    if [[ $is_scanning != "yes" ]]; then
        echo ""
        return
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