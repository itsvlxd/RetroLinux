#!/bin/bash

rx_start_log_output() {
  local ANSI_SAVE_CURSOR="\033[s"
  local ANSI_RESTORE_CURSOR="\033[u"
  local ANSI_CLEAR_LINE="\033[2K"
  local ANSI_HIDE_CURSOR="\033[?25l"
  local ANSI_RESET="\033[0m"
  local ANSI_GRAY="\033[90m"

  printf '%s' "$ANSI_SAVE_CURSOR"
  printf '%s' "$ANSI_HIDE_CURSOR"

  (
    local log_lines=20
    local max_line_width=$((LOGO_WIDTH - 4))

    while true; do
      mapfile -t current_lines < <(tail -n $log_lines "$RETRO_INSTALL_LOG_FILE" 2>/dev/null)

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
  monitor_pid=$!
}

rx_stop_log_output() {
  if [[ -n ${monitor_pid:-} ]]; then
    kill $monitor_pid 2>/dev/null || true
    wait $monitor_pid 2>/dev/null || true
    unset monitor_pid
  fi
}

rx_start_install_log() {
  sudo touch "$RETRO_INSTALL_LOG_FILE"
  sudo chmod 666 "$RETRO_INSTALL_LOG_FILE"

  export RETRO_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

  echo "=== RetroLinux Installation Started: $RETRO_START_TIME ===" >>"$RETRO_INSTALL_LOG_FILE"
  rx_start_log_output
}

rx_stop_install_log() {
  rx_stop_log_output
  rx_show_cursor

  if [[ -n ${RETRO_INSTALL_LOG_FILE:-} ]]; then
    RETRO_END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    {
      echo "=== RetroLinux Installation Completed: $RETRO_END_TIME ==="
      echo ""
      echo "=== Installation Time Summary ==="
    } >>"$RETRO_INSTALL_LOG_FILE"

    if [[ -f "/var/log/archinstall/install.log" ]]; then
      ARCHINSTALL_START=$(grep -m1 '^\[' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)
      ARCHINSTALL_END=$(grep 'Installation completed without any errors' /var/log/archinstall/install.log 2>/dev/null | sed 's/^\[\([^]]*\)\].*/\1/' || true)

      if [[ -n $ARCHINSTALL_START ]] && [[ -n $ARCHINSTALL_END ]]; then
        ARCH_START_EPOCH=$(date -d "$ARCHINSTALL_START" +%s)
        ARCH_END_EPOCH=$(date -d "$ARCHINSTALL_END" +%s)
        ARCH_DURATION=$((ARCH_END_EPOCH - ARCH_START_EPOCH))

        ARCH_MINS=$((ARCH_DURATION / 60))
        ARCH_SECS=$((ARCH_DURATION % 60))

        echo "Archinstall: ${ARCH_MINS}m ${ARCH_SECS}s" >>"$RETRO_INSTALL_LOG_FILE"
      fi
    fi

    if [[ -n $RETRO_START_TIME ]]; then
      RETRO_START_EPOCH=$(date -d "$RETRO_START_TIME" +%s)
      RETRO_END_EPOCH=$(date -d "$RETRO_END_TIME" +%s)
      RETRO_DURATION=$((RETRO_END_EPOCH - RETRO_START_EPOCH))

      RETRO_MINS=$((RETRO_DURATION / 60))
      RETRO_SECS=$((RETRO_DURATION % 60))

      echo "RetroLinux:  ${RETRO_MINS}m ${RETRO_SECS}s" >>"$RETRO_INSTALL_LOG_FILE"

      if [[ -n $ARCH_DURATION ]]; then
        TOTAL_DURATION=$((ARCH_DURATION + RETRO_DURATION))
        TOTAL_MINS=$((TOTAL_DURATION / 60))
        TOTAL_SECS=$((TOTAL_DURATION % 60))
        echo "Total:       ${TOTAL_MINS}m ${TOTAL_SECS}s" >>"$RETRO_INSTALL_LOG_FILE"
      fi
    fi
    {
      echo "================================="
      echo "Rebooting system..."
    } >>"$RETRO_INSTALL_LOG_FILE"
  fi
}

rx_run_logged() {
  local script="$1"

  export CURRENT_SCRIPT="$script"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting: $script" >>"$RETRO_INSTALL_LOG_FILE"

  bash -c "source '$script'" </dev/null >>"$RETRO_INSTALL_LOG_FILE" 2>&1

  local exit_code=$?

  if (( exit_code == 0 )); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed: $script" >>"$RETRO_INSTALL_LOG_FILE"
    unset CURRENT_SCRIPT
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed: $script (exit code: $exit_code)" >>"$RETRO_INSTALL_LOG_FILE"
  fi

  return $exit_code
}