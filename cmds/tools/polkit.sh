#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/setup.sh"

_ensure_polkit_agent() {
    local binary="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
    if [[ -x $binary ]]; then
        return 0
    fi
    if pacman -Qi polkit-gnome &>/dev/null; then
        return 0
    fi
    local helper
    helper=$(get_var "PKG_HELPER")
    : "${helper:=yay}"
    rx_log "error" "Missing required dependency: polkit-gnome"
    rx_confirm "Would you like to install [polkit-gnome] using $helper?" "N" || {
        rx_log "info" "Dependency required. Aborting."
        return 1
    }
    rx_log "info" "Installing..."

    check_dep "polkit-gnome" "polkit-gnome"

    return 0
}

cmd_polkit() {
    local action="${1,,}"
    shift
    local core="$RETRO_DIR/scripts/polkit_core.sh"

    case "$action" in
        "status")
            local data
            data=$(bash "$core" --status 2>/dev/null)
            [[ -z $data ]] && rx_log "error" "Failed to get polkit status" && return 1

            local daemon_status daemon_memory agent_bin agent_status
            local rules_count actions_count

            while IFS='=' read -r key val; do
                case "$key" in
                    daemon_status) daemon_status="$val" ;;
                    daemon_memory) daemon_memory="$val" ;;
                    agent_binary) agent_bin="$val" ;;
                    agent_status) agent_status="$val" ;;
                    rules_count) rules_count="$val" ;;
                    actions_count) actions_count="$val" ;;
                esac
            done <<<"$data"

            local daemon_color="$MUTE"
            local daemon_display="○ Inactive"
            [[ $daemon_status == "active" ]] && daemon_color="$SUCCESS" && daemon_display="● Active"
            local mem_display=""
            [[ -n $daemon_memory ]] && mem_display=" (${daemon_memory})"

            local agent_color="$WARN"
            local agent_display="○ Stopped"
            [[ $agent_status == "running" ]] && agent_color="$SUCCESS" && agent_display="● Running"
            local agent_name=""
            if [[ -n $agent_bin ]]; then
                agent_name=" ($(basename "$agent_bin"))"
            else
                agent_name=" (none installed)"
            fi

            local rules_color="$MUTE"
            [[ $rules_count -gt 0 ]] && rules_color="$SUCCESS"

            rx_table_header "󰒓" "Polkit Infrastructure Status"
            rx_table_row "󰀐" "Daemon:" "${daemon_display}${mem_display}" "$daemon_color" "24"
            rx_table_row "󰒋" "Auth Agent:" "${agent_display}${agent_name}" "$agent_color" "24"
            rx_table_row "󰋚" "Custom Rules:" "${rules_count} in /etc/polkit-1/rules.d/" "$rules_color" "24"
            rx_table_row "󰋚" "Registered Actions:" "${actions_count}" "$GRAY" "24"
            rx_table_separator
            rx_table_spacer
            ;;

        "setup")
            rx_setup_parse "$@"

            local config_exists=false
            local status_data
            status_data=$(bash "$core" --status 2>/dev/null)
            local current_daemon current_agent
            while IFS='=' read -r key val; do
                case "$key" in
                    daemon_status) current_daemon="$val" ;;
                    agent_status) current_agent="$val" ;;
                esac
            done <<<"$status_data"

            [[ $current_daemon == "active" || $current_agent == "running" ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                _ensure_polkit_agent || true
                bash "$core" --agent-start 2>/dev/null || rx_log "warn" "Failed to start auth agent"
            else
                if [[ $config_exists == true ]]; then
                    local daemon_display="${current_daemon^}"
                    local agent_display="${current_agent^}"

                    rx_setup_current "󰒓" "Current Polkit Configuration" \
                        "Daemon" "$daemon_display" \
                        "Auth Agent" "$agent_display" || true

                    if ! rx_confirm "Reconfigure?" "N"; then
                        rx_log "info" "Setup cancelled."
                        return 0
                    fi
                fi

                rx_log "info" "Ensuring polkit daemon is running..."
                if [[ $current_daemon != "active" ]]; then
                    $SUDO_CMD systemctl start polkit.service 2>/dev/null || rx_log "warn" "Could not start polkit.service"
                fi

                _ensure_polkit_agent || return 1

                if ! bash "$core" --agent-status 2>/dev/null | grep -q "agent_installed=true"; then
                    rx_log "error" "No polkit auth agent available — install polkit-gnome"
                    return 1
                fi

                if bash "$core" --agent-status 2>/dev/null | grep -q "agent_running=false"; then
                    if rx_confirm "Start the polkit auth agent now?" "Y"; then
                        bash "$core" --agent-start 2>/dev/null || rx_log "warn" "Failed to start agent"
                    fi
                fi

                local result_data
                result_data=$(bash "$core" --status 2>/dev/null)
                local result_daemon result_agent result_rules result_actions
                while IFS='=' read -r key val; do
                    case "$key" in
                        daemon_status) result_daemon="$val" ;;
                        agent_status) result_agent="$val" ;;
                        rules_count) result_rules="$val" ;;
                        actions_count) result_actions="$val" ;;
                    esac
                done <<<"$result_data"

                rx_setup_summary "󰒓" "Polkit Setup Summary" \
                    "Daemon" "${result_daemon^}" \
                    "Auth Agent" "${result_agent^}" \
                    "Custom Rules" "${result_rules} files" \
                    "Actions" "${result_actions} registered"

                rx_setup_confirm || return 0

                rx_setup_success "󰒓" "Polkit Configured" \
                    "Daemon" "${result_daemon^}" \
                    "Auth Agent" "${result_agent^}" \
                    "Custom Rules" "${result_rules} files" \
                    "Actions" "${result_actions} registered"
            fi
            ;;

        "start")
            local result
            result=$(bash "$core" --agent-start 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Polkit auth agent and keyring daemon started"
            else
                rx_log "error" "Failed to start auth agent"
                return 1
            fi
            ;;

        "stop")
            local result
            result=$(bash "$core" --agent-stop 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Polkit auth agent stopped"
            else
                rx_log "error" "Failed to stop auth agent"
                return 1
            fi
            ;;

        "restart")
            bash "$core" --agent-stop &>/dev/null || true
            sleep 0.3
            local result
            result=$(bash "$core" --agent-start 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Polkit auth agent restarted"
            else
                rx_log "error" "Failed to restart auth agent"
                return 1
            fi
            ;;

        "enable")
            local result
            result=$(bash "$core" --agent-configure 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Polkit agent enabled in startup sequence"
                rx_log "info" "It will start on next ${PINK}retro --load${RESET}"
            else
                rx_log "error" "Failed to enable polkit agent"
                return 1
            fi
            ;;

        "disable")
            local result
            result=$(bash "$core" --agent-disable 2>/dev/null)
            if echo "$result" | grep -q "^OK|"; then
                rx_log "success" "Polkit agent disabled in startup sequence"
            else
                rx_log "error" "Failed to disable polkit agent"
                return 1
            fi
            ;;

        "rules")
            local sub="$1"

            if [[ $sub == "show" ]]; then
                local rule_file="$2"
                if [[ -z $rule_file ]]; then
                    rx_log "error" "Usage: retro polkit rules show <filename>"
                    return 1
                fi
                bash "$core" --rules-show "$rule_file" 2>/dev/null || rx_log "error" "Rule not found: $rule_file"
                return 0
            fi

            local data
            data=$(bash "$core" --rules-list 2>/dev/null)
            if [[ -z $data ]]; then
                rx_log "info" "No custom polkit rules in /etc/polkit-1/rules.d/"
                return 0
            fi

            rx_table_header "󰋚" "Custom Polkit Rules"

            local count=0
            while IFS='|' read -r part; do
                if [[ $part =~ ^file=([^|]+) ]]; then
                    local filename="${BASH_REMATCH[1]}"
                    ((count++))
                fi
                if [[ $part =~ preview=(.*)$ ]]; then
                    local preview="${BASH_REMATCH[1]}"
                    rx_table_row "󰈐" "$filename" "$preview" "$GRAY" "36"
                fi
            done <<<"$data"

            rx_table_separator
            rx_table_row "" "Total:" "${count} files" "$PINK" "36"
            rx_table_spacer
            ;;

        "actions")
            local term="$1"

            if [[ -z $term ]]; then
                local data
                data=$(bash "$core" --actions-list 2>/dev/null)
                if [[ -z $data ]]; then
                    rx_log "info" "No polkit actions found"
                    return 0
                fi

                rx_table_header "󰋚" "Registered Polkit Actions"
                while IFS= read -r action_id; do
                    [[ -z $action_id ]] && continue
                    rx_table_row "󰄾" "$action_id" "" "$MUTE" "60"
                done <<<"$data"
                local total
                total=$(echo "$data" | wc -l)
                rx_table_separator
                rx_table_row "" "Total:" "${total} actions" "$PINK" "60"
                rx_table_spacer
            elif [[ $term == "show" ]]; then
                local action_id="$2"
                if [[ -z $action_id ]]; then
                    rx_log "error" "Usage: retro polkit actions show <action-id>"
                    return 1
                fi
                bash "$core" --actions-show "$action_id" 2>/dev/null || rx_log "error" "Action not found: $action_id"
            else
                local data
                data=$(bash "$core" --actions-search "$term" 2>/dev/null)
                if [[ -z $data ]]; then
                    rx_log "info" "No actions match: ${term}"
                    return 0
                fi

                rx_table_header "󰋚" "Actions matching \"${term}\""
                while IFS= read -r action_id; do
                    [[ -z $action_id ]] && continue
                    rx_table_row "󰄾" "$action_id" "" "$MUTE" "60"
                done <<<"$data"
                local total
                total=$(echo "$data" | wc -l)
                rx_table_separator
                rx_table_row "" "Total:" "${total} actions" "$PINK" "60"
                rx_table_spacer
            fi
            ;;

        "check")
            local action_id="$1"
            if [[ -z $action_id ]]; then
                rx_log "error" "Usage: retro polkit check <action-id>"
                return 1
            fi

            local result
            result=$(bash "$core" --check "$action_id" 2>/dev/null)
            if echo "$result" | grep -q "^OK|authorized"; then
                rx_log "success" "Authorized: ${PINK}${action_id}${RESET}"
            else
                rx_log "error" "Not authorized: ${PINK}${action_id}${RESET}"
                return 1
            fi
            ;;

        "temp")
            local sub="${1,,}"

            if [[ $sub == "--revoke" || $sub == "revoke" ]]; then
                local result
                result=$(bash "$core" --temp-revoke 2>/dev/null)
                if echo "$result" | grep -q "^OK|"; then
                    rx_log "success" "Temporary authorizations revoked"
                else
                    rx_log "error" "Failed to revoke temporary authorizations"
                    return 1
                fi
            else
                local data
                data=$(bash "$core" --temp-list 2>/dev/null)
                if [[ -z $data || $data == "result=none" ]]; then
                    rx_log "info" "No temporary authorizations"
                else
                    echo "$data"
                fi
            fi
            ;;

        "help" | "")
            rx_help_usage "retro polkit <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show polkit daemon, agent, rules, and actions overview" 24
            rx_help_cmd "setup" "Run polkit setup wizard (agent install + boot config)" 24
            rx_help_cmd "start" "Start auth agent and keyring daemon" 24
            rx_help_cmd "stop" "Stop the polkit auth agent" 24
            rx_help_cmd "restart" "Restart the polkit auth agent" 24
            rx_help_cmd "enable" "Enable agent in startup sequence" 24
            rx_help_cmd "disable" "Disable agent in startup sequence" 24
            rx_help_cmd "rules" "List custom polkit rules" 24
            rx_help_cmd "rules show <file>" "Show full rule content" 24
            rx_help_cmd "actions" "List all registered actions" 24
            rx_help_cmd "actions <term>" "Search actions by keyword" 24
            rx_help_cmd "actions show <id>" "Show action details" 24
            rx_help_cmd "check <action-id>" "Check authorization for an action" 24
            rx_help_cmd "temp" "List temporary authorizations" 24
            rx_help_cmd "temp --revoke" "Revoke all temporary auths" 24
            rx_help_examples
            rx_help_example "retro polkit status" "Show full polkit infrastructure status" "38"
            rx_help_example "retro polkit setup" "Run interactive polkit setup wizard" "38"
            rx_help_example "retro polkit start" "Launch auth agent and keyring daemon" "38"
            rx_help_example "retro polkit stop" "Stop the auth agent" "38"
            rx_help_example "retro polkit enable" "Add agent to boot startup" "38"
            rx_help_example "retro polkit rules" "List custom polkit rules" "38"
            rx_help_example "retro polkit actions network" "Search actions related to network" "38"
            rx_help_example "retro polkit check org.freedesktop.NetworkManager.settings.modify.system" "Check if authorized" "38"
            rx_help_example "retro polkit setup -o --needed" "Non-interactive setup" "38"
            rx_help_spacer
            ;;

        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}

register_command "TOOLS" "polkit" "PolicyKit authorization manager, auth agent, and rules" "cmd_polkit"
