#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"

cmd_system() {
    local core="$RETRO_DIR/scripts/system_core.sh"
    local action="${1,,}"
    shift 2>/dev/null

    case "$action" in
        "status")
            local raw
            raw=$(bash "$core" --status 2>/dev/null) || {
                rx_log "error" "Failed to read system configuration"
                return 1
            }

            rx_table_header "󰤄" "System Configuration"
            while IFS='|' read -r key val1 val2 val3 val4; do
                case "$key" in
                    POWER) rx_table_row "" "Power Button:"    "${val1^}" "$PINK" "28" ;;
                    LONG)  rx_table_row "" "Long Press:"      "${val1^}" "$PINK" "28" ;;
                    LID)   rx_table_row "󰋋" "Lid Close:"       "${val1^}" "$PINK" "28" ;;
                    SWAP)
                        local swap_color="$MUTE"
                        [[ ${val1:-0} -gt 0 ]] && swap_color="$PINK"
                        rx_table_row "󱋞" "Swap File:"        "${val1} Gi" "$swap_color" "28"
                        rx_table_row_gray "󱋞" "Swap Priority:"   "${val2:-10}" "28"
                        ;;
                    ZRAM)
                        rx_table_row "󰻠" "ZRAM:"              "${val1:-zstd}" "$PINK" "28"
                        rx_table_row_gray "󰻠" "ZRAM Size:"        "${val2:-0}" "28"
                        rx_table_row_gray "󰻠" "ZRAM Priority:"     "${val3:-80}" "28"
                        rx_table_row_gray "󰻠" "ZRAM Config:"       "${val4:-ram / 2}" "28"
                        ;;
                    RESUME)
                        local resume_color="$SUCCESS"
                        [[ $val1 != "ready" ]] && resume_color="$MUTE"
                        rx_table_row "󰑖" "Hibernation:"      "${val1^}" "$resume_color" "28"
                        ;;
                esac
            done <<<"$raw"
            rx_table_separator
            rx_table_spacer
            ;;

        "power")
            local val="$1"
            if [[ -z $val ]]; then
                rx_log "error" "Usage: retro system power <action>"
                rx_log "info" "Actions: ${PINK}suspend${RESET}, ${PINK}hibernate${RESET}, ${PINK}poweroff${RESET}, ${PINK}reboot${RESET}, ${PINK}ignore${RESET}, ${PINK}lock${RESET}"
                return 1
            fi
            bash "$core" --set-power "$val"
            set_var "PWR_POWER_BTN" "$val"
            rx_log "success" "Power button set to: ${PINK}${val}${RESET}"
            ;;

        "long")
            local val="$1"
            if [[ -z $val ]]; then
                rx_log "error" "Usage: retro system long <action>"
                rx_log "info" "Actions: ${PINK}suspend${RESET}, ${PINK}hibernate${RESET}, ${PINK}poweroff${RESET}, ${PINK}reboot${RESET}, ${PINK}ignore${RESET}, ${PINK}lock${RESET}"
                return 1
            fi
            bash "$core" --set-long "$val"
            set_var "PWR_POWER_BTN_LONG" "$val"
            rx_log "success" "Long press set to: ${PINK}${val}${RESET}"
            ;;

        "lid")
            local val="$1"
            if [[ -z $val ]]; then
                rx_log "error" "Usage: retro system lid <action>"
                rx_log "info" "Actions: ${PINK}suspend${RESET}, ${PINK}hibernate${RESET}, ${PINK}poweroff${RESET}, ${PINK}reboot${RESET}, ${PINK}ignore${RESET}, ${PINK}lock${RESET}"
                return 1
            fi
            bash "$core" --set-lid "$val"
            set_var "PWR_LID_CLOSE" "$val"
            rx_log "success" "Lid close set to: ${PINK}${val}${RESET}"
            ;;

        "zram")
            local size="$1"
            local priority="$2"
            if [[ -z $size ]]; then
                local raw=$(bash "$core" --status 2>/dev/null | grep "^ZRAM|")
                IFS='|' read -r _ cur_size cur_prio cur_conf <<<"$raw"
                rx_table_header "󰻠" "ZRAM Configuration"
                rx_table_row "󰻠" "Current:"     "${cur_size:-0}" "$PINK" "20"
                rx_table_row_gray "󰻠" "Priority:"    "${cur_prio:-100}" "20"
                rx_table_row_gray "󰻠" "Config:"      "${cur_conf:-ram / 2}" "20"
                rx_table_separator
                rx_log "info" "Usage: retro system zram <size> [priority]"
                rx_log "info" "Examples: ${PINK}ram / 2${RESET}, ${PINK}8G${RESET}, ${PINK}16G${RESET}"
                rx_table_spacer
                return 0
            fi
            [[ -z $priority ]] && priority="100"
            [[ $priority =~ ^[0-9]+$ ]] || { rx_log "error" "Priority must be a number"; return 1; }
            if [[ $SKIP_PROMPT != "true" ]]; then
                rx_confirm "Set ZRAM to ${PINK}${size}${RESET} with priority ${PINK}${priority}${RESET}?" "Y" || return 0
            fi
            bash "$core" --set-zram "$size" "$priority"
            set_var "SYSTEM_ZRAM_SIZE" "$size"
            set_var "SYSTEM_ZRAM_PRIO" "$priority"
            rx_log "success" "ZRAM set to ${PINK}${size}${RESET} (priority ${PINK}${priority}${RESET})"
            ;;

        "swap")
            local size="$1"
            local priority="$2"

            local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            local mem_gib=$(awk "BEGIN { printf \"%.0f\", $mem_kb / 1024 / 1024 }")
            local optimal_gib=$(( mem_gib + 3 ))

            if [[ -z $size ]]; then
                rx_log "info" "RAM: ${mem_gib} Gi  →  optimal swap: ${optimal_gib} Gi"
                if [[ $SKIP_PROMPT != "true" ]]; then
                    rx_confirm "Create ${optimal_gib} Gi swap file?" "Y" || return 0
                fi
                bash "$core" --set-swap "$optimal_gib" "${priority:-10}"
                set_var "SYSTEM_SWAP_SIZE" "$optimal_gib"
                set_var "SYSTEM_SWAP_PRIO" "${priority:-10}"
                rx_log "success" "Swap file created (${optimal_gib} Gi, priority ${priority:-10})"
                return 0
            fi

            [[ $size =~ ^[0-9]+$ ]] || { rx_log "error" "Size must be a number (GiB)"; return 1; }
            if [[ $size -lt $optimal_gib ]]; then
                rx_log "error" "Swap must be at least ${optimal_gib} Gi (${mem_gib} Gi RAM + 3 Gi)"
                return 1
            fi
            [[ -z $priority ]] && priority="10"
            [[ $priority =~ ^[0-9]+$ ]] || { rx_log "error" "Priority must be a number"; return 1; }
            if [[ $SKIP_PROMPT != "true" ]]; then
                rx_confirm "Resize swap to ${PINK}${size} Gi${RESET} (priority ${PINK}${priority}${RESET})? This drops current swap." "N" || return 0
            fi
            bash "$core" --set-swap "$size" "$priority"
            set_var "SYSTEM_SWAP_SIZE" "$size"
            set_var "SYSTEM_SWAP_PRIO" "$priority"
            rx_log "success" "Swap file set to ${PINK}${size} Gi${RESET} (priority ${PINK}${priority}${RESET})"
            ;;

        "apply")
            bash "$core" --apply
            rx_log "success" "All system settings applied"
            ;;

        *)
            rx_help_usage "retro system <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status"            "Show power/lid/zram/swap/hibernation config"
            rx_help_cmd "power <action>"    "Set power button action"
            rx_help_cmd "long <action>"     "Set long-press action (5+ seconds)"
            rx_help_cmd "lid <action>"      "Set lid close action"
            rx_help_cmd "zram [size]"       "Show or set ZRAM size (ram/2, 8G, 16G)"
            rx_help_cmd "swap [size]"       "Auto-create or set swap file size (GiB, min = RAM + 3 Gi)"
            rx_help_cmd "apply"             "Apply hibernation, ZRAM, swap, and power settings"
            rx_help_examples
            rx_help_example "retro system status"              "Show all config"
            rx_help_example "retro system lid hibernate"       "Hibernate on lid close"
            rx_help_example "retro system zram ram/2"         "Set ZRAM to half of RAM"
            rx_help_example "retro system swap"               "Auto-create swap (RAM + 3 Gi)"
            rx_help_example "retro system swap 18"             "Set swap file to 18 Gi"
            rx_help_example "retro system apply"               "Apply all pending settings"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "system" "Manage power, lid, ZRAM, swap, and hibernation" "cmd_system"
