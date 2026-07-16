#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/variable.sh"
rx_log_register "firewall"

SUDO_CMD="sudo"
[[ $EUID -eq 0 ]] && SUDO_CMD=""

_engine_get() {
    echo "nftables"
}

_disable_competing() {
    for eng in ufw firewalld iptables; do
        $SUDO_CMD systemctl stop "$eng" 2>/dev/null || true
        $SUDO_CMD systemctl disable "$eng" 2>/dev/null || true
        $SUDO_CMD systemctl mask "$eng" 2>/dev/null || true
    done
    $SUDO_CMD ufw --force disable 2>/dev/null || true
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

    local _input_rules
    _input_rules=$($SUDO_CMD nft list chain inet filter input 2>/dev/null)
    echo "$_input_rules" | grep -q "ct state established,related" || \
        $SUDO_CMD nft add rule inet filter input ct state established,related accept 2>/dev/null || true
    echo "$_input_rules" | grep -q 'iif "lo" accept' || \
        $SUDO_CMD nft add rule inet filter input iif lo accept 2>/dev/null || true
    echo "$_input_rules" | grep -q "icmp type echo-request" || \
        $SUDO_CMD nft add rule inet filter input ip protocol icmp icmp type echo-request accept 2>/dev/null || true
    echo "$_input_rules" | grep -q "icmpv6 type echo-request" || \
        $SUDO_CMD nft add rule inet filter input ip6 nexthdr icmpv6 icmpv6 type echo-request accept 2>/dev/null || true

    local _fwd_rules
    _fwd_rules=$($SUDO_CMD nft list chain inet filter forward 2>/dev/null)
    echo "$_fwd_rules" | grep -q "ct state established,related" || \
        $SUDO_CMD nft add rule inet filter forward ct state established,related accept 2>/dev/null || true
    echo "$_fwd_rules" | grep -q 'iifname "docker0"' || \
        $SUDO_CMD nft add rule inet filter forward iifname "docker0" accept 2>/dev/null || true
    echo "$_fwd_rules" | grep -q 'iifname "br-*"' || \
        $SUDO_CMD nft add rule inet filter forward iifname "br-*" accept 2>/dev/null || true

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
    _disable_competing
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

case "$1" in
    --status)
        engine=$(_engine_get)
        _nft_status
        _nft_shell=$($SUDO_CMD nft list chain inet filter input 2>/dev/null)
        rule_count=$(echo "$_nft_shell" | grep -cE '^\s+(tcp|udp)\s+dport' || true)
        default_policy=$(_nft_default_policy)
        open_ports=$(echo "$_nft_shell" | grep -E '^\s+(tcp|udp)\s+dport' | awk '{printf "%s/%s,", $3, $1}' | sed 's/,$//')
        echo "rule_count=${rule_count:-0}"
        echo "default_policy=${default_policy:-unknown}"
        echo "open_ports=${open_ports:-}"
        rx_log_file "info" "Status: engine=${engine} rules=${rule_count} policy=${default_policy}"
        ;;

    --engine)
        _engine_get
        ;;

    --setup-get)
        engine=$(_engine_get)
        status="inactive"
        systemctl is-active nftables &>/dev/null && status="active"
        policy=$(_nft_default_policy)
        echo "engine=${engine}"
        echo "daemon_status=${status}"
        echo "default_policy=${policy}"
        ;;

    --setup-apply)
        set_var "FIREWALL_ENGINE" "nftables"
        _disable_competing
        _nft_ensure_basic
        _nft_commit
        $SUDO_CMD nft flush ruleset 2>/dev/null || true
        $SUDO_CMD systemctl unmask nftables 2>/dev/null || true
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
        $SUDO_CMD systemctl start nftables 2>/dev/null || true

        shift 2
        while [[ $# -ge 2 ]]; do
            pport="$1"; pproto="$2"; shift 2
            _nft_allow "$pport" "$pproto"
        done

        _nft_commit
        echo "OK|configured|engine=nftables"
        rx_log_file "success" "Firewall configured (engine=nftables)"
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

    --rules)
        _nft_rules
        ;;

    --allow)
        port="$2" proto="${3:-tcp}"
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        _nft_allow "$port" "$proto"
        echo "OK|allowed|port=${port}|proto=${proto}"
        rx_log_file "success" "Port allowed: ${port}/${proto} (nftables)"
        ;;

    --allow-ip-port)
        ip="$2" port="$3" proto="${4:-tcp}"
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        _nft_allow_ip_port "$ip" "$port" "$proto"
        echo "OK|allowed|ip=${ip}|port=${port}|proto=${proto}"
        rx_log_file "success" "IP:Port allowed: ${ip}:${port}/${proto} (nftables)"
        ;;

    --deny)
        port="$2" proto="${3:-tcp}"
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        _nft_deny "$port" "$proto"
        echo "OK|denied|port=${port}|proto=${proto}"
        rx_log_file "success" "Port denied: ${port}/${proto} (nftables)"
        ;;

    --deny-ip-port)
        ip="$2" port="$3" proto="${4:-tcp}"
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        _nft_deny_ip_port "$ip" "$port" "$proto"
        echo "OK|denied|ip=${ip}|port=${port}|proto=${proto}"
        rx_log_file "success" "IP:Port denied: ${ip}:${port}/${proto} (nftables)"
        ;;

    --delete)
        port="$2" proto="${3:-tcp}"
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        _nft_delete "$port" "$proto"
        echo "OK|deleted|port=${port}|proto=${proto}"
        rx_log_file "success" "Rule deleted: ${port}/${proto} (nftables)"
        ;;

    --delete-id)
        id="$2"
        [[ -z $id || ! $id =~ ^[0-9]+(-[0-9]+)?$ ]] && { echo "result=error|reason=invalid_id"; exit 1; }
        _nft_delete_by_id "$id" || { echo "result=error|reason=not_found"; exit 1; }
        echo "OK|deleted|id=${id}"
        [[ $id == *-* ]] && rx_log_file "success" "Rules ${id} deleted (nftables)" || rx_log_file "success" "Rule #${id} deleted (nftables)"
        ;;

    --block)
        ip="$2"
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        _nft_block "$ip"
        echo "OK|blocked|ip=${ip}"
        rx_log_file "success" "IP blocked: ${ip} (nftables)"
        ;;

    --add-block)
        ip="$2"
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        _nft_add_block "$ip"
        echo "OK|blocked|ip=${ip}|mode=add"
        rx_log_file "success" "IP blocked (add): ${ip} (nftables)"
        ;;

    --add-deny-ip-port)
        ip="$2" port="$3" proto="${4:-tcp}"
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        _nft_add_deny_ip_port "$ip" "$port" "$proto"
        echo "OK|denied|ip=${ip}|port=${port}|proto=${proto}|mode=add"
        rx_log_file "success" "IP:Port denied (add): ${ip}:${port}/${proto} (nftables)"
        ;;

    --insert-block)
        ip="$2" idx="$3"
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }
        _nft_insert_block "$ip" "$idx"
        echo "OK|blocked|ip=${ip}|position=${idx}|mode=insert"
        rx_log_file "success" "IP blocked (insert): ${ip} at ${idx} (nftables)"
        ;;

    --insert-deny)
        port="$2" idx="$3" proto="${4:-tcp}"
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }
        _nft_insert_deny "$port" "$idx" "$proto"
        echo "OK|denied|port=${port}|proto=${proto}|position=${idx}|mode=insert"
        rx_log_file "success" "Port denied (insert): ${port}/${proto} at ${idx} (nftables)"
        ;;

    --insert-accept)
        port="$2" idx="$3" proto="${4:-tcp}"
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }
        _nft_insert_accept "$port" "$idx" "$proto"
        echo "OK|allowed|port=${port}|proto=${proto}|position=${idx}|mode=insert"
        rx_log_file "success" "Port allowed (insert): ${port}/${proto} at ${idx} (nftables)"
        ;;

    --insert-deny-ip-port)
        ip="$2" port="$3" idx="$4" proto="${5:-tcp}"
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }
        _nft_insert_deny_ip_port "$ip" "$port" "$idx" "$proto"
        echo "OK|denied|ip=${ip}|port=${port}|proto=${proto}|position=${idx}|mode=insert"
        rx_log_file "success" "IP:Port denied (insert): ${ip}:${port}/${proto} at ${idx} (nftables)"
        ;;

    --insert-accept-ip-port)
        ip="$2" port="$3" idx="$4" proto="${5:-tcp}"
        [[ -z $ip ]] && { echo "result=error|reason=no_ip"; exit 1; }
        [[ -z $port ]] && { echo "result=error|reason=no_port"; exit 1; }
        [[ -z $idx || ! $idx =~ ^[0-9]+$ ]] && { echo "result=error|reason=invalid_idx"; exit 1; }
        _nft_insert_accept_ip_port "$ip" "$port" "$idx" "$proto"
        echo "OK|allowed|ip=${ip}|port=${port}|proto=${proto}|position=${idx}|mode=insert"
        rx_log_file "success" "IP:Port allowed (insert): ${ip}:${port}/${proto} at ${idx} (nftables)"
        ;;

    --default)
        policy="$2"
        [[ -z $policy ]] && { echo "result=error|reason=no_policy"; exit 1; }
        _nft_default "$policy"
        echo "OK|default|policy=${policy}"
        rx_log_file "success" "Default policy set: ${policy} (nftables)"
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
        $SUDO_CMD journalctl -u nftables --no-pager -n "$lines" 2>/dev/null || echo "No logs available"
        ;;

    *)
        echo "result=error|reason=unknown_flag|flag=$1"
        exit 1
        ;;
esac
