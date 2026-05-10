#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_network() {
    rx_load_state
    rx_clear_logo
    echo
    gum style "Network connectivity check"
    echo

    rx_check_internet && {
        rx_clear_logo
        echo
        gum style --foreground 2 "Internet connected"
        echo
        return 0
    }

    if ! rx_check_network_hardware; then
        return 1
    fi

    local wifi_iface
    wifi_iface=$(rx_get_wifi_iface)
    local eth_iface
    eth_iface=$(rx_get_ethernet_iface)

    if [[ -n $wifi_iface ]]; then
        local retry=0
        local max_retries=5
        while ((retry < max_retries)); do
            rx_select_wifi_network
            local result=$?

            if ((result == 0)); then
                NETWORK_TYPE="WiFi"
                WIFI_SSID="$WIFI_SELECTED_SSID"
                rx_save_state
                return 0
            elif ((result == 2)); then
                ((retry++))
                if [[ $retry -lt $max_retries ]]; then
                    rx_clear_logo
                    echo
                    gum style --foreground 3 "${WIFI_SELECTED_SSID:-WiFi}: Wrong password ($retry/$max_retries)"
                    echo
                    gum spin --spinner dot --title "Retrying in 4 seconds..." -- sleep 4
                fi
            else
                ((retry++))
                if [[ $retry -lt $max_retries ]]; then
                    rx_clear_logo
                    echo
                    gum style --foreground 1 "${WIFI_SELECTED_SSID:-WiFi}: Connection failed"
                    echo
                    gum spin --spinner dot --title "Retrying in 4 seconds..." -- sleep 4
                fi
            fi
        done
    fi

    if [[ -n $eth_iface ]]; then
        if rx_wait_for_ethernet "$eth_iface" && rx_check_internet; then
            NETWORK_TYPE="Ethernet"
            WIFI_SSID=""
            rx_save_state
            rx_clear_logo
            echo
            gum style --foreground 2 "Ethernet connected"
            echo
            return 0
        fi
    fi

    rx_clear_logo
    echo
    gum style --foreground 1 "Network unavailable"
    echo
    return 1
}

if ! setup_network; then
    rx_setup_fail "Network"
fi