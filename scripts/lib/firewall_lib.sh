#!/bin/bash

SUDO_CMD="sudo"
[[ $EUID -eq 0 ]] && SUDO_CMD=""

VARS_FILE="${RETRO_CONFIG:-$HOME/.config/retro}/variables.sh"

_fw_get_engine() {
    local eng
    eng=$(grep -oP '^export FIREWALL_ENGINE="\K[^"]*' "$VARS_FILE" 2>/dev/null || true)
    [[ -z $eng || $eng == "auto" ]] && eng="nftables"
    echo "$eng"
}

_fw_block_nft() {
    local ip="$1"
    _fw_ensure_nft
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -qE "ip\\s+saddr\\s+${ip}\\s+drop" || \
        $SUDO_CMD nft add rule inet filter input ip saddr "${ip}" drop &>/dev/null || true
}

_fw_check_nft() {
    local ip="$1"
    $SUDO_CMD nft list chain inet filter input 2>/dev/null | grep -qE "ip\\s+saddr\\s+${ip}\\s+drop" && echo "blocked" || echo "not blocked"
}

_fw_block_ufw() {
    local ip="$1"
    $SUDO_CMD ufw deny from "${ip}" &>/dev/null || true
}

_fw_block_firewalld() {
    local ip="$1"
    $SUDO_CMD firewall-cmd --add-rich-rule="rule family='ipv4' source address='${ip}' drop" &>/dev/null || true
}

_fw_block_iptables() {
    local ip="$1"
    $SUDO_CMD iptables -A INPUT -s "${ip}" -j DROP &>/dev/null || true
}

_fw_ensure_nft() {
    $SUDO_CMD nft list tables 2>/dev/null | grep -q "inet filter" && return 0
    $SUDO_CMD nft add table inet filter &>/dev/null || true
    $SUDO_CMD nft list chain inet filter input &>/dev/null || \
        $SUDO_CMD nft add chain inet filter input '{ type filter hook input priority 0; policy drop; }' &>/dev/null || true
}

_fw_block() {
    local ip="$1"
    local engine
    engine=$(_fw_get_engine)

    case "$engine" in
        nftables) _fw_block_nft "$ip" ;;
        ufw) _fw_block_ufw "$ip" ;;
        firewalld) _fw_block_firewalld "$ip" ;;
        iptables) _fw_block_iptables "$ip" ;;
    esac
}

_fw_check() {
    local ip="$1"
    local engine
    engine=$(_fw_get_engine)

    case "$engine" in
        nftables) _fw_check_nft "$ip" ;;
        ufw)
            $SUDO_CMD ufw status 2>/dev/null | grep -q "DENY.*${ip}" && echo "blocked" || echo "not blocked"
            ;;
        firewalld)
            $SUDO_CMD firewall-cmd --list-rich-rules 2>/dev/null | grep -q "${ip}" && echo "blocked" || echo "not blocked"
            ;;
        iptables)
            $SUDO_CMD iptables -L INPUT -n 2>/dev/null | grep -qE "${ip}.*DROP" && echo "blocked" || echo "not blocked"
            ;;
    esac
}

_fw_kill_ssh_sessions() {
    local ip="$1"
    local pids
    pids=$(ss -tnp 2>/dev/null | grep ":22 " | grep "$ip" | grep -oP 'pid=\K[0-9]+' | sort -u)
    for pid in $pids; do
        $SUDO_CMD kill "$pid" &>/dev/null || true
    done
}

case "$1" in
    --engine)
        _fw_get_engine
        ;;
    --block)
        [[ -z $2 ]] && exit 1
        _fw_block "$2"
        ;;
    --check)
        [[ -z $2 ]] && exit 1
        _fw_check "$2"
        ;;
    --kill-ssh)
        [[ -z $2 ]] && exit 1
        _fw_kill_ssh_sessions "$2"
        ;;
    *)
        exit 1
        ;;
esac
