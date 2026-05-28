#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/lib/helpers.sh"
rx_log_register "polkit"



_agent_binary() {
    local binary="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
    if command -v polkit-gnome-authentication-agent-1 &>/dev/null; then
        echo "polkit-gnome-authentication-agent-1"
    elif [[ -x $binary ]]; then
        echo "$binary"
    elif pacman -Qi polkit-gnome &>/dev/null && [[ -x $binary ]]; then
        echo "$binary"
    else
        echo ""
    fi
}

_agent_running() {
    local bin
    bin=$(_agent_binary)
    [[ -z $bin ]] && return 1
    local basename
    basename=$(basename "$bin")
    pgrep -f "$basename" >/dev/null 2>&1
}

case "$1" in
    --status)
        daemon_status="inactive"
        daemon_memory=""
        agent_bin=""
        agent_status="stopped"
        rules_count=0
        actions_count=0

        if systemctl is-active polkit.service &>/dev/null; then
            daemon_status="active"
            daemon_memory=$(systemctl show polkit.service -P MemoryCurrent 2>/dev/null || true)
            if [[ -n $daemon_memory ]]; then
                daemon_memory="$(numfmt --to=iec "$daemon_memory" 2>/dev/null || echo "${daemon_memory}B")"
            fi
        fi

        agent_bin=$(_agent_binary)
        if _agent_running; then
            agent_status="running"
        fi

        rules_count=$(find /etc/polkit-1/rules.d/ -name '*.rules' 2>/dev/null | wc -l)
        actions_count=$(pkaction 2>/dev/null | wc -l)

        echo "daemon_status=${daemon_status}"
        echo "daemon_memory=${daemon_memory}"
        echo "agent_binary=${agent_bin}"
        echo "agent_status=${agent_status}"
        echo "rules_count=${rules_count}"
        echo "actions_count=${actions_count}"
        rx_log_file "info" "Status: daemon=${daemon_status} agent=${agent_status} rules=${rules_count} actions=${actions_count}"
        ;;

    --agent-start)
        if ! systemctl --user is-active gnome-keyring-daemon.service &>/dev/null; then
            gnome-keyring-daemon --start --components=secrets,ssh,pkcs11 &>/dev/null &
            disown
            sleep 0.3
        fi

        bin=$(_agent_binary)
        if [[ -z $bin ]]; then
            echo "result=error|reason=no_agent_installed"
            rx_log_file "error" "No polkit auth agent installed"
            exit 1
        fi

        if _agent_running; then
            echo "OK|already_running|binary=${bin}"
            rx_log_file "info" "Auth agent already running: ${bin}"
            exit 0
        fi

        if [[ $bin == "hyprpolkitagent" ]]; then
            hyprpolkitagent &>/dev/null &
        else
            "$bin" &>/dev/null &
        fi
        disown
        sleep 0.3

        if _agent_running; then
            echo "OK|started|binary=${bin}"
            rx_log_file "success" "Auth agent and keyring daemon started"
        else
            echo "result=error|reason=start_failed|binary=${bin}"
            rx_log_file "error" "Failed to start auth agent: ${bin}"
            exit 1
        fi
        ;;

    --agent-stop)
        bin=$(_agent_binary)
        if [[ -z $bin ]]; then
            echo "result=error|reason=no_agent_installed"
            rx_log_file "error" "No polkit auth agent installed"
            exit 1
        fi

        if ! _agent_running; then
            echo "OK|already_stopped"
            rx_log_file "info" "Auth agent not running"
            exit 0
        fi

        basename=$(basename "$bin")
        pkill -x "$basename" 2>/dev/null || true
        sleep 0.2

        if _agent_running; then
            echo "result=error|reason=stop_failed|binary=${bin}"
            rx_log_file "error" "Failed to stop auth agent: ${bin}"
            exit 1
        else
            echo "OK|stopped|binary=${bin}"
            rx_log_file "success" "Auth agent stopped: ${bin}"
        fi
        ;;

    --agent-status)
        bin=$(_agent_binary)
        if [[ -z $bin ]]; then
            echo "agent_installed=false"
            echo "agent_running=false"
            echo "agent_binary="
        else
            echo "agent_installed=true"
            if _agent_running; then
                echo "agent_running=true"
            else
                echo "agent_running=false"
            fi
            echo "agent_binary=${bin}"
        fi
        ;;

    --rules-list)
        rules_dir="/etc/polkit-1/rules.d"
        if [[ ! -d $rules_dir ]]; then
            rx_log_file "info" "No custom rules directory: ${rules_dir}"
            exit 0
        fi

        files=("$rules_dir"/*.rules)
        if [[ ! -e ${files[0]} ]]; then
            rx_log_file "info" "No custom polkit rules"
            exit 0
        fi

        for rule_file in "$rules_dir"/*.rules; do
            filename=$(basename "$rule_file")
            first_line=$(head -1 "$rule_file" 2>/dev/null || true)
            echo "file=${filename}|preview=${first_line}"
        done
        rx_log_file "info" "Listed rules from ${rules_dir}"
        ;;

    --rules-show)
        rule_file="$2"
        if [[ -z $rule_file ]]; then
            echo "result=error|reason=no_file"
            exit 1
        fi
        rules_dir="/etc/polkit-1/rules.d"
        full_path="${rules_dir}/${rule_file}"
        if [[ ! -f $full_path ]]; then
            echo "result=error|reason=file_not_found|file=${rule_file}"
            exit 1
        fi
        cat "$full_path"
        ;;

    --actions-list)
        pkaction 2>/dev/null || echo ""
        ;;

    --actions-search)
        term="$2"
        if [[ -z $term ]]; then
            echo "result=error|reason=no_term"
            exit 1
        fi
        pkaction 2>/dev/null | grep -i "$term" || echo ""
        ;;

    --actions-show)
        action_id="$2"
        if [[ -z $action_id ]]; then
            echo "result=error|reason=no_action_id"
            exit 1
        fi
        pkaction -v -a "$action_id" 2>/dev/null || echo "result=error|reason=action_not_found|action=${action_id}"
        ;;

    --check)
        action_id="$2"
        if [[ -z $action_id ]]; then
            echo "result=error|reason=no_action_id"
            exit 1
        fi
        if pkcheck -a "$action_id" --enable-internal-agent 2>/dev/null; then
            echo "OK|authorized|action=${action_id}"
        else
            echo "result=unauthorized|action=${action_id}"
        fi
        ;;

    --temp-list)
        output=$(pkcheck --list-temp 2>/dev/null)
        if [[ -z $output ]]; then
            echo "result=none"
        else
            echo "$output"
        fi
        ;;

    --temp-revoke)
        if pkcheck --revoke-temp 2>/dev/null; then
            echo "OK|revoked"
            rx_log_file "info" "Temporary authorizations revoked"
        else
            echo "result=error|reason=revoke_failed"
            rx_log_file "error" "Failed to revoke temporary authorizations"
            exit 1
        fi
        ;;

    --agent-configure)
        config_file="$RETRO_DIR/config/config.json"
        if [[ -f $config_file ]]; then
            tmp=$(mktemp)
            jq '.polkit_agent_enabled = true' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
            chmod 644 "$config_file" 2>/dev/null || true
            echo "OK|configured"
            rx_log_file "success" "Polkit agent enabled in config"
        else
            echo "result=error|reason=config_not_found"
            rx_log_file "error" "Config file not found: ${config_file}"
            exit 1
        fi
        ;;

    --agent-disable)
        config_file="$RETRO_DIR/config/config.json"
        if [[ -f $config_file ]]; then
            tmp=$(mktemp)
            jq '.polkit_agent_enabled = false' "$config_file" > "$tmp" && mv "$tmp" "$config_file"
            chmod 644 "$config_file" 2>/dev/null || true
            echo "OK|disabled"
            rx_log_file "success" "Polkit agent disabled in config"
        else
            echo "result=error|reason=config_not_found"
            rx_log_file "error" "Config file not found: ${config_file}"
            exit 1
        fi
        ;;

    *)
        echo "result=error|reason=unknown_flag|flag=$1"
        echo "Usage: $0 <--status|--agent-start|--agent-stop|--agent-status|--rules-list|--rules-show|--actions-list|--actions-search|--actions-show|--check|--temp-list|--temp-revoke|--agent-configure|--agent-disable>"
        exit 1
        ;;
esac
