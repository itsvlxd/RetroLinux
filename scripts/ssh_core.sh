#!/bin/bash

RETRO_DIR="${RETRO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/lib/helpers.sh"
rx_log_register "ssh"

if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

SSHD_CONFIG="/etc/ssh/sshd_config"
FIREWALL_CORE="$RETRO_DIR/scripts/firewall_core.sh"
FAILLOCK_CONF="/etc/security/faillock.conf"

_target_user() {
    if [[ -n $SUDO_USER ]]; then
        echo "$SUDO_USER"
    elif [[ $EUID -ne 0 ]]; then
        id -un
    else
        echo ""
    fi
}

_target_home() {
    local user
    user=$(_target_user)
    if [[ -n $user ]]; then
        getent passwd "$user" | cut -d: -f6
    else
        echo "$HOME"
    fi
}

_fw_allow() {
    bash "$FIREWALL_CORE" --allow "$1" tcp >/dev/null 2>&1 || true
    bash "$FIREWALL_CORE" --allow "$1" udp >/dev/null 2>&1 || true
}

_fw_deny() {
    bash "$FIREWALL_CORE" --deny "$1" tcp >/dev/null 2>&1 || true
    bash "$FIREWALL_CORE" --deny "$1" udp >/dev/null 2>&1 || true
}

_ssh_port() {
    local port
    port=$(grep -E "^Port\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
    echo "${port:-22}"
}

_ssh_conf_value() {
    local key="$1"
    grep -E "^\s*${key}\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{$1=""; print $0}' | xargs
}

_ssh_set_value() {
    local key="$1" value="$2"
    if grep -qE "^\s*${key}\s+" "$SSHD_CONFIG" 2>/dev/null; then
        $SUDO_CMD sed -i "s/^\s*${key}\s\+.*/${key} ${value}/" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" | $SUDO_CMD tee -a "$SSHD_CONFIG" >/dev/null
    fi
}

_faillock_read() {
    local key="$1"
    local default="${2:-}"
    local val
    val=$(grep -E "^\s*${key}\s*=" "$FAILLOCK_CONF" 2>/dev/null | head -1 | cut -d= -f2 | xargs)
    echo "${val:-$default}"
}

_faillock_set() {
    local key="$1" value="$2"
    [[ ! -f $FAILLOCK_CONF ]] && return 1
    local backup="${FAILLOCK_CONF}.bak.$(date +%s)"
    $SUDO_CMD cp "$FAILLOCK_CONF" "$backup" || return 1
    local applied=false
    if grep -qE "^\s*${key}\s*=" "$FAILLOCK_CONF" 2>/dev/null; then
        $SUDO_CMD sed -i "s|^\s*${key}\s*=.*|${key} = ${value}|" "$FAILLOCK_CONF" && applied=true
    else
        echo "${key} = ${value}" | $SUDO_CMD tee -a "$FAILLOCK_CONF" >/dev/null && applied=true
    fi
    $applied
}

case "$1" in
    --status)
        daemon_status="inactive"
        daemon_pid=""
        ssh_version=""
        ssh_port="$(_ssh_port)"
        password_auth="unknown"
        pubkey_auth="unknown"
        root_login="unknown"
        sessions_count=0
        host_keys=0
        firewall_status="unknown"

        if systemctl is-active sshd &>/dev/null; then
            daemon_status="active"
            daemon_pid=$(systemctl show sshd -P MainPID 2>/dev/null || true)
        fi

        ssh_version=$(ssh -V 2>&1 || echo "unknown")

        if [[ -f $SSHD_CONFIG ]]; then
            pass_val=$(_ssh_conf_value "PasswordAuthentication")
            [[ -n $pass_val ]] && password_auth="$pass_val"
            pub_val=$(_ssh_conf_value "PubkeyAuthentication")
            [[ -n $pub_val ]] && pubkey_auth="$pub_val"
            root_val=$(_ssh_conf_value "PermitRootLogin")
            [[ -n $root_val ]] && root_login="$root_val"
        fi

        sessions_count=$(ss -tnp 2>/dev/null | grep -c ":${ssh_port}\s" || true)

        host_keys=$(find /etc/ssh/ -name 'ssh_host_*key.pub' 2>/dev/null | wc -l)

        fw_data=$(bash "$FIREWALL_CORE" --status 2>/dev/null)
        fw_open_ports=""
        while IFS='=' read -r key val; do
            [[ $key == "open_ports" ]] && fw_open_ports="$val"
        done <<<"$fw_data"

        if echo "$fw_open_ports" | grep -qE "(^|,)${ssh_port}/"; then
            firewall_status="open"
        else
            firewall_status="closed"
        fi

        empty_passwords="unknown"
        x11_forwarding="unknown"
        tcp_forwarding="unknown"
        max_auth_tries="unknown"
        idle_timeout="unknown"
        if [[ -f $SSHD_CONFIG ]]; then
            empty_val=$(_ssh_conf_value "PermitEmptyPasswords")
            [[ -n $empty_val ]] && empty_passwords="$empty_val"
            x11_val=$(_ssh_conf_value "X11Forwarding")
            [[ -n $x11_val ]] && x11_forwarding="$x11_val"
            tcp_val=$(_ssh_conf_value "AllowTcpForwarding")
            [[ -n $tcp_val ]] && tcp_forwarding="$tcp_val"
            tries_val=$(_ssh_conf_value "MaxAuthTries")
            [[ -n $tries_val ]] && max_auth_tries="$tries_val"
            alive_val=$(_ssh_conf_value "ClientAliveInterval")
            [[ -n $alive_val ]] && idle_timeout="$alive_val"
        fi

        echo "daemon_status=${daemon_status}"
        echo "daemon_pid=${daemon_pid}"
        echo "ssh_version=${ssh_version}"
        echo "ssh_port=${ssh_port}"
        echo "password_auth=${password_auth}"
        echo "pubkey_auth=${pubkey_auth}"
        echo "root_login=${root_login}"
        echo "sessions_count=${sessions_count}"
        echo "host_keys=${host_keys}"
        echo "firewall_status=${firewall_status}"
        echo "empty_passwords=${empty_passwords}"
        echo "x11_forwarding=${x11_forwarding}"
        echo "tcp_forwarding=${tcp_forwarding}"
        echo "max_auth_tries=${max_auth_tries}"
        echo "idle_timeout=${idle_timeout}"
        rx_log_file "info" "Status: ${daemon_status} port=${ssh_port} sessions=${sessions_count} keys=${host_keys}"
        ;;

    --start)
        $SUDO_CMD systemctl start sshd 2>/dev/null || true
        if systemctl is-active sshd &>/dev/null; then
            echo "OK|started"
            rx_log_file "success" "sshd started"
        else
            echo "result=error|reason=start_failed"
            rx_log_file "error" "Failed to start sshd"
            exit 1
        fi
        ;;

    --stop)
        $SUDO_CMD systemctl stop sshd 2>/dev/null || true
        if ! systemctl is-active sshd &>/dev/null; then
            echo "OK|stopped"
            rx_log_file "success" "sshd stopped"
        else
            echo "result=error|reason=stop_failed"
            rx_log_file "error" "Failed to stop sshd"
            exit 1
        fi
        ;;

    --restart)
        $SUDO_CMD systemctl restart sshd 2>/dev/null || true
        if systemctl is-active sshd &>/dev/null; then
            echo "OK|restarted"
            rx_log_file "success" "sshd restarted"
        else
            echo "result=error|reason=restart_failed"
            rx_log_file "error" "Failed to restart sshd"
            exit 1
        fi
        ;;

    --enable)
        if ! ls /etc/ssh/ssh_host_* &>/dev/null; then
            $SUDO_CMD ssh-keygen -A 2>/dev/null || true
        fi

        if ! $SUDO_CMD sshd -t 2>/dev/null; then
            $SUDO_CMD sed -i "s/^#*Port.*/Port 22/" "$SSHD_CONFIG"
            $SUDO_CMD sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication no/" "$SSHD_CONFIG"
            $SUDO_CMD sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" "$SSHD_CONFIG"
            $SUDO_CMD sed -i "s/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/" "$SSHD_CONFIG"
        fi

        $SUDO_CMD systemctl enable sshd 2>/dev/null || true
        $SUDO_CMD systemctl start sshd 2>/dev/null || true
        port=$(_ssh_port)
        _fw_allow "$port"

        if systemctl is-enabled sshd &>/dev/null && systemctl is-active sshd &>/dev/null; then
            echo "OK|enabled"
            rx_log_file "success" "sshd enabled and running (port ${port} opened)"
        elif systemctl is-active sshd &>/dev/null; then
            echo "OK|started"
            rx_log_file "warn" "sshd running but not enabled at boot"
        else
            echo "result=error|reason=enable_failed"
            rx_log_file "error" "Failed to enable sshd"
            exit 1
        fi
        ;;

    --disable)
        port=$(_ssh_port)
        _fw_deny "$port"
        $SUDO_CMD systemctl disable sshd 2>/dev/null || true
        $SUDO_CMD systemctl stop sshd 2>/dev/null || true
        if ! systemctl is-enabled sshd &>/dev/null && ! systemctl is-active sshd &>/dev/null; then
            echo "OK|disabled"
            rx_log_file "success" "sshd disabled and stopped (port ${port} closed)"
        else
            echo "result=error|reason=disable_failed"
            rx_log_file "error" "Failed to disable sshd"
            exit 1
        fi
        ;;

    --sessions)
        if [[ ! -f $SSHD_CONFIG ]]; then
            echo "result=error|reason=no_config"
            exit 1
        fi
        port=$(_ssh_port)

        who_output=$(who 2>/dev/null || true)
        session_count=0
        while IFS= read -r line; do
            if echo "$line" | grep -qE "\(.*\."; then
                user=$(echo "$line" | awk '{print $1}')
                ip=$(echo "$line" | grep -oP '\(\K[^)]+' || echo "local")
                since=$(echo "$line" | awk '{print $3, $4}')
                echo "user=${user}|ip=${ip}|since=${since}"
                ((session_count++))
            fi
        done <<<"$who_output"
        echo "count=${session_count}"
        ;;

    --session-count)
        port=$(_ssh_port)
        ss -tnp 2>/dev/null | grep -c ":${port}\s" || echo 0
        ;;

    --config-get)
        key="$2"
        if [[ -z $key ]]; then
            echo "result=error|reason=no_key"
            exit 1
        fi
        if [[ ! -f $SSHD_CONFIG ]]; then
            echo "result=error|reason=no_config"
            exit 1
        fi
        val=$(_ssh_conf_value "$key")
        if [[ -z $val ]]; then
            echo "result=not_set|key=${key}"
        else
            echo "result=ok|key=${key}|value=${val}"
        fi
        ;;

    --config-set)
        key="$2"
        value="$3"
        if [[ -z $key || -z $value ]]; then
            echo "result=error|reason=missing_key_or_value"
            exit 1
        fi
        if [[ ! -f $SSHD_CONFIG ]]; then
            echo "result=error|reason=no_config"
            exit 1
        fi

        backup="${SSHD_CONFIG}.bak.$(date +%s)"
        $SUDO_CMD cp "$SSHD_CONFIG" "$backup"
        trap 'exit 1' INT TERM EXIT

        _ssh_set_value "$key" "$value"

        if $SUDO_CMD sshd -t 2>/dev/null; then
            $SUDO_CMD rm -f "$backup"
            trap - INT TERM EXIT
            echo "OK|set|key=${key}|value=${value}"
            rx_log_file "success" "sshd_config: ${key}=${value}"
        else
            $SUDO_CMD mv "$backup" "$SSHD_CONFIG"
            trap - INT TERM EXIT
            echo "result=error|reason=invalid_config|key=${key}|value=${value}"
            rx_log_file "error" "Invalid sshd config for ${key}=${value}, rolled back"
            exit 1
        fi
        ;;

    --setup-get)
        if [[ ! -f $SSHD_CONFIG ]]; then
            echo "result=error|reason=no_config"
            exit 1
        fi

        port=$(_ssh_port)
        pass=$(_ssh_conf_value "PasswordAuthentication")
        pass="${pass:-no}"
        pubkey=$(_ssh_conf_value "PubkeyAuthentication")
        pubkey="${pubkey:-yes}"
        root=$(_ssh_conf_value "PermitRootLogin")
        root="${root:-prohibit-password}"

        echo "port=${port}"
        echo "password_auth=${pass}"
        echo "pubkey_auth=${pubkey}"
        echo "root_login=${root}"
        ;;

    --setup-apply)
        $SUDO_CMD systemctl stop sshd 2>/dev/null || true

        if ! pacman -Qs openssh &>/dev/null; then
            $SUDO_CMD pacman -S --noconfirm openssh 2>&1 | tail -3 || true
        fi

        [[ -f $SSHD_CONFIG ]] || { echo "result=error|reason=no_config"; exit 1; }

        port="${2:-22}"
        password_auth="${3:-no}"
        pubkey_auth="${4:-yes}"
        root_login="${5:-prohibit-password}"

        if ! [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
            echo "result=error|reason=invalid_port"
            exit 1
        fi

        $SUDO_CMD sed -i "s/^#*Port.*/Port ${port}/" "$SSHD_CONFIG"
        $SUDO_CMD sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication ${password_auth}/" "$SSHD_CONFIG"
        $SUDO_CMD sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication ${pubkey_auth}/" "$SSHD_CONFIG"
        $SUDO_CMD sed -i "s/^#*PermitRootLogin.*/PermitRootLogin ${root_login}/" "$SSHD_CONFIG"

        if ! ls /etc/ssh/ssh_host_* &>/dev/null; then
            $SUDO_CMD ssh-keygen -A 2>/dev/null || true
        fi

        if $SUDO_CMD sshd -t 2>/dev/null; then
            _fw_allow "$port"
            $SUDO_CMD systemctl enable --now sshd 2>/dev/null || true

            user_home=$(_target_home)
            [[ ! -f "$user_home/.ssh/id_ed25519" ]] && mkdir -p "$user_home/.ssh" && ssh-keygen -t ed25519 -f "$user_home/.ssh/id_ed25519" -N "" 2>/dev/null || true

            echo "OK|configured|port=${port}"
            rx_log_file "success" "SSH configured (port ${port})"
        else
            error=$($SUDO_CMD sshd -t 2>&1)
            echo "result=error|reason=invalid_config|error=${error}"
            rx_log_file "error" "SSH setup produced invalid config: ${error}"
            exit 1
        fi
        ;;

    --key-status)
        user_home=$(_target_home)
        echo "---host_keys---"
        for key_file in /etc/ssh/ssh_host_*_key.pub; do
            if [[ -f $key_file ]]; then
                type=$(basename "$key_file" | sed 's/ssh_host_//;s/_key.pub//')
                fingerprint=$(ssh-keygen -lf "$key_file" 2>/dev/null | awk '{print $2}')
                echo "type=${type}|fingerprint=${fingerprint}"
            fi
        done
        echo "---user_keys---"
        for key_file in "$user_home/.ssh/"*.pub; do
            if [[ -f $key_file ]]; then
                type=$(basename "$key_file")
                fingerprint=$(ssh-keygen -lf "$key_file" 2>/dev/null | awk '{print $2}')
                echo "file=${type}|fingerprint=${fingerprint}"
            fi
        done
        ;;

    --key-generate)
        key_type="${2:-ed25519}"
        user_home=$(_target_home)
        key_path="$user_home/.ssh/id_${key_type}"
        if [[ -f $key_path ]]; then
            echo "result=error|reason=already_exists|path=${key_path}"
            rx_log_file "warn" "SSH key already exists: ${key_path}"
            exit 1
        fi
        mkdir -p "$user_home/.ssh"
        chmod 700 "$user_home/.ssh"
        if ssh-keygen -t "$key_type" -f "$key_path" -N "" 2>&1; then
            echo "OK|generated|path=${key_path}|type=${key_type}"
            fingerprint=$(ssh-keygen -lf "${key_path}.pub" 2>/dev/null | awk '{print $2}')
            echo "fingerprint=${fingerprint}"
            rx_log_file "success" "SSH key generated: ${key_path} (${fingerprint})"
        else
            echo "result=error|reason=generate_failed"
            rx_log_file "error" "Failed to generate SSH key"
            exit 1
        fi
        ;;

    --test)
        if $SUDO_CMD sshd -t 2>/dev/null; then
            echo "OK|valid"
            rx_log_file "info" "sshd_config is valid"
        else
            error=$($SUDO_CMD sshd -t 2>&1)
            echo "result=invalid|error=${error}"
            rx_log_file "error" "sshd_config invalid: ${error}"
            exit 1
        fi
        ;;

    --logs)
        lines="${2:-50}"
        $SUDO_CMD journalctl -u sshd --no-pager -n "$lines" 2>/dev/null || echo "No logs available"
        ;;

    --known-hosts)
        known_hosts="$(_target_home)/.ssh/known_hosts"
        if [[ ! -f $known_hosts ]]; then
            echo "result=error|reason=no_known_hosts"
            exit 0
        fi
        count=0
        while IFS= read -r line; do
            line=$(echo "$line" | sed 's/^|.*//' | xargs)
            [[ -z $line ]] && continue
            host=$(echo "$line" | awk '{print $1}' | cut -d, -f1)
            algo=$(echo "$line" | awk '{print $2}')
            fingerprint=$(echo "$line" | awk '{print $3}' | base64 -d 2>/dev/null | xxd -p -c 256 2>/dev/null | head -c 16 || echo "unknown")
            echo "host=${host}|algorithm=${algo}|hash=${fingerprint}"
            ((count++))
        done < "$known_hosts"
        echo "count=${count}"
        ;;

    --known-hosts-remove)
        host_to_remove="$2"
        [[ -z $host_to_remove ]] && { echo "result=error|reason=no_host"; exit 1; }
        known_hosts="$(_target_home)/.ssh/known_hosts"
        if [[ ! -f $known_hosts ]]; then
            echo "result=error|reason=no_known_hosts"
            exit 0
        fi
        kept=$(grep -vE "^(\\|1\\|)?${host_to_remove}(,|\\[|\\s|$)" "$known_hosts" 2>/dev/null || true)
        cp "$known_hosts" "${known_hosts}.bak" 2>/dev/null || true
        printf '%s\n' "$kept" > "$known_hosts" 2>/dev/null
        if [[ $EUID -eq 0 ]]; then
            user=$(_target_user)
            [[ -n $user ]] && chown "$user" "$known_hosts" 2>/dev/null || true
        fi
        echo "OK|removed|host=${host_to_remove}"
        rx_log_file "info" "Known host removed: ${host_to_remove}"
        ;;

    --users)
        while IFS=: read -r user _ uid _ _ shell _; do
            if [[ $uid -ge 1000 && $uid -lt 65534 ]]; then
                if echo "$shell" | grep -qE "/(bash|zsh|sh|fish)$"; then
                    echo "user=${user}|shell=${shell}"
                fi
            fi
        done < /etc/passwd
        ;;

    --faillock-status)
        if [[ ! -f $FAILLOCK_CONF ]]; then
            echo "configured=false"
            echo "deny=5"
            echo "unlock_time=600"
            echo "even_for_root=false"
        else
            echo "configured=true"
            echo "deny=$(_faillock_read "deny" "5")"
            echo "unlock_time=$(_faillock_read "unlock_time" "600")"
            echo "even_for_root=$(_faillock_read "even_for_root" "false")"
        fi
        state=$(faillock --user "$USER" 2>/dev/null | tail -1 || true)
        echo "state=${state}"
        ;;

    --faillock-set)
        key="$2"
        value="$3"
        if [[ -z $key || -z $value ]]; then
            echo "result=error|reason=missing_key_or_value"
            exit 1
        fi
        case "$key" in
            deny)
                [[ $value =~ ^[0-9]+$ ]] || { echo "result=error|reason=invalid_value"; exit 1; }
                ;;
            unlock_time)
                [[ $value =~ ^[0-9]+$ ]] || { echo "result=error|reason=invalid_value"; exit 1; }
                ;;
            even_for_root)
                [[ $value == "true" || $value == "false" ]] || { echo "result=error|reason=invalid_value"; exit 1; }
                ;;
            *)
                echo "result=error|reason=unknown_key"
                exit 1
                ;;
        esac
        if _faillock_set "$key" "$value"; then
            echo "OK|set|key=${key}|value=${value}"
            rx_log_file "success" "faillock.conf: ${key}=${value}"
        else
            echo "result=error|reason=apply_failed"
            rx_log_file "error" "Failed to set faillock.conf: ${key}=${value}"
            exit 1
        fi
        ;;

    --faillock-reset)
        user="${2:-$USER}"
        [[ -n $user ]] && faillock --user "$user" --reset 2>/dev/null
        echo "OK|reset|user=${user}"
        rx_log_file "success" "faillock reset for ${user}"
        ;;

    --faillock-users)
        deny=$(_faillock_read "deny" "5")
        even_root=$(_faillock_read "even_for_root" "false")
        for file in /run/faillock/*; do
            [[ -e $file ]] || continue
            user=$(basename "$file")
            [[ -r $file ]] || continue
            failures=0
            last_time=0
            source=""
            recsize=64
            size=$(stat -c%s "$file" 2>/dev/null || echo 0)
            if [[ $size -ge $recsize ]]; then
                count=$((size / recsize))
                for ((i = 0; i < count; i++)); do
                    off=$((i * recsize))
                    status=$(od -An -j $((off + 54)) -N 2 -t u2 "$file" 2>/dev/null | tr -d ' ')
                    tval=$(od -An -j $((off + 56)) -N 8 -t u8 "$file" 2>/dev/null | tr -d ' ')
                    [[ -z $status ]] && status=0
                    [[ -z $tval ]] && tval=0
                    if (( status & 1 )); then
                        ((failures += 1))
                        if (( tval > last_time )); then
                            last_time=$tval
                            if (( status & 2 )); then
                                src=$(dd if="$file" bs=1 skip="$off" count=52 2>/dev/null | tr -d '\0' | xargs)
                                [[ -n $src ]] && source=$src
                            fi
                        fi
                    fi
                done
            fi
            locked=false
            reason="no_failures"
            if (( failures > 0 )); then
                if (( failures >= deny )); then
                    locked=true
                    if [[ $even_root == "true" || $user != "root" ]]; then
                        reason="locked: ${failures} of ${deny} allowed attempts"
                    else
                        reason="failed: ${failures} attempts (root exempt)"
                    fi
                else
                    reason="failed: ${failures} of ${deny} allowed attempts"
                fi
            fi
            echo "user=${user}|failures=${failures}|locked=${locked}|reason=${reason}|source=${source}|last=${last_time}"
        done
        ;;

    *)
        echo "result=error|reason=unknown_flag|flag=$1"
        echo "Usage: $0 <--status|--start|--stop|--restart|--enable|--disable|--sessions|--session-count|--config-get|--config-set|--setup-get|--key-status|--key-generate|--test|--logs|--known-hosts|--users|--setup-apply|--faillock-status|--faillock-set|--faillock-reset>"
        exit 1
        ;;
esac
