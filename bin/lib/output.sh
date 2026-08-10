#!/bin/bash

rx_start_log_output() {
    local log_file="${1:-$RETRO_INSTALL_LOG_FILE}"
    local log_lines="${2:-25}"

    local ANSI_SAVE_CURSOR="\033[s"
    local ANSI_RESTORE_CURSOR="\033[u"
    local ANSI_CLEAR_LINE="\033[2K"
    local ANSI_HIDE_CURSOR="\033[?25l"
    local ANSI_RESET="\033[0m"
    local ANSI_GRAY="\033[2m"

    printf '%s' "$ANSI_SAVE_CURSOR"
    printf '%s' "$ANSI_HIDE_CURSOR"

    (
        local max_line_width=$((LOGO_WIDTH - 4))

        while true; do
            mapfile -t current_lines < <(tail -n $log_lines "$log_file" 2>/dev/null)

            output=""
            for ((i = 0; i < log_lines; i++)); do
                line="${current_lines[i]:-}"

                if (( ${#line} > max_line_width )); then
                    line="${line:0:$max_line_width}..."
                fi

                if [[ -n $line ]]; then
                    output+="${ANSI_CLEAR_LINE}${ANSI_GRAY}${PADDING_LEFT_SPACES}  → ${line}${ANSI_RESET}\n"
                else
                    output+="${ANSI_CLEAR_LINE}${PADDING_LEFT_SPACES}\n"
                fi
            done

            printf "${ANSI_RESTORE_CURSOR}%b" "$output"

            sleep 0.1
        done
    ) &
    RX_LOG_MONITOR_PID=$!
}

rx_stop_log_output() {
    if [[ -n ${RX_LOG_MONITOR_PID:-} ]]; then
        kill $RX_LOG_MONITOR_PID 2>/dev/null || true
        wait $RX_LOG_MONITOR_PID 2>/dev/null || true
        unset RX_LOG_MONITOR_PID
    fi
}

rx_start_install_log() {
    sudo touch "$RETRO_INSTALL_LOG_FILE"
    sudo chmod 666 "$RETRO_INSTALL_LOG_FILE"

    export RETRO_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    echo "=== RetroLinux Installation Started: $RETRO_START_TIME ===" >>"$RETRO_INSTALL_LOG_FILE"
}

rx_stop_install_log() {
    rx_stop_log_output
    rx_show_cursor

    if [[ -n ${RETRO_INSTALL_LOG_FILE:-} ]]; then
        RETRO_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
        {
            echo ""
            echo "=== Installation Time Summary ==="
        } >>"$RETRO_INSTALL_LOG_FILE"

        if [[ -n $RETRO_START_TIME ]]; then
            RETRO_START_EPOCH=$(date -d "$RETRO_START_TIME" +%s)
            RETRO_END_EPOCH=$(date -d "$RETRO_END_TIME" +%s)
            RETRO_DURATION=$((RETRO_END_EPOCH - RETRO_START_EPOCH))

            RETRO_MINS=$((RETRO_DURATION / 60))
            RETRO_SECS=$((RETRO_DURATION % 60))

            echo "Total: ${RETRO_MINS}m ${RETRO_SECS}s" >>"$RETRO_INSTALL_LOG_FILE"
        fi
    fi
}

start_log_output() {
    rx_start_log_output "$@"
}

stop_log_output() {
    rx_stop_log_output
}