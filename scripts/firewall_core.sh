#!/bin/bash

RETRO_DIR="${RETRO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/lib/helpers.sh"
rx_log_register "firewall"

SUDO_CMD="sudo"
[[ $EUID -eq 0 ]] && SUDO_CMD=""

NFT_CONF="/etc/nftables.conf"
BLOCK_LOG="/var/log/retro-firewall-blocked"

_nft() {
    $SUDO_CMD nft "$@"
}

_nft_chain_exists() {
    _nft list chain inet filter "$1" &>/dev/null
}

_nft_validate() {
    echo "$1" | $SUDO_CMD nft -c -f - &>/dev/null
}

_nft_ensure_basic() {
    _nft list tables 2>/dev/null | grep -q "inet filter" || {
        _nft flush ruleset 2>/dev/null || true
        _nft add table inet filter 2>/dev/null || true
    }
    _nft_chain_exists "input" || \
        _nft add chain inet filter input '{ type filter hook input priority 0; policy drop; }' 2>/dev/null || true
    _nft_chain_exists "forward" || \
        _nft add chain inet filter forward '{ type filter hook forward priority 0; policy drop; }' 2>/dev/null || true
    _nft_chain_exists "output" || \
        _nft add chain inet filter output '{ type filter hook output priority 0; policy accept; }' 2>/dev/null || true

    local _input_rules
    _input_rules=$(_nft list chain inet filter input 2>/dev/null)
    echo "$_input_rules" | grep -q "ct state established,related" || \
        _nft add rule inet filter input ct state established,related accept 2>/dev/null || true
    echo "$_input_rules" | grep -q 'iif "lo" accept' || \
        _nft add rule inet filter input iif lo accept 2>/dev/null || true
    echo "$_input_rules" | grep -q "icmp type echo-request" || \
        _nft add rule inet filter input ip protocol icmp icmp type echo-request accept 2>/dev/null || true
    echo "$_input_rules" | grep -q "icmpv6 type echo-request" || \
        _nft add rule inet filter input ip6 nexthdr icmpv6 icmpv6 type echo-request accept 2>/dev/null || true

    local _fwd_rules
    _fwd_rules=$(_nft list chain inet filter forward 2>/dev/null)
    echo "$_fwd_rules" | grep -q "ct state established,related" || \
        _nft add rule inet filter forward ct state established,related accept 2>/dev/null || true
    echo "$_fwd_rules" | grep -q 'iifname "docker0"' || \
        _nft add rule inet filter forward iifname "docker0" accept 2>/dev/null || true
    echo "$_fwd_rules" | grep -q 'iifname "br-*"' || \
        _nft add rule inet filter forward iifname "br-*" accept 2>/dev/null || true

    $SUDO_CMD sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    echo "net.ipv4.ip_forward=1" | $SUDO_CMD tee /etc/sysctl.d/99-retro-docker.conf >/dev/null 2>&1 || true

    _nft list tables 2>/dev/null | grep -q "inet nat" || \
        _nft add table inet nat 2>/dev/null || true
    _nft list chain inet nat postrouting &>/dev/null || \
        _nft add chain inet nat postrouting '{ type nat hook postrouting priority 100; }' 2>/dev/null || true
    local _nat_rules
    _nat_rules=$(_nft list chain inet nat postrouting 2>/dev/null)
    echo "$_nat_rules" | grep -q "172.17.0.0/16" || \
        _nft add rule inet nat postrouting ip saddr 172.17.0.0/16 oif != docker0 masquerade 2>/dev/null || true
}

_nft_commit() {
    _nft list ruleset | $SUDO_CMD tee "$NFT_CONF" >/dev/null 2>&1 || true
}

_nft_status() {
    local status="inactive"
    systemctl is-active nftables &>/dev/null && status="active"
    echo "engine=nftables"
    echo "daemon_status=${status}"
    echo "boot_enabled=$(_nft_boot_status)"
    echo "default_policy=$(_nft_default_policy)"
    echo "outbound_policy=$(_nft_output_policy)"
    echo "ping=$(_nft_ping_status)"
}

_nft_default_policy() {
    _nft list chain inet filter input 2>/dev/null | grep -oP 'policy \K\w+' || echo "drop"
}

_nft_on() {
    for eng in ufw firewalld iptables; do
        $SUDO_CMD systemctl stop "$eng" 2>/dev/null || true
        $SUDO_CMD systemctl disable "$eng" 2>/dev/null || true
        $SUDO_CMD systemctl mask "$eng" 2>/dev/null || true
    done
    $SUDO_CMD ufw --force disable 2>/dev/null || true

    $SUDO_CMD systemctl unmask nftables 2>/dev/null || true
    _nft_ensure_basic
    _nft_commit
    $SUDO_CMD nft flush ruleset 2>/dev/null || true
    $SUDO_CMD mkdir -p /etc/systemd/system/nftables.service.d 2>/dev/null || true
    printf '[Service]\nRemainAfterExit=yes\n' | $SUDO_CMD tee /etc/systemd/system/nftables.service.d/retro.conf >/dev/null 2>&1 || true
    $SUDO_CMD mkdir -p /etc/systemd/system/docker.service.d 2>/dev/null || true
    cat <<EOF | $SUDO_CMD tee /etc/systemd/system/docker.service.d/retro-nftables.conf >/dev/null 2>&1 || true
[Unit]
After=nftables.service
BindsTo=nftables.service
EOF
    $SUDO_CMD systemctl daemon-reload 2>/dev/null || true
    $SUDO_CMD systemctl enable nftables 2>/dev/null || true
    $SUDO_CMD nft -f "$NFT_CONF" 2>/dev/null || $SUDO_CMD systemctl restart nftables 2>/dev/null || true
}

_nft_off() {
    $SUDO_CMD nft flush ruleset 2>/dev/null || true
    $SUDO_CMD systemctl disable nftables 2>/dev/null || true
    $SUDO_CMD systemctl stop nftables 2>/dev/null || true
}

_nft_restart() {
    $SUDO_CMD systemctl restart nftables 2>/dev/null || true
}

_nft_rule_exists() {
    local pattern="$1"
    _nft list chain inet filter input 2>/dev/null | grep -qE "$pattern"
}

_nft_insert_rule() {
    local statement="$1"
    local pattern="$statement"
    if [[ $statement == *" drop" ]]; then
        pattern="${statement// counter drop/counter .* drop}"
    fi
    if ! _nft_validate "add rule inet filter input $statement"; then
        echo "result=error|reason=invalid_rule"
        return 1
    fi
    if _nft_rule_exists "$pattern"; then
        echo "OK|exists"
        return 0
    fi
    if _nft insert rule inet filter input $statement 2>/dev/null; then
        _nft_commit
        echo "OK|added"
    else
        echo "result=error|reason=apply_failed"
        return 1
    fi
}

_nft_drop_stmt() {
    local base="$1"
    local stmt="${base% drop}"
    echo "${stmt} log prefix \"retro-drop \" counter drop"
}

_nft_plain_drop() {
    local line="$1"
    line=$(echo "$line" | sed 's/ log prefix "retro-drop "//; s/ counter packets [0-9]* bytes [0-9]*//')
    echo "$line"
}

_nft_add_rule() {
    local statement="$1"
    local pattern="$statement"
    if [[ $statement == *" drop" ]]; then
        pattern="${statement// counter drop/counter .* drop}"
    fi
    if ! _nft_validate "add rule inet filter input $statement"; then
        echo "result=error|reason=invalid_rule"
        return 1
    fi
    if _nft_rule_exists "$pattern"; then
        echo "OK|exists"
        return 0
    fi
    if _nft add rule inet filter input $statement 2>/dev/null; then
        _nft_commit
        echo "OK|added"
    else
        echo "result=error|reason=apply_failed"
        return 1
    fi
}

_nft_remove_by_handle() {
    local handle="$1"
    if [[ -z $handle ]]; then
        return 1
    fi
    _nft delete rule inet filter input handle "$handle" 2>/dev/null
}

_nft_find_handle() {
    local pattern="$1"
    _nft -a list chain inet filter input 2>/dev/null | grep "$pattern" | grep -oP 'handle \K[0-9]+' | head -1
}

_nft_allow() {
    local port="$1" proto="${2:-both}"
    _nft_ensure_basic
    if ! [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
        echo "result=error|reason=invalid_port"
        return 1
    fi
    [[ $proto != "tcp" && $proto != "udp" ]] && proto="both"
    if [[ $proto == "both" ]]; then
        _nft_add_rule "tcp dport ${port} accept" >/dev/null
        _nft_add_rule "udp dport ${port} accept"
    else
        _nft_add_rule "${proto} dport ${port} accept"
    fi
}

_nft_deny() {
    local port="$1" proto="${2:-both}"
    _nft_ensure_basic
    if ! [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
        echo "result=error|reason=invalid_port"
        return 1
    fi
    [[ $proto != "tcp" && $proto != "udp" ]] && proto="both"
    if [[ $proto == "both" ]]; then
        local handle
        handle=$(_nft_find_handle "tcp dport ${port} accept")
        _nft_remove_by_handle "$handle" 2>/dev/null
        handle=$(_nft_find_handle "udp dport ${port} accept")
        _nft_remove_by_handle "$handle" 2>/dev/null
        _nft_add_rule "$(_nft_drop_stmt "tcp dport ${port} drop")" >/dev/null
        _nft_add_rule "$(_nft_drop_stmt "udp dport ${port} drop")"
    else
        local handle
        handle=$(_nft_find_handle "${proto} dport ${port} accept")
        _nft_remove_by_handle "$handle" 2>/dev/null
        _nft_add_rule "$(_nft_drop_stmt "${proto} dport ${port} drop")"
    fi
}

_nft_allow_ip() {
    local ip="$1" port="$2" proto="${3:-both}"
    _nft_ensure_basic
    if ! _valid_ip "$ip"; then
        echo "result=error|reason=invalid_ip"
        return 1
    fi
    if ! [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
        echo "result=error|reason=invalid_port"
        return 1
    fi
    [[ $proto != "tcp" && $proto != "udp" ]] && proto="both"
    if [[ $proto == "both" ]]; then
        local handle
        handle=$(_nft_find_handle "ip saddr ${ip} tcp dport ${port}.*drop")
        _nft_remove_by_handle "$handle" 2>/dev/null
        handle=$(_nft_find_handle "ip saddr ${ip} udp dport ${port}.*drop")
        _nft_remove_by_handle "$handle" 2>/dev/null
        _nft_add_rule "ip saddr ${ip} tcp dport ${port} accept" >/dev/null
        _nft_add_rule "ip saddr ${ip} udp dport ${port} accept"
    else
        local handle
        handle=$(_nft_find_handle "ip saddr ${ip} ${proto} dport ${port}.*drop")
        _nft_remove_by_handle "$handle" 2>/dev/null
        _nft_add_rule "ip saddr ${ip} ${proto} dport ${port} accept"
    fi
}

_nft_deny_ip() {
    local ip="$1" port="$2" proto="${3:-both}"
    _nft_ensure_basic
    if ! _valid_ip "$ip"; then
        echo "result=error|reason=invalid_ip"
        return 1
    fi
    if ! [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
        echo "result=error|reason=invalid_port"
        return 1
    fi
    [[ $proto != "tcp" && $proto != "udp" ]] && proto="both"
    if [[ $proto == "both" ]]; then
        local handle
        handle=$(_nft_find_handle "ip saddr ${ip} tcp dport ${port} accept")
        _nft_remove_by_handle "$handle" 2>/dev/null
        handle=$(_nft_find_handle "ip saddr ${ip} udp dport ${port} accept")
        _nft_remove_by_handle "$handle" 2>/dev/null
        _nft_add_rule "$(_nft_drop_stmt "ip saddr ${ip} tcp dport ${port} drop")" >/dev/null
        _nft_add_rule "$(_nft_drop_stmt "ip saddr ${ip} udp dport ${port} drop")"
    else
        local handle
        handle=$(_nft_find_handle "ip saddr ${ip} ${proto} dport ${port} accept")
        _nft_remove_by_handle "$handle" 2>/dev/null
        _nft_add_rule "$(_nft_drop_stmt "ip saddr ${ip} ${proto} dport ${port} drop")"
    fi
}

_nft_block() {
    local ip="$1" reason="${2:-manual}" proto="${3:-both}"
    _nft_ensure_basic
    if ! _valid_ip "$ip"; then
        echo "result=error|reason=invalid_ip"
        return 1
    fi
    [[ $proto != "tcp" && $proto != "udp" ]] && proto="both"
    local statement="ip saddr ${ip} drop"
    if [[ $proto != "both" ]]; then
        statement="ip saddr ${ip} meta l4proto ${proto} drop"
    fi
    local result
    result=$(_nft_insert_rule "$(_nft_drop_stmt "$statement")")
    if echo "$result" | grep -q "^OK|"; then
        _nft_block_registry_add "$ip" "$reason" "$proto"
    fi
    echo "$result"
}

_nft_unblock() {
    local ip="$1"
    _nft_ensure_basic
    if ! _valid_ip "$ip"; then
        echo "result=error|reason=invalid_ip"
        return 1
    fi
    local handles
    handles=$(_nft -a list chain inet filter input 2>/dev/null | grep "ip saddr ${ip}.*drop" | grep -oP 'handle \K[0-9]+')
    local deleted=0
    for h in $handles; do
        _nft_remove_by_handle "$h" 2>/dev/null && deleted=1
    done
    if [[ $deleted -eq 1 ]]; then
        _nft_commit
        _nft_block_registry_remove "$ip"
        echo "OK|unblocked|ip=${ip}"
    else
        echo "OK|exists"
    fi
}

_nft_block_registry_add() {
    local ip="$1" reason="${2:-manual}" proto="${3:-both}"
    $SUDO_CMD mkdir -p "$(dirname "$BLOCK_LOG")" 2>/dev/null || true
    local existing=""
    [[ -f $BLOCK_LOG ]] && existing=$(cat "$BLOCK_LOG" 2>/dev/null || true)
    { echo "$existing"; echo "${ip}|${reason}|${proto}|$(date +%s)"; } | $SUDO_CMD tee "$BLOCK_LOG" >/dev/null 2>&1 || true
}

_nft_block_registry_remove() {
    local ip="$1"
    [[ ! -f $BLOCK_LOG ]] && return 0
    local kept
    kept=$(grep -v "^${ip}|" "$BLOCK_LOG" 2>/dev/null || true)
    echo "$kept" | $SUDO_CMD tee "$BLOCK_LOG" >/dev/null 2>&1 || true
}

_nft_blocked_list() {
    [[ ! -f $BLOCK_LOG ]] && { echo "count=0"; return 0; }
    local count=0
    local line
    while IFS= read -r line; do
        local ip reason proto epoch
        ip=$(echo "$line" | cut -d'|' -f1)
        reason=$(echo "$line" | cut -d'|' -f2)
        proto=$(echo "$line" | cut -d'|' -f3)
        epoch=$(echo "$line" | cut -d'|' -f4)
        [[ -z $proto ]] && proto="both"
        [[ -z $ip ]] && continue
        if ! _nft_rule_exists "ip saddr ${ip}.*drop"; then
            continue
        fi
        local time_str
        time_str=$(date -d "@$epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")
        echo "BLOCK|${ip}|${reason}|${proto}|${time_str}"
        ((count++))
    done < <(cat "$BLOCK_LOG" 2>/dev/null)
    echo "count=${count}"
}

_nft_delete_by_id() {
    local id_range="$1"
    local start end
    if [[ $id_range =~ ^([0-9]+)-([0-9]+)$ ]]; then
        start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
    else
        start="$id_range"; end="$id_range"
    fi
    if [[ $end -lt $start ]]; then
        local tmp=$start; start=$end; end=$tmp
    fi
    local deleted=0
    for ((idx=end; idx>=start; idx--)); do
        local handle
        handle=$(_nft_handle_at_index "$idx")
        if _nft_remove_by_handle "$handle" 2>/dev/null; then
            deleted=1
        fi
    done
    if [[ $deleted -eq 1 ]]; then
        _nft_commit
        echo "OK|deleted|id=${id_range}"
    else
        echo "result=error|reason=not_found"
        return 1
    fi
}

_nft_handle_at_index() {
    local idx="$1"
    _nft -a list chain inet filter input 2>/dev/null | grep -E '^\s+(tcp|udp) dport |^\s+ip saddr ' | sed -n "${idx}p" | grep -oP 'handle \K[0-9]+'
}

_nft_rules() {
    local count=0
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z $line ]] && continue
        ((count++))
        local proto port action ip="" packets=0 bytes=0
        if [[ $line == ip\ saddr* ]]; then
            ip=$(awk '{print $3}' <<<"$line")
            action=$(awk '{print $NF}' <<<"$line")
            if [[ $line == *dport* ]]; then
                proto=$(awk '{print $4}' <<<"$line")
                port=$(awk '{print $6}' <<<"$line")
            else
                proto="-"
                port="-"
            fi
        else
            proto=$(awk '{print $1}' <<<"$line")
            port=$(awk '{print $3}' <<<"$line")
            action=$(awk '{print $NF}' <<<"$line")
        fi
        packets=$(echo "$line" | grep -oP 'counter packets \K[0-9]+' || echo 0)
        bytes=$(echo "$line" | grep -oP 'bytes \K[0-9]+' || echo 0)
        echo "RULES|${count}|${proto}|${port}|${ip}|${action}|${packets}|${bytes}"
    done < <(_nft list chain inet filter input 2>/dev/null | grep -E '^\s+(tcp|udp) dport |^\s+ip saddr ')
    echo "count=${count}"
}

_nft_blocked_total() {
    local total=0
    local line
    while IFS= read -r line; do
        local p
        p=$(echo "$line" | grep -oP 'counter packets \K[0-9]+' || echo 0)
        ((total += p))
    done < <(_nft list chain inet filter input 2>/dev/null | grep -E 'drop')
    echo "$total"
}

_nft_top_ports() {
    local -A counts=()
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        local port proto
        port=$(awk '{print $3}' <<<"$line")
        proto=$(awk '{print $1}' <<<"$line")
        [[ $port =~ ^[0-9]+$ ]] || continue
        counts["$port/$proto"]=$(( ${counts["$port/$proto"]:-0} + 1 ))
    done < <(_nft list chain inet filter input 2>/dev/null | grep -E '^\s+(tcp|udp) dport .* drop')
    local out=()
    local k
    for k in "${!counts[@]}"; do
        out+=("${k}:${counts[$k]}")
    done
    local IFS=","
    echo "${out[*]}"
}

_nft_open_ports() {
    local ports=()
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        local proto port action
        proto=$(echo "$line" | awk '{print $1}')
        port=$(echo "$line" | awk '{print $3}')
        action=$(echo "$line" | awk '{print $4}')
        [[ -z $port || ! $port =~ ^[0-9]+$ ]] && continue
        [[ $action != "accept" ]] && continue
        ports+=("${port}/${proto}")
    done < <(_nft list chain inet filter input 2>/dev/null | grep -E '^\s+(tcp|udp) dport ')
    local IFS=","
    echo "${ports[*]}"
}

_nft_default() {
    local policy="$1"
    _nft_ensure_basic
    local cur
    cur=$(_nft_default_policy)
    if [[ $cur == "$policy" ]]; then
        echo "OK|exists|policy=${policy}"
        return 0
    fi

    local rules=()
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z $line ]] && continue
        echo "$line" | grep -qE 'type filter hook input' && continue
        [[ $line == "}" ]] && continue
        line=$(echo "$line" | sed 's/\s*# handle [0-9]*//')
        [[ -z $line ]] && continue
        line=$(_nft_plain_drop "$line")
        [[ -z $line ]] && continue
        rules+=("$line")
    done < <(_nft -a list chain inet filter input 2>/dev/null)

    _nft delete chain inet filter input 2>/dev/null || true
    if _nft add chain inet filter input '{ type filter hook input priority 0; policy '"${policy}"'; }' 2>/dev/null; then
        for r in "${rules[@]}"; do
            _nft add rule inet filter input $r 2>/dev/null || true
        done
        _nft_commit
        echo "OK|default|policy=${policy}"
    else
        echo "result=error|reason=apply_failed"
        return 1
    fi
}

_nft_ping_status() {
    if _nft_rule_exists "ip protocol icmp icmp type echo-request accept"; then
        echo "on"
    else
        echo "off"
    fi
}

_nft_ping() {
    local mode="$1"
    _nft_ensure_basic
    if [[ $mode == "on" || $mode == "allow" ]]; then
        _nft_add_rule "ip protocol icmp icmp type echo-request accept" >/dev/null 2>&1
        _nft_add_rule "ip6 nexthdr icmpv6 icmpv6 type echo-request accept" >/dev/null 2>&1
        echo "OK|ping=on"
    else
        local handle
        handle=$(_nft_find_handle "ip protocol icmp icmp type echo-request accept")
        _nft_remove_by_handle "$handle" 2>/dev/null
        handle=$(_nft_find_handle "ip6 nexthdr icmpv6 icmpv6 type echo-request accept")
        _nft_remove_by_handle "$handle" 2>/dev/null
        _nft_commit
        echo "OK|ping=off"
    fi
}

_nft_output_policy() {
    _nft list chain inet filter output 2>/dev/null | grep -oP 'policy \K\w+' || echo "accept"
}

_nft_outbound() {
    local policy="$1"
    _nft_ensure_basic
    local cur
    cur=$(_nft_output_policy)
    if [[ $cur == "$policy" ]]; then
        echo "OK|exists|policy=${policy}"
        return 0
    fi
    local rules=()
    local line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z $line ]] && continue
        echo "$line" | grep -qE 'type filter hook output' && continue
        [[ $line == "}" ]] && continue
        line=$(echo "$line" | sed 's/\s*# handle [0-9]*//')
        [[ -z $line ]] && continue
        line=$(_nft_plain_drop "$line")
        [[ -z $line ]] && continue
        rules+=("$line")
    done < <(_nft -a list chain inet filter output 2>/dev/null)
    _nft delete chain inet filter output 2>/dev/null || true
    if _nft add chain inet filter output '{ type filter hook output priority 0; policy '"${policy}"'; }' 2>/dev/null; then
        for r in "${rules[@]}"; do
            _nft add rule inet filter output $r 2>/dev/null || true
        done
        if [[ $policy == "drop" ]]; then
            _nft add rule inet filter output ct state established,related accept 2>/dev/null || true
            _nft add rule inet filter output oif lo accept 2>/dev/null || true
            _nft add rule inet filter output udp dport 53 accept 2>/dev/null || true
        fi
        _nft_commit
        echo "OK|outbound=${policy}"
    else
        echo "result=error|reason=apply_failed"
        return 1
    fi
}

_nft_boot_status() {
    if systemctl is-enabled nftables &>/dev/null; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

_nft_boot() {
    local mode="$1"
    if [[ $mode == "enable" ]]; then
        $SUDO_CMD systemctl enable nftables 2>/dev/null || true
        echo "OK|boot=enabled"
    elif [[ $mode == "disable" ]]; then
        $SUDO_CMD systemctl disable nftables 2>/dev/null || true
        echo "OK|boot=disabled"
    else
        echo "boot=$(_nft_boot_status)"
    fi
}

_nft_connections() {
    local port_filter="$1"
    local count=0
    local line
    while IFS= read -r line; do
        local state proto local_addr remote_addr pid="" proc=""
        proto=$(echo "$line" | awk '{print $1}')
        state=$(echo "$line" | awk '{print $2}')
        local_addr=$(echo "$line" | awk '{print $5}')
        remote_addr=$(echo "$line" | awk '{print $6}')
        if [[ -n $port_filter ]]; then
            local lport
            lport="${local_addr##*:}"
            [[ $lport != "$port_filter" ]] && continue
        fi
        pid=$(echo "$line" | grep -oP 'pid=\K[0-9]+' || echo "")
        proc=$(echo "$line" | grep -oP 'users:\(\"\K[^"]+' || echo "")
        echo "CONN|${proto}|${state}|${local_addr}|${remote_addr}|${pid}|${proc}"
        ((count++))
    done < <(ss -tunp 2>/dev/null | grep -E "^tcp|^udp" | grep "ESTAB")
    echo "count=${count}"
}

_nft_drops() {
    local lines="${1:-10}"
    $SUDO_CMD journalctl -k --no-pager -n 2000 2>/dev/null | grep "retro-drop" | tail -n "$lines"
}

_nft_export() {
    local file="$1"
    if [[ -z $file ]]; then
        _nft list ruleset
        return 0
    fi
    if _nft list ruleset > "$file" 2>/dev/null; then
        echo "OK|exported|file=${file}"
    else
        echo "result=error|reason=export_failed"
        return 1
    fi
}

_nft_import() {
    local file="$1"
    if [[ -z $file || ! -f $file ]]; then
        echo "result=error|reason=no_file"
        return 1
    fi
    if ! $SUDO_CMD nft -c -f "$file" 2>/dev/null; then
        echo "result=error|reason=invalid_config"
        return 1
    fi
    $SUDO_CMD nft flush ruleset 2>/dev/null || true
    $SUDO_CMD nft -f "$file" 2>/dev/null || {
        echo "result=error|reason=apply_failed"
        return 1
    }
    _nft_commit
    echo "OK|imported|file=${file}"
}

_valid_ip() {
    local ip="$1"
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

_kill_ssh_sessions() {
    local ip="$1"
    [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
    local pids
    pids=$($SUDO_CMD ss -tnp 2>/dev/null | grep ":22 " | grep "$ip" | grep -oP 'pid=\K[0-9]+' | sort -u)
    for pid in $pids; do
        $SUDO_CMD kill "$pid" 2>/dev/null || true
    done
    echo "OK|killed|ip=${ip}|pids=${pids}"
    rx_log_file "success" "SSH sessions killed: ${ip} (pids: ${pids})"
}

_kill_connection() {
    local pid="$1"
    [[ -z $pid ]] && { echo "result=error|reason=no_pid"; exit 1; }
    if $SUDO_CMD kill "$pid" 2>/dev/null; then
        echo "OK|killed|pid=${pid}"
        rx_log_file "success" "Connection closed: pid=${pid}"
    else
        echo "result=error|reason=kill_failed|pid=${pid}"
        exit 1
    fi
}

case "$1" in
    --status)
        _nft_status
        rule_count=$(_nft_rules 2>/dev/null | grep "^count=" | cut -d= -f2)
        echo "rule_count=${rule_count:-0}"
        echo "blocked_packets=$(_nft_blocked_total)"
        echo "top_ports=$(_nft_top_ports)"
        echo "open_ports=$(_nft_open_ports)"
        rx_log_file "info" "Status: engine=nftables rules=${rule_count:-0}"
        ;;

    --rules)
        _nft_rules
        ;;

    --test)
        if $SUDO_CMD nft -c -f "$NFT_CONF" 2>/dev/null; then
            echo "OK|valid"
        else
            echo "result=error|reason=invalid_config"
            exit 1
        fi
        ;;

    --on)
        _nft_on
        ok=false
        systemctl is-active nftables &>/dev/null && ok=true
        if [[ $ok == true ]]; then
            echo "OK|enabled"
            rx_log_file "success" "Firewall enabled (nftables)"
        else
            echo "result=error|reason=enable_failed"
            rx_log_file "error" "Failed to enable firewall (nftables)"
            exit 1
        fi
        ;;

    --off)
        _nft_off
        echo "OK|disabled"
        rx_log_file "success" "Firewall disabled (nftables)"
        ;;

    --restart)
        _nft_restart
        ok=false
        systemctl is-active nftables &>/dev/null && ok=true
        if [[ $ok == true ]]; then
            echo "OK|restarted"
            rx_log_file "success" "Firewall restarted (nftables)"
        else
            echo "result=error|reason=restart_failed"
            rx_log_file "error" "Failed to restart firewall (nftables)"
            exit 1
        fi
        ;;

    --allow)
        _nft_allow "$2" "${3:-tcp}"
        ;;

    --deny)
        _nft_deny "$2" "${3:-tcp}"
        ;;

    --allow-ip)
        _nft_allow_ip "$2" "$3" "${4:-tcp}"
        ;;

    --deny-ip)
        _nft_deny_ip "$2" "$3" "${4:-tcp}"
        ;;

    --block)
        _nft_block "$2" "${3:-manual}" "${4:-both}"
        ;;

    --unblock)
        _nft_unblock "$2"
        ;;

    --blocked)
        _nft_blocked_list
        ;;

    --ping)
        mode="$2"
        [[ -z $mode ]] && { echo "result=error|reason=no_mode"; exit 1; }
        _nft_ping "$mode"
        ;;

    --outbound)
        policy="$2"
        [[ -z $policy ]] && { echo "result=error|reason=no_policy"; exit 1; }
        [[ $policy != "drop" && $policy != "accept" ]] && { echo "result=error|reason=invalid_policy"; exit 1; }
        _nft_outbound "$policy"
        ;;

    --boot)
        _nft_boot "$2"
        ;;

    --connections)
        _nft_connections "$2"
        ;;

    --drops)
        lines="${2:-10}"
        _nft_drops "$lines"
        ;;

    --export)
        _nft_export "$2"
        ;;

    --import)
        _nft_import "$2"
        ;;

    --delete)
        id="$2"
        [[ -z $id || ! $id =~ ^[0-9]+(-[0-9]+)?$ ]] && { echo "result=error|reason=invalid_id"; exit 1; }
        _nft_delete_by_id "$id"
        ;;

    --default)
        policy="$2"
        [[ -z $policy ]] && { echo "result=error|reason=no_policy"; exit 1; }
        [[ $policy != "drop" && $policy != "accept" ]] && { echo "result=error|reason=invalid_policy"; exit 1; }
        _nft_default "$policy"
        ;;

    --kill-ssh)
        _kill_ssh_sessions "$2"
        ;;

    --kill-connection)
        _kill_connection "$2"
        ;;

    --logs)
        lines="${2:-50}"
        $SUDO_CMD journalctl -u nftables --no-pager -n "$lines" 2>/dev/null || echo "No logs available"
        ;;

    *)
        echo "result=error|reason=unknown_flag|flag=$1"
        exit 1
        ;;
esac
