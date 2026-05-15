#!/bin/bash

RETRO_LOG_DIR="/tmp/retro_logs"
mkdir -p "$RETRO_LOG_DIR"

declare -A _RX_LOG_REGISTERED

rx_log_register() {
    local id="$1"
    [[ -z $id ]] && return 1
    _RX_LOG_REGISTERED["$id"]=1
    local log_file="$RETRO_LOG_DIR/${id}.log"
    [[ ! -f $log_file ]] && touch "$log_file"
}

rx_log() {
    local level="${1^^}"
    local message="$2"
    local icon=""
    local color=""

    case "${level}" in
        "INFO")
            icon=" "
            color="$PINK"
            ;;
        "SUCCESS")
            icon=" "
            color="$SUCCESS"
            ;;
        "WARN")
            icon=" "
            color="$WARN"
            ;;
        "ERROR")
            icon="󰅙 "
            color="$ERROR"
            ;;
        *)
            icon="󰀦 "
            color="$RESET"
            ;;
    esac

    local stripped_msg
    stripped_msg="$(echo "$message" | sed 's/'$'\033''\[[0-9;]*m//g')"

    local is_prompt=false
    if [[ $stripped_msg =~ \[[[:space:]]*[Yy]/[Nn][[:space:]]*\]:[[:space:]]* ]] ||
        [[ $stripped_msg =~ \[[[:space:]]*[Yy]/[Nn][[:space:]]*\]$ ]] ||
        [[ $stripped_msg =~ \[Default: ]]; then
        is_prompt=true
    fi

    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    if [[ $is_prompt == true ]]; then
        printf "${color}[${icon}${level}]${RESET} ${message}"
    else
        printf "${color}[${icon}${level}]${RESET} ${message}\n"
    fi

    local clean_msg
    clean_msg="$(echo "$message" | sed 's/'$'\033''\[[0-9;]*m//g')"

    for id in "${!_RX_LOG_REGISTERED[@]}"; do
        local log_file="$RETRO_LOG_DIR/${id}.log"
        local disabled_file="$RETRO_LOG_DIR/${id}.disabled"
        if [[ -f $log_file && ! -f $disabled_file ]]; then
            echo "[$ts] [$level] $clean_msg" >>"$log_file"
            _rx_log_rotate "$log_file"
        fi
    done
}

_rx_log_rotate() {
    local log_file="$1"
    local max_lines="${RX_LOG_MAX_LINES:-500}"
    local line_count
    line_count=$(wc -l <"$log_file" 2>/dev/null || echo 0)

    if ((line_count > max_lines)); then
        local tmp_file="${log_file}.tmp"
        tail -n "$max_lines" "$log_file" >"$tmp_file"
        mv "$tmp_file" "$log_file"
    fi
}

_rx_log_scan_files() {
    local -n _result=$1
    _result=()

    for log_file in "$RETRO_LOG_DIR"/*.log; do
        [[ -f $log_file ]] || continue
        local id
        id=$(basename "$log_file" .log)
        local lines
        lines=$(wc -l <"$log_file" 2>/dev/null || echo 0)
        local size
        size=$(du -h "$log_file" 2>/dev/null | cut -f1)
        local last
        last=$(tail -1 "$log_file" 2>/dev/null || echo "")
        local modified
        modified=$(stat -c %Y "$log_file" 2>/dev/null || echo 0)
        _result+=("$id|$lines|${size:-0}|$modified|$last")
    done
}

rx_log_list() {
    local entries=()
    _rx_log_scan_files entries

    if [[ ${#entries[@]} -eq 0 ]]; then
        echo "No logs registered."
        return
    fi

    for entry in "${entries[@]}"; do
        IFS='|' read -r id lines size _ last <<<"$entry"
        echo "$id ($lines lines)"
    done
}

rx_log_status() {
    local entries=()
    _rx_log_scan_files entries

    if [[ ${#entries[@]} -eq 0 ]]; then
        echo "none"
        return
    fi

    local now
    now=$(date +%s)

    for entry in "${entries[@]}"; do
        IFS='|' read -r id lines size modified last <<<"$entry"
        local ago=""
        if [[ $modified -gt 0 ]]; then
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
        echo "$id|$lines|${size:-0}|$ago|$last"
    done
}

rx_log_tail() {
    local id="$1"
    local limit="${2:-30}"
    local log_file="$RETRO_LOG_DIR/${id}.log"

    if [[ ! -f $log_file ]]; then
        echo "No log found for: $id"
        return 1
    fi

    tail -n "$limit" "$log_file"
}

rx_log_clear() {
    local id="$1"
    local log_file="$RETRO_LOG_DIR/${id}.log"

    if [[ -f $log_file ]]; then
        >"$log_file"
        return 0
    fi
    return 1
}

rx_log_disable() {
    local id="$1"
    local disabled_file="$RETRO_LOG_DIR/${id}.disabled"
    touch "$disabled_file"
}

rx_log_enable() {
    local id="$1"
    local disabled_file="$RETRO_LOG_DIR/${id}.disabled"
    [[ -f $disabled_file ]] && rm -f "$disabled_file"
}

rx_log_is_disabled() {
    local id="$1"
    local disabled_file="$RETRO_LOG_DIR/${id}.disabled"
    [[ -f $disabled_file ]]
}
