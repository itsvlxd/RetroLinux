#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_network() {
    rx_load_state
    rx_clear_logo
    rx_step "Configuring network..."

    _setup_ethernet() {
        local eth_iface
        eth_iface=$(rx_get_ethernet_iface)
        if [[ -n $eth_iface ]]; then
            ip link set "$eth_iface" up 2>/dev/null
        fi

        if rx_check_internet || (rx_wait_for_ethernet "$eth_iface" && rx_check_internet); then
            NETWORK_TYPE="Ethernet"
            WIFI_SSID=""
            WIFI_PASSWORD=""
            rx_save_state
            rx_clear_logo
            echo
            gum style --foreground 2 "Ethernet connected"
            echo
            return 0
        fi

        return 1
    }

    if gum confirm --affirmative "WiFi" --negative "Ethernet" "Select your network type" --default="$([[ $NETWORK_TYPE == "WiFi" ]] && echo true || echo false)" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        local wifi_iface
        wifi_iface=$(rx_get_wifi_iface)

        if [[ -z $wifi_iface ]]; then
            gum style --foreground 3 "No WiFi adapter detected, trying Ethernet..."
            echo
            if _setup_ethernet; then
                return 0
            fi
            rx_clear_logo
            echo
            gum style --foreground 1 "Network unavailable"
            echo
            rx_retry_or_exit "No network connection available" || rx_abort
            return 1
        fi

        local retry=0
        local max_retries=5
        while ((retry < max_retries)); do
            rx_select_wifi_network
            local result=$?

            if ((result == 0)); then
                NETWORK_TYPE="WiFi"
                WIFI_SSID="$WIFI_SELECTED_SSID"
                rx_save_state
                rx_clear_logo
                echo
                gum style --foreground 2 "WiFi connected: ${WIFI_SSID}"
                echo
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

        gum style --foreground 3 "WiFi connection failed, trying Ethernet..."
        echo
        if _setup_ethernet; then
            return 0
        fi

        rx_clear_logo
        echo
        gum style --foreground 1 "Network unavailable"
        echo
        rx_retry_or_exit "No network connection available" || rx_abort
        return 1
    fi

    if _setup_ethernet; then
        return 0
    fi

    rx_clear_logo
    echo
    gum style --foreground 1 "Ethernet connection failed"
    echo
    rx_retry_or_exit "Ethernet unavailable" || rx_abort
    return 1
}

if ! setup_network; then
    rx_setup_fail "Network"
fi
