#!/bin/bash

export RETRO_DIR="/opt/retrolinux"

WIFI_SELECTED_SSID=""

rx_check_internet() {
    ping -c 1 -W 3 1.1.1.1 &>/dev/null
}

get_wifi_iface() {
    ip link show 2>/dev/null | grep -E "^[0-9]+: wlan[0-9]+" | awk -F': ' '{print $2}' | head -n 1
}

get_ethernet_iface() {
    ip link show 2>/dev/null | grep -E "^[0-9]+: eth[0-9]+|^[0-9]+: en[a-z0-9]+" | awk -F': ' '{print $2}' | head -n 1
}

start_iwd() {
    if ! systemctl is-active --quiet iwd 2>/dev/null; then
        systemctl start iwd 2>/dev/null || true
        sleep 2
    fi
}

power_on_wifi() {
    local iface="${1:-}"
    [[ -z $iface ]] && iface=$(get_wifi_iface)
    [[ -z $iface ]] && return 1
    iwctl device "$iface" set-property Powered on 2>&1 || true
}

scan_wifi_networks() {
    local iface
    iface=$(get_wifi_iface)
    [[ -z $iface ]] && return 1

    ip link set "$iface" up 2>&1
    iwctl device "$iface" set-property Powered on 2>&1
    iwctl station "$iface" scan 2>&1
    sleep 3
    iwctl station "$iface" get-networks 2>&1
}

parse_iwctl_networks() {
    local raw_output="$1"

    echo "$raw_output" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | awk '
    /^[[:space:]]*$/ {next}
    /^-+$/ {next}
    /Available networks/ {next}
    /Network name/ {next}
    {
        gsub(/^[[:space:]]*>[[:space:]]*/, "")

        security = $(NF-1)
        gsub(/[[:space:]]+/, "", security)

        ssid = ""
        for(i = 1; i <= NF - 2; i++) {
            if (i > 1) ssid = ssid " "
            ssid = ssid $i
        }

        print ssid "|" security
    }'
}

wait_for_ethernet() {
    local iface
    iface=$(get_ethernet_iface)
    [[ -z $iface ]] && return 1

    ip link set "$iface" up 2>/dev/null

    local count=0
    while ((count < 15)); do
        local state
        state=$(ip link show "$iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
        [[ $state == "UP" ]] && return 0
        sleep 1
        ((count++))
    done
    return 1
}

select_wifi_network() {
    local iface
    iface=$(get_wifi_iface)
    [[ -z $iface ]] && return 1

    start_iwd
    power_on_wifi "$iface"

    local raw_output
    raw_output=$(scan_wifi_networks "$iface" 2>&1)

    local parsed
    parsed=$(parse_iwctl_networks "$raw_output")

    if [[ -z $parsed ]]; then
        sleep 3
        raw_output=$(scan_wifi_networks "$iface" 2>&1)
        parsed=$(parse_iwctl_networks "$raw_output")
    fi

    if [[ -z $parsed ]]; then
        clear_logo
        echo
        gum style --foreground 1 "No networks found"
        echo
        return 1
    fi

    local options=()
    local ssid security
    while IFS='|' read -r ssid security; do
        [[ -z $ssid ]] && continue
        options+=("$ssid ($security)")
    done <<<"$parsed"

    if [[ ${#options[@]} -eq 0 ]]; then
        clear_logo
        echo
        gum style --foreground 1 "No valid networks"
        echo
        return 1
    fi

    local selected
    selected=$(printf '%s\n' "${options[@]}" | gum choose --header "Select Wifi Network" --height 15 --padding "$GUM_CHOOSE_PADDING")
    local choose_status=$?
    [[ $choose_status -ne 0 || -z $selected ]] && return 1

    ssid=$(echo "$selected" | sed 's/ (.*$//')
    WIFI_SELECTED_SSID="$ssid"
    rx_debug "info" "Selected SSID: '$ssid'"

    local network_line
    network_line=$(echo "$parsed" | grep -F "$ssid|")
    security=$(echo "$network_line" | awk -F'|' '{print $2}')

    if [[ -z $security ]]; then
        security="Unknown"
    fi

    local password=""
    if [[ $security != "Open" ]]; then
        echo
        password=$(gum input --placeholder "WiFi Password" --prompt.foreground="#ff79c6" --password --prompt "Password> " --padding "$GUM_INPUT_PADDING")
        echo
        [[ -z $password ]] && return 1
    fi

    local iface
    iface=$(get_wifi_iface)
    [[ -z $iface ]] && return 1

    echo
    iwctl --passphrase "$password" station "$iface" connect "$ssid"

    gum spin --spinner dot --title "Checking connection..." -- bash -c "
        sleep 4
        if ping -c 1 -W 5 1.1.1.1 &>/dev/null; then
            exit 0
        else
            exit 1
        fi
    "

    if (($? == 0)); then
        return 0
    fi

    clear_logo
    echo
    gum style --foreground 1 "$ssid: Connection failed"
    echo
    return 1
}

check_network_hardware() {
    local wifi_iface
    local eth_iface

    wifi_iface=$(get_wifi_iface)
    eth_iface=$(get_ethernet_iface)

    rx_debug "info" "WiFi: ${wifi_iface:-none}"
    rx_debug "info" "Eth: ${eth_iface:-none}"

    if [[ -z $wifi_iface && -z $eth_iface ]]; then
        clear_logo
        echo
        gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "No network hardware found"
        echo
        gum style "This system has no WiFi or Ethernet adapter."
        gum style "Please connect a network cable or install a WiFi adapter."
        echo
        gum style --foreground 3 "Press Enter to exit..."
        read
        return 1
    fi

    if [[ -z $wifi_iface && -n $eth_iface ]]; then
        clear_logo
        echo
        gum style --foreground 3 "Ethernet only detected"
        echo
        gum style "Please connect your ethernet cable."
        echo
        gum style "Waiting for connection..."

        local count=0
        while ((count < 5)); do
            if wait_for_ethernet "$eth_iface" && rx_check_internet; then
                clear_logo
                echo
                gum style --foreground 2 "Ethernet connected"
                echo
                return 0
            fi
            sleep 2
            ((count++))
            gum style --foreground 7 "Waiting... ($count/5)"
        done

        clear_logo
        echo
        gum style --foreground 1 "Ethernet connection failed"
        echo
        gum style "Please check your cable and try again."
        return 1
    fi

    return 0
}

setup_network() {
    clear_logo
    echo
    gum style "Let's setup your WiFi"
    echo

    rx_check_internet && {
        clear_logo
        echo
        gum style --foreground 2 "Internet connected"
        echo
        return 0
    }

    if ! check_network_hardware; then
        return 1
    fi

    local wifi_iface
    wifi_iface=$(get_wifi_iface)
    local eth_iface
    eth_iface=$(get_ethernet_iface)

    if [[ -n $wifi_iface ]]; then
        local retry=0
        local max_retries=5
        while ((retry < max_retries)); do
            select_wifi_network
            local result=$?

            if ((result == 0)); then
                return 0
            elif ((result == 2)); then
                ((retry++))
                if [[ $retry -lt $max_retries ]]; then
                    clear_logo
                    echo
                    gum style --foreground 3 "${WIFI_SELECTED_SSID}: Wrong password ($retry/$max_retries)"
                    echo
                    gum spin --spinner dot --title "Retrying in 4 seconds..." -- sleep 4
                fi
            else
                ((retry++))
                if [[ $retry -lt $max_retries ]]; then
                    clear_logo
                    echo
                    gum style --foreground 1 "${WIFI_SELECTED_SSID}: Connection failed"
                    echo
                    gum spin --spinner dot --title "Retrying in 4 seconds..." -- sleep 4
                fi
            fi
        done
    fi

    if [[ -n $eth_iface ]]; then
        if wait_for_ethernet "$eth_iface" && rx_check_internet; then
            clear_logo
            echo
            gum style --foreground 2 "Ethernet connected"
            echo
            return 0
        fi
    fi

    clear_logo
    echo
    gum style --foreground 1 "Network unavailable"
    echo
    return 1
}
