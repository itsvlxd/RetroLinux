#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

get_wifi_interfaces() {
    ip link show | grep -E "^[0-9]+: wlan[0-9]+" | awk -F': ' '{print $2}'
}

get_ethernet_interfaces() {
    ip link show | grep -E "^[0-9]+: eth[0-9]+|^[0-9]+: en[a-z0-9]+" | awk -F': ' '{print $2}'
}

get_all_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$"
}

wifi_on() {
    local iface="${1:-wlan0}"
    ip link set "$iface" up
    rx_log "success" "WiFi interface ${PINK}$iface${RESET} is now UP"
}

wifi_off() {
    local iface="${1:-wlan0}"
    ip link set "$iface" down
    rx_log "info" "WiFi interface ${PINK}$iface${RESET} is now DOWN"
}

wifi_list() {
    local iface="${1:-wlan0}"

    if ! ip link show "$iface" >/dev/null 2>&1; then
        rx_log "error" "Interface ${PINK}$iface${RESET} not found"
        return 1
    fi

    local state=$(ip link show "$iface" | grep -o "state \w*" | awk '{print $2}')
    if [[ "$state" != "UP" ]]; then
        rx_log "warn" "Interface ${PINK}$iface${RESET} is DOWN. Bringing up..."
        ip link set "$iface" up
        sleep 2
    fi

    echo -e "\n ${PINK}󰤨  Available WiFi Networks${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    nmcli -t -f SSID,SIGNAL,SECURITY,BSSID device wifi list ifname "$iface" 2>/dev/null | while IFS=: read -r ssid signal security bssid; do
        [[ -z "$ssid" ]] && continue
        
        local signal_bars="▁▂▃▄▅▆▇"
        local signal_idx=$(( (signal * 8 / 100) ))
        [[ $signal_idx -gt 7 ]] && signal_idx=7
        local bars
        local filled=$((signal_idx / 2))
        local empty=$((8 - filled))
        bars=$(printf '%*s' "$filled" '' | tr ' ' '#')
        bars="$bars$(printf '%*s' "$empty" '' | tr ' ' '-')"
        
        local lock_icon="󰤂"
        [[ "$security" == "--" || -z "$security" ]] && lock_icon="󰤂" && security="Open"
        
        echo -e " ${PINK}󰤨${RESET} $ssid ${GRAY}($bssid)${RESET}"
        echo -e "   ${PINK}󰤂${RESET} Signal: ${PINK}$bars${RESET} ${GRAY}$signal%${RESET} | Security: ${PINK}$security${RESET}"
    done

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

wifi_connect() {
    local ssid="$1"
    local password="$2"
    local iface="${3:-wlan0}"

    if [[ -z "$ssid" ]]; then
        rx_log "error" "SSID is required"
        return 1
    fi

    if ! ip link show "$iface" >/dev/null 2>&1; then
        rx_log "error" "Interface ${PINK}$iface${RESET} not found"
        return 1
    fi

    ip link set "$iface" up 2>/dev/null

    rx_log "info" "Connecting to ${PINK}$ssid${RESET}..."

    local current_ssid
    current_ssid=$(iwd station "$iface" show 2>/dev/null | grep "Connected network" | sed 's/.*: //')
    if [[ "$current_ssid" == "$ssid" ]]; then
        rx_log "success" "Already connected to ${PINK}$ssid${RESET}"
        return 0
    fi

    local is_iwd_active=false
    if systemctl is-active --quiet iwd 2>/dev/null; then
        is_iwd_active=true
    fi

    if [[ "$is_iwd_active" == "true" ]]; then
        if [[ -n "$password" ]]; then
            echo "connect $ssid
$password" | iwd station "$iface" 2>/dev/null
        else
            iwd station "$iface" connect "$ssid" 2>/dev/null
        fi
        
        local count=0
        while [[ $count -lt 15 ]]; do
            current_ssid=$(iwd station "$iface" show 2>/dev/null | grep "Connected network" | sed 's/.*: //')
            [[ "$current_ssid" == "$ssid" ]] && break
            sleep 1
            ((count++))
        done
        
        if [[ "$current_ssid" == "$ssid" ]]; then
            rx_log "success" "Connected to ${PINK}$ssid${RESET} (iwd)"
            return 0
        fi
    fi

    local existing=$(nmcli -t -f SSID device wifi list ifname "$iface" 2>/dev/null | grep "^$ssid$")
    
    if [[ -n "$existing" ]]; then
        local is_connected=$(nmcli -t -f GENERAL.CONNECTION device show "$iface" 2>/dev/null | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
        if [[ "$is_connected" == "$ssid" ]]; then
            rx_log "success" "Already connected to ${PINK}$ssid${RESET}"
            return 0
        fi
    fi

    if [[ -n "$password" ]]; then
        nmcli device wifi connect "$ssid" password "$password" ifname "$iface" >/dev/null 2>&1
    else
        nmcli device wifi connect "$ssid" ifname "$iface" >/dev/null 2>&1
    fi

    sleep 3

    local connected_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$iface" 2>/dev/null | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
    
    if [[ "$connected_ssid" == "$ssid" ]]; then
        rx_log "success" "Connected to ${PINK}$ssid${RESET}"
    else
        rx_log "error" "Failed to connect to ${PINK}$ssid${RESET}"
        return 1
    fi
}

wifi_disconnect() {
    local iface="${1:-wlan0}"
    nmcli device disconnect "$iface" >/dev/null 2>&1
    rx_log "info" "Disconnected from ${PINK}$iface${RESET}"
}

wifi_status() {
    local iface="${1:-wlan0}"

    echo -e "\n ${PINK}󰤨  WiFi Status${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo -e " ${GRAY}No WiFi interface found${RESET}"
        return 1
    fi

    local state=$(ip link show "$iface" | grep -o "state \w*" | awk '{print $2}')
    local state_color="$PINK"
    [[ "$state" == "DOWN" ]] && state_color="$MUTE"

    printf " ${PINK}󰈐${RESET} %-20s ${state_color}%s${RESET}\n" "Status:" "${state^^}"

    local conn_info=$(nmcli -t -f GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$iface" 2>/dev/null | tr -d '\r')
    
    local ssid=$(echo "$conn_info" | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
    local ipaddr=$(echo "$conn_info" | grep "IP4.ADDRESS\[1\]:" | sed 's/IP4.ADDRESS\[1\]://')
    local gateway=$(echo "$conn_info" | grep "IP4.GATEWAY:" | sed 's/IP4.GATEWAY://')
    local dns=$(echo "$conn_info" | grep "IP4.DNS\[1\]:" | sed 's/IP4.DNS\[1\]://')

    if [[ -z "$ssid" || "$ssid" == "--" ]]; then
        ssid=$(iwd station "$iface" show 2>/dev/null | grep "Connected network" | sed 's/.*: //')
        ipaddr=$(ip addr show "$iface" 2>/dev/null | grep -oP "inet \K[\d.]+")
        gateway=$(ip route show default dev "$iface" 2>/dev/null | grep -oP "via \K[\d.]+")
    fi

    if [[ -n "$ssid" && "$ssid" != "--" ]]; then
        printf " ${PINK}󰤨${RESET} %-20s ${PINK}%s${RESET}\n" "Connected to:" "$ssid"
        printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "IP Address:" "$ipaddr"
        printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "Gateway:" "$gateway"
        printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "DNS:" "$dns"
    else
        printf " ${GRAY}%-20s ${GRAY}%s${RESET}\n" "Connected to:" "None"
    fi

    local mac=$(ip link show "$iface" | grep -oE "([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})" | head -1)
    printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "MAC Address:" "$mac"

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

ethernet_status() {
    local iface="${1:-eth0}"

    echo -e "\n ${PINK}󰈊  Ethernet Status${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    if ! ip link show "$iface" >/dev/null 2>&1; then
        rx_log "error" "No Ethernet interface found: ${PINK}$iface${RESET}"
        return 1
    fi

    local state=$(ip link show "$iface" | grep -o "state \w*" | awk '{print $2}')
    local state_color="$PINK"
    [[ "$state" == "DOWN" ]] && state_color="$MUTE"

    printf " ${PINK}󰈐${RESET} %-20s ${state_color}%s${RESET}\n" "Status:" "${state^^}"

    local conn_info=$(nmcli -t -f GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$iface" 2>/dev/null | tr -d '\r')
    
    local ssid=$(echo "$conn_info" | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
    local ipaddr=$(echo "$conn_info" | grep "IP4.ADDRESS\[1\]:" | sed 's/IP4.ADDRESS\[1\]://')
    local gateway=$(echo "$conn_info" | grep "IP4.GATEWAY:" | sed 's/IP4.GATEWAY://')
    local dns=$(echo "$conn_info" | grep "IP4.DNS\[1\]:" | sed 's/IP4.DNS\[1\]://')

    if [[ -n "$ssid" && "$ssid" != "--" ]]; then
        printf " ${PINK}󰈊${RESET} %-20s ${PINK}%s${RESET}\n" "Connection:" "$ssid"
    fi
    
    if [[ -n "$ipaddr" && "$ipaddr" != "--" ]]; then
        printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "IP Address:" "$ipaddr"
        printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "Gateway:" "$gateway"
        printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "DNS:" "$dns"
    else
        printf " ${GRAY}%-20s ${GRAY}%s${RESET}\n" "IP Address:" "DHCP"
    fi

    local mac=$(ip link show "$iface" | grep -oE "([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})" | head -1)
    printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "MAC Address:" "$mac"

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

network_status() {
    echo -e "\n ${PINK}󰤪  Network Status${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    local wifi_iface
    wifi_iface=$(get_wifi_interfaces | head -1)
    local eth_iface
    eth_iface=$(get_ethernet_interfaces | head -1)

    if [[ -n "$wifi_iface" ]]; then
        local wifi_state=$(ip link show "$wifi_iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
        local wifi_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$wifi_iface" 2>/dev/null | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
        
        if [[ -z "$wifi_ssid" || "$wifi_ssid" == "--" ]]; then
            wifi_ssid=$(iwd station "$wifi_iface" show 2>/dev/null | grep "Connected network" | sed 's/.*: //')
        fi
        
        printf " ${PINK}󰤨${RESET} %-20s ${PINK}%s${RESET}\n" "WiFi:" "$wifi_iface (${wifi_state,,})"
        if [[ -n "$wifi_ssid" && "$wifi_ssid" != "--" ]]; then
            printf " ${PINK}󰤨${RESET} %-20s ${GRAY}%s${RESET}\n" "  Connected:" "$wifi_ssid"
        fi
    fi

    if [[ -n "$eth_iface" ]]; then
        local eth_state=$(ip link show "$eth_iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
        printf " ${PINK}󰈊${RESET} %-20s ${PINK}%s${RESET}\n" "Ethernet:" "$eth_iface (${eth_state,,})"
    fi

    local primary=$(nmcli -t -f name,type,device connection show --active 2>/dev/null | grep ethernet | head -1 | cut -d: -f1)
    if [[ -n "$primary" ]]; then
        printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "Primary:" "$primary"
    fi

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

manual_ip() {
    local iface="$1"
    local ip_cidr="$2"
    local gateway="$3"

    if [[ -z "$iface" || -z "$ip_cidr" ]]; then
        rx_log "error" "Interface and IP address required"
        rx_log "info" "Usage: network manual <interface> <ip>/<cidr> [gateway]"
        return 1
    fi

    if ! ip link show "$iface" >/dev/null 2>&1; then
        rx_log "error" "Interface ${PINK}$iface${RESET} not found"
        return 1
    fi

    rx_log "info" "Setting static IP on ${PINK}$iface${RESET}..."

    local ip_part="${ip_cidr%/*}"
    local cidr="${ip_cidr#*/}"
    
    if [[ -z "$cidr" || "$cidr" == "$ip_cidr" ]]; then
        cidr=24
    fi

    local netmask
    case $cidr in
        32) netmask="255.255.255.255" ;;
        31) netmask="255.255.255.254" ;;
        30) netmask="255.255.255.252" ;;
        29) netmask="255.255.255.248" ;;
        28) netmask="255.255.255.240" ;;
        27) netmask="255.255.255.224" ;;
        26) netmask="255.255.255.192" ;;
        25) netmask="255.255.255.128" ;;
        24) netmask="255.255.255.0" ;;
        23) netmask="255.255.254.0" ;;
        22) netmask="255.255.252.0" ;;
        21) netmask="255.255.248.0" ;;
        20) netmask="255.255.240.0" ;;
        16) netmask="255.255.0.0" ;;
        8) netmask="255.0.0.0" ;;
        *) netmask="255.255.255.0" ;;
    esac

    ip addr flush dev "$iface" >/dev/null 2>&1
    ip addr add "$ip_cidr" dev "$iface" >/dev/null 2>&1

    if [[ -n "$gateway" ]]; then
        ip route replace default via "$gateway" dev "$iface" >/dev/null 2>&1
    fi

    nmcli connection modify "$iface" ipv4.method manual ipv4.addresses "$ip_cidr" >/dev/null 2>&1
    [[ -n "$gateway" ]] && nmcli connection modify "$iface" ipv4.gateway "$gateway" >/dev/null 2>&1

    rx_log "success" "Static IP ${PINK}$ip_cidr${RESET} set on ${PINK}$iface${RESET}"
    [[ -n "$gateway" ]] && rx_log "info" "Gateway: ${PINK}$gateway${RESET}"
}

set_dhcp() {
    local iface="$1"

    if [[ -z "$iface" ]]; then
        rx_log "error" "Interface required"
        rx_log "info" "Usage: network dhcp <interface>"
        return 1
    fi

    if ! ip link show "$iface" >/dev/null 2>&1; then
        rx_log "error" "Interface ${PINK}$iface${RESET} not found"
        return 1
    fi

    rx_log "info" "Setting DHCP on ${PINK}$iface${RESET}..."

    ip addr flush dev "$iface" >/dev/null 2>&1
    ip link set "$iface" down
    sleep 1
    ip link set "$iface" up

    nmcli connection modify "$iface" ipv4.method auto >/dev/null 2>&1
    nmcli connection down "$iface" >/dev/null 2>&1
    sleep 1
    nmcli connection up "$iface" >/dev/null 2>&1

    rx_log "success" "DHCP enabled on ${PINK}$iface${RESET}"
}

vlan_create() {
    local parent="$1"
    local vlan_id="$2"
    local vlan_name="${3:-${parent}.${vlan_id}}"

    if [[ -z "$parent" || -z "$vlan_id" ]]; then
        rx_log "error" "Parent interface and VLAN ID required"
        rx_log "info" "Usage: network vlan create <parent> <vlan_id> [name]"
        return 1
    fi

    if ! ip link show "$parent" >/dev/null 2>&1; then
        rx_log "error" "Parent interface ${PINK}$parent${RESET} not found"
        return 1
    fi

    rx_log "info" "Creating VLAN ${PINK}$vlan_id${RESET} on ${PINK}$parent${RESET}..."

    ip link add link "$parent" name "$vlan_name" type vlan id "$vlan_id" 2>/dev/null
    ip link set "$vlan_name" up

    rx_log "success" "VLAN ${PINK}$vlan_name${RESET} (ID: $vlan_id) created"
}

vlan_delete() {
    local vlan_name="$1"

    if [[ -z "$vlan_name" ]]; then
        rx_log "error" "VLAN name required"
        rx_log "info" "Usage: network vlan delete <vlan_name>"
        return 1
    fi

    if ! ip link show "$vlan_name" >/dev/null 2>&1; then
        rx_log "error" "VLAN ${PINK}$vlan_name${RESET} not found"
        return 1
    fi

    ip link set "$vlan_name" down
    ip link delete "$vlan_name" 2>/dev/null

    rx_log "success" "VLAN ${PINK}$vlan_name${RESET} deleted"
}

vlan_list() {
    echo -e "\n ${PINK}󰤪  Active VLANs${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    local vlans=$(ip link show | grep -E "\.[0-9]+@" | awk -F': ' '{print $2}')
    
    if [[ -z "$vlans" ]]; then
        echo -e " ${GRAY}No VLANs found${RESET}"
        echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
        return 0
    fi

    for vlan in $vlans; do
        local info=$(ip -d link show "$vlan" | grep "vlan" | head -1)
        local vlan_id=$(echo "$info" | grep -oP "id \d+" | awk '{print $2}')
        local parent=$(echo "$info" | grep -oP "link.*" | awk '{print $2}')
        
        printf " ${PINK}󰤪${RESET} %-15s ${PINK}ID: %s${RESET} | Parent: ${GRAY}%s${RESET}\n" "$vlan" "$vlan_id" "$parent"
    done

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

dns_flush() {
    rx_log "info" "Flushing DNS cache..."

    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches 2>/dev/null
        rx_log "success" "systemd-resolved cache flushed"
    fi

    if command -v systemd-resolve >/dev/null 2>&1; then
        systemd-resolve --flush-caches 2>/dev/null
        rx_log "success" "systemd-resolve cache flushed"
    fi

    rm -rf /etc/.resolv.conf 2>/dev/null
    rm -rf /run/systemd/resolve/stub-resolv.conf 2>/dev/null
    rm -rf /run/nscd/hosts 2>/dev/null

    if pgrep -x nscd >/dev/null; then
        pkill -USR1 nscd 2>/dev/null
        rx_log "success" "nscd cache flushed"
    fi

    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        nmcli general reload 2>/dev/null
        rx_log "success" "NetworkManager reloaded"
    fi

    rx_log "success" "DNS cache cleared"
}

interface_info() {
    local iface="$1"

    if [[ -z "$iface" ]]; then
        echo -e "\n ${PINK}󰤪  Available Interfaces${RESET}"
        echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

        local wifis=$(get_wifi_interfaces)
        local eths=$(get_ethernet_interfaces)
        local vlans=$(ip link show | grep -E "\.[0-9]+@" | awk -F': ' '{print $2}')

        if [[ -n "$wifis" ]]; then
            echo -e " ${PINK}󰤨  WiFi:${RESET}"
            for w in $wifis; do
                local state=$(ip link show "$w" | grep -o "state \w*" | awk '{print $2}')
                echo -e "   ${PINK}$w${RESET} - ${state^^}"
            done
        fi

        if [[ -n "$eths" ]]; then
            echo -e " ${PINK}󰈊  Ethernet:${RESET}"
            for e in $eths; do
                local state=$(ip link show "$e" | grep -o "state \w*" | awk '{print $2}')
                echo -e "   ${PINK}$e${RESET} - ${state^^}"
            done
        fi

        if [[ -n "$vlans" ]]; then
            echo -e " ${PINK}󰤪  VLANs:${RESET}"
            for v in $vlans; do
                echo -e "   ${PINK}$v${RESET}"
            done
        fi

        echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
        return 0
    fi

    if ! ip link show "$iface" >/dev/null 2>&1; then
        rx_log "error" "Interface ${PINK}$iface${RESET} not found"
        return 1
    fi

    echo -e "\n ${PINK}󰈐  Interface: $iface${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    local state=$(ip link show "$iface" | grep -o "state \w*" | awk '{print $2}')
    local state_color="$PINK"
    [[ "$state" == "DOWN" ]] && state_color="$MUTE"

    printf " ${PINK}󰈐${RESET} %-20s ${state_color}%s${RESET}\n" "Status:" "${state^^}"

    local mac=$(ip link show "$iface" | grep -oE "([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})" | head -1)
    printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "MAC Address:" "$mac"

    local mtu=$(ip link show "$iface" | grep -oP "mtu \d+")
    printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "MTU:" "${mtu#mtu }"

    local ips=$(ip addr show "$iface" | grep -oP "inet \K[\d.]+/\d+")
    if [[ -n "$ips" ]]; then
        printf " ${PINK}󰈐${RESET} %-20s ${GRAY}%s${RESET}\n" "IP Addresses:" "$ips"
    fi

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

case "$1" in
    "--wifi-on") wifi_on "$2" ;;
    "--wifi-off") wifi_off "$2" ;;
    "--wifi-list") wifi_list "$2" ;;
    "--wifi-connect") wifi_connect "$2" "$3" "$4" ;;
    "--wifi-disconnect") wifi_disconnect "$2" ;;
    "--wifi-status") wifi_status "$2" ;;
    "--ethernet-status") ethernet_status "$2" ;;
    "--network-status") network_status ;;
    "--manual-ip") manual_ip "$2" "$3" "$4" ;;
    "--dhcp") set_dhcp "$2" ;;
    "--vlan-create") vlan_create "$2" "$3" "$4" ;;
    "--vlan-delete") vlan_delete "$2" ;;
    "--vlan-list") vlan_list ;;
    "--dns-flush") dns_flush ;;
    "--interface-info") interface_info "$2" ;;
esac
