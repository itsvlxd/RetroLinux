#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/setup.sh"

cmd_ssh() {
    local action="${1,,}"
    shift
    local core="$RETRO_DIR/scripts/ssh_core.sh"

    case "$action" in
        "status")
            local data
            data=$(bash "$core" --status 2>/dev/null)
            [[ -z $data ]] && rx_log "error" "Failed to get SSH status" && return 1

            local daemon_status daemon_pid ssh_version ssh_port
            local password_auth pubkey_auth root_login
            local sessions_count host_keys firewall_status

            while IFS='=' read -r key val; do
                case "$key" in
                    daemon_status) daemon_status="$val" ;;
                    daemon_pid) daemon_pid="$val" ;;
                    ssh_version) ssh_version="$val" ;;
                    ssh_port) ssh_port="$val" ;;
                    password_auth) password_auth="$val" ;;
                    pubkey_auth) pubkey_auth="$val" ;;
                    root_login) root_login="$val" ;;
                    sessions_count) sessions_count="$val" ;;
                    host_keys) host_keys="$val" ;;
                    firewall_status) firewall_status="$val" ;;
                esac
            done <<<"$data"

            local daemon_color="$MUTE"
            local daemon_display="○ Inactive"
            [[ $daemon_status == "active" ]] && daemon_color="$SUCCESS" && daemon_display="● Active (PID: ${daemon_pid})"

            local version_display="${ssh_version:-unknown}"
            local port_display="Port ${ssh_port}"

            local auth_display="Password: ${password_auth^} | Pubkey: ${pubkey_auth^} | Root: ${root_login^}"

            local sessions_color="$MUTE"
            [[ $sessions_count -gt 0 ]] && sessions_color="$SUCCESS"

            local keys_color="$SUCCESS"
            [[ $host_keys -eq 0 ]] && keys_color="$WARN"

            local fw_color="$MUTE"
            [[ $firewall_status == "open" ]] && fw_color="$SUCCESS"
            [[ $firewall_status == "closed" ]] && fw_color="$WARN"

            rx_table_header "󰒓" "SSH Status"
            rx_table_row "󰀐" "Daemon:" "${daemon_display}" "$daemon_color" "24"
            rx_table_row "󰒋" "Version:" "${version_display}" "$PINK" "24"
            rx_table_row "󰩭" "Port:" "${port_display}" "$PINK" "24"
            rx_table_row "󰒋" "Auth Methods:" "${auth_display}" "$MUTE" "24"
            rx_table_row "󱓓" "Sessions:" "${sessions_count} active" "$sessions_color" "24"
            rx_table_row "󰇵" "Host Keys:" "${host_keys} present" "$keys_color" "24"
            rx_table_row "󱂷" "Firewall:" "Port ${ssh_port} ${firewall_status}" "$fw_color" "24"
            rx_table_separator
            rx_table_spacer
            ;;

        "setup")
            rx_setup_parse "$@"

            rx_setup_validate "port,password,pubkey,root" "port:numeric|min=1|max=65535|required|password:required|pubkey:required|root:required" || return 1

            local config_data
            config_data=$(bash "$core" --setup-get 2>/dev/null)
            local current_port current_password current_pubkey current_root

            while IFS='=' read -r key val; do
                case "$key" in
                    port) current_port="$val" ;;
                    password_auth) current_password="$val" ;;
                    pubkey_auth) current_pubkey="$val" ;;
                    root_login) current_root="$val" ;;
                esac
            done <<<"$config_data"

            : "${current_port:=22}"
            [[ $current_port =~ ^[0-9]+$ && $current_port -ge 1 && $current_port -le 65535 ]] || current_port=22
            : "${current_password:=no}"
            : "${current_pubkey:=yes}"
            : "${current_root:=prohibit-password}"

            local config_exists=true
            [[ -z $current_port ]] && config_exists=false

            rx_setup_check_needed "$config_exists" && return 0

            local port_input="" password_input="" pubkey_input="" root_input=""

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                port_input=$(rx_setup_get_opt "port" "$current_port")
                password_input=$(rx_setup_get_opt "password" "$current_password")
                pubkey_input=$(rx_setup_get_opt "pubkey" "$current_pubkey")
                root_input=$(rx_setup_get_opt "root" "$current_root")
            else
                if [[ $config_exists == true ]]; then
                    rx_setup_prompt_reconfigure "󰒓" "Current SSH Configuration" \
                        "Port" "$current_port" \
                        "Password Auth" "$current_password" \
                        "Pubkey Auth" "$current_pubkey" \
                        "Root Login" "$current_root" || return 0
                fi

                rx_log "info" "Installing openssh..."
                check_dep "ssh" "openssh" || return 1

                rx_log "info" "SSH Configuration"

                port_input=$(rx_input_numeric "Enter SSH port" "$current_port" 1 65535)

                if rx_confirm "Enable password authentication?" "$( [[ $current_password == "yes" ]] && echo "Y" || echo "N" )"; then
                    password_input="yes"
                else
                    password_input="no"
                fi

                if rx_confirm "Enable public key authentication?" "$( [[ $current_pubkey == "yes" ]] && echo "Y" || echo "N" )"; then
                    pubkey_input="yes"
                else
                    pubkey_input="no"
                fi

                if rx_confirm "Allow root login?" "$( [[ $current_root == "yes" ]] && echo "Y" || echo "N" )"; then
                    root_input="yes"
                else
                    root_input="prohibit-password"
                fi

                rx_setup_summary "󰒓" "SSH Setup Summary" \
                    "Port" "$port_input" \
                    "Password Auth" "$password_input" \
                    "Pubkey Auth" "$pubkey_input" \
                    "Root Login" "$root_input"

                rx_setup_confirm || return 0
            fi

            rx_log "info" "Applying SSH configuration..."
            local result
            result=$(bash "$core" --setup-apply "$port_input" "$password_input" "$pubkey_input" "$root_input" 2>/dev/null)

            if echo "$result" | grep -q "^OK|"; then
                local result_data
                result_data=$(bash "$core" --status 2>/dev/null)
                local result_daemon result_port result_sessions result_keys
                while IFS='=' read -r key val; do
                    case "$key" in
                        daemon_status) result_daemon="$val" ;;
                        ssh_port) result_port="$val" ;;
                        sessions_count) result_sessions="$val" ;;
                        host_keys) result_keys="$val" ;;
                    esac
                done <<<"$result_data"

                rx_setup_success "󰒓" "SSH Configured" \
                    "Daemon" "${result_daemon^}" \
                    "Port" "${result_port}" \
                    "Sessions" "${result_sessions} active" \
                    "Host Keys" "${result_keys} present"
            else
                local error_reason
                error_reason=$(echo "$result" | grep -oP 'error=\K[^|]+' || echo "unknown")
                rx_log "error" "Failed to apply SSH config: ${error_reason}"
                return 1
            fi
            ;;

        "on")
            local result
            result=$(bash "$core" --enable 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "SSH enabled and started"
            else
                rx_log "error" "Failed to enable SSH"
                return 1
            fi
            ;;

        "off")
            local result
            result=$(bash "$core" --disable 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "SSH disabled and stopped"
            else
                rx_log "error" "Failed to disable SSH"
                return 1
            fi
            ;;

        "restart")
            local result
            result=$(bash "$core" --restart 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "SSH restarted"
            else
                rx_log "error" "Failed to restart SSH"
                return 1
            fi
            ;;

        "sessions")
            local data
            data=$(bash "$core" --sessions 2>/dev/null)
            local count=0

            while IFS='=' read -r key val; do
                if [[ $key == "count" ]]; then
                    count="$val"
                fi
            done <<<"$data"

            if [[ $count -eq 0 ]]; then
                rx_log "info" "No active SSH sessions"
                return 0
            fi

            rx_table_header "󱓓" "Active SSH Sessions"
            while IFS='|' read -r part; do
                if [[ $part =~ ^user=([^|]+) ]]; then
                    local user="${BASH_REMATCH[1]}"
                fi
                if [[ $part =~ ip=([^|]+) ]]; then
                    local ip="${BASH_REMATCH[1]}"
                fi
                if [[ $part =~ since=(.+) ]]; then
                    local since="${BASH_REMATCH[1]}"
                    rx_table_row "󰈀" "${user}" "${ip}  (since ${since})" "$PINK" "20"
                fi
            done <<<"$data"
            rx_table_separator
            rx_table_row "" "Total:" "${count} sessions" "$PINK" "20"
            rx_table_spacer
            ;;

        "config")
            local sub="$1"
            shift

            if [[ -z $sub ]]; then
                local data
                data=$(bash "$core" --status 2>/dev/null)
                local port pass pubkey root
                while IFS='=' read -r key val; do
                    case "$key" in
                        ssh_port) port="$val" ;;
                        password_auth) pass="$val" ;;
                        pubkey_auth) pubkey="$val" ;;
                        root_login) root="$val" ;;
                    esac
                done <<<"$data"

                rx_table_header "󰒓" "SSH Configuration"
                rx_table_row "󰩭" "Port:" "${port}" "$PINK" "24"
                rx_table_row "󰒋" "Password Auth:" "${pass^}" "$( [[ $pass == "yes" ]] && echo "$SUCCESS" || echo "$WARN" )" "24"
                rx_table_row "󰒋" "Pubkey Auth:" "${pubkey^}" "$( [[ $pubkey == "yes" ]] && echo "$SUCCESS" || echo "$WARN" )" "24"
                rx_table_row "󰒋" "Root Login:" "${root^}" "$( [[ $root == "no" || $root == "prohibit-password" ]] && echo "$SUCCESS" || echo "$WARN" )" "24"
                rx_table_separator
                rx_table_spacer
            elif [[ $sub == "set" ]]; then
                local key="$1"
                local value="$2"
                if [[ -z $key || -z $value ]]; then
                    rx_log "error" "Usage: retro ssh config set <key> <value>"
                    return 1
                fi
                local result
                result=$(bash "$core" --config-set "$key" "$value" 2>/dev/null)
                if echo "$result" | grep -q "^OK|"; then
                    rx_log "success" "${key} set to ${value}"
                    rx_log "info" "Run ${PINK}retro ssh restart${RESET} to apply"
                else
                    rx_log "error" "Failed to set ${key}"
                    return 1
                fi
            else
                rx_log "error" "Usage: retro ssh config [set <key> <value>]"
                return 1
            fi
            ;;

        "key")
            local sub="$1"

            if [[ $sub == "generate" ]]; then
                local key_type="${2:-ed25519}"
                local result
                result=$(bash "$core" --key-generate "$key_type" 2>/dev/null)
                if echo "$result" | grep -q "^OK|"; then
                    rx_log "success" "SSH key generated (${key_type})"
                    local fingerprint
                    fingerprint=$(echo "$result" | grep "^fingerprint=" | cut -d= -f2-)
                    [[ -n $fingerprint ]] && rx_log "info" "Fingerprint: ${PINK}${fingerprint}${RESET}"
                else
                    rx_log "error" "Failed to generate SSH key"
                    return 1
                fi
            else
                local data
                data=$(bash "$core" --key-status 2>/dev/null)
                local in_host=false
                local in_user=false

                while IFS= read -r line; do
                    if [[ $line == "---host_keys---" ]]; then
                        in_host=true
                        in_user=false
                        rx_table_header "󰇵" "Host Keys"
                    elif [[ $line == "---user_keys---" ]]; then
                        in_host=false
                        in_user=true
                        rx_table_row "" "" "" "" "24"
                        rx_table_header "󰇵" "User Keys"
                    elif [[ $in_host == true && $line =~ ^type= ]]; then
                        local ktype="${line#type=}"
                        ktype="${ktype%%|*}"
                        local fp="${line#*fingerprint=}"
                        rx_table_row "󰇵" "${ktype}" "${fp}" "$GRAY" "20"
                    elif [[ $in_user == true && $line =~ ^file= ]]; then
                        local fname="${line#file=}"
                        fname="${fname%%|*}"
                        local fp="${line#*fingerprint=}"
                        rx_table_row "󰇵" "${fname}" "${fp}" "$GRAY" "20"
                    fi
                done <<<"$data"
                rx_table_separator
                rx_table_spacer
            fi
            ;;

        "test")
            local result
            result=$(bash "$core" --test 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "sshd_config is valid"
            else
                local error
                error=$(echo "$result" | grep "^result=invalid" | cut -d= -f3-)
                rx_log "error" "sshd_config invalid: ${error}"
                return 1
            fi
            ;;

        "logs")
            local lines="${1:-50}"
            bash "$core" --logs "$lines" 2>/dev/null
            ;;

        "known-hosts")
            local data
            data=$(bash "$core" --known-hosts 2>/dev/null)
            local count=0

            while IFS='=' read -r key val; do
                if [[ $key == "count" ]]; then
                    count="$val"
                fi
            done <<<"$data"

            if [[ $count -eq 0 ]]; then
                rx_log "info" "No known hosts"
                return 0
            fi

            rx_table_header "󰋚" "Known Hosts"
            while IFS='|' read -r part; do
                if [[ $part =~ ^host=([^|]+) ]]; then
                    local host="${BASH_REMATCH[1]}"
                fi
                if [[ $part =~ algorithm=([^|]+) ]]; then
                    local algo="${BASH_REMATCH[1]}"
                    rx_table_row "󰈀" "${host}" "${algo}" "$GRAY" "40"
                fi
            done <<<"$data"
            rx_table_separator
            rx_table_row "" "Total:" "${count} hosts" "$PINK" "40"
            rx_table_spacer
            ;;

        "users")
            local data
            data=$(bash "$core" --users 2>/dev/null)
            if [[ -z $data ]]; then
                rx_log "info" "No users with shell access"
                return 0
            fi

            rx_table_header "󰈀" "Users with SSH Access"
            while IFS='=' read -r key val; do
                if [[ $key == "user" ]]; then
                    local user="$val"
                fi
                if [[ $key == "shell" ]]; then
                    rx_table_row "󰒋" "${user}" "${val}" "$GRAY" "24"
                fi
            done <<<"$data"
            rx_table_spacer
            ;;

        "help"|"")
            rx_help_usage "retro ssh <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show SSH daemon, sessions, and config overview" 24
            rx_help_cmd "setup" "Run SSH setup wizard" 24
            rx_help_cmd "on" "Enable and start SSH at boot" 24
            rx_help_cmd "off" "Disable and stop SSH" 24
            rx_help_cmd "restart" "Restart SSH daemon" 24
            rx_help_cmd "sessions" "List active SSH connections" 24
            rx_help_cmd "config" "Show current SSH configuration" 24
            rx_help_cmd "config set <key> <val>" "Change an SSH config value" 24
            rx_help_cmd "key" "List SSH host and user keys" 24
            rx_help_cmd "key generate [type]" "Generate a new SSH key" 24
            rx_help_cmd "test" "Validate sshd_config" 24
            rx_help_cmd "logs [lines]" "Tail SSH daemon logs" 24
            rx_help_cmd "known-hosts" "List known remote hosts" 24
            rx_help_cmd "users" "List users who can SSH in" 24
            rx_help_spacer
            rx_help_examples
            rx_help_example "retro ssh status" "Show full SSH status" "38"
            rx_help_example "retro ssh setup" "Run interactive SSH setup" "38"
            rx_help_example "retro ssh on" "Enable and start SSH" "38"
            rx_help_example "retro ssh sessions" "List active sessions" "38"
            rx_help_example "retro ssh config set Port 2222" "Change SSH port" "38"
            rx_help_example "retro ssh key generate" "Generate ed25519 key" "38"
            rx_help_example "retro ssh setup -o --needed" "Non-interactive setup" "38"
            rx_help_spacer
            ;;

        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}

register_command "TOOLS" "ssh" "OpenSSH daemon management and session monitoring" "cmd_ssh"
