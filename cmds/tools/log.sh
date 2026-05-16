#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/scripts/log_core.sh"

cmd_log_status() {
    local entries=()
    _rx_log_scan_files entries

    if [[ ${#entries[@]} -eq 0 ]]; then
        rx_table_header "" "No logs found"
        rx_log "info" "Logs are created when core scripts are executed."
        rx_table_spacer
        return
    fi

    local active=0
    local disabled=0
    local total_lines=0

    for entry in "${entries[@]}"; do
        IFS='|' read -r id lines _ _ _ <<<"$entry"
        total_lines=$((total_lines + lines))
        if rx_log_is_disabled "$id"; then
            disabled=$((disabled + 1))
        else
            active=$((active + 1))
        fi
    done

    rx_table_header "" "System Logs"
    rx_table_row "" "Total Sources:" "${#entries[@]}" "$PINK" "18"
    rx_table_row "󰓅" "Active:" "$active" "$SUCCESS" "18"
    rx_table_row "" "Disabled:" "$disabled" "$ERROR" "18"
    rx_table_row "󰓅" "Total Entries:" "$total_lines" "$PINK" "18"
    rx_table_separator
    rx_table_spacer
}

cmd_log_list() {
    local entries=()
    _rx_log_scan_files entries

    if [[ ${#entries[@]} -eq 0 ]]; then
        rx_table_header "" "No logs found"
        rx_table_spacer
        return
    fi

    rx_table_header "" "Log Sources"

    for entry in "${entries[@]}"; do
        IFS='|' read -r id lines size modified last <<<"$entry"

        local ago=""
        if [[ $modified -gt 0 ]]; then
            local now
            now=$(date +%s)
            local diff=$((now - modified))
            if ((diff < 60)); then
                ago="${diff}s ago"
            elif ((diff < 3600)); then
                ago="$((diff / 60))m ago"
            elif ((diff < 86400)); then
                ago="$((diff / 3600))h ago"
            else
                ago="$((diff / 86400))d ago"
            fi
        fi

        local status_color="$SUCCESS"
        local status_text="ON"
        if rx_log_is_disabled "$id"; then
            status_color="$ERROR"
            status_text="OFF"
        fi

        local color="$GRAY"
        [[ $lines -gt 0 ]] && color="$PINK"

        rx_table_row "" "$id" "$status_text  $lines lines  Last: $ago" "$color" "18"
    done

    rx_table_separator
    rx_table_spacer
}

cmd_log_view() {
    local id="$1"
    local limit="${2:-30}"

    if [[ -z $id ]]; then
        rx_log "error" "Log identifier required"
        rx_log "info" "Usage: retro log <identifier> [lines]"
        return 1
    fi

    local log_file="$RETRO_LOG_DIR/${id}.log"
    if [[ ! -f $log_file ]]; then
        rx_log "error" "No log found for: $id"
        return 1
    fi

    local total
    total=$(wc -l <"$log_file" 2>/dev/null || echo 0)

    rx_table_header "" "$id Logs ($total total, showing last $limit)"

    while IFS= read -r line; do
        local level
        level=$(echo "$line" | grep -oP '\] \[\K[^\]]+' | head -1)

        local color="$RESET"
        case "$level" in
            ERROR) color="$ERROR" ;;
            WARN) color="$WARN" ;;
            SUCCESS) color="$SUCCESS" ;;
            INFO) color="$PINK" ;;
        esac

        printf " ${color}%s${RESET}\n" "$line"
    done < <(tail -n "$limit" "$log_file")

    rx_table_separator
    rx_table_spacer
}

cmd_log_open() {
    local id="$1"

    if [[ -z $id ]]; then
        rx_log "error" "Log identifier required"
        rx_log "info" "Usage: retro log open <identifier>"
        return 1
    fi

    local log_file="$RETRO_LOG_DIR/${id}.log"
    if [[ ! -f $log_file ]]; then
        rx_log "error" "No log found for: $id"
        return 1
    fi

    rx_log "info" "Streaming ${PINK}$id${RESET} log (Ctrl+C to stop)..."
    tail -f "$log_file"
}

cmd_log_clear() {
    local id="$1"

    if [[ $id == "all" ]]; then
        local entries=()
        _rx_log_scan_files entries
        local count=0
        for entry in "${entries[@]}"; do
            IFS='|' read -r eid _ _ _ _ <<<"$entry"
            rx_log_clear "$eid"
            count=$((count + 1))
        done
        rx_log "success" "Cleared $count log(s)"
        return
    fi

    if [[ -z $id ]]; then
        rx_log "error" "Log identifier required"
        rx_log "info" "Usage: retro log clear <identifier>"
        return 1
    fi

    if rx_log_clear "$id"; then
        rx_log "success" "Log cleared: $id"
    else
        rx_log "error" "No log found for: $id"
        return 1
    fi
}

cmd_log_enable() {
    local id="$1"

    if [[ $id == "all" ]]; then
        local entries=()
        _rx_log_scan_files entries
        local count=0
        for entry in "${entries[@]}"; do
            IFS='|' read -r eid _ _ _ _ <<<"$entry"
            rx_log_enable "$eid"
            count=$((count + 1))
        done
        rx_log "success" "Enabled $count log(s)"
        return
    fi

    if [[ -z $id ]]; then
        rx_log "error" "Log identifier required"
        rx_log "info" "Usage: retro log enable <identifier>"
        return 1
    fi

    local log_file="$RETRO_LOG_DIR/${id}.log"
    if [[ ! -f $log_file ]]; then
        rx_log "error" "No log found for: $id"
        return 1
    fi

    rx_log_enable "$id"
    rx_log "success" "Log enabled: $id"
}

cmd_log_disable() {
    local id="$1"

    if [[ $id == "all" ]]; then
        local entries=()
        _rx_log_scan_files entries
        local count=0
        for entry in "${entries[@]}"; do
            IFS='|' read -r eid _ _ _ _ <<<"$entry"
            rx_log_disable "$eid"
            count=$((count + 1))
        done
        rx_log "success" "Disabled $count log(s)"
        return
    fi

    if [[ -z $id ]]; then
        rx_log "error" "Log identifier required"
        rx_log "info" "Usage: retro log disable <identifier>"
        return 1
    fi

    local log_file="$RETRO_LOG_DIR/${id}.log"
    if [[ ! -f $log_file ]]; then
        rx_log "error" "No log found for: $id"
        return 1
    fi

    rx_log_disable "$id"
    rx_log "warn" "Log disabled: $id"
}

cmd_log_help() {
    rx_help_usage "retro log <command>"
    rx_help_commands "Commands"
    rx_help_cmd "status" "Show status of all registered logs"
    rx_help_cmd "list" "List all registered log sources"
    rx_help_cmd "<name> [lines]" "View last N lines of a log (default: 30)"
    rx_help_cmd "open <name>" "Stream log in real-time (tail -f)"
    rx_help_cmd "enable <name|all>" "Enable logging for a source or all"
    rx_help_cmd "disable <name|all>" "Disable logging for a source or all"
    rx_help_cmd "clear <name|all>" "Clear a log file or all"
    rx_help_examples
    rx_help_example "retro log status" "Show all logs"
    rx_help_example "retro log power" "View power log"
    rx_help_example "retro log open power" "Stream power log live"
    rx_help_example "retro log disable power" "Stop logging power events"
    rx_help_example "retro log disable all" "Stop logging all sources"
    rx_help_example "retro log enable power" "Resume logging power events"
    rx_help_example "retro log enable all" "Resume logging all sources"
    rx_help_example "retro log clear power" "Clear power log"
    rx_help_example "retro log clear all" "Clear all logs"
    rx_help_spacer
}

cmd_log() {
    case "${1:-}" in
        "status") cmd_log_status ;;
        "list") cmd_log_list ;;
        "clear") cmd_log_clear "$2" ;;
        "open") cmd_log_open "$2" ;;
        "enable") cmd_log_enable "$2" ;;
        "disable") cmd_log_disable "$2" ;;
        "help") cmd_log_help ;;
        "") cmd_log_help ;;
        *) cmd_log_view "$1" "$2" ;;
    esac
}

register_command "Tools" "log" "View and manage system logs" "cmd_log"
