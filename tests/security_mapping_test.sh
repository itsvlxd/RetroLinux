#!/bin/bash

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

FAILURES=()

FW_CORE="$RETRO_DIR/scripts/firewall_core.sh"
SSH_CORE="$RETRO_DIR/scripts/ssh_core.sh"
FW_CLI="$RETRO_DIR/cmds/tools/firewall.sh"
SSH_CLI="$RETRO_DIR/cmds/tools/ssh.sh"

check_core_flag() {
    local core="$1" flag="$2" label="$3"
    if ! grep -qE -- "^[[:space:]]*${flag}\)" "$core" 2>/dev/null; then
        FAILURES+=("$label: core missing flag $flag")
    fi
}

check_cli_uses() {
    local cli="$1" pattern="$2" label="$3"
    if ! grep -qE -- "$pattern" "$cli" 2>/dev/null; then
        FAILURES+=("$label: CLI does not call $pattern")
    fi
}

# ── firewall_core.sh flags ──
for f in --status --rules --test --on --off --restart --dedup --allow --deny --allow-ip --deny-ip --block --unblock --delete --default --kill-ssh --kill-connection --logs --blocked --ping --outbound --boot --connections --drops --export --import; do
    check_core_flag "$FW_CORE" "$f" "firewall"
done

# ── ssh_core.sh flags ──
for f in --status --start --stop --restart --enable --disable --sessions --session-count --config-get --config-set --setup-get --setup-apply --key-status --key-generate --test --logs --known-hosts --known-hosts-remove --users --faillock-status --faillock-set --faillock-reset --faillock-users; do
    check_core_flag "$SSH_CORE" "$f" "ssh"
done

# ── CLI -> core mapping ──
check_cli_uses "$FW_CLI" '--default' "firewall default"
check_cli_uses "$FW_CLI" '--allow' "firewall add accept"
check_cli_uses "$FW_CLI" '--deny' "firewall add deny"
check_cli_uses "$FW_CLI" '--block' "firewall add deny ip"
check_cli_uses "$FW_CLI" '--unblock' "firewall unblock"
check_cli_uses "$FW_CLI" '--delete' "firewall delete"
check_cli_uses "$FW_CLI" '--rules' "firewall rules"
check_cli_uses "$FW_CLI" '--on' "firewall on"
check_cli_uses "$FW_CLI" '--off' "firewall off"
check_cli_uses "$FW_CLI" '--ping' "firewall ping"
check_cli_uses "$FW_CLI" '--outbound' "firewall outbound"
check_cli_uses "$FW_CLI" '--boot' "firewall boot"
check_cli_uses "$FW_CLI" '--blocked' "firewall blocked"
check_cli_uses "$FW_CLI" '--connections' "firewall connections"
check_cli_uses "$FW_CLI" '--kill-connection' "firewall close"
check_cli_uses "$FW_CLI" '--drops' "firewall drops"
check_cli_uses "$FW_CLI" '--export' "firewall export"
check_cli_uses "$FW_CLI" '--import' "firewall import"

check_cli_uses "$SSH_CLI" '--setup-apply' "ssh setup"
check_cli_uses "$SSH_CLI" '--faillock-status' "ssh faillock status"
check_cli_uses "$SSH_CLI" '--faillock-reset' "ssh faillock reset"
check_cli_uses "$SSH_CLI" '--faillock-set' "ssh faillock set"
check_cli_uses "$SSH_CLI" '--config-set' "ssh config set"
check_cli_uses "$SSH_CLI" '--enable' "ssh on"
check_cli_uses "$SSH_CLI" '--disable' "ssh off"

# ── ssh_core auto-manages the firewall port ──
if grep -q "_fw_allow" "$SSH_CORE" 2>/dev/null; then
    echo "OK: ssh_core opens firewall port on enable/setup"
else
    FAILURES+=("ssh_core: no _fw_allow helper (firewall auto-open missing)")
fi
if grep -q "_fw_deny" "$SSH_CORE" 2>/dev/null; then
    echo "OK: ssh_core closes firewall port on disable"
else
    FAILURES+=("ssh_core: no _fw_deny helper (firewall auto-close missing)")
fi

# ── no legacy engine refs in new core ──
if grep -qE "insert-block|--set-engine|--engine\b" "$FW_CORE" 2>/dev/null; then
    FAILURES+=("firewall_core: still references legacy engine flags")
fi

if [[ ${#FAILURES[@]} -gt 0 ]]; then
    echo "FAIL: ${#FAILURES[@]} security mapping issues"
    for f in "${FAILURES[@]}"; do
        echo "ERROR: $f"
    done
    exit 1
fi

echo "PASS: firewall/ssh mapping consistent"
exit 0
