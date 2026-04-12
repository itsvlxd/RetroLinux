#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"

cmd_cleanup() {
    local cleanup_core="$RETRO_DIR/scripts/cleanup_core.sh"
    local action="$1"
    local arg1="$2"
    local arg2="$3"

    if [[ -z "$action" ]]; then
        action="help"
    fi

    action="${action,,}"

    case "$action" in
        status|healthy|health)
            local status_output
            status_output=$(bash "$cleanup_core" --status)
            [[ -z $status_output ]] && rx_log "error" "Failed to get cleanup status" && return 1

            local disk_root="" disk_home="" mem="" boot="" logs="" cache="" pacman_cache=""
            while IFS='=' read -r key val; do
                case "$key" in
                    "disk_root") disk_root="$val" ;;
                    "disk_home") disk_home="$val" ;;
                    "mem") mem="$val" ;;
                    "boot") boot="$val" ;;
                    "logs") logs="$val" ;;
                    "cache") cache="$val" ;;
                    "pacman_cache") pacman_cache="$val" ;;
                esac
            done <<<"$status_output"

            rx_table_header "󰟩" "System Health"
            rx_table_row "󰉈" "Root Disk:" "$disk_root" "$PINK" "14"
            rx_table_row "󰉖" "Home Disk:" "$disk_home" "$GRAY" "14"
            rx_table_row "󰍾" "Memory:" "$mem" "$GRAY" "14"
            rx_table_separator
            rx_table_row "󰌪" "Boot:" "$boot" "$GRAY" "14"
            rx_table_row "󰌢" "Logs:" "$logs" "$GRAY" "14"
            rx_table_row "󰉖" "Cache:" "$cache" "$GRAY" "14"
            rx_table_row "󰆼" "Pacman:" "$pacman_cache" "$GRAY" "14"
            rx_table_separator
            rx_table_spacer
            ;;

        clean|clean-all)
            rx_log "info" "Running full cleanup..."

            local cache_result
            cache_result=$(bash "$cleanup_core" --clean-caches)
            local cache_before=$(echo "$cache_result" | grep -oP 'before=\K[^|]+' || echo "N/A")

            local thumb_result
            thumb_result=$(bash "$cleanup_core" --clean-thumbnails)

            local log_result
            log_result=$(bash "$cleanup_core" --clean-logs "$arg1")

            rx_table_header "󰟩" "Cleanup Results"
            rx_table_row "󰉖" "Cache cleaned:" "$cache_before" "$SUCCESS" "14"
            rx_table_row "󰉖" "Thumbnails cleaned" "$SUCCESS" "$GRAY" "14"
            rx_table_row "󰌢" "Logs cleaned:" "$SUCCESS" "$GRAY" "14"
            rx_table_separator
            rx_log "success" "Full cleanup completed."
            rx_table_spacer
            ;;

        cache|caches)
            local result
            result=$(bash "$cleanup_core" --clean-caches)
            local before=$(echo "$result" | grep -oP 'before=\K[^|]+' || echo "N/A")
            local res=$(echo "$result" | grep -oP 'result=\K[^|]+' || echo "failed")

            if [[ "$res" == "success" ]]; then
                rx_log "success" "User cache cleaned (was ${before})"
            else
                rx_log "error" "Failed to clean cache"
            fi
            ;;

        thumbnails|thumbs)
            local result
            result=$(bash "$cleanup_core" --clean-thumbnails)
            local res=$(echo "$result" | grep -oP 'result=\K[^|]+' || echo "none")

            if [[ "$res" == "success" ]]; then
                rx_log "success" "Thumbnails cleaned."
            else
                rx_log "warn" "No thumbnails found to clean."
            fi
            ;;

        logs)
            local result
            result=$(bash "$cleanup_core" --clean-logs "$arg1")
            local before=$(echo "$result" | grep -oP 'before=\K[^|]+' || echo "N/A")
            local after=$(echo "$result" | grep -oP 'after=\K[^|]+' || echo "N/A")
            local res=$(echo "$result" | grep -oP 'result=\K[^|]+' || echo "failed")

            if [[ "$res" == "success" ]]; then
                rx_log "success" "Logs cleaned (${before} → ${after})"
            else
                rx_log "error" "Failed to clean logs"
            fi
            ;;

        pacman)
            if [[ "$EUID" -ne 0 ]]; then
                rx_log "warn" "Pacman cleanup requires root privileges"
                rx_log "info" "Run with sudo or as root"
                return 1
            fi
            local result
            result=$(bash "$cleanup_core" --clean-pacman)
            local before=$(echo "$result" | grep -oP 'before=\K[^|]+' || echo "N/A")
            local after=$(echo "$result" | grep -oP 'after=\K[^|]+' || echo "0B")
            local res=$(echo "$result" | grep -oP 'result=\K[^|]+' || echo "failed")

            if [[ "$res" == "success" ]]; then
                rx_log "success" "Pacman cache cleaned (${before} → ${after})"
            else
                rx_log "error" "Failed to clean pacman cache"
            fi
            ;;

        orphans)
            if [[ "$EUID" -ne 0 ]]; then
                rx_log "warn" "Orphan removal requires root privileges"
                rx_log "info" "Run with sudo or as root"
                return 1
            fi
            local result
            result=$(bash "$cleanup_core" --clean-orphans)
            local res=$(echo "$result" | grep -oP 'result=\K[^|]+' || echo "none")
            local count=$(echo "$result" | grep -oP 'count=\K[^|]+' || echo "0")

            if [[ "$res" == "removed" ]]; then
                rx_log "success" "Removed ${count} orphan packages."
            elif [[ "$count" == "0" ]]; then
                rx_log "info" "No orphans found."
            else
                rx_log "error" "Failed to remove orphans"
            fi
            ;;

        temp)
            local result
            result=$(bash "$cleanup_core" --clean-temp)
            local res=$(echo "$result" | grep -oP 'result=\K[^|]+' || echo "failed")

            if [[ "$res" == "success" ]]; then
                rx_log "success" "Old temp files cleaned."
            else
                rx_log "error" "Failed to clean temp files"
            fi
            ;;

        *)
            rx_help_usage "retro cleanup <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show system health overview"
            rx_help_cmd "clean" "Run full cleanup"
            rx_help_cmd "cache" "Clean user cache"
            rx_help_cmd "thumbs" "Clean thumbnails"
            rx_help_cmd "logs [days]" "Clean journal logs"
            rx_help_cmd "pacman" "Clean pkg cache (root)"
            rx_help_cmd "orphans" "Remove orphans (root)"
            rx_help_cmd "temp" "Clean old temp files"
            rx_help_examples
            rx_help_example "retro cleanup status" "Show disk/memory usage"
            rx_help_example "retro cleanup clean" "Run all cleanup tasks"
            rx_help_example "retro cleanup cache" "Clear user cache"
            rx_help_example "retro cleanup logs 3" "Keep last 3 days of logs"
            rx_help_example "sudo retro cleanup pacman" "Clear pacman pkg cache"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "cleanup" "Clean caches, logs, and maintain system health" "cmd_cleanup"
