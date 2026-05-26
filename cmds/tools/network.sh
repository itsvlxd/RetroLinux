#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"

cmd_network() {
    local action="${1,,}"
    local subarg1="$2"
    local subarg2="$3"
    local subarg3="$4"

    local wifi_iface
    wifi_iface=$(ip link show 2>/dev/null | grep -E "^[0-9]+: wlan[0-9]+" | head -1 | awk -F': ' '{print $2}')
    : ${wifi_iface:=wlan0}

    case "$action" in
        wifi)
            local wifi_action="${subarg1,,}"

            case "$wifi_action" in
                on)
                    local result=$(bash "$RETRO_DIR/scripts/network_core.sh" --wifi-on "$wifi_iface")
                    local status=$(echo "$result" | grep -oP "result=\K[^|]+")
                    if [[ "$status" == "success" ]]; then
                        rx_log "success" "WiFi interface ${PINK}$wifi_iface${RESET} is now UP"
                    fi
                    ;;
                off)
                    local result=$(bash "$RETRO_DIR/scripts/network_core.sh" --wifi-off "$wifi_iface")
                    local status=$(echo "$result" | grep -oP "result=\K[^|]+")
                    if [[ "$status" == "success" ]]; then
                        rx_log "info" "WiFi interface ${PINK}$wifi_iface${RESET} is now DOWN"
                    fi
                    ;;
                list|scan)
                    local scan_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --wifi-list "$wifi_iface")
                    if echo "$scan_result" | grep -q "result=error"; then
                        local reason=$(echo "$scan_result" | grep -oP "reason=\K[^|]+")
                        rx_log "error" "WiFi interface ${PINK}$wifi_iface${RESET} not found"
                        return 1
                    fi

                    local state=$(ip link show "$wifi_iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
                    if [[ "$state" != "UP" ]]; then
                        rx_log "warn" "Interface ${PINK}$wifi_iface${RESET} is DOWN. Bringing up..."
                        ip link set "$wifi_iface" up
                        sleep 2
                    fi

                    rx_table_header "󰤨" "Available WiFi Networks"

                    while IFS='|' read -r type ssid signal security bssid; do
                        [[ "$type" != "network" || -z "$ssid" ]] && continue
                        
                        local signal_bars="▁▂▃▄▅▆▇"
                        local signal_idx=$(( (signal * 8 / 100) ))
                        [[ $signal_idx -gt 7 ]] && signal_idx=7
                        local bars
                        local filled=$((signal_idx / 2))
                        local empty=$((8 - filled))
                        bars=$(printf '%*s' "$filled" '' | tr ' ' '#')
                        bars="$bars$(printf '%*s' "$empty" '' | tr ' ' '-')"
                        
                        local lock_icon="󰤂"
                        [[ "$security" == "Open" ]] && lock_icon="󰤂"
                        
                        rx_table_row "󰤨" "$ssid" "$bssid" "$PINK" "20"
                        rx_table_row "󰤂" "Signal" "$bars $signal% | $security" "$GRAY" "20"
                    done <<<"$scan_result"

                    rx_table_separator
                    rx_table_spacer
                    ;;
                connect)
                    [[ -z "$subarg2" ]] && rx_log "error" "SSID required" && return 1

                    rx_log "info" "Connecting to ${PINK}$subarg2${RESET}..."
                    local conn_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --wifi-connect "$subarg2" "$subarg3" "$wifi_iface")

                    local status=$(echo "$conn_result" | grep -oP "result=\K[^|]+")
                    local method=$(echo "$conn_result" | grep -oP "method=\K[^|]+")

                    if [[ "$status" == "success" ]]; then
                        rx_log "success" "Connected to ${PINK}$subarg2${RESET}"
                    elif [[ "$status" == "already_connected" ]]; then
                        rx_log "success" "Already connected to ${PINK}$subarg2${RESET}"
                    else
                        rx_log "error" "Failed to connect to ${PINK}$subarg2${RESET}"
                        return 1
                    fi
                    ;;
                disconnect)
                    bash "$RETRO_DIR/scripts/network_core.sh" --wifi-disconnect "$wifi_iface"
                    rx_log "info" "Disconnected from ${PINK}$wifi_iface${RESET}"
                    ;;
                status)
                    local status_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --wifi-status "$wifi_iface")

                    if echo "$status_result" | grep -q "result=error"; then
                        rx_log "error" "WiFi interface not found"
                        return 1
                    fi

                    local iface=$(echo "$status_result" | grep -oP "iface=\K[^|]+")
                    local state=$(echo "$status_result" | grep -oP "state=\K[^|]+")

                    local state_color="$PINK"
                    [[ "$state" == "DOWN" ]] && state_color="$MUTE"

                    rx_table_header "󰤨" "WiFi Status"
                    rx_table_row "󰈐" "Status:" "${state^^}" "$state_color" "20"

                    local ssid=$(echo "$status_result" | grep -oP "ssid=\K[^|]+")
                    local ip=$(echo "$status_result" | grep -oP "ip=\K[^|]+")
                    local gateway=$(echo "$status_result" | grep -oP "gateway=\K[^|]+")
                    local dns=$(echo "$status_result" | grep -oP "dns=\K[^|]+")

                    if [[ -n "$ssid" && "$ssid" != "none" ]]; then
                        rx_table_row "󰤨" "Connected to:" "$ssid" "$PINK" "20"
                        rx_table_row_gray "󰈐" "IP Address:" "$ip" "20"
                        rx_table_row_gray "󰈐" "Gateway:" "$gateway" "20"
                        rx_table_row_gray "󰈐" "DNS:" "$dns" "20"
                    else
                        rx_table_row "󰤨" "Connected to:" "None" "$GRAY" "20"
                    fi

                    local mac=$(echo "$status_result" | grep -oP "mac=\K[^|]+")
                    rx_table_row_gray "󰈐" "MAC Address:" "$mac" "20"
                    rx_table_separator
                    rx_table_spacer
                    ;;
                *)
                    rx_help_usage "retro network wifi <command>"
                    rx_help_commands "WiFi commands"
                    rx_help_cmd "on" "Turn WiFi on"
                    rx_help_cmd "off" "Turn WiFi off"
                    rx_help_cmd "list" "List available networks"
                    rx_help_cmd "connect <ssid> [pass]" "Connect to a network"
                    rx_help_cmd "disconnect" "Disconnect current network"
                    rx_help_cmd "status" "Show WiFi status"
                    rx_help_examples
                    rx_help_example "retro network wifi list" "Scan for WiFi networks"
                    rx_help_example "retro network wifi connect MyWifi" "Connect to open network"
                    rx_help_example "retro network wifi status" "Show WiFi status"
                    ;;
            esac
            ;;

        ethernet|eth)
            local eth_iface
            eth_iface=$(ip link show 2>/dev/null | grep -E "^[0-9]+: eth[0-9]+|^[0-9]+: en[a-z0-9]+" | head -1 | awk -F': ' '{print $2}')
            : ${eth_iface:=eth0}

            local eth_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --ethernet-status "$eth_iface")

            if echo "$eth_result" | grep -q "result=error"; then
                rx_log "error" "No Ethernet interface found: ${PINK}$eth_iface${RESET}"
                return 1
            fi

            local state=$(echo "$eth_result" | grep -oP "state=\K[^|]+")
            local state_color="$PINK"
            [[ "$state" == "DOWN" ]] && state_color="$MUTE"

            rx_table_header "󰈊" "Ethernet Status"
            rx_table_row "󰈐" "Status:" "${state^^}" "$state_color" "20"

            local conn=$(echo "$eth_result" | grep -oP "connection=\K[^|]+")
            local ip=$(echo "$eth_result" | grep -oP "ip=\K[^|]+")
            local gateway=$(echo "$eth_result" | grep -oP "gateway=\K[^|]+")
            local dns=$(echo "$eth_result" | grep -oP "dns=\K[^|]+")

            if [[ -n "$conn" && "$conn" != "none" ]]; then
                rx_table_row "󰈊" "Connection:" "$conn" "$PINK" "20"
            fi
            
            if [[ -n "$ip" && "$ip" != "none" ]]; then
                rx_table_row_gray "󰈐" "IP Address:" "$ip" "20"
                rx_table_row_gray "󰈐" "Gateway:" "$gateway" "20"
                rx_table_row_gray "󰈐" "DNS:" "$dns" "20"
            else
                rx_table_row_gray "󰈐" "IP Address:" "DHCP" "20"
            fi

            local mac=$(echo "$eth_result" | grep -oP "mac=\K[^|]+")
            rx_table_row_gray "󰈐" "MAC Address:" "$mac" "20"
            rx_table_separator
            rx_table_spacer
            ;;

        status)
            local net_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --network-status)

            local conn_type=$(echo "$net_result" | grep -oP "connection_type=\K[^|]+")
            local conn_iface=$(echo "$net_result" | grep -oP "conn_interface=\K[^|]+")
            local conn_ip=$(echo "$net_result" | grep -oP "conn_ip=\K[^|]+")
            local conn_gw=$(echo "$net_result" | grep -oP "conn_gateway=\K[^|]+")
            local conn_dns=$(echo "$net_result" | grep -oP "conn_dns=\K[^|]+")
            local conn_mac=$(echo "$net_result" | grep -oP "conn_mac=\K[^|]+")
            local internet=$(echo "$net_result" | grep -oP "internet=\K[^|]+")

            local wifi_if=$(echo "$net_result" | grep -oP "wifi_iface=\K[^|]+")
            local w_ssid=$(echo "$net_result" | grep -oP "wifi_ssid=\K[^|]+")
            local eth_if=$(echo "$net_result" | grep -oP "eth_iface=\K[^|]+")
            local e_state=$(echo "$net_result" | grep -oP "eth_state=\K[^|]+")

            rx_table_header "󰤪" "Network Status"

            if [[ $conn_type == "wifi" ]]; then
                local w_state=$(echo "$net_result" | grep -oP "wifi_state=\K[^|]+")
                local state_color="$SUCCESS"; [[ $w_state != "UP" ]] && state_color="$MUTE"
                rx_table_row "󰀐" "Connection:" "WiFi" "$PINK" "22"
                rx_table_row "󰤨" "Interface:" "$conn_iface" "$PINK" "22"
                rx_table_row "󰈐" "Status:" "${w_state^^}" "$state_color" "22"
                if [[ -n $w_ssid && $w_ssid != "none" ]]; then
                    rx_table_row "󰤨" "Connected to:" "$w_ssid" "$PINK" "22"
                fi
                rx_table_row_gray "󰈐" "IP Address:" "$conn_ip" "22"
                rx_table_row_gray "󰈐" "Gateway:" "${conn_gw:-none}" "22"
                rx_table_row_gray "󰈐" "DNS:" "${conn_dns:-none}" "22"
                rx_table_row_gray "󰈐" "MAC Address:" "$conn_mac" "22"
            elif [[ $conn_type == "ethernet" ]]; then
                local state_color="$SUCCESS"; [[ $e_state != "UP" ]] && state_color="$MUTE"
                rx_table_row "󰀐" "Connection:" "Ethernet" "$PINK" "22"
                rx_table_row "󰈊" "Interface:" "$conn_iface" "$PINK" "22"
                rx_table_row "󰈐" "Status:" "${e_state^^}" "$state_color" "22"
                rx_table_row_gray "󰈐" "IP Address:" "$conn_ip" "22"
                rx_table_row_gray "󰈐" "Gateway:" "${conn_gw:-none}" "22"
                rx_table_row_gray "󰈐" "DNS:" "${conn_dns:-none}" "22"
                rx_table_row_gray "󰈐" "MAC Address:" "$conn_mac" "22"
            else
                rx_table_row "󰀐" "Connection:" "None" "$MUTE" "22"
                if [[ -n $wifi_if && $wifi_if != "none" ]]; then
                    local w_state=$(echo "$net_result" | grep -oP "wifi_state=\K[^|]+")
                    rx_table_row "󰤨" "WiFi:" "$wifi_if (${w_state:-down})" "$MUTE" "22"
                fi
                if [[ -n $eth_if && $eth_if != "none" ]]; then
                    rx_table_row "󰈊" "Ethernet:" "$eth_if (${e_state:-down})" "$MUTE" "22"
                fi
            fi

            local inet_color="$SUCCESS"
            local inet_display="● Online"
            [[ $internet != "online" ]] && inet_color="$ERROR" && inet_display="● Offline"
            rx_table_row "󰅀" "Internet:" "$inet_display" "$inet_color" "22"

            if [[ $conn_type == "wifi" && -n $eth_if && $eth_if != "none" ]]; then
                rx_table_separator
                rx_table_row "󰈊" "Ethernet:" "$eth_if (${e_state:-down})" "$MUTE" "22"
            fi
            if [[ $conn_type == "ethernet" && -n $wifi_if && $wifi_if != "none" ]]; then
                local w_state=$(echo "$net_result" | grep -oP "wifi_state=\K[^|]+")
                rx_table_separator
                rx_table_row "󰤨" "WiFi:" "$wifi_if (${w_state:-down})" "$MUTE" "22"
                [[ -n $w_ssid && $w_ssid != "none" ]] && rx_table_row "󰤨" "  SSID:" "$w_ssid" "$MUTE" "22"
            fi

            rx_table_separator
            rx_table_spacer
            ;;

        manual)
            [[ -z "$subarg1" || -z "$subarg2" ]] && rx_log "error" "Usage: network manual <interface> <ip>/<cidr> [gateway]" && return 1

            local manual_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --manual-ip "$subarg1" "$subarg2" "$subarg3")

            if echo "$manual_result" | grep -q "result=error"; then
                rx_log "error" "Failed to set static IP"
                return 1
            fi

            rx_log "success" "Static IP ${PINK}$subarg2${RESET} set on ${PINK}$subarg1${RESET}"
            [[ -n "$subarg3" ]] && rx_log "info" "Gateway: ${PINK}$subarg3${RESET}"
            ;;

        dhcp)
            [[ -z "$subarg1" ]] && rx_log "error" "Usage: network dhcp <interface>" && return 1

            local dhcp_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --dhcp "$subarg1")

            if echo "$dhcp_result" | grep -q "result=error"; then
                rx_log "error" "Failed to set DHCP"
                return 1
            fi

            rx_log "success" "DHCP enabled on ${PINK}$subarg1${RESET}"
            ;;

        vlan)
            local vlan_action="${subarg1,,}"

            case "$vlan_action" in
                create)
                    [[ -z "$subarg2" || -z "$subarg3" ]] && rx_log "error" "Usage: network vlan create <parent> <vlan_id> [name]" && return 1
                    
                    local vlan_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --vlan-create "$subarg2" "$subarg3" "$subarg4")

                    if echo "$vlan_result" | grep -q "result=error"; then
                        rx_log "error" "Failed to create VLAN"
                        return 1
                    fi

                    local vlan_name=$(echo "$vlan_result" | grep -oP "vlan_name=\K[^|]+")
                    rx_log "success" "VLAN ${PINK}$vlan_name${RESET} (ID: $subarg3) created"
                    ;;
                delete)
                    [[ -z "$subarg2" ]] && rx_log "error" "Usage: network vlan delete <vlan_name>" && return 1

                    local del_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --vlan-delete "$subarg2")

                    if echo "$del_result" | grep -q "result=error"; then
                        rx_log "error" "VLAN ${PINK}$subarg2${RESET} not found"
                        return 1
                    fi

                    rx_log "success" "VLAN ${PINK}$subarg2${RESET} deleted"
                    ;;
                list)
                    local list_result=$(bash "$RETRO_DIR/scripts/network_core.sh" --vlan-list)

                    rx_table_header "󰤪" "Active VLANs"

                    if echo "$list_result" | grep -q "result=none"; then
                        rx_table_row "󰤪" "No VLANs found" "" "$GRAY" "30"
                    else
                        while IFS='|' read -r _ vlan vlan_id parent; do
                            rx_table_row "󰤪" "$vlan" "ID: $vlan_id | Parent: $parent" "$GRAY" "30"
                        done <<<"$list_result"
                    fi

            rx_table_separator
            rx_table_spacer
            ;;
                *)
                    rx_help_usage "network vlan <command>"
                    rx_help_commands "VLAN commands"
                    rx_help_cmd "create <parent> <id> [name]" "Create a VLAN"
                    rx_help_cmd "delete <vlan_name>" "Delete a VLAN"
                    rx_help_cmd "list" "List active VLANs"
                    ;;
            esac
            ;;

        dns)
            local dns_action="${subarg1,,}"

            case "$dns_action" in
                flush|clear)
                    bash "$RETRO_DIR/scripts/network_core.sh" --dns-flush
                    rx_log "success" "DNS cache cleared"
                    ;;
                *)
                    rx_help_usage "network dns <command>"
                    rx_help_commands "DNS commands"
                    rx_help_cmd "flush" "Clear DNS cache"
                    ;;
            esac
            ;;

        interface|if)
            bash "$RETRO_DIR/scripts/network_core.sh" --interface-info "$subarg1"
            ;;

        *)
            rx_help_usage "retro network <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show network status overview"
            rx_help_cmd "wifi [args]" "WiFi management"
            rx_help_cmd "ethernet" "Show Ethernet status"
            rx_help_cmd "manual <iface> <ip> [gw]" "Set static IP"
            rx_help_cmd "dhcp <iface>" "Set DHCP"
            rx_help_cmd "vlan [args]" "VLAN management"
            rx_help_cmd "dns flush" "Clear DNS cache"
            rx_help_cmd "interface [name]" "List/show interfaces"
            rx_help_examples
            rx_help_example "retro network wifi list" "Scan for WiFi networks"
            rx_help_example "retro network wifi connect MyWifi" "Connect to open network"
            rx_help_example "retro network wifi connect MyWifi password" "Connect to secure network"
            rx_help_example "retro network manual eth0 192.168.1.10/24 192.168.1.1" "Set static IP"
            rx_help_example "retro network dhcp eth0" "Reset to DHCP"
            rx_help_example "retro network vlan create eth0 100" "Create VLAN 100"
            rx_help_example "retro network dns flush" "Clear DNS cache"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "network" "Manage network connections, WiFi, VLANs, and DNS" "cmd_network"