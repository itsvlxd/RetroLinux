#!/bin/bash

list_services() {
    local filter="${1:-all}"
    local unit_type="${2:-service}"

    local services
    case "$filter" in
        running)
            services=$(systemctl list-units --type="$unit_type" --state=running 2>/dev/null | tail -n +2 | head -n -1)
            ;;
        failed)
            services=$(systemctl list-units --type="$unit_type" --state=failed 2>/dev/null | tail -n +2 | head -n -1)
            ;;
        enabled)
            services=$(systemctl list-unit-files --type="$unit_type" --state=enabled 2>/dev/null | tail -n +2)
            ;;
        all|"")
            services=$(systemctl list-units --type="$unit_type" --all --no-legend 2>/dev/null | tail -n +2 | head -n -1)
            ;;
        *)
            services=$(systemctl list-units --type="$unit_type" --no-legend 2>/dev/null | tail -n +2 | head -n -1)
            ;;
    esac

    if [[ -z "$services" ]]; then
        echo "result=none"
    else
        echo "$services" | while read -r name load active sub description; do
            [[ -z "$name" || "$name" == "●"* ]] && continue
            description=$(echo "$description" | sed 's/\x1b\[[0-9;]*m//g')
            echo "service|$name|$load|$active|$sub|$description"
        done
    fi
}

list_failed() {
    local failed=$(systemctl list-units --state=failed 2>/dev/null | tail -n +2 | head -n -1)
    
    if [[ -z "$failed" ]]; then
        echo "result=none"
    else
        local count=0
        echo "$failed" | while read -r name load active sub description; do
            [[ -z "$name" ]] && continue
            ((count++))
            echo "failed|$name|$description"
        done
        echo "count=$count"
    fi
}

list_enabled() {
    local enabled=$(systemctl list-unit-files --type=service --state=enabled 2>/dev/null | grep -v "unit files listed" | tail -n +2)
    
    if [[ -z "$enabled" ]]; then
        echo "result=none"
    else
        echo "$enabled" | while read -r name state; do
            [[ -z "$name" ]] && continue
            echo "enabled|$name|$state"
        done
    fi
}

service_status() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        echo "result=error|reason=service_name_required"
        return 1
    fi

    if [[ "$svc" != *.service && "$svc" != *.socket && "$svc" != *.target && "$svc" != *.timer && "$svc" != *.mount ]]; then
        svc="${svc}.service"
    fi

    if ! systemctl list-unit-files "$svc" 2>/dev/null | grep -q "^$svc"; then
        if ! systemctl list-units "$svc" 2>/dev/null | grep -q "^$svc"; then
            echo "result=error|reason=service_not_found|service=$svc"
            return 1
        fi
    fi

    local status=$(systemctl is-active "$svc" 2>/dev/null)
    local enabled=$(systemctl is-enabled "$svc" 2>/dev/null)
    local pid=$(systemctl show "$svc" -p MainPID --value 2>/dev/null)
    local memory=$(systemctl show "$svc" -p MemoryCurrent --value 2>/dev/null)
    local since=$(systemctl show "$svc" -p ActiveEnterTimestamp --value 2>/dev/null)

    echo "service=$svc|status=${status:-unknown}|enabled=${enabled:-unknown}|pid=$pid|memory=${memory:-N/A}|since=${since:-N/A}"
}

service_start() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        echo "result=error|reason=service_name_required"
        return 1
    fi

    if sudo systemctl start "$svc" 2>&1; then
        echo "result=success|service=$svc|action=started"
    else
        echo "result=error|reason=start_failed|service=$svc"
        return 1
    fi
}

service_stop() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        echo "result=error|reason=service_name_required"
        return 1
    fi

    if sudo systemctl stop "$svc" 2>&1; then
        echo "result=success|service=$svc|action=stopped"
    else
        echo "result=error|reason=stop_failed|service=$svc"
        return 1
    fi
}

service_restart() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        echo "result=error|reason=service_name_required"
        return 1
    fi

    if sudo systemctl restart "$svc" 2>&1; then
        echo "result=success|service=$svc|action=restarted"
    else
        echo "result=error|reason=restart_failed|service=$svc"
        return 1
    fi
}

service_enable() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        echo "result=error|reason=service_name_required"
        return 1
    fi

    if sudo systemctl enable "$svc" 2>&1; then
        echo "result=success|service=$svc|action=enabled"
    else
        echo "result=error|reason=enable_failed|service=$svc"
        return 1
    fi
}

service_disable() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        echo "result=error|reason=service_name_required"
        return 1
    fi

    if sudo systemctl disable "$svc" 2>&1; then
        echo "result=success|service=$svc|action=disabled"
    else
        echo "result=error|reason=disable_failed|service=$svc"
        return 1
    fi
}

service_logs() {
    local svc="$1"
    local lines="${2:-50}"
    
    if [[ -z "$svc" ]]; then
        echo "result=error|reason=service_name_required"
        return 1
    fi

    sudo journalctl -u "$svc" -n "$lines" --no-pager 2>/dev/null
    echo "result=logs_shown"
}

clean_failed() {
    if sudo systemctl reset-failed 2>&1; then
        echo "result=success|action=failed_state_reset"
    else
        echo "result=error|reason=reset_failed"
        return 1
    fi
}

case "$1" in
    "--list") list_services "$2" "$3" ;;
    "--list-failed") list_failed ;;
    "--list-enabled") list_enabled ;;
    "--status") service_status "$2" ;;
    "--start") service_start "$2" ;;
    "--stop") service_stop "$2" ;;
    "--restart") service_restart "$2" ;;
    "--enable") service_enable "$2" ;;
    "--disable") service_disable "$2" ;;
    "--logs") service_logs "$2" "$3" ;;
    "--clean-failed") clean_failed ;;
esac