#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/lib/helpers.sh"
rx_log_register "ssh"

if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

SSHD_CONFIG="/etc/ssh/sshd_config"

case "$1" in
    --status)
        daemon_status="inactive"
        daemon_pid=""
        ssh_version=""
        ssh_port="22"
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
            port_val=$(grep -E "^Port\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
            [[ -n $port_val ]] && ssh_port="$port_val"

            pass_val=$(grep -E "^PasswordAuthentication\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
            [[ -n $pass_val ]] && password_auth="$pass_val"

            pub_val=$(grep -E "^PubkeyAuthentication\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
            [[ -n $pub_val ]] && pubkey_auth="$pub_val"

            root_val=$(grep -E "^PermitRootLogin\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
            [[ -n $root_val ]] && root_login="$root_val"
        fi

        sessions_count=$(ss -tnp 2>/dev/null | grep -c ":${ssh_port}\s" || true)

        host_keys=$(find /etc/ssh/ -name 'ssh_host_*key.pub' 2>/dev/null | wc -l)

        local firewall_status="unmanaged"
        local fw_data fw_engine fw_open_ports
        fw_data=$(bash "$RETRO_DIR/scripts/firewall_core.sh" --status 2>/dev/null)
        while IFS='=' read -r key val; do
            case "$key" in
                engine) fw_engine="$val" ;;
                open_ports) fw_open_ports="$val" ;;
            esac
        done <<<"$fw_data"

        if [[ -n $fw_engine && $fw_engine != "none" ]]; then
            if echo "$fw_open_ports" | grep -qE "(^|,)${ssh_port}/"; then
                firewall_status="open"
            else
                firewall_status="closed"
            fi
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
        if systemctl is-enabled sshd &>/dev/null && systemctl is-active sshd &>/dev/null; then
            echo "OK|enabled"
            rx_log_file "success" "sshd enabled and running"
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
        $SUDO_CMD systemctl disable sshd 2>/dev/null || true
        $SUDO_CMD systemctl stop sshd 2>/dev/null || true
        if ! systemctl is-enabled sshd &>/dev/null && ! systemctl is-active sshd &>/dev/null; then
            echo "OK|disabled"
            rx_log_file "success" "sshd disabled and stopped"
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
        port=$(grep -E "^Port\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
        port="${port:-22}"

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
        port=$(grep -E "^Port\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
        port="${port:-22}"
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
        val=$(grep -E "^\s*${key}\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{$1=""; print $0}' | xargs)
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
        trap "$SUDO_CMD mv '$backup' '$SSHD_CONFIG'; exit 1" INT TERM EXIT

        if grep -qE "^\s*${key}\s+" "$SSHD_CONFIG" 2>/dev/null; then
            $SUDO_CMD sed -i "s/^\s*${key}\s\+.*/${key} ${value}/" "$SSHD_CONFIG"
        else
            echo "${key} ${value}" | $SUDO_CMD tee -a "$SSHD_CONFIG" >/dev/null
        fi

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

        port=$(grep -E "^\s*Port\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
        port="${port:-22}"

        pass=$(grep -E "^\s*PasswordAuthentication\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
        pass="${pass:-no}"

        pubkey=$(grep -E "^\s*PubkeyAuthentication\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
        pubkey="${pubkey:-yes}"

        root=$(grep -E "^\s*PermitRootLogin\s+" "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}')
        root="${root:-prohibit-password}"

        echo "port=${port}"
        echo "password_auth=${pass}"
        echo "pubkey_auth=${pubkey}"
        echo "root_login=${root}"
        ;;

    --key-status)
        echo "---host_keys---"
        for key_file in /etc/ssh/ssh_host_*_key.pub; do
            if [[ -f $key_file ]]; then
                type=$(basename "$key_file" | sed 's/ssh_host_//;s/_key.pub//')
                fingerprint=$(ssh-keygen -lf "$key_file" 2>/dev/null | awk '{print $2}')
                echo "type=${type}|fingerprint=${fingerprint}"
            fi
        done
        echo "---user_keys---"
        for key_file in "$HOME/.ssh/"*.pub; do
            if [[ -f $key_file ]]; then
                type=$(basename "$key_file")
                fingerprint=$(ssh-keygen -lf "$key_file" 2>/dev/null | awk '{print $2}')
                echo "file=${type}|fingerprint=${fingerprint}"
            fi
        done
        ;;

    --key-generate)
        key_type="${2:-ed25519}"
        key_path="$HOME/.ssh/id_${key_type}"
        if [[ -f $key_path ]]; then
            echo "result=error|reason=already_exists|path=${key_path}"
            rx_log_file "warn" "SSH key already exists: ${key_path}"
            exit 1
        fi
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
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
        known_hosts="$HOME/.ssh/known_hosts"
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

    --users)
        while IFS=: read -r user _ uid _ _ shell _; do
            if [[ $uid -ge 1000 && $uid -lt 65534 ]]; then
                if echo "$shell" | grep -qE "/(bash|zsh|sh|fish)$"; then
                    echo "user=${user}|shell=${shell}"
                fi
            fi
        done < /etc/passwd
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

        $SUDO_CMD sed -i "s/^#*Port.*/Port ${port}/" "$SSHD_CONFIG"
        $SUDO_CMD sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication ${password_auth}/" "$SSHD_CONFIG"
        $SUDO_CMD sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication ${pubkey_auth}/" "$SSHD_CONFIG"
        $SUDO_CMD sed -i "s/^#*PermitRootLogin.*/PermitRootLogin ${root_login}/" "$SSHD_CONFIG"

        if ! ls /etc/ssh/ssh_host_* &>/dev/null; then
            $SUDO_CMD ssh-keygen -A 2>/dev/null || true
        fi

        bash "$RETRO_DIR/scripts/firewall_core.sh" --allow "${port}" tcp >/dev/null 2>&1 || true

        if $SUDO_CMD sshd -t 2>/dev/null; then
            $SUDO_CMD systemctl enable --now sshd 2>/dev/null || true

            [[ ! -f "$HOME/.ssh/id_ed25519" ]] && mkdir -p "$HOME/.ssh" && ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" 2>/dev/null || true

            echo "OK|configured|port=${port}"
            rx_log_file "success" "SSH configured (port ${port})"
        else
            error=$($SUDO_CMD sshd -t 2>&1)
            echo "result=error|reason=invalid_config|error=${error}"
            rx_log_file "error" "SSH setup produced invalid config: ${error}"
            exit 1
        fi
        ;;

    *)
        echo "result=error|reason=unknown_flag|flag=$1"
        echo "Usage: $0 <--status|--start|--stop|--restart|--enable|--disable|--sessions|--session-count|--config-get|--config-set|--setup-get|--key-status|--key-generate|--test|--logs|--known-hosts|--users|--setup-apply>"
        exit 1
        ;;
esac
