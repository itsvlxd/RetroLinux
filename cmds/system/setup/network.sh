#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/menu.sh"

setup_network() {
    sudo -v
    rx_log "info" "Configuring network connection..."

    sudo systemctl enable NetworkManager.service 2>&1 | tail -1
    sudo systemctl start NetworkManager.service 2>&1 | tail -1
    sleep 2

    command -v nmcli &>/dev/null || sudo pacman -S --noconfirm networkmanager 2>&1 | tail -3

    local net_status
    net_status=$(bash "$RETRO_DIR/scripts/network_core.sh" --network-status)
    local current_con
    current_con=$(echo "$net_status" | grep -oP "primary_connection=\K[^|]+")

    if [[ -n $current_con && $current_con != "none" ]]; then
        rx_log "success" "Network already connected: $current_con"
        return 0
    fi

    local eth_iface wifi_iface
    eth_iface=$(ip link show 2>/dev/null | grep -E "^[0-9]+: eth[0-9]+|^[0-9]+: en[a-z0-9]+" | grep -v "^lo" | awk -F': ' '{print $2}' | head -1)
    wifi_iface=$(ip link show 2>/dev/null | grep -E "^[0-9]+: w(l|lo|lp)[a-z0-9]+" | awk -F': ' '{print $2}' | head -1)

    rx_log "info" "Detected interfaces: eth=${eth_iface:-none} wifi=${wifi_iface:-none}"

    if [[ -n $eth_iface ]]; then
        rx_log "info" "Configuring ethernet: $eth_iface"
        sudo ip link set "$eth_iface" up 2>&1
        sleep 2

        if ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
            rx_log "success" "Ethernet connected: $eth_iface"
            return 0
        fi
    fi

    if [[ -n $wifi_iface && -n $WIFI_SSID && -n $WIFI_PASSWORD ]]; then
        rx_log "info" "Connecting to WiFi: $WIFI_SSID"

        local conn_result
        conn_result=$(sudo RETRO_DIR="$RETRO_DIR" bash "$RETRO_DIR/scripts/network_core.sh" --wifi-connect "$WIFI_SSID" "$WIFI_PASSWORD" "$wifi_iface")

        local status
        status=$(echo "$conn_result" | grep -oP "result=\K[^|]+")

        if [[ $status == "success" || $status == "already_connected" ]]; then
            rx_log "success" "WiFi connected: $WIFI_SSID"
            
            sudo nmcli connection modify "$WIFI_SSID" connection.interface-name "" 2>/dev/null || true
            sudo nmcli connection modify "$WIFI_SSID" 802-11-wireless.cloned-mac-address "random" 2>/dev/null || true
            sudo nmcli connection up "$WIFI_SSID" 2>/dev/null || true
            
            rx_log "info" "WiFi connection made persistent (interface-agnostic)"
            return 0
        else
            rx_log "warn" "WiFi connection failed, trying alternative method..."

            sudo nmcli device wifi delete "$WIFI_SSID" 2>/dev/null || true

            sudo nmcli device wifi hotspot ifname "$wifi_iface" ssid "temp-connection" password "temp1234" 2>&1 | tail -1
            sudo nmcli connection down "temp-connection" 2>&1 | tail -1
            sudo nmcli connection delete "temp-connection" 2>&1 | tail -1

            conn_result=$(sudo RETRO_DIR="$RETRO_DIR" bash "$RETRO_DIR/scripts/network_core.sh" --wifi-connect "$WIFI_SSID" "$WIFI_PASSWORD" "$wifi_iface")
            status=$(echo "$conn_result" | grep -oP "result=\K[^|]+")

            if [[ $status == "success" ]]; then
                rx_log "success" "WiFi connected: $WIFI_SSID"
                
                sudo nmcli connection modify "$WIFI_SSID" connection.interface-name "" 2>/dev/null || true
                sudo nmcli connection modify "$WIFI_SSID" 802-11-wireless.cloned-mac-address "random" 2>/dev/null || true
                sudo nmcli connection up "$WIFI_SSID" 2>/dev/null || true
                
                rx_log "info" "WiFi connection made persistent (interface-agnostic)"
                return 0
            fi
        fi
    fi

    if [[ -n $wifi_iface ]]; then
        rx_log "info" "No saved WiFi credentials, scanning for networks..."

        sudo RETRO_DIR="$RETRO_DIR" bash "$RETRO_DIR/scripts/network_core.sh" --wifi-on "$wifi_iface" >/dev/null
        sleep 2

        local scan_result
        scan_result=$(sudo RETRO_DIR="$RETRO_DIR" bash "$RETRO_DIR/scripts/network_core.sh" --wifi-list "$wifi_iface")

        local ssid_list
        ssid_list=$(echo "$scan_result" | grep "^network|" | cut -d'|' -f2 | sort -u)

        if [[ -z $ssid_list ]]; then
            rx_log "warn" "No WiFi networks found"
        else
            local options=()
            while IFS= read -r ssid; do
                [[ -n $ssid ]] && options+=("$ssid")
            done <<<"$ssid_list"

            if [[ ${#options[@]} -gt 0 ]]; then
                local selected_ssid
                selected_ssid=$(rx_menu "󰤨" "Select WiFi Network" "${options[@]}")

                if [[ -n $selected_ssid ]]; then
                    rx_log "info" "Selected network: $selected_ssid"

                    echo ""
                    echo -ne " ${PINK}󰄾${RESET} Enter WiFi password: "
                    read -r -s wifi_password
                    echo ""

                    if [[ -n $wifi_password ]]; then
                        local conn_result
                        conn_result=$(sudo RETRO_DIR="$RETRO_DIR" bash "$RETRO_DIR/scripts/network_core.sh" --wifi-connect "$selected_ssid" "$wifi_password" "$wifi_iface")

                        local status
                        status=$(echo "$conn_result" | grep -oP "result=\K[^|]+")

                        if [[ $status == "success" ]]; then
                            WIFI_SSID="$selected_ssid"
                            WIFI_PASSWORD="$wifi_password"
                            rx_log "success" "WiFi connected: $selected_ssid"
                            
                            sudo nmcli connection modify "$selected_ssid" connection.interface-name "" 2>/dev/null || true
                            sudo nmcli connection modify "$selected_ssid" 802-11-wireless.cloned-mac-address "random" 2>/dev/null || true
                            sudo nmcli connection up "$selected_ssid" 2>/dev/null || true
                            
                            rx_log "info" "WiFi connection made persistent (interface-agnostic)"
                            return 0
                        else
                            rx_log "error" "Failed to connect to $selected_ssid"
                        fi
                    else
                        rx_log "warn" "No password entered"
                    fi
                fi
            fi
        fi
    fi

    rx_log "warn" "No network connectivity established"
    return 1
}

