#!/bin/bash

source "$RETRO_DIR/lib/help.sh"

cmd_timeshift() {
    local ts_script="$RETRO_DIR/scripts/timeshift_core.sh"
    local action="${1,,}"

    case "$action" in
        "status")
            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_log "error" "Timeshift is not installed"
                return 1
            fi

            local config=$(bash "$ts_script" --config)
            local disk=$(bash "$ts_script" --disk-usage)

            IFS='|' read -r ckey device dir btrfs daily weekly monthly hourly boot count size <<<"$config"
            IFS='|' read -r dkey dev_name total used avail pct <<<"$disk"

            local snapshots=$(bash "$ts_script" --list)
            local snap_count=0
            if [[ $snapshots != "NONE" && $snapshots != "ERROR"* ]]; then
                snap_count=$(echo "$snapshots" | grep -c "^SNAPSHOT|")
            fi

            rx_table_header "󰕰" "Timeshift Status"
            rx_table_row "󰏗" "Device:" "$device" "$PINK" "20"
            rx_table_row "󰏗" "Type:" "$([ "$btrfs" == "true" ] && echo "BTRFS" || echo "RSYNC")" "$PINK" "20"
            rx_table_row "󰏗" "Snapshots:" "$snap_count" "$PINK" "20"
            rx_table_separator
            rx_table_row "󰓅" "Daily:" "$daily" "$PINK" "20"
            rx_table_row "󰓅" "Weekly:" "$weekly" "$PINK" "20"
            rx_table_row "󰓅" "Monthly:" "$monthly" "$PINK" "20"
            if [[ $dev_name != "none" && -n $total ]]; then
                rx_table_separator
                rx_table_row "󰓅" "Disk:" "$used / $total ($pct used)" "$PINK" "20"
            fi
            rx_table_separator
            rx_table_spacer
            ;;

        "list")
            local snapshots=$(bash "$ts_script" --list)

            if [[ $snapshots == "ERROR"* ]]; then
                rx_log "error" "Timeshift is not configured"
                return 1
            fi

            if [[ $snapshots == "NONE" ]]; then
                rx_table_header "󰕰" "Timeshift Snapshots"
                rx_table_simple "󰄪" "No snapshots found" "$PINK"
                rx_table_separator
                rx_table_spacer
                return 0
            fi

            if [[ $snapshots == *"AUTH_REQUIRED"* ]]; then
                local snap_count=$(echo "$snapshots" | grep "^COUNT|" | cut -d'|' -f2)
                rx_table_header "󰕰" "Timeshift Snapshots"
                rx_table_row "󰏗" "Total snapshots:" "$snap_count" "$PINK" "25"
                rx_table_row "󰓅" "Run with sudo to list:" "sudo retro timeshift list" "$GRAY" "25"
                rx_table_separator
                rx_table_spacer
                return 0
            fi

            rx_table_header "󰕰" "Timeshift Snapshots"

            while IFS= read -r line; do
                IFS='|' read -r key date tag comment <<<"$line"
                if [[ $key == "SNAPSHOT" ]]; then
                    local tag_icon="󰕰"
                    [[ $tag == "B" ]] && tag_icon="󰀧"
                    local comment_text=""
                    [[ -n $comment ]] && comment_text=" - $comment"
                    rx_table_simple "$tag_icon" "$date - $tag$comment_text" "$GRAY"
                fi
            done <<<"$snapshots"
            rx_table_separator
            rx_table_spacer
            ;;

        "create")
            local comment="$2"
            local tag="${3:-O}"

            rx_log "info" "Creating snapshot${comment:+: $comment}..."

            local result=$(bash "$ts_script" --create "$comment" "$tag")

            if [[ $result == *"CREATED"* ]]; then
                rx_log "success" "Snapshot created successfully"
            else
                rx_log "error" "Failed to create snapshot"
            fi
            ;;

        "restore")
            local snapshot="$2"
            [[ -z $snapshot ]] && rx_log "info" "Usage: retro timeshift restore <snapshot-name>" && return 1

            rx_log "warn" "This will restore snapshot: ${PINK}$snapshot${RESET}"
            rx_log "warn" "The system will reboot after restore"
            rx_yesno "Continue?" || {
                rx_log "info" "Aborted."
                return 0
            }

            bash "$ts_script" --restore "$snapshot"
            ;;

        "delete")
            local snapshot="$2"
            [[ -z $snapshot ]] && rx_log "info" "Usage: retro timeshift delete <snapshot-name>" && return 1

            rx_log "warn" "This will delete snapshot: ${PINK}$snapshot${RESET}"
            rx_yesno "Continue?" || {
                rx_log "info" "Aborted."
                return 0
            }

            local result=$(bash "$ts_script" --delete "$snapshot")

            if [[ $result == *"DELETED"* ]]; then
                rx_log "success" "Snapshot deleted"
            else
                rx_log "error" "Failed to delete snapshot"
            fi
            ;;

        "config")
            local config=$(bash "$ts_script" --config)

            if [[ $config == "ERROR"* ]]; then
                rx_log "error" "Timeshift is not configured. Run ${PINK}retro timeshift setup${RESET}"
                return 1
            fi

            IFS='|' read -r key device uuid dir daily weekly monthly hourly boot hidden level <<<"$config"

            rx_table_header "󰕰" "Timeshift Configuration"
            rx_table_row "󰏗" "Device:" "$device" "$PINK" "20"
            rx_table_row "󰏗" "UUID:" "$uuid" "$PINK" "20"
            rx_table_row "󰏗" "Directory:" "$dir" "$PINK" "20"
            rx_table_separator
            rx_table_row "󰓅" "Daily:" "$daily" "$PINK" "20"
            rx_table_row "󰓅" "Weekly:" "$weekly" "$PINK" "20"
            rx_table_row "󰓅" "Monthly:" "$monthly" "$PINK" "20"
            rx_table_row "󰓅" "Hourly:" "$hourly" "$PINK" "20"
            rx_table_row "󰓅" "Boot:" "$boot" "$PINK" "20"
            rx_table_separator
            rx_table_spacer
            ;;

        "schedule")
            local timeframe="${2,,}"
            local value="${3,,}"

            if [[ -z $timeframe ]]; then
                local config=$(bash "$ts_script" --config)
                if [[ $config == "ERROR"* ]]; then
                    rx_log "error" "Timeshift is not configured"
                    return 1
                fi

                IFS='|' read -r key device uuid dir btrfs daily weekly monthly hourly boot count size <<<"$config"

                rx_table_header "󰕰" "Backup Schedule"
                rx_table_row "󰓅" "Daily:" "$daily" "$PINK" "20"
                rx_table_row "󰓅" "Weekly:" "$weekly" "$PINK" "20"
                rx_table_row "󰓅" "Monthly:" "$monthly" "$PINK" "20"
                rx_table_row "󰓅" "Hourly:" "$hourly" "$PINK" "20"
                rx_table_row "󰓅" "Boot:" "$boot" "$PINK" "20"
                rx_table_separator
                rx_log "info" "Usage: retro timeshift schedule [daily|weekly|monthly|hourly|boot] [number|disable]"
                echo ""
                return 0
            fi

            [[ -z $value ]] && value="disable"

            local result=$(bash "$ts_script" --schedule "$timeframe" "$value")

            if [[ $result == *"SET"* ]]; then
                IFS='|' read -r status tf count <<<"$result"
                if [[ $count == "0" ]]; then
                    rx_log "success" "${PINK}${tf^}${RESET} backups disabled"
                else
                    rx_log "success" "${PINK}${tf^}${RESET} set to ${PINK}$count${RESET} snapshots"
                fi
            else
                rx_log "error" "Failed to set schedule"
            fi
            ;;

        "setup")
            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_confirm "Timeshift is not installed. Would you like to install it?" "Y" || {
                    rx_log "info" "Aborted."
                    return 0
                }

                local pkg_helper=$(bash "$RETRO_DIR/scripts/variable_core.sh" --get PKG_HELPER 2>/dev/null)
                : ${pkg_helper:="yay"}
                if command -v "$pkg_helper" >/dev/null 2>&1; then
                    $pkg_helper -S --needed --noconfirm timeshift 2>&1
                else
                    sudo pacman -S --needed --noconfirm timeshift 2>&1
                fi
                if [[ $? -eq 0 ]]; then
                    rx_log "success" "Timeshift installed successfully"
                else
                    rx_log "error" "Failed to install timeshift"
                    return 1
                fi
            fi

            local config=$(bash "$ts_script" --config)
            if [[ $config != "ERROR"* ]]; then
                rx_log "info" "Timeshift is already configured"
                rx_table_spacer
                return 0
            fi

            rx_help_header "󰕰" "Timeshift Setup"
            rx_log "info" "This will configure Timeshift for system backups"

            sudo $RETRO_DIR/cmds/tools/timeshift.sh "gui"

            rx_log "success" "Timeshift setup complete"
            ;;

        "gui")
            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_confirm "Timeshift is not installed. Would you like to install it?" "Y" || {
                    rx_log "info" "Aborted."
                    return 0
                }

                local pkg_helper=$(bash "$RETRO_DIR/scripts/variable_core.sh" --get PKG_HELPER 2>/dev/null)
                : ${pkg_helper:="yay"}
                if command -v "$pkg_helper" >/dev/null 2>&1; then
                    $pkg_helper -S --needed --noconfirm timeshift 2>&1
                else
                    sudo pacman -S --needed --noconfirm timeshift 2>&1
                fi
                if [[ $? -eq 0 ]]; then
                    rx_log "success" "Timeshift installed successfully"
                else
                    rx_log "error" "Failed to install timeshift"
                    return 1
                fi
            fi

            local result=$(bash "$ts_script" --gui)

            if [[ $result == *"OPENED"* ]]; then
                rx_log "success" "Timeshift GUI opened"
            elif [[ $result == *"ERROR:no_gui"* ]]; then
                rx_log "error" "GUI not available. Install timeshift-gtk for graphical interface"
            else
                rx_log "error" "Failed to open Timeshift GUI"
            fi
            ;;

        *)
            rx_help_usage "retro timeshift <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show backup config and snapshot count"
            rx_help_cmd "list" "List all snapshots"
            rx_help_cmd "create [comment]" "Create a new snapshot"
            rx_help_cmd "restore <snapshot>" "Restore a specific snapshot"
            rx_help_cmd "delete <snapshot>" "Delete a specific snapshot"
            rx_help_cmd "config" "Show current Timeshift configuration"
            rx_help_cmd "schedule" "Set snapshot retention counts"
            rx_help_cmd "setup" "Interactive setup wizard"
            rx_help_cmd "gui" "Open Timeshift GUI"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "timeshift" "Timeshift backup manager" "cmd_timeshift"
