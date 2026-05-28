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

            local engine daemon_status rule_count default_policy open_ports
            while IFS='=' read -r key val; do
                case "$key" in
                    engine) engine="$val" ;;
                    daemon_status) daemon_status="$val" ;;
                    rule_count) rule_count="$val" ;;
                    default_policy) default_policy="$val" ;;
                    open_ports) open_ports="$val" ;;
                esac
            done <<<"$data"

            local engine_color="$MUTE"
            [[ $engine != "none" && $engine != "unknown" ]] && engine_color="$PINK"

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

            local ports_color="$MUTE"
            [[ -n $open_ports ]] && ports_color="$PINK"

            rx_table_header "󰦝" "Firewall Status"
            rx_table_row "󰀐" "Engine:" "${engine^}" "$engine_color" "24"
            rx_table_row "󰈐" "Status:" "${daemon_display}" "$daemon_color" "24"
            rx_table_row "󰦝" "Rules:" "${rule_count:-0}" "$rules_color" "24"
            rx_table_row "󰒋" "Default Policy:" "${default_policy^}" "$policy_color" "24"
            rx_table_row "󱂷" "Open Ports:" "${open_ports:-None}" "$ports_color" "24"
            rx_table_separator
            rx_table_spacer
            ;;

        "setup")
            rx_setup_parse "$@"
            rx_setup_validate "engine" "engine:in=nftables,ufw,firewalld,iptables" || return 1

            local config_data
            config_data=$(bash "$core" --setup-get 2>/dev/null)
            local current_engine current_status
            while IFS='=' read -r key val; do
                case "$key" in
                    engine) current_engine="$val" ;;
                    daemon_status) current_status="$val" ;;
                esac
            done <<<"$config_data"

            : "${current_engine:=none}"
            : "${current_status:=inactive}"

            local config_exists=false
            [[ $current_engine != "none" ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            local engine_input=""
            local -a port_inputs=()

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                engine_input=$(rx_setup_get_opt "engine" "$current_engine")
            else
                local available
                available=$(bash "$core" --list-engines 2>/dev/null)
                local -a engines=($available)

                if [[ ${#engines[@]} -eq 0 ]]; then
                    rx_log "error" "No firewall engines found. Install one: ${PINK}nftables, ufw, firewalld, iptables${RESET}"
                    return 1
                fi

                if [[ $config_exists == true ]]; then
                    rx_setup_prompt_reconfigure "󰦝" "Current Firewall Configuration" \
                        "Engine" "${current_engine^}" \
                        "Status" "${current_status^}" || return 0
                fi

                if [[ ${#engines[@]} -eq 1 ]]; then
                    engine_input="${engines[0]}"
                    rx_log "info" "Using only available engine: ${PINK}${engine_input^}${RESET}"
                else
                    engine_input=$(rx_menu "󰦝" "Select Firewall Engine" "${engines[@]}")
                fi

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

                rx_setup_summary "󰦝" "Firewall Setup Summary" \
                    "Engine" "${engine_input^}" \
                    "Open Ports" "$ports_preview"

                rx_setup_confirm || return 0
            fi

            rx_log "info" "Applying firewall configuration..."
            local result
            result=$(bash "$core" --setup-apply "$engine_input" "${port_inputs[@]}" 2>/dev/null)

            if echo "$result" | grep -q "^OK|"; then
                local result_data
                result_data=$(bash "$core" --status 2>/dev/null)
                local res_engine res_status res_rules res_policy res_ports
                while IFS='=' read -r key val; do
                    case "$key" in
                        engine) res_engine="$val" ;;
                        daemon_status) res_status="$val" ;;
                        rule_count) res_rules="$val" ;;
                        default_policy) res_policy="$val" ;;
                        open_ports) res_ports="$val" ;;
                    esac
                done <<<"$result_data"

                rx_setup_success "󰦝" "Firewall Configured" \
                    "Engine" "${res_engine^}" \
                    "Status" "${res_status^}" \
                    "Rules" "${res_rules:-0}" \
                    "Default Policy" "${res_policy^}" \
                    "Open Ports" "${res_ports:-None}"
            else
                local error_reason
                error_reason=$(echo "$result" | grep -oP 'error=\K[^|]+' || echo "unknown")
                rx_log "error" "Failed to apply firewall config: ${error_reason}"
                return 1
            fi
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
            while IFS='=' read -r key val; do
                if [[ $key == "count" ]]; then
                    count="$val"
                fi
            done <<<"$data"

            if [[ $count -eq 0 ]]; then
                rx_log "info" "No firewall rules configured"
                return 0
            fi

            rx_table_header "󰦝" "Firewall Rules: ${count} rules"
            local entry chain port proto action
            while IFS='|' read -r part; do
                if [[ $part =~ ^entry=([0-9]+) ]]; then
                    entry="${BASH_REMATCH[1]}"
                fi
                if [[ $part =~ chain=([a-z_]+) ]]; then
                    chain="${BASH_REMATCH[1]}"
                fi
                if [[ $part =~ port=([0-9]+) ]]; then
                    port="${BASH_REMATCH[1]}"
                fi
                if [[ $part =~ proto=([a-z0-9]+) ]]; then
                    proto="${BASH_REMATCH[1]}"
                fi
                if [[ $part =~ action=([a-z]+) ]]; then
                    action="${BASH_REMATCH[1]}"
                    local action_color="$PINK"
                    [[ $action == "drop" || $action == "deny" ]] && action_color="$WARN"
                    [[ $action == "accept" || $action == "allow" ]] && action_color="$SUCCESS"
                    rx_table_row "󰦝" "#${entry}" "${chain}:${port}/${proto} → ${action}" "$action_color" "20"
                fi
            done <<<"$data"
            rx_table_separator
            rx_table_spacer
            ;;

        "allow")
            local port="$1"
            local proto="${2:-tcp}"
            [[ -z $port ]] && rx_log "error" "Usage: retro firewall allow <port> [tcp|udp]" && return 1
            local result
            result=$(bash "$core" --allow "$port" "$proto" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Port ${PINK}${port}/${proto}${RESET} allowed"
            else
                rx_log "error" "Failed to allow port ${port}/${proto}"
                return 1
            fi
            ;;

        "deny")
            local port="$1"
            local proto="${2:-tcp}"
            [[ -z $port ]] && rx_log "error" "Usage: retro firewall deny <port> [tcp|udp]" && return 1
            local result
            result=$(bash "$core" --deny "$port" "$proto" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Port ${PINK}${port}/${proto}${RESET} denied"
            else
                rx_log "error" "Failed to deny port ${port}/${proto}"
                return 1
            fi
            ;;

        "delete")
            local port="$1"
            local proto="${2:-tcp}"
            [[ -z $port ]] && rx_log "error" "Usage: retro firewall delete <port> [tcp|udp]" && return 1
            local result
            result=$(bash "$core" --delete "$port" "$proto" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Rule deleted for ${PINK}${port}/${proto}${RESET}"
            else
                rx_log "error" "Failed to delete rule for ${port}/${proto}"
                return 1
            fi
            ;;

        "block")
            local ip="$1"
            [[ -z $ip ]] && rx_log "error" "Usage: retro firewall block <ip>" && return 1
            local result
            result=$(bash "$core" --block "$ip" 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "IP ${PINK}${ip}${RESET} blocked"
            else
                rx_log "error" "Failed to block IP ${ip}"
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

        "engine")
            local engine
            engine=$(bash "$core" --engine 2>/dev/null)
            rx_log "info" "Current firewall engine: ${PINK}${engine^}${RESET}"
            ;;

        "logs")
            local lines="${1:-50}"
            bash "$core" --logs "$lines" 2>/dev/null
            ;;

        "help" | "")
            rx_help_usage "retro firewall <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show firewall engine, status, rules, and open ports" 24
            rx_help_cmd "setup" "Run firewall setup wizard" 24
            rx_help_cmd "on" "Enable and start firewall" 24
            rx_help_cmd "off" "Disable and stop firewall" 24
            rx_help_cmd "restart" "Restart firewall" 24
            rx_help_cmd "rules" "List all firewall rules" 24
            rx_help_cmd "allow <port> [tcp|udp]" "Open a port" 24
            rx_help_cmd "deny <port> [tcp|udp]" "Close a port" 24
            rx_help_cmd "delete <port> [tcp|udp]" "Delete a rule" 24
            rx_help_cmd "block <ip>" "Block an IP address" 24
            rx_help_cmd "default <drop|accept>" "Set default input policy" 24
            rx_help_cmd "engine" "Show current firewall engine" 24
            rx_help_cmd "logs [lines]" "Show firewall daemon logs" 24
            rx_help_spacer
            rx_help_examples
            rx_help_example "retro firewall status" "Show full firewall status" "38"
            rx_help_example "retro firewall setup" "Run interactive firewall setup" "38"
            rx_help_example "retro firewall on" "Enable and start firewall" "38"
            rx_help_example "retro firewall allow 80" "Open HTTP port" "38"
            rx_help_example "retro firewall deny 443" "Close HTTPS port" "38"
            rx_help_example "retro firewall block 10.0.0.5" "Block suspicious IP" "38"
            rx_help_example "retro firewall default drop" "Drop all incoming by default" "38"
            rx_help_example "retro firewall rules" "List active rules" "38"
            rx_help_spacer
            ;;

        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}

register_command "TOOLS" "firewall" "Multi-engine firewall management (nftables, ufw, firewalld, iptables)" "cmd_firewall"
