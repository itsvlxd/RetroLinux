#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/setup.sh"

cmd_firewall() {
    local action="${1,,}"
    shift
    local core="$RETRO_DIR/scripts/firewall_core.sh"

    case "$action" in
        "status")
            local data
            data=$(bash "$core" --status 2>/dev/null)
            [[ -z $data ]] && rx_log "error" "Failed to get firewall status" && return 1

            local engine daemon_status rule_count default_policy open_ports boot_enabled outbound_policy ping blocked_packets
            while IFS='=' read -r key val; do
                case "$key" in
                    engine) engine="$val" ;;
                    daemon_status) daemon_status="$val" ;;
                    rule_count) rule_count="$val" ;;
                    default_policy) default_policy="$val" ;;
                    open_ports) open_ports="$val" ;;
                    boot_enabled) boot_enabled="$val" ;;
                    outbound_policy) outbound_policy="$val" ;;
                    ping) ping="$val" ;;
                    blocked_packets) blocked_packets="$val" ;;
                esac
            done <<<"$data"

            local daemon_color="$MUTE"
            local daemon_display="○ Inactive"
            [[ $daemon_status == "active" ]] && daemon_color="$SUCCESS" && daemon_display="● Active"

            local rules_color="$MUTE"
            [[ ${rule_count:-0} -gt 0 ]] && rules_color="$PINK"

            local policy_color="$MUTE"
            case "${default_policy,,}" in
                drop | deny) policy_color="$SUCCESS" ;;
                accept | allow) policy_color="$WARN" ;;
            esac

            local boot_color="$SUCCESS"
            [[ $boot_enabled != "enabled" ]] && boot_color="$MUTE"

            local out_color="$SUCCESS"
            [[ ${outbound_policy:-accept} == "drop" ]] && out_color="$WARN"

            local ping_color="$MUTE"
            [[ ${ping:-on} == "on" ]] && ping_color="$SUCCESS"

            local ports_color="$MUTE"
            [[ -n $open_ports ]] && ports_color="$PINK"

            local blocked_color="$MUTE"
            [[ ${blocked_packets:-0} -gt 0 ]] && blocked_color="$WARN"

            rx_table_header "󰦝" "Firewall Status"
            rx_table_row "󰀐" "Engine:" "${engine:-nftables}" "$PINK" "24"
            rx_table_row "󰈐" "Status:" "${daemon_display}" "$daemon_color" "24"
            rx_table_row "󰦝" "Rules:" "${rule_count:-0}" "$rules_color" "24"
            rx_table_row "󰒋" "Default Policy:" "${default_policy^}" "$policy_color" "24"
            rx_table_row "󰰔" "Outbound Policy:" "${outbound_policy^}" "$out_color" "24"
            rx_table_row "󰈐" "Boot:" "${boot_enabled^}" "$boot_color" "24"
            rx_table_row "󰒈" "Ping:" "${ping^}" "$ping_color" "24"
            rx_table_row "󰘦" "Packets Blocked:" "${blocked_packets:-0}" "$blocked_color" "24"
            rx_table_row "󱂷" "Open Ports:" "${open_ports:-None}" "$ports_color" "24"
            rx_table_separator
            rx_table_spacer
            ;;

        "setup")
            rx_setup_parse "$@"
            rx_setup_validate "default,ports" "default:in=drop,accept" || return 1

            local config_data
            config_data=$(bash "$core" --status 2>/dev/null)
            local current_status current_policy
            while IFS='=' read -r key val; do
                case "$key" in
                    daemon_status) current_status="$val" ;;
                    default_policy) current_policy="$val" ;;
                esac
            done <<<"$config_data"

            : "${current_status:=inactive}"

            local config_exists=false
            [[ $current_status == "active" ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            local -a port_inputs=()
            local default_input="drop"

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                default_input=$(rx_setup_get_opt "default" "drop")
                local opt_ports
                opt_ports=$(rx_setup_get_opt "ports" "")
                if [[ -n $opt_ports ]]; then
                    local IFS_SAVE=$IFS
                    IFS=','
                    for pp in $opt_ports; do
                        [[ -n $pp ]] && port_inputs+=("$pp" "tcp")
                    done
                    IFS=$IFS_SAVE
                fi
            else
                if [[ $config_exists == true ]]; then
                    rx_setup_prompt_reconfigure "󰦝" "Current Firewall Configuration" \
                        "Engine" "nftables" \
                        "Status" "${current_status^}" \
                        "Default Policy" "${current_policy^}" || return 0
                fi

                rx_log "info" "Engine: ${PINK}nftables${RESET} (only supported engine)"

                rx_log "info" "Select ports to open:"
                rx_confirm "Open SSH (22/tcp)?" "Y" && { port_inputs+=("22" "tcp"); }
                rx_confirm "Open HTTP (80/tcp)?" "N" && { port_inputs+=("80" "tcp"); }
                rx_confirm "Open HTTPS (443/tcp)?" "N" && { port_inputs+=("443" "tcp"); }
                rx_confirm "Open IMAP (143/tcp)?" "N" && { port_inputs+=("143" "tcp"); }
                rx_confirm "Open SMTP (25/tcp)?" "N" && { port_inputs+=("25" "tcp"); }

                if rx_confirm "Open a custom port?" "N"; then
                    local cport
                    cport=$(rx_input_numeric "Enter port number" "" 1 65535)
                    local cproto
                    cproto=$(rx_input "Protocol (tcp/udp)" "tcp")
                    [[ -n $cport ]] && port_inputs+=("$cport" "$cproto")
                fi

                local ports_preview="None"
                if [[ ${#port_inputs[@]} -gt 0 ]]; then
                    ports_preview=""
                    local i=0
                    while [[ $i -lt ${#port_inputs[@]} ]]; do
                        [[ -n $ports_preview ]] && ports_preview+=", "
                        ports_preview+="${port_inputs[$i]}/${port_inputs[$((i + 1))]}"
                        i=$((i + 2))
                    done
                fi

                default_input=$(rx_menu "󰦝" "Default Input Policy" "drop" "accept")

                rx_setup_summary "󰦝" "Firewall Setup Summary" \
                    "Engine" "nftables" \
                    "Default Policy" "${default_input^}" \
                    "Open Ports" "$ports_preview"

                rx_setup_confirm || return 0
            fi

            rx_log "info" "Applying firewall configuration..."
            bash "$core" --on >/dev/null 2>&1 || true
            bash "$core" --default "$default_input" >/dev/null 2>&1 || true

            local i=0
            while [[ $i -lt ${#port_inputs[@]} ]]; do
                bash "$core" --allow "${port_inputs[$i]}" "${port_inputs[$((i + 1))]}" >/dev/null 2>&1 || true
                i=$((i + 2))
            done

            local sudoers_file="/etc/sudoers.d/99-retro-security"
            if [[ ! -f $sudoers_file ]]; then
                cat <<'EOF' | sudo tee "$sudoers_file" >/dev/null 2>&1 && sudo chmod 440 "$sudoers_file" 2>/dev/null || true
%wheel ALL=(ALL) NOPASSWD: /opt/retrolinux/scripts/firewall_core.sh
%wheel ALL=(ALL) NOPASSWD: /opt/retrolinux/scripts/ssh_core.sh
%wheel ALL=(ALL) NOPASSWD: /usr/bin/nft
%wheel ALL=(ALL) NOPASSWD: /usr/bin/ss
%wheel ALL=(ALL) NOPASSWD: /usr/bin/kill
%wheel ALL=(ALL) NOPASSWD: /usr/bin/faillock
%wheel ALL=(ALL) NOPASSWD: /usr/bin/tee /var/log/retro-firewall-blocked
EOF
            fi

            local result_data
            result_data=$(bash "$core" --status 2>/dev/null)
            local res_status res_rules res_policy res_ports
            while IFS='=' read -r key val; do
                case "$key" in
                    daemon_status) res_status="$val" ;;
                    rule_count) res_rules="$val" ;;
                    default_policy) res_policy="$val" ;;
                    open_ports) res_ports="$val" ;;
                esac
            done <<<"$result_data"

            rx_setup_success "󰦝" "Firewall Configured" \
                "Engine" "nftables" \
                "Status" "${res_status^}" \
                "Rules" "${res_rules:-0}" \
                "Default Policy" "${res_policy^}" \
                "Open Ports" "${res_ports:-None}"
            ;;

        "on")
            local result
            result=$(bash "$core" --on 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Firewall enabled and started"
            else
                rx_log "error" "Failed to enable firewall"
                return 1
            fi
            ;;

        "off")
            local result
            result=$(bash "$core" --off 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Firewall disabled and stopped"
            else
                rx_log "error" "Failed to disable firewall"
                return 1
            fi
            ;;

        "restart")
            local result
            result=$(bash "$core" --restart 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Firewall restarted"
            else
                rx_log "error" "Failed to restart firewall"
                return 1
            fi
            ;;

        "rules")
            local data
            data=$(bash "$core" --rules 2>/dev/null)
            local count=0
            while IFS='|' read -r entry proto port ip action; do
                [[ $entry =~ ^count=([0-9]+)$ ]] && count="${BASH_REMATCH[1]}"
            done <<<"$data"

            count=$(echo "$data" | grep "^count=" | cut -d= -f2)
            if [[ $count -eq 0 ]]; then
                rx_log "info" "No firewall rules configured"
                return 0
            fi

            rx_table_header "󰦝" "Firewall Rules: ${count} rules"
            while IFS='|' read -r entry proto port ip action; do
                [[ $entry != "RULES" ]] && continue
                local action_color="$PINK"
                [[ $action == "drop" ]] && action_color="$WARN"
                [[ $action == "accept" ]] && action_color="$SUCCESS"
                local rule_desc
                if [[ -n $ip && $ip != "-" ]]; then
                    if [[ $port != "-" ]]; then
                        rule_desc="ip:${ip}:${port}/${proto} → ${action}"
                    else
                        rule_desc="ip:${ip} → ${action}"
                    fi
                else
                    rule_desc="input:${port}/${proto} → ${action}"
                fi
                rx_table_row "󰦝" "#${entry}" "$rule_desc" "$action_color" "4"
            done <<<"$data"
            rx_table_separator
            rx_table_spacer
            ;;

        "add")
            local rule_action="${1,,}" target="$2" proto="${3:-both}"
            [[ -z $rule_action || ! $rule_action =~ ^(deny|accept)$ ]] && \
                rx_log "error" "Usage: retro firewall add <deny|accept> <port|ip> [both|tcp|udp]" && return 1
            [[ -z $target ]] && \
                rx_log "error" "Usage: retro firewall add <deny|accept> <port|ip> [both|tcp|udp]" && return 1
            [[ ! $proto =~ ^(both|tcp|udp)$ ]] && \
                rx_log "error" "Invalid protocol '${proto}'. Use both, tcp or udp." && return 1

            local ip="" port="" is_ip_only=false
            if [[ $target =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]+$ ]]; then
                ip="${target%:*}"; port="${target#*:}"
            elif [[ $target =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                ip="$target"; is_ip_only=true
            else
                port="$target"
            fi

            if [[ -n $port ]]; then
                [[ ! $port =~ ^[0-9]+$ || $port -lt 1 || $port -gt 65535 ]] && \
                    rx_log "error" "Invalid port '${port}'. Must be a number 1-65535." && return 1
            fi

            if [[ $is_ip_only == true && $rule_action == "accept" ]]; then
                rx_log "error" "Cannot accept an entire IP. Use a specific port or 'deny' to block."
                return 1
            fi

            local result
            if [[ $is_ip_only == true ]]; then
                result=$(bash "$core" --block "$ip" "manual" "$proto" 2>/dev/null)
            elif [[ -n $ip ]]; then
                if [[ $rule_action == "deny" ]]; then
                    result=$(bash "$core" --deny-ip "$ip" "$port" "$proto" 2>/dev/null)
                else
                    result=$(bash "$core" --allow-ip "$ip" "$port" "$proto" 2>/dev/null)
                fi
            else
                if [[ $rule_action == "deny" ]]; then
                    result=$(bash "$core" --deny "$port" "$proto" 2>/dev/null)
                else
                    result=$(bash "$core" --allow "$port" "$proto" 2>/dev/null)
                fi
            fi

            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Rule added: ${rule_action} ${target}"
            else
                rx_log "error" "Failed to add ${rule_action} for ${target}"
                return 1
            fi
            ;;

        "unblock")
            local target="$1"
            [[ -z $target ]] && rx_log "error" "Usage: retro firewall unblock <ip>" && return 1
            local result
            result=$(bash "$core" --unblock "$target" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Unblocked ${PINK}${target}${RESET}"
            else
                rx_log "error" "Failed to unblock ${target}"
                return 1
            fi
            ;;

        "delete")
            local id="$1"
            [[ -z $id || ! $id =~ ^[0-9]+(-[0-9]+)?$ ]] && \
                rx_log "error" "Usage: retro firewall delete <rule_number> (e.g. 5 or 1-3)" && return 1
            local result
            result=$(bash "$core" --delete "$id" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                if [[ $id == *-* ]]; then
                    rx_log "success" "Rules ${PINK}${id}${RESET} deleted"
                else
                    rx_log "success" "Rule #${PINK}${id}${RESET} deleted"
                fi
            else
                rx_log "error" "Failed to delete rule(s) ${id}. Do they exist?"
                return 1
            fi
            ;;

        "default")
            local policy="$1"
            [[ -z $policy ]] && rx_log "error" "Usage: retro firewall default <drop|accept>" && return 1
            local result
            result=$(bash "$core" --default "$policy" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Default policy set to ${PINK}${policy}${RESET}"
            else
                rx_log "error" "Failed to set default policy"
                return 1
            fi
            ;;

        "test")
            local result
            result=$(bash "$core" --test 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "nftables config is valid"
            else
                rx_log "error" "nftables config is invalid"
                return 1
            fi
            ;;

        "ping")
            local mode="$1"
            [[ -z $mode || ! $mode =~ ^(on|off)$ ]] && rx_log "error" "Usage: retro firewall ping <on|off>" && return 1
            local result
            result=$(bash "$core" --ping "$mode" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Ping ${PINK}${mode}${RESET}"
            else
                rx_log "error" "Failed to set ping policy"
                return 1
            fi
            ;;

        "outbound")
            local policy="$1"
            [[ -z $policy || ! $policy =~ ^(drop|accept)$ ]] && rx_log "error" "Usage: retro firewall outbound <drop|accept>" && return 1
            local result
            result=$(bash "$core" --outbound "$policy" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Outbound policy set to ${PINK}${policy}${RESET}"
            else
                rx_log "error" "Failed to set outbound policy"
                return 1
            fi
            ;;

        "boot")
            local mode="${1:-status}"
            local result
            result=$(bash "$core" --boot "$mode" 2>/dev/null)
            case "$mode" in
                enable) rx_log "success" "Firewall will start at boot" ;;
                disable) rx_log "success" "Firewall will not start at boot" ;;
                *) rx_log "info" "Boot: ${result#boot=}" ;;
            esac
            ;;

        "blocked")
            local data
            data=$(bash "$core" --blocked 2>/dev/null)
            local count=0
            count=$(echo "$data" | grep "^count=" | cut -d= -f2)
            if [[ $count -eq 0 ]]; then
                rx_log "info" "No blocked addresses"
                return 0
            fi
            rx_table_header "󰦝" "Blocked Addresses: ${count}"
            while IFS='|' read -r entry ip reason time_str; do
                [[ $entry != "BLOCK" ]] && continue
                rx_table_row "󰒋" "$ip" "${reason} \u00b7 ${time_str}" "$WARN" "4"
            done <<<"$data"
            rx_table_separator
            rx_table_spacer
            ;;

        "connections")
            local port="${1:-}"
            local data
            data=$(bash "$core" --connections "$port" 2>/dev/null)
            local count=0
            count=$(echo "$data" | grep "^count=" | cut -d= -f2)
            if [[ $count -eq 0 ]]; then
                rx_log "info" "No active connections"
                return 0
            fi
            rx_table_header "󰦝" "Active Connections: ${count}"
            while IFS='|' read -r entry proto state _local_addr remote_addr _pid proc; do
                [[ $entry != "CONN" ]] && continue
                rx_table_row "󰈐" "$remote_addr" "${proto}/${state} \u00b7 ${proc:-unknown}" "$PINK" "4"
            done <<<"$data"
            rx_table_separator
            rx_table_spacer
            ;;

        "drops")
            local lines="${1:-10}"
            bash "$core" --drops "$lines" 2>/dev/null
            ;;

        "close")
            local pid="$2"
            [[ -z $pid ]] && rx_log "error" "Usage: retro firewall close <pid>" && return 1
            local result
            result=$(bash "$core" --kill-connection "$pid" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Connection closed (pid ${pid})"
            else
                rx_log "error" "Failed to close connection ${pid}: $result"
                return 1
            fi
            ;;

        "export")
            local file="$2"
            [[ -z $file ]] && rx_log "error" "Usage: retro firewall export <file>" && return 1
            local result
            result=$(bash "$core" --export "$file" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Ruleset exported to ${PINK}${file}${RESET}"
            else
                rx_log "error" "Failed to export ruleset"
                return 1
            fi
            ;;

        "import")
            local file="$2"
            [[ -z $file ]] && rx_log "error" "Usage: retro firewall import <file>" && return 1
            local result
            result=$(bash "$core" --import "$file" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Ruleset imported from ${PINK}${file}${RESET}"
            else
                rx_log "error" "Failed to import ruleset (is it valid nftables?)"
                return 1
            fi
            ;;

        "logs")
            local lines="${1:-50}"
            bash "$core" --logs "$lines" 2>/dev/null
            ;;

        "help" | "")
            rx_help_usage "retro firewall <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show firewall status, rules, and open ports" 50
            rx_help_cmd "setup" "Run firewall setup wizard" 50
            rx_help_cmd "on" "Enable and start firewall" 50
            rx_help_cmd "off" "Disable and stop firewall" 50
            rx_help_cmd "restart" "Restart firewall" 50
            rx_help_cmd "rules" "List all firewall rules" 50
            rx_help_cmd "add deny <port|ip> [both|tcp|udp]" "Append a deny rule" 50
            rx_help_cmd "add accept <port|ip> [both|tcp|udp]" "Append an accept rule" 50
            rx_help_cmd "unblock <ip>" "Remove a blocked IP" 50
            rx_help_cmd "delete <id>" "Delete rule(s) by ID (e.g. 5 or 1-3)" 50
            rx_help_cmd "default <drop|accept>" "Set default input policy" 50
            rx_help_cmd "ping <on|off>" "Allow or block ping (ICMP)" 50
            rx_help_cmd "outbound <drop|accept>" "Set default outbound policy" 50
            rx_help_cmd "boot <enable|disable|status>" "Control firewall at boot" 50
            rx_help_cmd "blocked" "List blocked addresses" 50
            rx_help_cmd "connections [port]" "Show active connections" 50
            rx_help_cmd "close <pid>" "Close an active connection by PID" 50
            rx_help_cmd "drops [lines]" "Show recent dropped packets" 50
            rx_help_cmd "export <file>" "Export the ruleset to a file" 50
            rx_help_cmd "import <file>" "Import a ruleset from a file" 50
            rx_help_cmd "test" "Validate the nftables config" 50
            rx_help_cmd "logs [lines]" "Show firewall daemon logs" 50
            rx_help_spacer
            rx_help_examples
            rx_help_example "retro firewall status" "Show full firewall status" "44"
            rx_help_example "retro firewall setup" "Run interactive firewall setup" "44"
            rx_help_example "retro firewall add deny 10.0.0.5" "Block IP (append)" "44"
            rx_help_example "retro firewall add deny 8080" "Deny port 8080 (append)" "44"
            rx_help_example "retro firewall add accept 80" "Allow port 80 (append)" "44"
            rx_help_example "retro firewall add deny 10.0.0.5:22" "Deny IP on specific port" "44"
            rx_help_example "retro firewall unblock 10.0.0.5" "Unblock an IP" "44"
            rx_help_example "retro firewall default drop" "Drop all incoming by default" "44"
            rx_help_example "retro firewall rules" "List active rules" "44"
            rx_help_spacer
            ;;

        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}

register_command "TOOLS" "firewall" "nftables firewall management (ports, rules, blocked IPs)" "cmd_firewall"
