#!/bin/bash

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

            echo -e "\n ${PINK}󰕰 Timeshift Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            printf " ${PINK}󰏗${RESET} Device: ${PINK}%s${RESET}\n" "${device}"
            printf " ${PINK}󰏗${RESET} Type: ${PINK}%s${RESET}\n" "$([ "$btrfs" == "true" ] && echo "BTRFS" || echo "RSYNC")"
            printf " ${PINK}󰏗${RESET} Snapshots: ${PINK}%s${RESET}\n" "${snap_count}"

            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            printf " ${PINK}󰓅${RESET} Daily: ${PINK}%s${RESET}\n" "${daily}"
            printf " ${PINK}󰓅${RESET} Weekly: ${PINK}%s${RESET}\n" "${weekly}"
            printf " ${PINK}󰓅${RESET} Monthly: ${PINK}%s${RESET}\n" "${monthly}"
            if [[ $dev_name != "none" && -n $total ]]; then
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                printf " ${PINK}󰓅${RESET} Disk: ${PINK}%s${RESET} / %s (%s used)\n" "$used" "$total" "$pct"
            fi
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
            ;;

        "list")
            local snapshots=$(bash "$ts_script" --list)

            if [[ $snapshots == "ERROR"* ]]; then
                rx_log "error" "Timeshift is not configured"
                return 1
            fi

            if [[ $snapshots == "NONE" ]]; then
                echo -e "\n ${PINK}󰕰 Timeshift Snapshots${RESET}"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                printf " ${PINK}󰄪${RESET} ${PINK}No snapshots found${RESET}\n"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
                return 0
            fi

            if [[ $snapshots == *"AUTH_REQUIRED"* ]]; then
                local snap_count=$(echo "$snapshots" | grep "^COUNT|" | cut -d'|' -f2)
                echo -e "\n ${PINK}󰕰 Timeshift Snapshots${RESET}"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                printf " ${PINK}󰏗${RESET} ${PINK}Total snapshots:${RESET} %s\n" "$snap_count"
                printf " ${PINK}󰓅${RESET} ${PINK}Run with sudo to list:${RESET} sudo retro timeshift list\n"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
                return 0
            fi

            echo -e "\n ${PINK}󰕰 Timeshift Snapshots${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"

            while IFS= read -r line; do
                IFS='|' read -r key date tag comment <<<"$line"
                if [[ $key == "SNAPSHOT" ]]; then
                    local tag_icon="󰕰"
                    [[ $tag == "B" ]] && tag_icon="󰀧"
                    printf " ${PINK}${tag_icon}${RESET} ${RESET}%s${RESET}  ${GRAY}%s${RESET}" "$date" "$tag"
                    [[ -n $comment ]] && printf "  ${GRAY}%s${RESET}" "$comment"
                    printf "\n"
                fi
            done <<<"$snapshots"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
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
            rx_log "info" "Continue? ${PINK}[y/N]${RESET}: "
            read -r confirm
            [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Aborted." && return 0

            bash "$ts_script" --restore "$snapshot"
            ;;

        "delete")
            local snapshot="$2"
            [[ -z $snapshot ]] && rx_log "info" "Usage: retro timeshift delete <snapshot-name>" && return 1

            rx_log "warn" "This will delete snapshot: ${PINK}$snapshot${RESET}"
            rx_log "info" "Continue? ${PINK}[y/N]${RESET}: "
            read -r confirm
            [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Aborted." && return 0

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

            echo -e "\n ${PINK}󰕰 Timeshift Configuration${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            printf " ${PINK}󰏗${RESET} Device: ${PINK}%s${RESET}\n" "${device}"
            printf " ${PINK}󰏗${RESET} UUID: ${PINK}%s${RESET}\n" "${uuid}"
            printf " ${PINK}󰏗${RESET} Directory: ${PINK}%s${RESET}\n" "${dir}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            printf " ${PINK}󰓅${RESET} Daily: ${PINK}%s${RESET}\n" "${daily}"
            printf " ${PINK}󰓅${RESET} Weekly: ${PINK}%s${RESET}\n" "${weekly}"
            printf " ${PINK}󰓅${RESET} Monthly: ${PINK}%s${RESET}\n" "${monthly}"
            printf " ${PINK}󰓅${RESET} Hourly: ${PINK}%s${RESET}\n" "${hourly}"
            printf " ${PINK}󰓅${RESET} Boot: ${PINK}%s${RESET}\n" "${boot}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
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

                echo -e "\n ${PINK}󰕰 Backup Schedule${RESET}"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                printf " ${PINK}󰓅${RESET} Daily: ${PINK}%s${RESET}\n" "${daily}"
                printf " ${PINK}󰓅${RESET} Weekly: ${PINK}%s${RESET}\n" "${weekly}"
                printf " ${PINK}󰓅${RESET} Monthly: ${PINK}%s${RESET}\n" "${monthly}"
                printf " ${PINK}󰓅${RESET} Hourly: ${PINK}%s${RESET}\n" "${hourly}"
                printf " ${PINK}󰓅${RESET} Boot: ${PINK}%s${RESET}\n" "${boot}"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
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
                rx_log "info" "Timeshift is not installed. Would you like to install it? ${PINK}[y/N]${RESET}: "
                read -r confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
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
                else
                    rx_log "info" "Aborted."
                    return 0
                fi
            fi

            local config=$(bash "$ts_script" --config)
            if [[ $config != "ERROR"* ]]; then
                rx_log "info" "Timeshift is already configured"
                return 0
            fi

            echo -e "\n ${PINK}󰕰 Timeshift Setup${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            rx_log "info" "This will configure Timeshift for system backups"
            echo ""

            rx_log "info" "Select backup schedule: [daily/weekly/monthly/disabled] "
            read -r schedule
            : ${schedule:="daily"}

            rx_log "info" "Setting up ${PINK}$schedule${RESET} schedule..."
            bash "$ts_script" --schedule "$schedule"

            rx_log "success" "Timeshift setup complete"
            echo ""
            ;;

        "gui")
            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_log "info" "Timeshift is not installed. Would you like to install it? ${PINK}[y/N]${RESET}: "
                read -r confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
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
                else
                    rx_log "info" "Aborted."
                    return 0
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
            rx_log "info" "Usage: retro timeshift <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show backup config and snapshot count"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list" "List all snapshots"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "create [comment]" "Create a new snapshot"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "restore <snapshot>" "Restore a specific snapshot"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "delete <snapshot>" "Delete a specific snapshot"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "config" "Show current Timeshift configuration"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "schedule" "Set snapshot retention counts"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "setup" "Interactive setup wizard"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "gui" "Open Timeshift GUI"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "timeshift" "Timeshift backup manager" "cmd_timeshift"
