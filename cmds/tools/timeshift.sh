#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/menu.sh"
source "$RETRO_DIR/scripts/timeshift_core.sh"

cmd_timeshift() {
    local ts_script="$RETRO_DIR/scripts/timeshift_core.sh"
    local action="${1,,}"
    shift 2>/dev/null || true
    local setup_args=("$@")

    case "$action" in
        "status")
            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_log "error" "Timeshift is not installed"
                return 1
            fi

            local config=$(bash "$ts_script" --config)
            if [[ $config == "ERROR"* ]]; then
                rx_table_header "󰕰" "Timeshift Status"
                rx_table_row "󰓅" "State:" "Not configured" "$WARN" "20"
                rx_table_row "󱗼" "Run setup:" "retro timeshift setup" "$GRAY" "20"
                rx_table_separator
                rx_table_spacer
                return 0
            fi

            local disk=$(bash "$ts_script" --disk-usage)
            local snapshots=$(bash "$ts_script" --list 2>/dev/null)
            local snap_count=0
            if [[ $snapshots != "NONE" && $snapshots != "ERROR"* ]]; then
                snap_count=$(echo "$snapshots" | grep -c "^SNAPSHOT|" 2>/dev/null)
            fi

            IFS='|' read -r ckey device uuid parent btrfs daily weekly monthly hourly boot hidden snap_count_raw snap_size <<<"$config"
            IFS='|' read -r dkey dev_name total used avail pct <<<"$disk"

            local snap_label="$snap_count"
            [[ -z $snap_count || $snap_count == "0" ]] && snap_label="${snap_count}" || true

            rx_table_header "󰕰" "Timeshift Status"
            rx_table_row "󰏗" "State:" "Configured" "$SUCCESS" "20"
            rx_table_row "󰏗" "Device:" "$device" "$PINK" "20"
            rx_table_row "󰏗" "Type:" "$([ "$btrfs" == "true" ] && echo "BTRFS" || echo "RSYNC")" "$PINK" "20"
            rx_table_row "󰕰" "Snapshots:" "$snap_count" "$PINK" "20"
            rx_table_separator
            rx_table_row "󰓅" "Daily:" "$daily" "$PINK" "20"
            rx_table_row "󰓅" "Weekly:" "$weekly" "$PINK" "20"
            rx_table_row "󰓅" "Monthly:" "$monthly" "$PINK" "20"
            rx_table_row "󰓅" "Hourly:" "$hourly" "$PINK" "20"
            rx_table_row "󰀧" "Boot:" "$boot" "$PINK" "20"
            if [[ $dev_name != "none" && -n $total ]]; then
                rx_table_separator
                rx_table_row "󰓅" "Disk:" "$used / $total ($pct)" "$PINK" "20"
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
            local comment="$1"
            local tag="O"

            rx_log "info" "Creating snapshot${comment:+: $comment}..."

            local result=$(bash "$ts_script" --create "$comment" "$tag")

            if [[ $result == *"CREATED"* ]]; then
                rx_log "success" "Snapshot created successfully"
            else
                rx_log "error" "Failed to create snapshot"
            fi
            ;;

        "restore")
            local snapshot="$1"
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
            local snapshot="$1"
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
            local config=$(bash "$ts_script" --config 2>/dev/null || echo "ERROR")

            if [[ $config == "ERROR"* ]]; then
                rx_log "error" "Timeshift is not configured. Run ${PINK}retro timeshift setup${RESET}"
                return 1
            fi

            IFS='|' read -r key device uuid parent btrfs daily weekly monthly hourly boot snap_count snap_size <<<"$config"

            rx_table_header "󰕰" "Timeshift Configuration"
            rx_table_row "󰏗" "Device:" "$device" "$PINK" "20"
            rx_table_row "󰏗" "UUID:" "$uuid" "$PINK" "20"
            rx_table_row "󰏗" "Type:" "$([ "$btrfs" == "true" ] && echo "BTRFS" || echo "RSYNC")" "$PINK" "20"
            rx_table_separator
            rx_table_row "󰓅" "Daily:" "$daily" "$PINK" "20"
            rx_table_row "󰓅" "Weekly:" "$weekly" "$PINK" "20"
            rx_table_row "󰓅" "Monthly:" "$monthly" "$PINK" "20"
            rx_table_row "󰓅" "Hourly:" "$hourly" "$PINK" "20"
            rx_table_row "󰀧" "Boot:" "$boot" "$PINK" "20"
            rx_table_separator
            rx_table_spacer
            ;;

        "schedule")
            local timeframe="${1,,}"
            local value="${2,,}"

            if [[ -z $timeframe ]]; then
                local config=$(bash "$ts_script" --config 2>/dev/null || echo "ERROR")
                if [[ $config == "ERROR"* ]]; then
                    rx_log "error" "Timeshift is not configured"
                    return 1
                fi

                IFS='|' read -r key device uuid parent btrfs daily weekly monthly hourly boot snap_count snap_size <<<"$config"

                rx_table_header "󰕰" "Backup Schedule"
                rx_table_row "󰓅" "Daily:" "$daily" "$PINK" "20"
                rx_table_row "󰓅" "Weekly:" "$weekly" "$PINK" "20"
                rx_table_row "󰓅" "Monthly:" "$monthly" "$PINK" "20"
                rx_table_row "󰓅" "Hourly:" "$hourly" "$PINK" "20"
                rx_table_row "󰀧" "Boot:" "$boot" "$PINK" "20"
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
            local non_interactive=false
            local options=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -o|--options) non_interactive=true; options="$2"; [[ -n $2 ]] && shift 2 || shift ;;
                    *) shift ;;
                esac
            done

            if [[ $non_interactive == true && -z $options ]]; then
                rx_log "error" "Empty options. Valid keys: device, btrfs, daily, weekly, monthly, boot, boot_count, exclude_home"
                return 1
            fi

            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_confirm "Timeshift is not installed. Would you like to install it?" "Y" || {
                    rx_log "info" "Aborted."
                    return 0
                }

                local pkg_helper=$(get_var "PKG_HELPER" "yay")
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

            local device_choice=""
            local btrfs_mode="true"
            local daily_count="5"
            local weekly_count="3"
            local monthly_count="2"
            local boot_enabled="true"
            local boot_count="2"
            local exclude_home="false"

            if [[ -n $options ]]; then
                IFS=',' read -ra opts_array <<<"$options"
                for pair in "${opts_array[@]}"; do
                    local key="${pair%%=*}"
                    local val="${pair#*=}"
                    case "$key" in
                        device) device_choice="$val" ;;
                        btrfs) btrfs_mode="$val" ;;
                        daily) daily_count="$val" ;;
                        weekly) weekly_count="$val" ;;
                        monthly) monthly_count="$val" ;;
                        boot) boot_enabled="$val" ;;
                        boot_count) boot_count="$val" ;;
                        exclude_home) exclude_home="$val" ;;
                        *) rx_log "warn" "Unknown key: ${PINK}$key${RESET} (valid: device, btrfs, daily, weekly, monthly, boot, boot_count, exclude_home)" ;;
                    esac
                done
            else
                local config=$(bash "$ts_script" --config 2>/dev/null || echo "ERROR")
                if [[ $config != "ERROR"* ]]; then
                    IFS='|' read -r ckey cur_device cur_uuid cur_parent cur_btrfs cur_daily cur_weekly cur_monthly cur_hourly cur_boot cur_snap_count cur_snap_size <<<"$config"

                    rx_table_header "󰕰" "Current Timeshift Configuration"
                    rx_table_row "󰏗" "Device:" "$cur_device" "$PINK" "20"
                    rx_table_row "󰏗" "Type:" "$([ "$cur_btrfs" == "true" ] && echo "BTRFS" || echo "RSYNC")" "$PINK" "20"
                    rx_table_row "󰓅" "Daily:" "$cur_daily" "$PINK" "20"
                    rx_table_row "󰓅" "Weekly:" "$cur_weekly" "$PINK" "20"
                    rx_table_row "󰓅" "Monthly:" "$cur_monthly" "$PINK" "20"
                    rx_table_row "󰀧" "Boot:" "$cur_boot" "$PINK" "20"
                    rx_table_separator
                    rx_table_spacer

                    if ! rx_confirm "Reconfigure Timeshift?" "N"; then
                        rx_log "info" "Aborted."
                        return 0
                    fi
                fi

                rx_table_header "󰕰" "Timeshift Setup"

                local devices=()
                local device_labels=()
                while IFS= read -r line; do
                    IFS='|' read -r key dev size fstype mount <<<"$line"
                    [[ -z $dev || $key != "DEVICE" ]] && continue
                    devices+=("$dev")
                    device_labels+=("$dev (${size}, ${fstype:-unknown})")
                done < <(bash "$ts_script" --list-devices 2>/dev/null)

                if [[ ${#devices[@]} -eq 0 ]]; then
                    rx_log "error" "No writable devices found"
                    rx_table_separator
                    rx_table_spacer
                    return 1
                fi

                local selected_device=$(rx_menu "󰏗" "Select backup device:" "${device_labels[@]}")
                device_choice="$selected_device"

                local fstype=""
                for i in "${!device_labels[@]}"; do
                    if [[ "${device_labels[$i]}" == "$selected_device" ]]; then
                        fstype=$(bash "$ts_script" --list-devices 2>/dev/null | grep "DEVICE|${devices[$i]}|" | cut -d'|' -f4)
                        break
                    fi
                done

                if [[ $fstype == "btrfs" ]]; then
                    btrfs_mode="true"
                    local type_label="BTRFS (recommended)"
                else
                    btrfs_mode="false"
                    local type_label="RSYNC"
                fi
                rx_log "info" "Backup type: ${PINK}${type_label}${RESET}"

                rx_table_separator
                rx_table_spacer

                echo ""
                echo -ne " ${PINK}󰄾${RESET} Daily snapshots ${MUTE}[default: 5, 0=off]${RESET}: "
                read -r input; [[ -n $input && $input =~ ^[0-9]+$ ]] && daily_count="$input"

                echo -ne " ${PINK}󰄾${RESET} Weekly snapshots ${MUTE}[default: 3, 0=off]${RESET}: "
                read -r input; [[ -n $input && $input =~ ^[0-9]+$ ]] && weekly_count="$input"

                echo -ne " ${PINK}󰄾${RESET} Monthly snapshots ${MUTE}[default: 2, 0=off]${RESET}: "
                read -r input; [[ -n $input && $input =~ ^[0-9]+$ ]] && monthly_count="$input"

                if rx_confirm "Enable boot snapshots (before package updates)?" "Y"; then
                    boot_enabled="true"
                    echo -ne " ${PINK}󰄾${RESET} Boot snapshots to keep ${MUTE}[default: 2]${RESET}: "
                    read -r input; [[ -n $input && $input =~ ^[0-9]+$ ]] && boot_count="$input"
                else
                    boot_enabled="false"
                fi

                if [[ $btrfs_mode == "true" ]]; then
                    rx_confirm "Exclude /home from backups?" "N" && exclude_home="true" || exclude_home="false"
                fi

                local daily_label="$([ $daily_count -gt 0 ] && echo "$daily_count" || echo "off")"
                local weekly_label="$([ $weekly_count -gt 0 ] && echo "$weekly_count" || echo "off")"
                local monthly_label="$([ $monthly_count -gt 0 ] && echo "$monthly_count" || echo "off")"
                local boot_label="$([ $boot_enabled == "true" ] && echo "$boot_count boot snaps" || echo "off")"

                rx_table_header "󰕰" "Setup Summary"
                rx_table_row "󰏗" "Device:" "$device_choice" "$PINK" "20"
                rx_table_row "󰏗" "Type:" "$([ "$btrfs_mode" == "true" ] && echo "BTRFS" || echo "RSYNC")" "$PINK" "20"
                rx_table_separator
                rx_table_row "󰓅" "Daily:" "$daily_label" "$PINK" "20"
                rx_table_row "󰓅" "Weekly:" "$weekly_label" "$PINK" "20"
                rx_table_row "󰓅" "Monthly:" "$monthly_label" "$PINK" "20"
                rx_table_row "󰀧" "Boot:" "$boot_label" "$PINK" "20"
                rx_table_row "󰉋" "Exclude Home:" "$exclude_home" "$PINK" "20"
                rx_table_separator
                rx_table_spacer

                if ! rx_confirm "Apply this configuration?" "N"; then
                    rx_log "info" "Setup cancelled."
                    return 0
                fi
            fi

            local opts="device=${device_choice},btrfs=${btrfs_mode},daily=${daily_count},weekly=${weekly_count},monthly=${monthly_count},boot=${boot_enabled},boot_count=${boot_count},exclude_home=${exclude_home}"
            local result=$(sudo bash "$ts_script" --apply-setup "$opts" 2>&1)

            if echo "$result" | grep -q "^OK|"; then
                rx_table_header "󱗼" "Timeshift Configured"
                rx_table_row "󰏗" "Device:" "$device_choice" "$SUCCESS" "20"
                rx_table_row "󰏗" "Type:" "$([ "$btrfs_mode" == "true" ] && echo "BTRFS" || echo "RSYNC")" "$SUCCESS" "20"
                rx_table_row "󰓅" "Daily:" "$daily_count" "$SUCCESS" "20"
                rx_table_row "󰓅" "Weekly:" "$weekly_count" "$SUCCESS" "20"
                rx_table_row "󰓅" "Monthly:" "$monthly_count" "$SUCCESS" "20"
                rx_table_row "󰀧" "Boot:" "$boot_count" "$SUCCESS" "20"
                rx_table_separator
                rx_table_spacer

                rx_log "success" "Timeshift setup complete"
            else
                rx_log "error" "Failed to apply Timeshift configuration: $result"
                return 1
            fi
            ;;

        "gui")
            local check=$(bash "$ts_script" --check)
            if [[ $check == "ERROR"* ]]; then
                rx_confirm "Timeshift is not installed. Would you like to install it?" "Y" || {
                    rx_log "info" "Aborted."
                    return 0
                }

                local pkg_helper=$(get_var "PKG_HELPER" "yay")
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
            rx_help_cmd "status" "Show backup config and snapshot count" "40"
            rx_help_cmd "list" "List all snapshots" "40"
            rx_help_cmd "create [comment]" "Create a new snapshot" "40"
            rx_help_cmd "restore <snapshot>" "Restore a specific snapshot" "40"
            rx_help_cmd "delete <snapshot>" "Delete a specific snapshot" "40"
            rx_help_cmd "config" "Show current Timeshift configuration" "40"
            rx_help_cmd "schedule [timeframe] [count|disable]" "Show or set snapshot retention schedule" "40"
            rx_help_cmd "setup [-o key=val,...]" "Interactive or scripted setup wizard" "40"
            rx_help_cmd "gui" "Open Timeshift graphical interface" "40"
            rx_help_examples
            rx_help_example "retro timeshift status" "Show current config and snapshot count" "40"
            rx_help_example "retro timeshift list" "List all snapshots" "40"
            rx_help_example "retro timeshift create 'Before update'" "Create a snapshot with comment" "40"
            rx_help_example "retro timeshift schedule daily 5" "Keep 5 daily snapshots" "40"
            rx_help_example "retro timeshift schedule weekly disable" "Turn off weekly backups" "40"
            rx_help_example "retro timeshift setup" "Interactive setup wizard" "40"
            rx_help_example "retro timeshift setup -o device=/dev/sda1,daily=5,weekly=3,monthly=2,boot=true" "Non-interactive setup" "40"
            rx_help_example "retro timeshift gui" "Open GUI for manual management" "40"
            rx_help_spacer
            ;;
    esac
}

if command -v timeshift &>/dev/null; then
    register_command "TOOLS" "timeshift" "Timeshift backup manager — snapshots, scheduling, and setup" "cmd_timeshift"
fi
