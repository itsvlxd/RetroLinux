#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_network() {
    rx_load_state

    rx_clear_logo
    rx_step "Configuring network connection..."

    arch-chroot /mnt systemctl enable NetworkManager.service >/dev/null 2>&1
    arch-chroot /mnt systemctl start NetworkManager.service >/dev/null 2>&1

    sleep 3

    local wifi_iface=""
    local eth_iface=""

    eth_iface=$(arch-chroot /mnt nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep ":ethernet$" | cut -d: -f1 | head -1)
    wifi_iface=$(arch-chroot /mnt nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep ":wifi$" | cut -d: -f1 | head -1)

    if [[ -n "$eth_iface" ]]; then
        gum style "Ethernet detected: ${eth_iface}"
        echo

        arch-chroot /mnt nmcli connection add type ethernet ifname "$eth_iface" con-name "ethernet-connection" >/dev/null 2>&1
        arch-chroot /mnt nmcli connection up "ethernet-connection" >/dev/null 2>&1

        if [[ $? -eq 0 ]]; then
            gum style --foreground 2 "Ethernet configured"
        else
            gum style --foreground 3 "Warning: Ethernet configuration failed"
        fi
        echo
        return 0
    fi

    if [[ -n "$wifi_iface" ]]; then
        if [[ -n "$WIFI_SSID" && -n "$WIFI_PASSWORD" ]]; then
            gum style "Configuring WiFi: ${WIFI_SSID}"
            echo

            arch-chroot /mnt nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" >/dev/null 2>&1

            if [[ $? -eq 0 ]]; then
                gum style --foreground 2 "WiFi connected: ${WIFI_SSID}"
            else
                gum style --foreground 3 "Warning: WiFi connection failed"
            fi
        else
            gum style --foreground 7 "WiFi adapter detected: ${wifi_iface}"
            gum style "No saved credentials, skipping WiFi"
        fi
        echo
        return 0
    fi

    gum style --foreground 3 "No network adapters detected"
    echo
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rx_post_network "$@"
fi