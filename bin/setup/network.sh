#!/bin/bash

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

if [[ "${RETRO_SETUP_SOURCED:-}" != "1" ]]; then
    export RETRO_SETUP_SOURCED=1
    source "$RETRO_INSTALL/lib/display.sh"
    source "$RETRO_INSTALL/lib/errors.sh"
    source "$RETRO_INSTALL/lib/gum.sh"
    source "$RETRO_INSTALL/lib/wifi.sh"
    source "$RETRO_INSTALL/lib/qr.sh"
    source "$RETRO_INSTALL/lib/locale.sh"
    source "$RETRO_INSTALL/lib/timezone.sh"
    source "$RETRO_INSTALL/lib/handlers.sh"
    source "$RETRO_INSTALL/lib/output.sh"
    source "$RETRO_INSTALL/lib/debug.sh"
    rx_set_retro_colors
fi

if ! setup_network; then
    rx_clear_logo
    echo
    gum style --foreground 1 --padding "1 0 1 $PADDING_LEFT" "Network setup failed"
    echo
    gum style "Would you like to retry or exit?"
    echo
    if gum confirm --negative "Exit" --affirmative "Retry" "Network setup" --padding "$GUM_CONFIRM_PADDING"; then
        exec /opt/retrolinux/bin/retroinstall
    fi
    gum style "Run 'retroinstall' to try again"
    exit 1
fi