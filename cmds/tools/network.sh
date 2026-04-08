#!/bin/bash

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
                    bash "$RETRO_DIR/scripts/network_core.sh" --wifi-on "$wifi_iface"
                    ;;
                off)
                    bash "$RETRO_DIR/scripts/network_core.sh" --wifi-off "$wifi_iface"
                    ;;
                list|scan)
                    bash "$RETRO_DIR/scripts/network_core.sh" --wifi-list "$wifi_iface"
                    ;;
                connect)
                    [[ -z "$subarg2" ]] && rx_log "error" "SSID required" && return 1
                    bash "$RETRO_DIR/scripts/network_core.sh" --wifi-connect "$subarg2" "$subarg3" "$wifi_iface"
                    ;;
                disconnect)
                    bash "$RETRO_DIR/scripts/network_core.sh" --wifi-disconnect "$wifi_iface"
                    ;;
                status)
                    bash "$RETRO_DIR/scripts/network_core.sh" --wifi-status "$wifi_iface"
                    ;;
                *)
                    rx_log "info" "Usage: retro network wifi <command>"
                    echo -e ""
                    echo -e " ${PINK}  ${RESET}WiFi commands${GRAY}:${RESET}"
                    printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "on" "Turn WiFi on"
                    printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "off" "Turn WiFi off"
                    printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "list" "List available networks"
                    printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "connect <ssid> [pass]" "Connect to a network"
                    printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "disconnect" "Disconnect current network"
                    printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "status" "Show WiFi status"
                    echo ""
                    ;;
            esac
            ;;

        ethernet|eth)
            local eth_iface
            eth_iface=$(ip link show 2>/dev/null | grep -E "^[0-9]+: eth[0-9]+|^[0-9]+: en[a-z0-9]+" | head -1 | awk -F': ' '{print $2}')
            : ${eth_iface:=eth0}

            bash "$RETRO_DIR/scripts/network_core.sh" --ethernet-status "$eth_iface"
            ;;

        status)
            bash "$RETRO_DIR/scripts/network_core.sh" --network-status
            ;;

        manual)
            [[ -z "$subarg1" || -z "$subarg2" ]] && rx_log "error" "Usage: network manual <interface> <ip>/<cidr> [gateway]" && return 1
            bash "$RETRO_DIR/scripts/network_core.sh" --manual-ip "$subarg1" "$subarg2" "$subarg3"
            ;;

        dhcp)
            [[ -z "$subarg1" ]] && rx_log "error" "Usage: network dhcp <interface>" && return 1
            bash "$RETRO_DIR/scripts/network_core.sh" --dhcp "$subarg1"
            ;;

        vlan)
            local vlan_action="${subarg1,,}"

            case "$vlan_action" in
                create)
                    [[ -z "$subarg2" || -z "$subarg3" ]] && rx_log "error" "Usage: network vlan create <parent> <vlan_id> [name]" && return 1
                    bash "$RETRO_DIR/scripts/network_core.sh" --vlan-create "$subarg2" "$subarg3" "$subarg4"
                    ;;
                delete)
                    [[ -z "$subarg2" ]] && rx_log "error" "Usage: network vlan delete <vlan_name>" && return 1
                    bash "$RETRO_DIR/scripts/network_core.sh" --vlan-delete "$subarg2"
                    ;;
                list)
                    bash "$RETRO_DIR/scripts/network_core.sh" --vlan-list
                    ;;
                *)
                    rx_log "info" "Usage: network vlan <command>"
                    echo -e ""
                    echo -e " ${PINK}  ${RESET}VLAN commands${GRAY}:${RESET}"
                    printf " ${PINK}%-24s${GRAY}- ${RESET}%s\n" "create <parent> <id> [name]" "Create a VLAN"
                    printf " ${PINK}%-24s${GRAY}- ${RESET}%s\n" "delete <vlan_name>" "Delete a VLAN"
                    printf " ${PINK}%-24s${GRAY}- ${RESET}%s\n" "list" "List active VLANs"
                    echo ""
                    ;;
            esac
            ;;

        dns)
            local dns_action="${subarg1,,}"

            case "$dns_action" in
                flush|clear)
                    bash "$RETRO_DIR/scripts/network_core.sh" --dns-flush
                    ;;
                *)
                    rx_log "info" "Usage: network dns <command>"
                    echo -e ""
                    echo -e " ${PINK}  ${RESET}DNS commands${GRAY}:${RESET}"
                    printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "flush" "Clear DNS cache"
                    echo ""
                    ;;
            esac
            ;;

        interface|if)
            bash "$RETRO_DIR/scripts/network_core.sh" --interface-info "$subarg1"
            ;;

        *)
            rx_log "info" "Usage: retro network <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "status" "Show network status overview"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "wifi [args]" "WiFi management"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "ethernet" "Show Ethernet status"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "manual <iface> <ip> [gw]" "Set static IP"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "dhcp <iface>" "Set DHCP"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "vlan [args]" "VLAN management"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "dns flush" "Clear DNS cache"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "interface [name]" "List/show interfaces"
            echo ""
            echo -e " ${PINK}  ${RESET}Examples${GRAY}:${RESET}"
            printf " ${GRAY}%-25s${RESET} %s\n" "retro network wifi list" "Scan for WiFi networks"
            printf " ${GRAY}%-25s${RESET} %s\n" "retro network wifi connect MyWifi" "Connect to open network"
            printf " ${GRAY}%-25s${RESET} %s\n" "retro network wifi connect MyWifi password" "Connect to secure network"
            printf " ${GRAY}%-25s${RESET} %s\n" "retro network manual eth0 192.168.1.10/24 192.168.1.1" "Set static IP"
            printf " ${GRAY}%-25s${RESET} %s\n" "retro network dhcp eth0" "Reset to DHCP"
            printf " ${GRAY}%-25s${RESET} %s\n" "retro network vlan create eth0 100" "Create VLAN 100"
            printf " ${GRAY}%-25s${RESET} %s\n" "retro network dns flush" "Clear DNS cache"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "network" "Manage network connections, WiFi, VLANs, and DNS" "cmd_network"
