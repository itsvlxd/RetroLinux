#!/bin/bash

get_wifi_interfaces() {
    ip link show | grep -E "^[0-9]+: w(l|lo|lp)[a-z0-9]+" | awk -F': ' '{print $2}'
}

get_ethernet_interfaces() {
    ip link show | grep -E "^[0-9]+: eth[0-9]+|^[0-9]+: en[a-z0-9]+" | awk -F': ' '{print $2}'
}

get_all_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$"
}

wifi_on() {
    local iface="${1:-$(get_wifi_interfaces | head -1)}"
    ip link set "$iface" up 2>/dev/null
    echo "result=success|iface=$iface|action=up"
}

wifi_off() {
    local iface="${1:-$(get_wifi_interfaces | head -1)}"
    ip link set "$iface" down 2>/dev/null
    echo "result=success|iface=$iface|action=down"
}

wifi_list() {
    local iface="${1:-$(get_wifi_interfaces | head -1)}"

    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "result=error|reason=interface_not_found|iface=$iface"
        return 1
    fi

    local state=$(ip link show "$iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
    if [[ $state != "UP" ]]; then
        ip link set "$iface" up 2>/dev/null
        sleep 2
    fi

    nmcli -t -f SSID,SIGNAL,SECURITY,BSSID device wifi list ifname "$iface" 2>/dev/null | while IFS=: read -r ssid signal security bssid; do
        [[ -z $ssid ]] && continue
        local sec="Open"
        [[ $security != "--" && -n $security ]] && sec="$security"
        echo "network|$ssid|$signal|$sec|$bssid"
    done
}

wifi_connect() {
    local ssid="$1"
    local password="$2"
    local iface="${3:-$(get_wifi_interfaces | head -1)}"

    if [[ -z $ssid ]]; then
        echo "result=error|reason=ssid_required"
        return 1
    fi

    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "result=error|reason=interface_not_found|iface=$iface"
        return 1
    fi

    ip link set "$iface" up 2>/dev/null
    sleep 1

    local connected_ssid
    connected_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$iface" 2>/dev/null | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
    if [[ "$connected_ssid" == "$ssid" ]]; then
        echo "result=already_connected|ssid=$ssid"
        return 0
    fi

    local nmcli_result
    if [[ -n $password ]]; then
        nmcli_result=$(nmcli device wifi connect "$ssid" password "$password" ifname "$iface" 2>&1)
    else
        nmcli_result=$(nmcli device wifi connect "$ssid" ifname "$iface" 2>&1)
    fi

    local count=0
    while [[ $count -lt 10 ]]; do
        connected_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$iface" 2>/dev/null | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
        [[ "$connected_ssid" == "$ssid" ]] && break
        sleep 1
        ((count++))
    done

    if [[ "$connected_ssid" == "$ssid" ]]; then
        echo "result=success|method=nmcli|ssid=$ssid"
        
        nmcli connection modify "$ssid" connection.interface-name "" 2>/dev/null
        nmcli connection modify "$ssid" 802-11-wireless.cloned-mac-address "random" 2>/dev/null
        nmcli connection up "$ssid" 2>/dev/null
        
        return 0
    fi

    if command -v iwd >/dev/null 2>&1 && systemctl is-active --quiet iwd 2>/dev/null; then
        echo "warn|nmcli failed, trying iwd fallback..."

        if [[ -n $password ]]; then
            echo "connect $ssid
$password" | iwd station "$iface" 2>/dev/null
        else
            iwd station "$iface" connect "$ssid" 2>/dev/null
        fi

        count=0
        while [[ $count -lt 15 ]]; do
            connected_ssid=$(iwd station "$iface" show 2>/dev/null | grep "Connected network" | sed 's/.*: //')
            [[ "$connected_ssid" == "$ssid" ]] && break
            sleep 1
            ((count++))
        done

        if [[ "$connected_ssid" == "$ssid" ]]; then
            echo "result=success|method=iwd|ssid=$ssid"
            return 0
        fi
    fi

    echo "result=error|reason=connection_failed|ssid=$ssid"
    return 1
}

wifi_disconnect() {
    local iface="${1:-$(get_wifi_interfaces | head -1)}"
    nmcli device disconnect "$iface" >/dev/null 2>&1
    echo "result=success|iface=$iface"
}

wifi_status() {
    local iface="${1:-$(get_wifi_interfaces | head -1)}"

    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "result=error|reason=interface_not_found|iface=$iface"
        return 1
    fi

    local state=$(ip link show "$iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
    echo "iface=$iface|state=$state"

    local conn_info=$(nmcli -t -f GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$iface" 2>/dev/null | tr -d '\r')

    local ssid=$(echo "$conn_info" | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
    local ipaddr=$(echo "$conn_info" | grep "IP4.ADDRESS\[1\]:" | sed 's/IP4.ADDRESS\[1\]://')
    local gateway=$(echo "$conn_info" | grep "IP4.GATEWAY:" | sed 's/IP4.GATEWAY://')
    local dns=$(echo "$conn_info" | grep "IP4.DNS\[1\]:" | sed 's/IP4.DNS\[1\]://')

    if [[ -z $ssid || $ssid == "--" ]]; then
        if command -v iwd >/dev/null 2>&1; then
            ssid=$(iwd station "$iface" show 2>/dev/null | grep "Connected network" | sed 's/.*: //')
            ipaddr=$(ip addr show "$iface" 2>/dev/null | grep -oP "inet \K[\d.]+")
            gateway=$(ip route show default dev "$iface" 2>/dev/null | grep -oP "via \K[\d.]+")
        fi
    fi

    echo "ssid=${ssid:-none}|ip=$ipaddr|gateway=$gateway|dns=$dns"

    local mac=$(ip link show "$iface" 2>/dev/null | grep -oE "([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})" | head -1)
    echo "mac=$mac"
}

ethernet_status() {
    local iface="${1:-eth0}"

    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "result=error|reason=interface_not_found|iface=$iface"
        return 1
    fi

    local state=$(ip link show "$iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
    echo "iface=$iface|state=$state"

    local conn_info=$(nmcli -t -f GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show "$iface" 2>/dev/null | tr -d '\r')

    local ssid=$(echo "$conn_info" | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
    local ipaddr=$(echo "$conn_info" | grep "IP4.ADDRESS\[1\]:" | sed 's/IP4.ADDRESS\[1\]://')
    local gateway=$(echo "$conn_info" | grep "IP4.GATEWAY:" | sed 's/IP4.GATEWAY://')
    local dns=$(echo "$conn_info" | grep "IP4.DNS\[1\]:" | sed 's/IP4.DNS\[1\]://')

    echo "connection=${ssid:-none}|ip=$ipaddr|gateway=$gateway|dns=$dns"

    local mac=$(ip link show "$iface" 2>/dev/null | grep -oE "([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})" | head -1)
    echo "mac=$mac"
}

network_status() {
    local wifi_iface
    wifi_iface=$(get_wifi_interfaces | head -1)
    local eth_iface
    eth_iface=$(get_ethernet_interfaces | head -1)

    echo "wifi_iface=${wifi_iface:-none}|eth_iface=${eth_iface:-none}"

    if [[ -n $wifi_iface ]]; then
        local wifi_state=$(ip link show "$wifi_iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
        local wifi_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$wifi_iface" 2>/dev/null | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')

        if [[ -z $wifi_ssid || $wifi_ssid == "--" ]]; then
            if command -v iwd >/dev/null 2>&1; then
                wifi_ssid=$(iwd station "$wifi_iface" show 2>/dev/null | grep "Connected network" | sed 's/.*: //')
            fi
        fi

        echo "wifi_state=${wifi_state:-down}|wifi_ssid=${wifi_ssid:-none}"
    fi

    if [[ -n $eth_iface ]]; then
        local eth_state=$(ip link show "$eth_iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
        echo "eth_state=${eth_state:-down}"
    fi

    local primary=$(nmcli -t -f name,type,device connection show --active 2>/dev/null | grep ethernet | head -1 | cut -d: -f1)
    echo "primary_connection=${primary:-none}"
}

manual_ip() {
    local iface="$1"
    local ip_cidr="$2"
    local gateway="$3"

    if [[ -z $iface || -z $ip_cidr ]]; then
        echo "result=error|reason=missing_params"
        return 1
    fi

    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "result=error|reason=interface_not_found|iface=$iface"
        return 1
    fi

    local ip_part="${ip_cidr%/*}"
    local cidr="${ip_cidr#*/}"

    if [[ -z $cidr || $cidr == "$ip_cidr" ]]; then
        cidr=24
    fi

    ip addr flush dev "$iface" >/dev/null 2>&1
    ip addr add "$ip_cidr" dev "$iface" >/dev/null 2>&1

    if [[ -n $gateway ]]; then
        ip route replace default via "$gateway" dev "$iface" >/dev/null 2>&1
    fi

    nmcli connection modify "$iface" ipv4.method manual ipv4.addresses "$ip_cidr" >/dev/null 2>&1
    [[ -n $gateway ]] && nmcli connection modify "$iface" ipv4.gateway "$gateway" >/dev/null 2>&1

    echo "result=success|iface=$iface|ip=$ip_cidr|gateway=${gateway:-none}"
}

set_dhcp() {
    local iface="$1"

    if [[ -z $iface ]]; then
        echo "result=error|reason=interface_required"
        return 1
    fi

    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "result=error|reason=interface_not_found|iface=$iface"
        return 1
    fi

    ip addr flush dev "$iface" >/dev/null 2>&1
    ip link set "$iface" down
    sleep 1
    ip link set "$iface" up

    nmcli connection modify "$iface" ipv4.method auto >/dev/null 2>&1
    nmcli connection down "$iface" >/dev/null 2>&1
    sleep 1
    nmcli connection up "$iface" >/dev/null 2>&1

    echo "result=success|iface=$iface|method=dhcp"
}

vlan_create() {
    local parent="$1"
    local vlan_id="$2"
    local vlan_name="${3:-${parent}.${vlan_id}}"

    if [[ -z $parent || -z $vlan_id ]]; then
        echo "result=error|reason=missing_params"
        return 1
    fi

    if ! ip link show "$parent" >/dev/null 2>&1; then
        echo "result=error|reason=parent_not_found|parent=$parent"
        return 1
    fi

    ip link add link "$parent" name "$vlan_name" type vlan id "$vlan_id" 2>/dev/null
    ip link set "$vlan_name" up

    echo "result=success|vlan_name=$vlan_name|vlan_id=$vlan_id|parent=$parent"
}

vlan_delete() {
    local vlan_name="$1"

    if [[ -z $vlan_name ]]; then
        echo "result=error|reason=vlan_name_required"
        return 1
    fi

    if ! ip link show "$vlan_name" >/dev/null 2>&1; then
        echo "result=error|reason=vlan_not_found|vlan=$vlan_name"
        return 1
    fi

    ip link set "$vlan_name" down
    ip link delete "$vlan_name" 2>/dev/null

    echo "result=success|vlan=$vlan_name"
}

vlan_list() {
    local vlans=$(ip link show | grep -E "\.[0-9]+@" | awk -F': ' '{print $2}')

    if [[ -z $vlans ]]; then
        echo "result=none"
        return 0
    fi

    for vlan in $vlans; do
        local info=$(ip -d link show "$vlan" | grep "vlan" | head -1)
        local vlan_id=$(echo "$info" | grep -oP "id \d+" | awk '{print $2}')
        local parent=$(echo "$info" | grep -oP "link.*" | awk '{print $2}')
        echo "vlan|$vlan|$vlan_id|$parent"
    done
}

dns_flush() {
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches 2>/dev/null
    fi

    if command -v systemd-resolve >/dev/null 2>&1; then
        systemd-resolve --flush-caches 2>/dev/null
    fi

    rm -rf /etc/.resolv.conf 2>/dev/null
    rm -rf /run/systemd/resolve/stub-resolv.conf 2>/dev/null
    rm -rf /run/nscd/hosts 2>/dev/null

    if pgrep -x nscd >/dev/null; then
        pkill -USR1 nscd 2>/dev/null
    fi

    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        nmcli general reload 2>/dev/null
    fi

    echo "result=success"
}

interface_info() {
    local iface="$1"

    if [[ -z $iface ]]; then
        local wifis=$(get_wifi_interfaces)
        local eths=$(get_ethernet_interfaces)
        local vlans=$(ip link show | grep -E "\.[0-9]+@" | awk -F': ' '{print $2}')

        echo "wifi_interfaces=$wifis"
        echo "ethernet_interfaces=$eths"
        echo "vlan_interfaces=$vlans"
        return 0
    fi

    if ! ip link show "$iface" >/dev/null 2>&1; then
        echo "result=error|reason=interface_not_found|iface=$iface"
        return 1
    fi

    local state=$(ip link show "$iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
    local mac=$(ip link show "$iface" 2>/dev/null | grep -oE "([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})" | head -1)
    local mtu=$(ip link show "$iface" 2>/dev/null | grep -oP "mtu \d+")
    local ips=$(ip addr show "$iface" 2>/dev/null | grep -oP "inet \K[\d.]+/\d+")

    echo "iface=$iface|state=$state|mac=$mac|mtu=${mtu#mtu }|ips=$ips"
}

check_internet() {
    ping -c 1 -W 3 1.1.1.1 &>/dev/null
}

wifi_autoconnect() {
    local wifi_iface
    wifi_iface=$(get_wifi_interfaces | head -1)
    
    [[ -z $wifi_iface ]] && return 1
    
    local conn_name
    conn_name=$(nmcli -t -f NAME,DEVICE connection show active 2>/dev/null | grep -v "^lo" | head -1 | cut -d: -f1)
    
    if [[ -n $conn_name ]]; then
        echo "result=already_connected|connection=$conn_name"
        return 0
    fi
    
    local saved_con
    saved_con=$(nmcli -t -f connection.id connection show 2>/dev/null | head -1 | cut -d: -f2)
    
    if [[ -n $saved_con ]]; then
        nmcli connection up "$saved_con" 2>/dev/null
        sleep 2
        
        if ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
            echo "result=autoconnect|connection=$saved_con"
            return 0
        fi
    fi
    
    local available_iface
    available_iface=$(get_wifi_interfaces | head -1)
    if [[ -n $available_iface ]]; then
        ip link set "$available_iface" up 2>/dev/null
        sleep 1
        
        local saved_con
        saved_con=$(nmcli -t -f connection.id connection show 2>/dev/null | head -1 | cut -d: -f2)
        
        if [[ -n $saved_con ]]; then
            nmcli device wifi connect "$saved_con" ifname "$available_iface" 2>/dev/null
            sleep 3
            
            if ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
                nmcli connection modify "$saved_con" connection.interface-name "" 2>/dev/null
                echo "result=reconnected|connection=$saved_con"
                return 0
            fi
        fi
    fi
    
    echo "result=no_connection"
    return 1
}

case "$1" in
    "--wifi-on") wifi_on "$2" ;;
    "--wifi-off") wifi_off "$2" ;;
    "--wifi-list") wifi_list "$2" ;;
    "--wifi-connect") wifi_connect "$2" "$3" "$4" ;;
    "--wifi-disconnect") wifi_disconnect "$2" ;;
    "--wifi-status") wifi_status "$2" ;;
    "--wifi-autoconnect") wifi_autoconnect ;;
    "--ethernet-status") ethernet_status "$2" ;;
    "--network-status") network_status ;;
    "--manual-ip") manual_ip "$2" "$3" "$4" ;;
    "--dhcp") set_dhcp "$2" ;;
    "--vlan-create") vlan_create "$2" "$3" "$4" ;;
    "--vlan-delete") vlan_delete "$2" ;;
    "--vlan-list") vlan_list ;;
    "--dns-flush") dns_flush ;;
    "--interface-info") interface_info "$2" ;;
    "--check-internet") check_internet && echo "result=online" || echo "result=offline" ;;
esac