#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

list_services() {
    local filter="${1:-all}"
    local unit_type="${2:-service}"

    echo -e "\n ${PINK}󰒑  System Services${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

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
            services=$(systemctl list-units --type="$unit_type" --all 2>/dev/null | tail -n +2 | head -n -1)
            ;;
        *)
            services=$(systemctl list-units --type="$unit_type" 2>/dev/null | tail -n +2 | head -n -1)
            ;;
    esac

    if [[ -z "$services" ]]; then
        echo -e " ${GRAY}No services found${RESET}"
    else
        echo "$services" | while read -r name load active sub description; do
            [[ -z "$name" ]] && continue
            
            local load_color="$GRAY"
            local active_color="$GRAY"
            local sub_color="$MUTE"
            
            case "$load" in
                loaded) load_color="$SUCCESS" ;;
                not-loaded|error) load_color="$ERROR" ;;
            esac
            
            case "$active" in
                active|running) active_color="$SUCCESS" ;;
                inactive|dead) active_color="$MUTE" ;;
                failed) active_color="$ERROR" ;;
                activating|deactivating) active_color="$WARN" ;;
            esac
            
            case "$sub" in
                running) sub_color="$SUCCESS" ;;
                exited) sub_color="$SUCCESS" ;;
                waiting) sub_color="$WARN" ;;
                dead) sub_color="$MUTE" ;;
                failed) sub_color="$ERROR" ;;
            esac
            
            printf " ${PINK}󰒑${RESET} ${PINK}%-30s${RESET} ${active_color}%-12s${RESET} ${sub_color}%s${RESET}\n" "$name" "$active" "$sub"
        done
    fi

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

list_failed() {
    echo -e "\n ${PINK}󰚥  Failed Services${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    local failed=$(systemctl list-units --state=failed 2>/dev/null | tail -n +2 | head -n -1)
    
    if [[ -z "$failed" ]]; then
        echo -e " ${SUCCESS}No failed services${RESET}"
    else
        local count=0
        echo "$failed" | while read -r name load active sub description; do
            [[ -z "$name" ]] && continue
            ((count++))
            printf " ${PINK}󰅗${RESET} ${ERROR}%-30s${RESET} ${GRAY}%s${RESET}\n" "$name" "$description"
        done
        echo -e " ${ERROR}Total: $count failed services${RESET}"
    fi

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

list_enabled() {
    echo -e "\n ${PINK}󰒑  Enabled Services (Boot)${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    local enabled=$(systemctl list-unit-files --type=service --state=enabled 2>/dev/null | grep -v "unit files listed" | tail -n +2)
    
    if [[ -z "$enabled" ]]; then
        echo -e " ${GRAY}No enabled services${RESET}"
    else
        echo "$enabled" | while read -r name state; do
            [[ -z "$name" ]] && continue
            printf " ${PINK}󰒑${RESET} ${PINK}%-35s${RESET} ${SUCCESS}%s${RESET}\n" "$name" "$state"
        done
    fi

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

service_status() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        rx_log "error" "Service name required"
        return 1
    fi

    if [[ "$svc" != *.service && "$svc" != *.socket && "$svc" != *.target && "$svc" != *.timer && "$svc" != *.mount ]]; then
        svc="${svc}.service"
    fi

    if ! systemctl list-unit-files "$svc" 2>/dev/null | grep -q "^$svc"; then
        if ! systemctl list-units "$svc" 2>/dev/null | grep -q "^$svc"; then
            rx_log "error" "Service ${PINK}$svc${RESET} not found"
            return 1
        fi
    fi

    echo -e "\n ${PINK}󰒑  Service: $svc${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    local status=$(systemctl is-active "$svc" 2>/dev/null)
    local enabled=$(systemctl is-enabled "$svc" 2>/dev/null)
    local pid=$(systemctl show "$svc" -p MainPID --value 2>/dev/null)
    
    local status_color="$MUTE"
    case "$status" in
        active|running) status_color="$SUCCESS" ;;
        failed) status_color="$ERROR" ;;
        inactive|dead) status_color="$MUTE" ;;
    esac
    
    local enabled_color="$MUTE"
    case "$enabled" in
        enabled) enabled_color="$SUCCESS" ;;
        enabled-runtime) enabled_color="$WARN" ;;
        masked) enabled_color="$ERROR" ;;
    esac

    printf " ${PINK}󰈐${RESET} %-20s ${status_color}%s${RESET}\n" "Status:" "${status:-unknown}"
    printf " ${PINK}󰒑${RESET} %-20s ${enabled_color}%s${RESET}\n" "Enabled:" "${enabled:-unknown}"
    
    if [[ "$pid" -gt 0 && "$pid" != "0" ]]; then
        printf " ${PINK}󰃺${RESET} %-20s ${GRAY}%s${RESET}\n" "PID:" "$pid"
    fi

    local memory=$(systemctl show "$svc" -p MemoryCurrent --value 2>/dev/null)
    if [[ -n "$memory" && "$memory" != "[not set]" && "$memory" != "18446744073709551615" ]]; then
        local mem_mb=$((memory / 1024 / 1024))
        printf " ${PINK}󰠮${RESET} %-20s ${GRAY}%s MB${RESET}\n" "Memory:" "$mem_mb"
    fi

    local since=$(systemctl show "$svc" -p ActiveEnterTimestamp --value 2>/dev/null)
    if [[ -n "$since" && "$since" != "[not set]" ]]; then
        printf " ${PINK}󰶐${RESET} %-20s ${GRAY}%s${RESET}\n" "Since:" "$since"
    fi

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

service_start() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        rx_log "error" "Service name required"
        return 1
    fi

    rx_log "info" "Starting ${PINK}$svc${RESET}..."
    
    if sudo systemctl start "$svc" 2>&1; then
        rx_log "success" "Service ${PINK}$svc${RESET} started"
    else
        rx_log "error" "Failed to start ${PINK}$svc${RESET}"
        return 1
    fi
}

service_stop() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        rx_log "error" "Service name required"
        return 1
    fi

    rx_log "info" "Stopping ${PINK}$svc${RESET}..."
    
    if sudo systemctl stop "$svc" 2>&1; then
        rx_log "success" "Service ${PINK}$svc${RESET} stopped"
    else
        rx_log "error" "Failed to stop ${PINK}$svc${RESET}"
        return 1
    fi
}

service_restart() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        rx_log "error" "Service name required"
        return 1
    fi

    rx_log "info" "Restarting ${PINK}$svc${RESET}..."
    
    if sudo systemctl restart "$svc" 2>&1; then
        rx_log "success" "Service ${PINK}$svc${RESET} restarted"
    else
        rx_log "error" "Failed to restart ${PINK}$svc${RESET}"
        return 1
    fi
}

service_enable() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        rx_log "error" "Service name required"
        return 1
    fi

    rx_log "info" "Enabling ${PINK}$svc${RESET} at boot..."
    
    if sudo systemctl enable "$svc" 2>&1; then
        rx_log "success" "Service ${PINK}$svc${RESET} enabled"
    else
        rx_log "error" "Failed to enable ${PINK}$svc${RESET}"
        return 1
    fi
}

service_disable() {
    local svc="$1"
    
    if [[ -z "$svc" ]]; then
        rx_log "error" "Service name required"
        return 1
    fi

    rx_log "info" "Disabling ${PINK}$svc${RESET} at boot..."
    
    if sudo systemctl disable "$svc" 2>&1; then
        rx_log "success" "Service ${PINK}$svc${RESET} disabled"
    else
        rx_log "error" "Failed to disable ${PINK}$svc${RESET}"
        return 1
    fi
}

service_logs() {
    local svc="$1"
    local lines="${2:-50}"
    
    if [[ -z "$svc" ]]; then
        rx_log "error" "Service name required"
        rx_log "info" "Usage: service logs <name> [lines]"
        return 1
    fi

    rx_log "info" "Showing logs for ${PINK}$svc${RESET}..."
    echo ""
    sudo journalctl -u "$svc" -n "$lines" --no-pager 2>/dev/null
    echo ""
}

clean_failed() {
    rx_log "info" "Resetting failed state..."
    
    sudo systemctl reset-failed 2>&1
    rx_log "success" "Failed state reset"
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
