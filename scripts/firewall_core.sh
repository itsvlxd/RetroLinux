#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/variable.sh"
rx_log_register "firewall"

SUDO_CMD="sudo"
[[ $EUID -eq 0 ]] && SUDO_CMD=""

_engines_available() {
    local list=()
    command -v nft &>/dev/null && list+=("nftables")
    command -v ufw &>/dev/null && list+=("ufw")
    command -v firewall-cmd &>/dev/null && list+=("firewalld")
    command -v iptables &>/dev/null && list+=("iptables")
    echo "${list[@]}"
}

_engine_get() {
    local configured
    configured=$(get_var "FIREWALL_ENGINE" "auto")
    if [[ -z $configured || $configured == "auto" ]]; then
        configured=$(_engines_available | awk '{print $1}')
        [[ -z $configured ]] && configured="none"
    fi
    echo "$configured"
}

_disable_competing() {
    local active="$1"
    for eng in nftables ufw firewalld iptables; do
        [[ $eng == $active ]] && continue
        $SUDO_CMD systemctl stop "$eng" 2>/dev/null || true
        $SUDO_CMD systemctl disable "$eng" 2>/dev/null || true
        $SUDO_CMD systemctl mask "$eng" 2>/dev/null || true
    done
    if [[ $active != "ufw" ]]; then
        $SUDO_CMD ufw --force disable 2>/dev/null || true
    fi
}

_nft_chain_exists() {
    $SUDO_CMD nft list chain inet filter "$1" &>/dev/null
}

_nft_ensure_basic() {
    if ! $SUDO_CMD nft list tables 2>/dev/null | grep -q "inet filter"; then
        $SUDO_CMD nft flush ruleset 2>/dev/null || true
        $SUDO_CMD nft add table inet filter 2>/dev/null || true
    fi
    if ! _nft_chain_exists "input"; then
        $SUDO_CMD nft add chain inet filter input '{ type filter hook input priority 0; policy drop; }' 2>/dev/null || true
    fi
    if ! _nft_chain_exists "forward"; then
        $SUDO_CMD nft add chain inet filter forward '{ type filter hook forward priority 0; policy drop; }' 2>/dev/null || true
    fi
    if ! _nft_chain_exists "output"; then
        $SUDO_CMD nft add chain inet filter output '{ type filter hook output priority 0; policy accept; }' 2>/dev/null || true
    fi

    local _chain_rules
    _chain_rules=$($SUDO_CMD nft list chain inet filter input 2>/dev/null)
    echo "$_chain_rules" | grep -q "ct state established,related" || \
        $SUDO_CMD nft add rule inet filter input ct state established,related accept 2>/dev/null || true
    echo "$_chain_rules" | grep -q 'iif "lo" accept' || \
        $SUDO_CMD nft add rule inet filter input iif lo accept 2>/dev/null || true
    echo "$_chain_rules" | grep -q "icmp type echo-request" || \
        $SUDO_CMD nft add rule inet filter input ip protocol icmp icmp type echo-request accept 2>/dev/null || true
    echo "$_chain_rules" | grep -q "icmpv6 type echo-request" || \
        $SUDO_CMD nft add rule inet filter input ip6 nexthdr icmpv6 icmpv6 type echo-request accept 2>/dev/null || true

    $SUDO_CMD sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    echo "net.ipv4.ip_forward=1" | $SUDO_CMD tee /etc/sysctl.d/99-retro-docker.conf >/dev/null 2>&1 || true

    $SUDO_CMD nft list tables 2>/dev/null | grep -q "inet nat" || \
        $SUDO_CMD nft add table inet nat 2>/dev/null || true
    $SUDO_CMD nft list chain inet nat postrouting &>/dev/null || \
        $SUDO_CMD nft add chain inet nat postrouting '{ type nat hook postrouting priority 100; }' 2>/dev/null || true
    local _nat_rules
    _nat_rules=$($SUDO_CMD nft list chain inet nat postrouting 2>/dev/null)
    echo "$_nat_rules" | grep -q "172.17.0.0/16" || \
        $SUDO_CMD nft add rule inet nat postrouting ip saddr 172.17.0.0/16 oif != docker0 masquerade 2>/dev/null || true

    local _fwd_rules
    _fwd_rules=$($SUDO_CMD nft list chain inet filter forward 2>/dev/null)
    echo "$_fwd_rules" | grep -q "ct state established,related" || \
        $SUDO_CMD nft add rule inet filter forward ct state established,related accept 2>/dev/null || true
    echo "$_fwd_rules" | grep -q "iif docker0 oif != docker0" || \
        $SUDO_CMD nft add rule inet filter forward iif docker0 oif != docker0 accept 2>/dev/null || true
    echo "$_fwd_rules" | grep -q "oif docker0" || \
        $SUDO_CMD nft add rule inet filter forward oif docker0 iif != docker0 accept 2>/dev/null || true
}

_nft_commit() {
    $SUDO_CMD nft list ruleset | $SUDO_CMD tee /etc/nftables.conf >/dev/null 2>&1 || true
}

_nft_status() {
    local status="inactive"
    systemctl is-active nftables &>/dev/null && status="active"
    echo "engine=nftables"
    echo "daemon_status=${status}"
}

_nft_on() {
    _disable_competing "nftables"
    $SUDO_CMD systemctl unmask nftables 2>/dev/null || true
    _nft_ensure_basic
    _nft_commit
    $SUDO_CMD nft flush ruleset 2>/dev/null || true
    $SUDO_CMD mkdir -p /etc/systemd/system/nftables.service.d 2>/dev/null || true
    printf '[Service]\nRemainAfterExit=yes\n' | $SUDO_CMD tee /etc/systemd/system/nftables.service.d/retro.conf >/dev/null 2>&1 || true
    $SUDO_CMD systemctl daemon-reload 2>/dev/null || true
    $SUDO_CMD systemctl enable nftables 2>/dev/null || true
    $SUDO_CMD systemctl start nftables 2>/dev/null || true
}

_nft_off() {
    $SUDO_CMD nft flush ruleset 2>/dev/null || true
    $SUDO_CMD systemctl disable nftables 2>/dev/null || true
    $SUDO_CMD systemctl stop nftables 2>/dev/null || true
}

_nft_restart() {
    $SUDO_CMD systemctl restart nftables 2>/dev/null || true
}

_nft_rules() {
    local count=0
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z $line ]] && continue
        local proto port action ip
        if [[ $line == ip\ saddr* ]]; then
            ip=$(awk '{print $3}' <<<"$line")
            action=$(awk '{print $NF}' <<<"$line")
            if [[ $line == *dport* ]]; then
                proto=$(awk '{print $4}' <<<"$line")
                port=$(awk '{print $6}' <<<"$line")
            fi
        else
            proto=$(awk '{print $1}' <<<"$line")
            port=$(awk '{print $3}' <<<"$line")
            action=$(awk '{print $4}' <<<"$line")
            [[ -z $port || ! $port =~ ^[0-9]+$ ]] && continue
        fi
        ((count++))
        if [[ -n $ip ]]; then
            if [[ -n $port ]]; then
                echo "entry=${count}|chain=input|ip=${ip}|port=${port}|proto=${proto}|action=${action}"
            else
                echo "entry=${count}|chain=input|ip=${ip}|action=${action}"
            fi
        else
            echo "entry=${count}|chain=input|port=${port}|proto=${proto}|action=${action}"
        fi
    done < <($SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -E '^\s+(tcp|udp) dport |^\s+ip saddr ')
    echo "count=${count}"
}

_nft_rule_count() {
    _nft_rules 2>/dev/null | grep "^count=" | cut -d= -f2 || echo "0"
}

_nft_open_ports() {
    local ports=()
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        local proto port action
        proto=$(echo "$line" | awk '{print $1}')
        port=$(echo "$line" | awk '{print $3}')
        action=$(echo "$line" | awk '{print $4}')
        [[ -z $port || ! $port =~ ^[0-9]+$ ]] && continue
        [[ $action != "accept" ]] && continue
        ports+=("${port}/${proto}")
    done < <($SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -E '^\s+(tcp|udp) dport ')
    local IFS=","
    echo "${ports[*]}"
}

_nft_default_policy() {
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -oP 'policy \K\w+' || echo "drop"
}

_nft_allow() {
    local port="$1" proto="${2:-tcp}"
    _nft_ensure_basic
    _nft_delete "$port" "$proto"
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -qE "${proto}\\s+dport\\s+${port}\\s+accept" || {
        $SUDO_CMD nft add rule inet filter input "${proto}" dport "${port}" accept 2>/dev/null && _nft_commit
    }
}

_nft_allow_ip_port() {
    local ip="$1" port="$2" proto="${3:-tcp}"
    _nft_ensure_basic
    local handle
    handle=$($SUDO_CMD nft -a list chain inet filter input 2>/dev/null | grep "${proto} dport ${port}.*ip saddr ${ip}.*drop" | grep -oP 'handle \K[0-9]+' | head -1)
    if [[ -n $handle ]]; then
        $SUDO_CMD nft delete rule inet filter input handle "${handle}" 2>/dev/null && _nft_commit
    fi
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -qE "ip saddr ${ip}.*${proto} dport ${port}.*accept" || {
        $SUDO_CMD nft add rule inet filter input ip saddr "${ip}" "${proto}" dport "${port}" accept 2>/dev/null && _nft_commit
    }
}

_nft_deny() {
    local port="$1" proto="${2:-tcp}"
    _nft_ensure_basic
    _nft_delete "$port" "$proto"
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -qE "${proto}\\s+dport\\s+${port}\\s+drop" || {
        $SUDO_CMD nft add rule inet filter input "${proto}" dport "${port}" drop 2>/dev/null && _nft_commit
    }
}

_nft_delete() {
    local port="$1" proto="${2:-tcp}"
    local handle
    handle=$($SUDO_CMD nft -a list chain inet filter input 2>/dev/null | grep "${proto} dport ${port}" | grep -oP 'handle \K[0-9]+' | head -1)
    if [[ -n $handle ]]; then
        $SUDO_CMD nft delete rule inet filter input handle "${handle}" 2>/dev/null && _nft_commit
    fi
}

_nft_delete_by_id() {
    local id_range="$1"

    local start end
    if [[ $id_range =~ ^([0-9]+)-([0-9]+)$ ]]; then
        start="${BASH_REMATCH[1]}"
        end="${BASH_REMATCH[2]}"
    else
        start="$id_range"
        end="$id_range"
    fi

    if [[ $end -lt $start ]]; then
        local tmp=$start; start=$end; end=$tmp
    fi

    local deleted=0
    for ((idx=end; idx>=start; idx--)); do
        local handle
        handle=$(_nft_handle_at_index "$idx")
        if [[ -n $handle ]]; then
            $SUDO_CMD nft delete rule inet filter input handle "${handle}" 2>/dev/null && ((deleted++)) || true
        fi
    done

    if [[ $deleted -gt 0 ]]; then
        _nft_commit
        return 0
    fi
    return 1
}

_nft_handle_at_index() {
    local idx="$1"
    $SUDO_CMD nft -a list chain inet filter input 2>/dev/null | grep -E '^\s+(tcp|udp) dport |^\s+ip saddr ' | sed -n "${idx}p" | grep -oP 'handle \K[0-9]+'
}

_nft_insert_block() {
    local ip="$1" idx="$2"
    _nft_ensure_basic
    local handle
    handle=$(_nft_handle_at_index "$idx")
    if [[ -n $handle ]]; then
        $SUDO_CMD nft insert rule inet filter input position "$handle" ip saddr "${ip}" drop 2>/dev/null && _nft_commit
    else
        $SUDO_CMD nft add rule inet filter input ip saddr "${ip}" drop 2>/dev/null && _nft_commit
    fi
}

_nft_insert_deny() {
    local port="$1" idx="$2" proto="${3:-tcp}"
    _nft_ensure_basic
    _nft_delete "$port" "$proto"
    local handle
    handle=$(_nft_handle_at_index "$idx")
    if [[ -n $handle ]]; then
        $SUDO_CMD nft insert rule inet filter input position "$handle" "${proto}" dport "${port}" drop 2>/dev/null && _nft_commit
    else
        $SUDO_CMD nft add rule inet filter input "${proto}" dport "${port}" drop 2>/dev/null && _nft_commit
    fi
}

_nft_insert_accept() {
    local port="$1" idx="$2" proto="${3:-tcp}"
    _nft_ensure_basic
    _nft_delete "$port" "$proto"
    local handle
    handle=$(_nft_handle_at_index "$idx")
    if [[ -n $handle ]]; then
        $SUDO_CMD nft insert rule inet filter input position "$handle" "${proto}" dport "${port}" accept 2>/dev/null && _nft_commit
    else
        $SUDO_CMD nft add rule inet filter input "${proto}" dport "${port}" accept 2>/dev/null && _nft_commit
    fi
}

_nft_insert_deny_ip_port() {
    local ip="$1" port="$2" idx="$3" proto="${4:-tcp}"
    _nft_ensure_basic
    local handle
    handle=$($SUDO_CMD nft -a list chain inet filter input 2>/dev/null | grep "${proto} dport ${port}.*ip saddr ${ip}.*accept" | grep -oP 'handle \K[0-9]+' | head -1)
    if [[ -n $handle ]]; then
        $SUDO_CMD nft delete rule inet filter input handle "${handle}" 2>/dev/null && _nft_commit
    fi
    local target_handle
    target_handle=$(_nft_handle_at_index "$idx")
    if [[ -n $target_handle ]]; then
        $SUDO_CMD nft insert rule inet filter input position "$target_handle" ip saddr "${ip}" "${proto}" dport "${port}" drop 2>/dev/null && _nft_commit
    else
        $SUDO_CMD nft add rule inet filter input ip saddr "${ip}" "${proto}" dport "${port}" drop 2>/dev/null && _nft_commit
    fi
}

_nft_insert_accept_ip_port() {
    local ip="$1" port="$2" idx="$3" proto="${4:-tcp}"
    _nft_ensure_basic
    local handle
    handle=$($SUDO_CMD nft -a list chain inet filter input 2>/dev/null | grep "${proto} dport ${port}.*ip saddr ${ip}.*drop" | grep -oP 'handle \K[0-9]+' | head -1)
    if [[ -n $handle ]]; then
        $SUDO_CMD nft delete rule inet filter input handle "${handle}" 2>/dev/null && _nft_commit
    fi
    local target_handle
    target_handle=$(_nft_handle_at_index "$idx")
    if [[ -n $target_handle ]]; then
        $SUDO_CMD nft insert rule inet filter input position "$target_handle" ip saddr "${ip}" "${proto}" dport "${port}" accept 2>/dev/null && _nft_commit
    else
        $SUDO_CMD nft add rule inet filter input ip saddr "${ip}" "${proto}" dport "${port}" accept 2>/dev/null && _nft_commit
    fi
}

_nft_deny_ip_port() {
    local ip="$1" port="$2" proto="${3:-tcp}"
    _nft_ensure_basic
    local handle
    handle=$($SUDO_CMD nft -a list chain inet filter input 2>/dev/null | grep "${proto} dport ${port}.*ip saddr ${ip}.*accept" | grep -oP 'handle \K[0-9]+' | head -1)
    if [[ -n $handle ]]; then
        $SUDO_CMD nft delete rule inet filter input handle "${handle}" 2>/dev/null && _nft_commit
    fi
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -qE "ip saddr ${ip}.*${proto} dport ${port}.*drop" || {
        $SUDO_CMD nft insert rule inet filter input ip saddr "${ip}" "${proto}" dport "${port}" drop 2>/dev/null && _nft_commit
    }
}

_nft_add_deny_ip_port() {
    local ip="$1" port="$2" proto="${3:-tcp}"
    _nft_ensure_basic
    local handle
    handle=$($SUDO_CMD nft -a list chain inet filter input 2>/dev/null | grep "${proto} dport ${port}.*ip saddr ${ip}.*accept" | grep -oP 'handle \K[0-9]+' | head -1)
    if [[ -n $handle ]]; then
        $SUDO_CMD nft delete rule inet filter input handle "${handle}" 2>/dev/null && _nft_commit
    fi
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -qE "ip saddr ${ip}.*${proto} dport ${port}.*drop" || {
        $SUDO_CMD nft add rule inet filter input ip saddr "${ip}" "${proto}" dport "${port}" drop 2>/dev/null && _nft_commit
    }
}

_nft_block() {
    local ip="$1"
    _nft_ensure_basic
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -qE "ip\\s+saddr\\s+${ip}\\s+drop" || {
        $SUDO_CMD nft insert rule inet filter input ip saddr "${ip}" drop 2>/dev/null && _nft_commit
    }
}

_nft_add_block() {
    local ip="$1"
    _nft_ensure_basic
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -qE "ip\\s+saddr\\s+${ip}\\s+drop" || {
        $SUDO_CMD nft add rule inet filter input ip saddr "${ip}" drop 2>/dev/null && _nft_commit
    }
}

_nft_default() {
    local policy="$1"
    _nft_ensure_basic
    local cur
    cur=$(_nft_default_policy)
    if [[ $cur != "unknown" && $cur != "$policy" ]]; then
        local handle
        handle=$($SUDO_CMD nft -a list chain inet filter input 2>/dev/null | grep -oP 'policy \S+.*handle \K[0-9]+' | head -1)
        if [[ -n $handle ]]; then
            $SUDO_CMD nft delete chain inet filter input handle "${handle}" 2>/dev/null || true
        fi
        $SUDO_CMD nft add chain inet filter input '{ type filter hook input priority 0; policy '"${policy}"'; }' 2>/dev/null || true
        _nft_commit
    fi
}

_ufw_open_ports() {
    local ports=()
    while IFS= read -r line; do
        if [[ $line =~ ^([0-9]+)/(tcp|udp) ]]; then
            ports+=("${BASH_REMATCH[1]}/${BASH_REMATCH[2]}")
        fi
    done < <(ufw status verbose 2>/dev/null | grep "^[0-9]")
    local IFS=","
    echo "${ports[*]}"
}

_ufw_status() {
    local status="inactive"
    ufw status 2>/dev/null | head -1 | grep -qi "active" && status="active"
    echo "engine=ufw"
    echo "daemon_status=${status}"
}

_ufw_on() {
    _disable_competing "ufw"
    $SUDO_CMD systemctl unmask ufw 2>/dev/null || true
    $SUDO_CMD ufw --force enable 2>/dev/null || true
}

_ufw_off() {
    $SUDO_CMD ufw --force disable 2>/dev/null || true
}

_ufw_restart() {
    _ufw_off && _ufw_on
}

_ufw_rule_count() {
    ufw status numbered 2>/dev/null | grep -cE '^\[\s*[0-9]+\]' || true
}

_ufw_rules() {
    local count=0
    while IFS= read -r line; do
        if [[ $line =~ ^\[\s*([0-9]+)\]\s+([0-9]+)/(tcp|udp)\s+([A-Z]+) ]]; then
            ((count++))
            echo "entry=${BASH_REMATCH[1]}|chain=input|port=${BASH_REMATCH[2]}|proto=${BASH_REMATCH[3]}|action=${BASH_REMATCH[4],,}"
        fi
    done < <(ufw status numbered 2>/dev/null)
    echo "count=${count}"
}

_ufw_allow() {
    local port="$1" proto="${2:-tcp}"
    $SUDO_CMD ufw allow "${port}/${proto}" 2>/dev/null || true
}

_ufw_deny() {
    local port="$1" proto="${2:-tcp}"
    $SUDO_CMD ufw deny "${port}/${proto}" 2>/dev/null || true
}

_ufw_delete() {
    local port="$1" proto="${2:-tcp}"
    local num
    num=$(ufw status numbered 2>/dev/null | grep -E "^\s*\[\s*[0-9]+\]\s+${port}/${proto}\s" | grep -oP '(?<=\[)\s*\d+\s*(?=\])' | head -1 | xargs)
    [[ -n $num ]] && $SUDO_CMD ufw --force delete "${num}" 2>/dev/null || true
}

_ufw_block() {
    local ip="$1"
    $SUDO_CMD ufw deny from "${ip}" 2>/dev/null || true
}

_ufw_default() {
    local policy="$1"
    $SUDO_CMD ufw default "${policy}" 2>/dev/null || true
}

_ufw_default_policy() {
    ufw status verbose 2>/dev/null | grep "Default:" | grep -oP '(deny|allow|reject)' | head -1 || echo "unknown"
}

_fwd_open_ports() {
    local ports
    ports=$(firewall-cmd --list-ports 2>/dev/null)
    echo "${ports:-}" | tr ' ' ','
}

_fwd_status() {
    local status="inactive"
    firewall-cmd --state 2>/dev/null | grep -qi "running" && status="active"
    echo "engine=firewalld"
    echo "daemon_status=${status}"
}

_fwd_on() {
    _disable_competing "firewalld"
    $SUDO_CMD systemctl unmask firewalld 2>/dev/null || true
    $SUDO_CMD systemctl enable firewalld 2>/dev/null || true
    $SUDO_CMD systemctl start firewalld 2>/dev/null || true
}

_fwd_off() {
    $SUDO_CMD systemctl disable firewalld 2>/dev/null || true
    $SUDO_CMD systemctl stop firewalld 2>/dev/null || true
}

_fwd_restart() {
    $SUDO_CMD systemctl restart firewalld 2>/dev/null || true
}

_fwd_rule_count() {
    local count=0
    for zone in $(firewall-cmd --get-zones 2>/dev/null); do
        local zcount
        zcount=$(firewall-cmd --zone="$zone" --list-ports 2>/dev/null | wc -w)
        ((count += zcount))
    done
    echo "${count}"
}

_fwd_rules() {
    local count=0
    for zone in $(firewall-cmd --get-zones 2>/dev/null); do
        for entry in $(firewall-cmd --zone="$zone" --list-ports 2>/dev/null); do
            ((count++))
            if [[ $entry =~ ^([0-9]+)/(tcp|udp)$ ]]; then
                echo "entry=${count}|zone=${zone}|port=${BASH_REMATCH[1]}|proto=${BASH_REMATCH[2]}|action=accept"
            fi
        done
    done
    echo "count=${count}"
}

_fwd_allow() {
    local port="$1" proto="${2:-tcp}"
    $SUDO_CMD firewall-cmd --add-port="${port}/${proto}" 2>/dev/null || true
    $SUDO_CMD firewall-cmd --runtime-to-permanent 2>/dev/null || true
}

_fwd_deny() {
    local port="$1" proto="${2:-tcp}"
    $SUDO_CMD firewall-cmd --remove-port="${port}/${proto}" 2>/dev/null || true
    $SUDO_CMD firewall-cmd --runtime-to-permanent 2>/dev/null || true
}

_fwd_delete() {
    _fwd_deny "$1" "$2"
}

_fwd_block() {
    local ip="$1"
    $SUDO_CMD firewall-cmd --add-rich-rule="rule family='ipv4' source address='${ip}' drop" 2>/dev/null || true
    $SUDO_CMD firewall-cmd --runtime-to-permanent 2>/dev/null || true
}

_fwd_default() {
    local policy="$1"
    local zone
    zone=$(firewall-cmd --get-default-zone 2>/dev/null || echo "public")
    $SUDO_CMD firewall-cmd --zone="${zone}" --set-target="${policy}" 2>/dev/null || true
    $SUDO_CMD firewall-cmd --runtime-to-permanent 2>/dev/null || true
}

_fwd_default_policy() {
    local zone
    zone=$(firewall-cmd --get-default-zone 2>/dev/null || echo "public")
    firewall-cmd --zone="${zone}" --list-all 2>/dev/null | grep "target:" | awk '{print $2}' || echo "unknown"
}

_ipt_open_ports() {
    local ports=()
    while IFS= read -r line; do
        if [[ $line =~ dpt:([0-9]+) ]]; then
            local p="${BASH_REMATCH[1]}"
            local proto
            proto=$(echo "$line" | awk '{print $4}')
            ports+=("${p}/${proto}")
        fi
    done < <($SUDO_CMD iptables -L INPUT -n 2>/dev/null)
    local IFS=","
    echo "${ports[*]}"
}

_ipt_status() {
    local status="inactive"
    $SUDO_CMD iptables -L -n &>/dev/null && status="active"
    echo "engine=iptables"
    echo "daemon_status=${status}"
}

_ipt_on() {
    _disable_competing "iptables"
    $SUDO_CMD systemctl unmask iptables 2>/dev/null || true
    _ipt_ensure_basic
    $SUDO_CMD iptables-save 2>/dev/null | $SUDO_CMD tee /etc/iptables/iptables.rules >/dev/null 2>&1 || true
    $SUDO_CMD systemctl enable iptables 2>/dev/null || true
    $SUDO_CMD systemctl start iptables 2>/dev/null || true
}

_ipt_off() {
    $SUDO_CMD iptables -P INPUT ACCEPT 2>/dev/null || true
    $SUDO_CMD iptables -P FORWARD ACCEPT 2>/dev/null || true
    $SUDO_CMD iptables -P OUTPUT ACCEPT 2>/dev/null || true
    $SUDO_CMD iptables -F 2>/dev/null || true
    $SUDO_CMD iptables -X 2>/dev/null || true
    $SUDO_CMD systemctl disable iptables 2>/dev/null || true
    $SUDO_CMD systemctl stop iptables 2>/dev/null || true
}

_ipt_ensure_basic() {
    $SUDO_CMD iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        $SUDO_CMD iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    $SUDO_CMD iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || \
        $SUDO_CMD iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
    $SUDO_CMD iptables -C INPUT -p icmp --icmp-type echo-request -j ACCEPT 2>/dev/null || \
        $SUDO_CMD iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT 2>/dev/null || true
}

_ipt_restart() {
    $SUDO_CMD systemctl restart iptables 2>/dev/null || true
}

_ipt_rule_count() {
    $SUDO_CMD iptables -L INPUT -n 2>/dev/null | grep -cE '^\s*[0-9]+' || true
}

_ipt_rules() {
    local count=0
    while IFS= read -r line; do
        if [[ $line =~ ^([0-9]+)\s+([0-9]+)\s+([A-Z]+)\s+([a-z0-9]+) ]]; then
            ((count++))
            local num="${BASH_REMATCH[1]}"
            local target="${BASH_REMATCH[3]}"
            local proto="${BASH_REMATCH[4]}"
            local port=""
            if [[ $line =~ dpt:([0-9]+) ]]; then
                port="${BASH_REMATCH[1]}"
            fi
            echo "entry=${num}|chain=input|port=${port}|proto=${proto}|action=${target,,}"
        fi
    done < <($SUDO_CMD iptables -L INPUT -n --line-numbers 2>/dev/null | tail -n +2)
    echo "count=${count}"
}

_ipt_allow() {
    local port="$1" proto="${2:-tcp}"
    $SUDO_CMD iptables -A INPUT -p "${proto}" --dport "${port}" -j ACCEPT 2>/dev/null || true
    $SUDO_CMD iptables-save 2>/dev/null | $SUDO_CMD tee /etc/iptables/iptables.rules >/dev/null 2>&1 || true
}

_ipt_deny() {
    local port="$1" proto="${2:-tcp}"
    $SUDO_CMD iptables -A INPUT -p "${proto}" --dport "${port}" -j DROP 2>/dev/null || true
    $SUDO_CMD iptables-save 2>/dev/null | $SUDO_CMD tee /etc/iptables/iptables.rules >/dev/null 2>&1 || true
}

_ipt_delete() {
    local port="$1" proto="${2:-tcp}"
    local num
    num=$($SUDO_CMD iptables -L INPUT -n --line-numbers 2>/dev/null | grep "dpt:${port}" | head -1 | awk '{print $1}')
    [[ -n $num ]] && $SUDO_CMD iptables -D INPUT "${num}" 2>/dev/null || true
    $SUDO_CMD iptables-save 2>/dev/null | $SUDO_CMD tee /etc/iptables/iptables.rules >/dev/null 2>&1 || true
}

_ipt_block() {
    local ip="$1"
    $SUDO_CMD iptables -A INPUT -s "${ip}" -j DROP 2>/dev/null || true
    $SUDO_CMD iptables-save 2>/dev/null | $SUDO_CMD tee /etc/iptables/iptables.rules >/dev/null 2>&1 || true
}

_ipt_default() {
    local policy="$1"
    $SUDO_CMD iptables -P INPUT "${policy^^}" 2>/dev/null || true
    $SUDO_CMD iptables-save 2>/dev/null | $SUDO_CMD tee /etc/iptables/iptables.rules >/dev/null 2>&1 || true
}

_ipt_default_policy() {
    $SUDO_CMD iptables -L INPUT -n 2>/dev/null | head -1 | grep -oP 'policy \K\w+' || echo "unknown"
}

case "$1" in
    --status)
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "engine=none"; echo "daemon_status=inactive"; echo "rule_count=0"; echo "default_policy="; echo "open_ports="; exit 0; }

        case "$engine" in
            nftables) _nft_status ;;
            ufw) _ufw_status ;;
            firewalld) _fwd_status ;;
            iptables) _ipt_status ;;
        esac

        case "$engine" in
            nftables)
                _nft_shell=$($SUDO_CMD nft list chain inet filter input 2>/dev/null)
                rule_count=$(echo "$_nft_shell" | grep -cE '^\s+(tcp|udp)\s+dport' || true)
                default_policy=$(_nft_default_policy)
                open_ports=$(echo "$_nft_shell" | grep -E '^\s+(tcp|udp)\s+dport' | awk '{printf "%s/%s,", $3, $1}' | sed 's/,$//')
                ;;
            ufw) rule_count=$(_ufw_rule_count); default_policy=$(_ufw_default_policy); open_ports=$(_ufw_open_ports) ;;
            firewalld) rule_count=$(_fwd_rule_count); default_policy=$(_fwd_default_policy); open_ports=$(_fwd_open_ports) ;;
            iptables) rule_count=$(_ipt_rule_count); default_policy=$(_ipt_default_policy); open_ports=$(_ipt_open_ports) ;;
        esac

        echo "rule_count=${rule_count:-0}"
        echo "default_policy=${default_policy:-unknown}"
        echo "open_ports=${open_ports:-}"
        rx_log_file "info" "Status: engine=${engine} rules=${rule_count} policy=${default_policy}"
        ;;

    --engine)
        _engine_get
        ;;

    --list-engines)
        _engines_available
        ;;

    --setup-get)
        engine=$(_engine_get)
        status="inactive"
        case "$engine" in
            nftables) systemctl is-active nftables &>/dev/null && status="active" ;;
            ufw) ufw status 2>/dev/null | head -1 | grep -qi "active" && status="active" ;;
            firewalld) firewall-cmd --state 2>/dev/null | grep -qi "running" && status="active" ;;
            iptables) $SUDO_CMD iptables -L -n &>/dev/null && status="active" ;;
        esac
        local policy=""
        case "$engine" in
            nftables) policy=$(_nft_default_policy) ;;
            ufw) policy=$(_ufw_default_policy) ;;
            firewalld) policy=$(_fwd_default_policy) ;;
            iptables) policy=$(_ipt_default_policy) ;;
        esac
        echo "engine=${engine}"
        echo "daemon_status=${status}"
        echo "default_policy=${policy}"
        ;;

    --setup-apply)
        engine="${2:-nftables}"
        set_var "FIREWALL_ENGINE" "$engine"
        _disable_competing "$engine"

        case "$engine" in
            nftables)
                _nft_ensure_basic
                _nft_commit
                $SUDO_CMD nft flush ruleset 2>/dev/null || true
                $SUDO_CMD systemctl unmask nftables 2>/dev/null || true
                $SUDO_CMD mkdir -p /etc/systemd/system/nftables.service.d 2>/dev/null || true
                printf '[Service]\nRemainAfterExit=yes\n' | $SUDO_CMD tee /etc/systemd/system/nftables.service.d/retro.conf >/dev/null 2>&1 || true
                $SUDO_CMD systemctl daemon-reload 2>/dev/null || true
                $SUDO_CMD systemctl enable nftables 2>/dev/null || true
                $SUDO_CMD systemctl start nftables 2>/dev/null || true
                ;;
            ufw)
                $SUDO_CMD systemctl unmask ufw 2>/dev/null || true
                $SUDO_CMD ufw --force enable 2>/dev/null || true
                ;;
            firewalld)
                $SUDO_CMD systemctl unmask firewalld 2>/dev/null || true
                $SUDO_CMD systemctl enable firewalld 2>/dev/null || true
                $SUDO_CMD systemctl start firewalld 2>/dev/null || true
                ;;
            iptables)
                $SUDO_CMD systemctl unmask iptables 2>/dev/null || true
                _ipt_ensure_basic
                $SUDO_CMD iptables-save 2>/dev/null | $SUDO_CMD tee /etc/iptables/iptables.rules >/dev/null 2>&1 || true
                $SUDO_CMD systemctl enable iptables 2>/dev/null || true
                $SUDO_CMD systemctl start iptables 2>/dev/null || true
                ;;
        esac

        shift 2
        while [[ $# -ge 2 ]]; do
            pport="$1"; pproto="$2"; shift 2
            case "$engine" in
                nftables) _nft_allow "$pport" "$pproto" ;;
                ufw) _ufw_allow "$pport" "$pproto" ;;
                firewalld) _fwd_allow "$pport" "$pproto" ;;
                iptables) _ipt_allow "$pport" "$pproto" ;;
            esac
        done

        [[ $engine == "nftables" ]] && _nft_commit

        echo "OK|configured|engine=${engine}"
        rx_log_file "success" "Firewall configured (engine=${engine})"
        ;;

    --on)
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }

        case "$engine" in
            nftables) _nft_on ;;
            ufw) _ufw_on ;;
            firewalld) _fwd_on ;;
            iptables) _ipt_on ;;
        esac

        ok=false
        case "$engine" in
            nftables) systemctl is-active nftables &>/dev/null && ok=true ;;
            ufw) ufw status 2>/dev/null | head -1 | grep -qi "active" && ok=true ;;
            firewalld) firewall-cmd --state 2>/dev/null | grep -qi "running" && ok=true ;;
            iptables) $SUDO_CMD iptables -L -n &>/dev/null && ok=true ;;
        esac

        if [[ $ok == true ]]; then
            echo "OK|enabled"
            rx_log_file "success" "Firewall enabled (${engine})"
        else
            echo "result=error|reason=enable_failed"
            rx_log_file "error" "Failed to enable firewall (${engine})"
            exit 1
        fi
        ;;

    --off)
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }

        case "$engine" in
            nftables) _nft_off ;;
            ufw) _ufw_off ;;
            firewalld) _fwd_off ;;
            iptables) _ipt_off ;;
        esac
        echo "OK|disabled"
        rx_log_file "success" "Firewall disabled (${engine})"
        ;;

    --restart)
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }

        case "$engine" in
            nftables) _nft_restart ;;
            ufw) _ufw_restart ;;
            firewalld) _fwd_restart ;;
            iptables) _ipt_restart ;;
        esac

        ok=false
        case "$engine" in
            nftables) systemctl is-active nftables &>/dev/null && ok=true ;;
            ufw) ufw status 2>/dev/null | head -1 | grep -qi "active" && ok=true ;;
            firewalld) firewall-cmd --state 2>/dev/null | grep -qi "running" && ok=true ;;
            iptables) $SUDO_CMD iptables -L -n &>/dev/null && ok=true ;;
        esac

        if [[ $ok == true ]]; then
            echo "OK|restarted"
            rx_log_file "success" "Firewall restarted (${engine})"
        else
            echo "result=error|reason=restart_failed"
            rx_log_file "error" "Failed to restart firewall (${engine})"
            exit 1
        fi
        ;;

    --rules)
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "count=0"; exit 0; }

        case "$engine" in
            nftables) _nft_rules ;;
            ufw) _ufw_rules ;;
            firewalld) _fwd_rules ;;
            iptables) _ipt_rules ;;
        esac
        ;;

    --allow)
        port="$2" proto="${3:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }

        case "$engine" in
            nftables) _nft_allow "$port" "$proto" ;;
            ufw) _ufw_allow "$port" "$proto" ;;
            firewalld) _fwd_allow "$port" "$proto" ;;
            iptables) _ipt_allow "$port" "$proto" ;;
        esac
        echo "OK|allowed|port=${port}|proto=${proto}"
        rx_log_file "success" "Port allowed: ${port}/${proto} (${engine})"
        ;;

    --allow-ip-port)
        ip="$2" port="$3" proto="${4:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }

        case "$engine" in
            nftables) _nft_allow_ip_port "$ip" "$port" "$proto" ;;
            ufw) _ufw_allow "$port" "$proto" ;;
            firewalld) _fwd_allow "$port" "$proto" ;;
            iptables) _ipt_allow "$port" "$proto" ;;
        esac
        echo "OK|allowed|ip=${ip}|port=${port}|proto=${proto}"
        rx_log_file "success" "IP:Port allowed: ${ip}:${port}/${proto} (${engine})"
        ;;

    --deny)
        port="$2" proto="${3:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }

        case "$engine" in
            nftables) _nft_deny "$port" "$proto" ;;
            ufw) _ufw_deny "$port" "$proto" ;;
            firewalld) _fwd_deny "$port" "$proto" ;;
            iptables) _ipt_deny "$port" "$proto" ;;
        esac
        echo "OK|denied|port=${port}|proto=${proto}"
        rx_log_file "success" "Port denied: ${port}/${proto} (${engine})"
        ;;

    --deny-ip-port)
        ip="$2" port="$3" proto="${4:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }

        case "$engine" in
            nftables) _nft_deny_ip_port "$ip" "$port" "$proto" ;;
            ufw) _ufw_block "$ip" ;;
            firewalld) _fwd_block "$ip" ;;
            iptables) _ipt_block "$ip" ;;
        esac
        echo "OK|denied|ip=${ip}|port=${port}|proto=${proto}"
        rx_log_file "success" "IP:Port denied: ${ip}:${port}/${proto} (${engine})"
        ;;

    --delete)
        port="$2" proto="${3:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }

        case "$engine" in
            nftables) _nft_delete "$port" "$proto" ;;
            ufw) _ufw_delete "$port" "$proto" ;;
            firewalld) _fwd_delete "$port" "$proto" ;;
            iptables) _ipt_delete "$port" "$proto" ;;
        esac
        echo "OK|deleted|port=${port}|proto=${proto}"
        rx_log_file "success" "Rule deleted: ${port}/${proto} (${engine})"
        ;;

    --delete-id)
        id="$2"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $id || ! $id =~ ^[0-9]+(-[0-9]+)?$ ]] && { echo "result=error|reason=invalid_id"; exit 1; }

        case "$engine" in
            nftables) _nft_delete_by_id "$id" || { echo "result=error|reason=not_found"; exit 1; } ;;
            ufw) echo "result=error|reason=unsupported"; exit 1 ;;
            firewalld) echo "result=error|reason=unsupported"; exit 1 ;;
            iptables) echo "result=error|reason=unsupported"; exit 1 ;;
        esac
        echo "OK|deleted|id=${id}"
        if [[ $id == *-* ]]; then
            rx_log_file "success" "Rules ${id} deleted (${engine})"
        else
            rx_log_file "success" "Rule #${id} deleted (${engine})"
        fi
        ;;

    --block)
        ip="$2"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }

        case "$engine" in
            nftables) _nft_block "$ip" ;;
            ufw) _ufw_block "$ip" ;;
            firewalld) _fwd_block "$ip" ;;
            iptables) _ipt_block "$ip" ;;
        esac
        echo "OK|blocked|ip=${ip}"
        rx_log_file "success" "IP blocked: ${ip} (${engine})"
        ;;

    --add-block)
        ip="$2"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }

        case "$engine" in
            nftables) _nft_add_block "$ip" ;;
            ufw) _ufw_block "$ip" ;;
            firewalld) _fwd_block "$ip" ;;
            iptables) _ipt_block "$ip" ;;
        esac
        echo "OK|blocked|ip=${ip}|mode=add"
        rx_log_file "success" "IP blocked (add): ${ip} (${engine})"
        ;;

    --add-deny-ip-port)
        ip="$2" port="$3" proto="${4:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }

        case "$engine" in
            nftables) _nft_add_deny_ip_port "$ip" "$port" "$proto" ;;
            ufw) _ufw_block "$ip" ;;
            firewalld) _fwd_block "$ip" ;;
            iptables) _ipt_block "$ip" ;;
        esac
        echo "OK|denied|ip=${ip}|port=${port}|proto=${proto}|mode=add"
        rx_log_file "success" "IP:Port denied (add): ${ip}:${port}/${proto} (${engine})"
        ;;

    --insert-block)
        ip="$2" idx="$3"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }

        case "$engine" in
            nftables) _nft_insert_block "$ip" "$idx" ;;
            ufw) echo "result=error|reason=unsupported"; exit 1 ;;
            firewalld) echo "result=error|reason=unsupported"; exit 1 ;;
            iptables) echo "result=error|reason=unsupported"; exit 1 ;;
        esac
        echo "OK|blocked|ip=${ip}|position=${idx}|mode=insert"
        rx_log_file "success" "IP blocked (insert): ${ip} at ${idx} (${engine})"
        ;;

    --insert-deny)
        port="$2" idx="$3" proto="${4:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }

        case "$engine" in
            nftables) _nft_insert_deny "$port" "$idx" "$proto" ;;
            ufw) echo "result=error|reason=unsupported"; exit 1 ;;
            firewalld) echo "result=error|reason=unsupported"; exit 1 ;;
            iptables) echo "result=error|reason=unsupported"; exit 1 ;;
        esac
        echo "OK|denied|port=${port}|proto=${proto}|position=${idx}|mode=insert"
        rx_log_file "success" "Port denied (insert): ${port}/${proto} at ${idx} (${engine})"
        ;;

    --insert-accept)
        port="$2" idx="$3" proto="${4:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }

        case "$engine" in
            nftables) _nft_insert_accept "$port" "$idx" "$proto" ;;
            ufw) echo "result=error|reason=unsupported"; exit 1 ;;
            firewalld) echo "result=error|reason=unsupported"; exit 1 ;;
            iptables) echo "result=error|reason=unsupported"; exit 1 ;;
        esac
        echo "OK|allowed|port=${port}|proto=${proto}|position=${idx}|mode=insert"
        rx_log_file "success" "Port allowed (insert): ${port}/${proto} at ${idx} (${engine})"
        ;;

    --insert-deny-ip-port)
        ip="$2" port="$3" idx="$4" proto="${5:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }

        case "$engine" in
            nftables) _nft_insert_deny_ip_port "$ip" "$port" "$idx" "$proto" ;;
            ufw) echo "result=error|reason=unsupported"; exit 1 ;;
            firewalld) echo "result=error|reason=unsupported"; exit 1 ;;
            iptables) echo "result=error|reason=unsupported"; exit 1 ;;
        esac
        echo "OK|denied|ip=${ip}|port=${port}|proto=${proto}|position=${idx}|mode=insert"
        rx_log_file "success" "IP:Port denied (insert): ${ip}:${port}/${proto} at ${idx} (${engine})"
        ;;

    --insert-accept-ip-port)
        ip="$2" port="$3" idx="$4" proto="${5:-tcp}"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }

        case "$engine" in
            nftables) _nft_insert_accept_ip_port "$ip" "$port" "$idx" "$proto" ;;
            ufw) echo "result=error|reason=unsupported"; exit 1 ;;
            firewalld) echo "result=error|reason=unsupported"; exit 1 ;;
            iptables) echo "result=error|reason=unsupported"; exit 1 ;;
        esac
        echo "OK|allowed|ip=${ip}|port=${port}|proto=${proto}|position=${idx}|mode=insert"
        rx_log_file "success" "IP:Port allowed (insert): ${ip}:${port}/${proto} at ${idx} (${engine})"
        ;;

    --default)
        policy="$2"
        engine=$(_engine_get)
        [[ $engine == "none" ]] && { echo "result=error|reason=no_engine"; exit 1; }
        [[ -z $policy ]] && { echo "result=error|reason=no_policy"; exit 1; }

        case "$engine" in
            nftables) _nft_default "$policy" ;;
            ufw) _ufw_default "$policy" ;;
            firewalld) _fwd_default "$policy" ;;
            iptables) _ipt_default "$policy" ;;
        esac
        echo "OK|default|policy=${policy}"
        rx_log_file "success" "Default policy set: ${policy} (${engine})"
        ;;

    --kill-ssh)
        ip="$2"
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        local pids
        pids=$(ss -tnp 2>/dev/null | grep ":22 " | grep "$ip" | grep -oP 'pid=\K[0-9]+' | sort -u)
        for pid in $pids; do
            $SUDO_CMD kill "$pid" 2>/dev/null || true
        done
        echo "OK|killed|ip=${ip}"
        rx_log_file "success" "SSH sessions killed: ${ip}"
        ;;

    --logs)
        lines="${2:-50}"
        $SUDO_CMD journalctl -u nftables -u ufw -u firewalld -u iptables --no-pager -n "$lines" 2>/dev/null || echo "No logs available"
        ;;

    *)
        echo "result=error|reason=unknown_flag|flag=$1"
        exit 1
        ;;
esac
