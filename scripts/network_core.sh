#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "network"

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
        if ! _wifi_has_ip_and_internet "$iface"; then
            echo "result=error|reason=no_internet|ssid=$ssid"
            return 1
        fi

        echo "result=success|method=nmcli|ssid=$ssid"

        nmcli connection modify "$ssid" connection.interface-name "" 2>/dev/null
        nmcli connection modify "$ssid" 802-11-wireless.cloned-mac-address "random" 2>/dev/null
        nmcli connection up "$ssid" 2>/dev/null

        nmcli connection modify "$ssid" ipv4.dns "1.1.1.1 1.0.0.1" 2>/dev/null
        nmcli connection modify "$ssid" ipv4.ignore-auto-dns yes 2>/dev/null

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
            if ! _wifi_has_ip_and_internet "$iface"; then
                echo "result=error|reason=no_internet|ssid=$ssid"
                return 1
            fi
            echo "result=success|method=iwd|ssid=$ssid"
            return 0
        fi
    fi

    echo "result=error|reason=connection_failed|ssid=$ssid"
    return 1
}

_wifi_has_ip_and_internet() {
    local iface="$1"
    local ip_try=0
    while (( ip_try < 15 )); do
        if ip addr show "$iface" 2>/dev/null | grep -q "inet "; then
            break
        fi
        sleep 1
        ((ip_try++))
    done

    if ! ip addr show "$iface" 2>/dev/null | grep -q "inet "; then
        return 1
    fi

    local ping_try=0
    while (( ping_try < 10 )); do
        if ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
            return 0
        fi
        sleep 1
        ((ping_try++))
    done
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
    local wifi_iface eth_iface
    wifi_iface=$(get_wifi_interfaces | head -1)
    eth_iface=$(get_ethernet_interfaces | head -1)

    local conn_type="none" conn_iface="" conn_ip="" conn_gw="" conn_dns=""
    local wifi_state="down" wifi_ssid="none" eth_state="down"

    if [[ -n $wifi_iface ]]; then
        wifi_state=$(ip link show "$wifi_iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
        wifi_state="${wifi_state:-down}"
        wifi_ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$wifi_iface" 2>/dev/null | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
        if [[ -z $wifi_ssid || $wifi_ssid == "--" ]]; then
            command -v iwd >/dev/null 2>&1 && wifi_ssid=$(iwd station "$wifi_iface" show 2>/dev/null | grep "Connected network" | sed 's/.*: //')
        fi
        wifi_ssid="${wifi_ssid:-none}"
        if [[ $wifi_state == "UP" ]]; then
            local wip
            wip=$(ip -4 addr show "$wifi_iface" 2>/dev/null | grep -oP 'inet \K[\d.]+/\d+')
            if [[ -n $wip ]]; then
                conn_type="wifi"
                conn_iface="$wifi_iface"
                conn_ip="$wip"
            fi
        fi
    fi

    if [[ -n $eth_iface ]]; then
        eth_state=$(ip link show "$eth_iface" 2>/dev/null | grep -o "state \w*" | awk '{print $2}')
        eth_state="${eth_state:-down}"
        if [[ $conn_type == "none" && $eth_state == "UP" ]]; then
            local eip
            eip=$(ip -4 addr show "$eth_iface" 2>/dev/null | grep -oP 'inet \K[\d.]+/\d+')
            if [[ -n $eip ]]; then
                conn_type="ethernet"
                conn_iface="$eth_iface"
                conn_ip="$eip"
            fi
        fi
    fi

    if [[ $conn_type != "none" ]]; then
        conn_gw=$(ip route 2>/dev/null | grep "^default" | head -1 | awk '{print $3}')
        conn_gw="${conn_gw:-none}"
        conn_dns=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
        conn_dns="${conn_dns:-none}"
    fi

    local conn_mac
    if [[ -n $conn_iface ]]; then
        conn_mac=$(ip link show "$conn_iface" 2>/dev/null | grep -oP 'link/ether \K[\da-f:]+')
    fi
    conn_mac="${conn_mac:-none}"

    local internet="offline"
    ping -c1 -W2 1.1.1.1 &>/dev/null && internet="online"

    echo "wifi_iface=${wifi_iface:-none}|eth_iface=${eth_iface:-none}|connection_type=${conn_type}|conn_interface=${conn_iface:-none}|conn_ip=${conn_ip:-none}|conn_gateway=${conn_gw:-none}|conn_dns=${conn_dns:-none}|conn_mac=${conn_mac:-none}|internet=${internet}"

    [[ -n $wifi_iface ]] && echo "wifi_state=${wifi_state}|wifi_ssid=${wifi_ssid}"
    [[ -n $eth_iface ]] && echo "eth_state=${eth_state}"
}

manual_ip() {
    local iface="$1"
    local ip_cidr="$2"
    local gateway="$3"

    if [[ -z $iface || -z $ip_cidr ]]; then
        echo "result=error|reason=missing_params"
        return 1
    fi

    local conn_name
    conn_name=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$iface$" | cut -d: -f1)

    if [[ -z $conn_name ]]; then
        echo "result=error|reason=no_active_connection|iface=$iface"
        return 1
    fi

    nmcli connection modify "$conn_name" ipv4.method manual >/dev/null 2>&1
    nmcli connection modify "$conn_name" ipv4.addresses "$ip_cidr" >/dev/null 2>&1
    if [[ -n $gateway ]]; then
        nmcli connection modify "$conn_name" ipv4.gateway "$gateway" >/dev/null 2>&1
    fi
    nmcli connection modify "$conn_name" ipv4.dns "" >/dev/null 2>&1
    nmcli connection modify "$conn_name" ipv4.ignore-auto-dns yes >/dev/null 2>&1

    nmcli connection down "$conn_name" >/dev/null 2>&1
    ip addr flush dev "$iface" 2>/dev/null
    sleep 1
    nmcli connection up "$conn_name" >/dev/null 2>&1

    echo "result=success|iface=$iface|ip=$ip_cidr|gateway=${gateway:-none}"
}

set_dhcp() {
    local iface="$1"

    if [[ -z $iface ]]; then
        echo "result=error|reason=interface_required"
        return 1
    fi

    local conn_name
    conn_name=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$iface$" | cut -d: -f1)

    if [[ -z $conn_name ]]; then
        echo "result=error|reason=no_active_connection|iface=$iface"
        return 1
    fi

    nmcli connection modify "$conn_name" ipv4.method auto >/dev/null 2>&1
    nmcli connection modify "$conn_name" ipv4.addresses "" >/dev/null 2>&1
    nmcli connection modify "$conn_name" ipv4.gateway "" >/dev/null 2>&1
    nmcli connection modify "$conn_name" ipv4.dns "" >/dev/null 2>&1
    nmcli connection modify "$conn_name" ipv4.ignore-auto-dns no >/dev/null 2>&1

    nmcli connection down "$conn_name" >/dev/null 2>&1
    ip addr flush dev "$iface" 2>/dev/null
    sleep 1
    nmcli connection up "$conn_name" >/dev/null 2>&1

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

    if ! ip link add link "$parent" name "$vlan_name" type vlan id "$vlan_id" 2>/dev/null; then
        echo "result=error|reason=create_failed|parent=$parent|vlan_id=$vlan_id"
        return 1
    fi
    ip link set "$vlan_name" up 2>/dev/null

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

set_dns() {
    local iface="$1"
    local dns1="$2"
    local dns2="$3"

    [[ -z $iface || -z $dns1 ]] && echo "result=error|reason=missing_params" && return 1

    local conn_name
    conn_name=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$iface$" | cut -d: -f1)

    if [[ -n $conn_name ]]; then
        nmcli connection modify "$conn_name" ipv4.dns "$dns1${dns2:+ $dns2}" >/dev/null 2>&1
        nmcli connection modify "$conn_name" ipv4.ignore-auto-dns yes >/dev/null 2>&1
        nmcli connection down "$conn_name" >/dev/null 2>&1
        ip addr flush dev "$iface" 2>/dev/null
        sleep 1
        nmcli connection up "$conn_name" >/dev/null 2>&1
    else
        printf "nameserver %s\n" "$dns1" > /etc/resolv.conf
        [[ -n $dns2 ]] && printf "nameserver %s\n" "$dns2" >> /etc/resolv.conf
    fi

    echo "result=success|iface=$iface|dns1=$dns1|dns2=${dns2:-none}"
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

set_dns_provider() {
    local provider="$1"
    local iface="${2:-$(get_wifi_interfaces | head -1)}"

    [[ -z $provider ]] && echo "result=error|reason=provider_required" && return 1

    local dns1="" dns2=""

    case "$provider" in
        cloudflare)  dns1="1.1.1.1"; dns2="1.0.0.1" ;;
        google)      dns1="8.8.8.8"; dns2="8.8.4.4" ;;
        cloud9)      dns1="9.9.9.9"; dns2="149.112.112.112" ;;
        dhcp)
            local conn_name
            conn_name=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$iface$" | cut -d: -f1)
            if [[ -n $conn_name ]]; then
                nmcli connection modify "$conn_name" ipv4.method auto >/dev/null 2>&1
                nmcli connection modify "$conn_name" ipv4.dns "" >/dev/null 2>&1
                nmcli connection modify "$conn_name" ipv4.ignore-auto-dns no >/dev/null 2>&1
                nmcli connection down "$conn_name" >/dev/null 2>&1
                ip addr flush dev "$iface" 2>/dev/null
                sleep 1
                nmcli connection up "$conn_name" >/dev/null 2>&1
            fi
            echo "result=success|provider=dhcp|iface=$iface"
            return 0
            ;;
        *)
            echo "result=error|reason=unknown_provider|provider=$provider"
            return 1
            ;;
    esac

    local conn_name
    conn_name=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$iface$" | cut -d: -f1)

    if [[ -n $conn_name ]]; then
        nmcli connection modify "$conn_name" ipv4.dns "$dns1 $dns2" >/dev/null 2>&1
        nmcli connection modify "$conn_name" ipv4.ignore-auto-dns yes >/dev/null 2>&1
        nmcli connection down "$conn_name" >/dev/null 2>&1
        ip addr flush dev "$iface" 2>/dev/null
        sleep 1
        nmcli connection up "$conn_name" >/dev/null 2>&1
    fi

    echo "result=success|provider=$provider|dns1=$dns1|dns2=$dns2|iface=$iface"
}

get_dns_provider() {
    local iface="${1:-$(get_wifi_interfaces | head -1)}"
    local conn_name
    conn_name=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":$iface$" | cut -d: -f1)

    if [[ -n $conn_name ]]; then
        local ignore_dns
        ignore_dns=$(nmcli -t -f ipv4.ignore-auto-dns connection show "$conn_name" 2>/dev/null | sed 's/ipv4.ignore-auto-dns://')

        if [[ "$ignore_dns" == "no" || -z "$ignore_dns" ]]; then
            echo "provider=dhcp"
            return 0
        fi

        local dns_servers
        dns_servers=$(nmcli -t -f ipv4.dns connection show "$conn_name" 2>/dev/null | sed 's/ipv4.dns://')

        if echo "$dns_servers" | grep -q "1.1.1.1"; then
            echo "provider=cloudflare"
        elif echo "$dns_servers" | grep -q "8.8.8.8"; then
            echo "provider=google"
        elif echo "$dns_servers" | grep -q "9.9.9.9"; then
            echo "provider=cloud9"
        else
            echo "provider=custom|dns=$dns_servers"
        fi
    else
        echo "provider=dhcp"
    fi
}

net_stats() {
    local DEV=$(ip route show default 2>/dev/null | awk '/default/{print $5}' | head -1)
    [[ -z "$DEV" ]] && exit 1

    local PING=$(ping -c 1 -W 2 8.8.8.8 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/')
    local LOSS=$(ping -c 3 -W 2 8.8.8.8 2>/dev/null | grep -o '[0-9]*% packet loss' | grep -o '[0-9]*')
    local RX=$(cat "/sys/class/net/$DEV/statistics/rx_bytes" 2>/dev/null || echo 0)
    local TX=$(cat "/sys/class/net/$DEV/statistics/tx_bytes" 2>/dev/null || echo 0)
    local IP=$(ip -4 addr show "$DEV" 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -1)
    local GW=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)

    local STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/retro"
    mkdir -p "$STATE_DIR" 2>/dev/null
    local STATE_FILE="$STATE_DIR/net_stats.json"

    local CUM_RX=$RX CUM_TX=$TX
    if [[ -f "$STATE_FILE" ]]; then
        local prev_rx prev_tx prev_dev
        prev_dev=$(grep '^dev=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
        prev_rx=$(grep '^rx=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)
        prev_tx=$(grep '^tx=' "$STATE_FILE" 2>/dev/null | cut -d= -f2)

        if [[ -n "$prev_dev" && -n "$prev_rx" && -n "$prev_tx" ]]; then
            if [[ "$prev_dev" != "$DEV" ]]; then
                CUM_RX=$RX
                CUM_TX=$TX
            elif (( RX < prev_rx || TX < prev_tx )); then
                CUM_RX=$(( prev_rx + RX ))
                CUM_TX=$(( prev_tx + TX ))
            else
                CUM_RX=$RX
                CUM_TX=$TX
            fi
        fi
    fi

    cat > "$STATE_FILE" <<EOF
dev=$DEV
rx=$CUM_RX
tx=$CUM_TX
EOF

    echo "${PING:-0}|${LOSS:-0}|${RX:-0}|${TX:-0}|${IP:-N/A}|${GW:-N/A}|${CUM_RX}|${CUM_TX}"
}

wifi_saved() {
    nmcli -t -f NAME,TYPE connection show 2>/dev/null | grep ":802-11-wireless" | sed 's/:802-11-wireless//'
}

wifi_qr() {
    local iface="${1:-$(get_wifi_interfaces | head -1)}"

    local ssid
    ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$iface" 2>/dev/null | grep "GENERAL.CONNECTION:" | sed 's/GENERAL.CONNECTION://')
    [[ -z "$ssid" || "$ssid" == "--" ]] && exit 1

    local password
    password=$(nmcli -s -t -f 802-11-wireless-security.psk connection show "$ssid" 2>/dev/null | sed 's/802-11-wireless-security.psk://')
    [[ -z "$password" ]] && exit 1

    local ssid_escaped password_escaped
    ssid_escaped=$(printf '%s' "$ssid" | sed 's/\\/\\\\/g; s/;/\\;/g; s/:/\\:/g')
    password_escaped=$(printf '%s' "$password" | sed 's/\\/\\\\/g; s/;/\\;/g; s/:/\\:/g')

    local qr_string="WIFI:T:WPA;S:${ssid_escaped};P:${password_escaped};;"

    local tmp_png tmp_rgb output_dir output
    tmp_png=$(mktemp /tmp/wifi_qr_XXXXXX.png)
    tmp_rgb=$(mktemp /tmp/wifi_qr_XXXXXX.rgb)

    qrencode -o "$tmp_png" -s 8 -m 2 "$qr_string" 2>/dev/null
    [[ $? -ne 0 ]] && rm -f "$tmp_png" "$tmp_rgb" && exit 1

    python3 -c "
from PIL import Image
import sys
img = Image.open(sys.argv[1]).convert('RGB')
img.save(sys.argv[2], 'RGB')
" "$tmp_png" "$tmp_rgb" 2>/dev/null

    output_dir="${XDG_CACHE_HOME:-$HOME/.cache}/retro"
    mkdir -p "$output_dir" 2>/dev/null
    output="$output_dir/wifi_qr.png"

    python3 -c "
from PIL import Image
import sys
img = Image.open(sys.argv[1]).convert('RGB')
img.save(sys.argv[2], 'PNG')
" "$tmp_rgb" "$output" 2>/dev/null

    rm -f "$tmp_png" "$tmp_rgb"
    echo "$output"
}

wifi_forget() {
    local name="$1"
    [[ -z $name ]] && echo "result=error|reason=name_required" && return 1
    nmcli connection delete "$name" 2>/dev/null && echo "result=success|name=$name" || echo "result=error|reason=delete_failed"
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
    "--wifi-saved") wifi_saved ;;
    "--wifi-qr") wifi_qr "$2" ;;
    "--wifi-forget") wifi_forget "$2" ;;
    "--ethernet-status") ethernet_status "$2" ;;
    "--network-status") network_status ;;
    "--manual-ip") manual_ip "$2" "$3" "$4" ;;
    "--dhcp") set_dhcp "$2" ;;
    "--vlan-create") vlan_create "$2" "$3" "$4" ;;
    "--vlan-delete") vlan_delete "$2" ;;
    "--vlan-list") vlan_list ;;
    "--dns-flush") dns_flush ;;
    "--set-dns") set_dns "$2" "$3" "$4" ;;
    "--interface-info") interface_info "$2" ;;
    "--check-internet") check_internet && echo "result=online" || echo "result=offline" ;;
    "--net-stats") net_stats ;;
    "--set-dns-provider") set_dns_provider "$2" "$3" ;;
    "--get-dns-provider") get_dns_provider "$2" ;;
esac