#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_network() {
    sudo -v
    rx_log "info" "Configuring network connection..."

    sudo systemctl enable NetworkManager.service 2>&1
    sudo systemctl start NetworkManager.service 2>&1
    sleep 2
    command -v nmcli &>/dev/null || sudo pacman -S --noconfirm networkmanager

    local current_con
    current_con=$(nmcli -t -f NAME,STATE connection show 2>/dev/null | grep "activated" | head -1)
    if [[ -n "$current_con" ]]; then
        rx_log "success" "Network connected: $current_con"
        return 0
    fi

    local eth_iface wifi_iface
    eth_iface=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep ":ethernet$" | cut -d: -f1 | head -1)
    wifi_iface=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep ":wifi$" | cut -d: -f1 | head -1)

    if [[ -n "$eth_iface" ]]; then
        nmcli device connect "$eth_iface" 2>&1
        rx_log "success" "Ethernet configured: $eth_iface"
        return 0
    fi

    if [[ -n "$wifi_iface" && -n "$WIFI_SSID" ]]; then
        nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" 2>&1
        if [[ $? -eq 0 ]]; then
            rx_log "success" "WiFi connected: $WIFI_SSID"
            return 0
        fi
    fi

    if [[ -n "$wifi_iface" ]]; then
        nmcli device wifi rescan 2>&1
        sleep 1
        nmcli device connect "$wifi_iface" 2>&1
        rx_log "success" "WiFi configured: $wifi_iface"
        return 0
    fi

    rx_log "warn" "No network adapters detected"
    return 1
}