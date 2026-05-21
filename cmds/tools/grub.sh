#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/scripts/grub_core.sh"

cmd_grub() {
    local driver_script="$RETRO_DIR/scripts/driver_core.sh"
    local action="${1,,}"
    shift
    local setup_args=("$@")
    local pending_file="/tmp/retro_grub_pending"

    _grub_add_pending() {
        local key="$1"
        local val="$2"
        local tmp_file="${pending_file}.tmp"
        if [[ -f $pending_file ]]; then
            grep -v "^${key}=" "$pending_file" > "$tmp_file" 2>/dev/null || true
            mv "$tmp_file" "$pending_file"
        fi
        echo "${key}=${val}" >> "$pending_file"
    }

    _grub_show_pending() {
        if [[ -f $pending_file ]]; then
            local changes=""
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                if [[ -n $changes ]]; then
                    changes="${changes}, ${line}"
                else
                    changes="$line"
                fi
            done < "$pending_file"
            if [[ -n $changes ]]; then
                rx_log "warn" "Pending changes: ${changes}"
            fi
        fi
    }

    case "$action" in
        "status")
            local grub_defaults="/etc/default/grub"
            
            if [[ ! -f $grub_defaults ]]; then
                rx_log "error" "GRUB configuration not found at $grub_defaults"
                return 1
            fi

            local timeout=$(grep "^GRUB_TIMEOUT=" "$grub_defaults" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
            local gfxmode=$(grep "^GRUB_GFXMODE=" "$grub_defaults" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
            local theme=$(grep "^GRUB_THEME=" "$grub_defaults" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
            local os_prober=$(grep "^GRUB_DISABLE_OS_PROBER=" "$grub_defaults" 2>/dev/null | cut -d'=' -f2)
            local cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_defaults" 2>/dev/null | cut -d'=' -f2- | tr -d '"')
            local distributor=$(grep "^GRUB_DISTRIBUTOR=" "$grub_defaults" 2>/dev/null | cut -d'=' -f2 | tr -d '"')

            : ${timeout:="10"}
            : ${gfxmode:="auto"}
            : ${theme:="none"}
            : ${os_prober:="true"}
            : ${cmdline:="quiet splash"}
            : ${distributor:="RetroLinux"}

            local theme_name="none"
            if [[ $theme =~ /themes/([^/]+)/theme\.txt ]]; then
                theme_name="${BASH_REMATCH[1]}"
            fi

            local snapshot_status="Inactive"
            local snapshot_color="$MUTE"
            if systemctl is-active --quiet grub-btrfsd 2>/dev/null; then
                snapshot_status="Active"
                snapshot_color="$PINK"
            fi

            local os_prober_status="Disabled"
            local os_prober_color="$MUTE"
            if [[ $os_prober == "false" ]]; then
                os_prober_status="Disabled"
                os_prober_color="$PINK"
            else
                os_prober_status="Enabled"
                os_prober_color="$PINK"
            fi

            local hw_info=""
            local cpu_vendor=""
            local gpu_vendor=""
            
            if [[ -f /proc/cpuinfo ]]; then
                cpu_vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | awk -F': ' '{print $2}')
                case "$cpu_vendor" in
                    *Intel*) cpu_vendor="Intel" ;;
                    *AMD*) cpu_vendor="AMD" ;;
                    *) cpu_vendor="Unknown" ;;
                esac
            fi

            local gpu_model=$(bash "$driver_script" --gpu-status 2>/dev/null | grep "^ACTIVE|" | cut -d'|' -f2)
            if [[ -n $gpu_model ]]; then
                IFS='|' read -r g_vendor g_model g_driver <<<"$gpu_model"
                gpu_vendor="${g_vendor^}"
                hw_info="${cpu_vendor} CPU + ${gpu_vendor} GPU (${g_model})"
            else
                hw_info="${cpu_vendor} CPU (GPU not detected)"
            fi

            rx_table_header "󰂕" "GRUB Configuration Status"
            rx_table_row "󰂱" "Detected Hardware:" "$hw_info" "$PINK" "20"
            rx_table_row "󰈔" "Boot Cmdline:" "$cmdline" "$PINK" "20"
            rx_table_row "󰓅" "Boot Timeout:" "${timeout}s" "$PINK" "20"
            rx_table_row "󰉋" "Snapshot Daemon:" "$snapshot_status" "$snapshot_color" "20"
            rx_table_row "󰍹" "OS Prober:" "$os_prober_status" "$os_prober_color" "20"
            rx_table_row "󰈐" "Resolution:" "$gfxmode" "$PINK" "20"
            rx_table_row "󰀻" "Theme:" "${theme_name^}" "$PINK" "20"
            rx_table_row "󰆍" "Distributor:" "$distributor" "$PINK" "20"
            rx_table_separator
            rx_table_spacer
            ;;

        "theme")
            if [[ -z "$1" ]]; then
                rx_log "error" "Please provide a theme name"

                rx_table_header "󰀻" "Available GRUB Themes"

                local theme_dir="$RETRO_DIR/modules/grub/files"
                for t in "$theme_dir"/*/; do
                    [[ -d "$t" ]] || continue
                    local tname=$(basename "$t")
                    local tpath="/boot/grub/themes/$tname"
                    local installed="No"
                    local status_color="$MUTE"
                    if [[ -d "$tpath" ]]; then
                        installed="Installed"
                        status_color="$PINK"
                    fi
                    rx_table_row "󰂕" "${tname^}" "$installed" "$status_color" "14"
                done

                rx_table_separator
                rx_table_spacer
                return 1
            fi

            local theme_name="$1"
            
            if [[ ! -d "$RETRO_DIR/modules/grub/files/$theme_name" ]]; then
                rx_log "error" "Theme '$theme_name' not found in GRUB module"

                rx_table_header "󰀻" "Available GRUB Themes"

                local theme_dir="$RETRO_DIR/modules/grub/files"
                for t in "$theme_dir"/*/; do
                    [[ -d "$t" ]] || continue
                    local tname=$(basename "$t")
                    local tpath="/boot/grub/themes/$tname"
                    local installed="No"
                    local status_color="$MUTE"
                    if [[ -d "$tpath" ]]; then
                        installed="Installed"
                        status_color="$PINK"
                    fi
                    rx_table_row "󰂕" "${tname^}" "$installed" "$status_color" "14"
                done

                rx_table_separator
                rx_table_spacer
                return 1
            fi

            set_var "GRUB_THEME_CHOICE" "$theme_name"
            rx_log "success" "GRUB theme set to: ${PINK}${theme_name^}${RESET}"
            _grub_add_pending "theme" "$theme_name"
            _grub_show_pending
            ;;

        "resolution")
            local res="$1"
            
            if [[ -z "$res" ]]; then
                rx_log "error" "Please provide a resolution (e.g., 1920x1080)"
                return 1
            fi

            if [[ ! $res =~ ^[0-9]+x[0-9]+$ ]]; then
                rx_log "error" "Invalid resolution format. Use WxH (e.g., 1920x1080)"
                return 1
            fi

            set_var "BOOT_VIDEO_GRUB" "$res"
            rx_log "success" "GRUB resolution set to: ${PINK}${res}${RESET}"
            _grub_add_pending "resolution" "$res"
            _grub_show_pending
            ;;

        "timeout")
            local secs="$1"
            
            if [[ -z "$secs" ]]; then
                rx_log "error" "Please provide a timeout in seconds"
                return 1
            fi

            if [[ ! $secs =~ ^[0-9]+$ ]]; then
                rx_log "error" "Timeout must be a number"
                return 1
            fi

            set_var "GRUB_TIMEOUT" "$secs"
            rx_log "success" "GRUB timeout set to: ${PINK}${secs}s${RESET}"
            _grub_add_pending "timeout" "$secs"
            _grub_show_pending
            ;;

        "os-prober")
            local mode="$1"
            
            if [[ -z "$mode" ]]; then
                rx_log "error" "Please specify on or off"
                return 1
            fi

            local new_val="true"

            case "$mode" in
                on|true|enable) new_val="true" ;;
                off|false|disable) new_val="false" ;;
                *) rx_log "error" "Invalid mode. Use: on, off, true, false, enable, disable" && return 1 ;;
            esac

            set_var "GRUB_OS_PROBER" "$new_val"
            local status_text="ENABLED"
            [[ $new_val == "false" ]] && status_text="DISABLED"
            rx_log "success" "OS prober ${status_text}"
            _grub_add_pending "os-prober" "$new_val"
            _grub_show_pending
            ;;

        "snapshots")
            local mode="$1"
            
            if [[ -z "$mode" ]]; then
                rx_log "error" "Please specify on or off"
                return 1
            fi

            local new_val="true"

            case "$mode" in
                on|true|enable) new_val="true" ;;
                off|false|disable) new_val="false" ;;
                *) rx_log "error" "Invalid mode. Use: on, off, true, false, enable, disable" && return 1 ;;
            esac

            set_var "GRUB_SNAPSHOTS_ENABLED" "$new_val"
            
            if [[ $new_val == "true" ]]; then
                sudo systemctl enable --now grub-btrfsd 2>/dev/null
                rx_log "success" "Snapshot boot ${PINK}ENABLED${RESET} (grub-btrfsd started)"
            else
                sudo systemctl disable --now grub-btrfsd 2>/dev/null
                rx_log "success" "Snapshot boot ${MUTE}DISABLED${RESET} (grub-btrfsd stopped)"
            fi

            _grub_add_pending "snapshots" "$new_val"
            _grub_show_pending
            ;;

        "apply")
            if [[ -f $pending_file ]]; then
                rx_log "info" "Applying GRUB configuration:"
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    local key="${line%%=*}"
                    local val="${line#*=}"
                    case "$key" in
                        theme) rx_log "info" "Theme: ${PINK}${val^}${RESET}" ;;
                        resolution) rx_log "info" "Resolution: ${PINK}${val}${RESET}" ;;
                        timeout) rx_log "info" "Timeout: ${PINK}${val}s${RESET}" ;;
                        os-prober)
                            local status="false"
                            [[ $val == "true" ]] && status="true"
                            rx_log "info" "OS Prober: ${PINK}${status}${RESET}"
                            ;;
                        snapshots)
                            local status="false"
                            [[ $val == "true" ]] && status="true"
                            rx_log "info" "Snapshots: ${PINK}${status}${RESET}"
                            ;;
                        *) rx_log "info" "${key}: ${PINK}${val}${RESET}" ;;
                    esac
                done < "$pending_file"
            else
                rx_log "info" "Applying GRUB configuration..."
            fi

            update_grub_config
            regenerate_grub

            if [[ -f $pending_file ]]; then
                rm -f "$pending_file"
            fi
            ;;

        "setup")
            local interactive=true
            local opts=""

            for arg in "${setup_args[@]}"; do
                case "$arg" in
                    -o|--options)
                        interactive=false
                        ;;
                    *)
                        if [[ $interactive == false ]]; then
                            opts="$arg"
                        fi
                        ;;
                esac
            done

            if [[ $interactive == false && -n $opts ]]; then
                IFS=',' read -ra pairs <<<"$opts"
                for pair in "${pairs[@]}"; do
                    local key="${pair%%=*}"
                    local val="${pair#*=}"
                    
                    case "$key" in
                        theme) set_var "GRUB_THEME_CHOICE" "$val" ;;
                        resolution) set_var "BOOT_VIDEO_GRUB" "$val" ;;
                        timeout) set_var "GRUB_TIMEOUT" "$val" ;;
                        os-prober|os_prober)
                            [[ $val == "true" || $val == "on" ]] && val="true" || val="false"
                            set_var "GRUB_OS_PROBER" "$val"
                            ;;
                        snapshots)
                            [[ $val == "true" || $val == "on" ]] && val="true" || val="false"
                            set_var "GRUB_SNAPSHOTS_ENABLED" "$val"
                            ;;
                    esac
                done

                rx_log "info" "GRUB configured (non-interactive mode)"
                update_grub_config
                regenerate_grub
                if [[ -f $pending_file ]]; then
                    rm -f "$pending_file"
                fi
                return $?
            fi

            source "$RETRO_DIR/cmds/system/setup/grub.sh"
            setup_grub
            ;;

        *)
            rx_help_usage "retro grub <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show current GRUB configuration"
            rx_help_cmd "theme <name>" "Set GRUB theme (retropunk, retrolinux)"
            rx_help_cmd "resolution <WxH>" "Set GRUB resolution (e.g., 1920x1080)"
            rx_help_cmd "timeout <seconds>" "Set boot timeout"
            rx_help_cmd "os-prober <on|off>" "Enable/disable OS prober"
            rx_help_cmd "snapshots <on|off>" "Enable/disable grub-btrfs snapshots"
            rx_help_cmd "apply" "Regenerate GRUB configuration"
            rx_help_cmd "setup" "Run GRUB setup wizard"
            rx_help_examples
            rx_help_example "retro grub status" "Show current GRUB config"
            rx_help_example "retro grub theme retrolinux" "Switch to retrolinux theme"
            rx_help_example "retro grub resolution 2560x1440" "Set 1440p resolution"
            rx_help_example "retro grub os-prober on" "Enable dual-boot detection"
            rx_help_example "retro grub snapshots off" "Disable snapshot boot"
            rx_help_example "retro grub setup -o theme=retropunk,resolution=1920x1080" "Non-interactive setup"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "grub" "GRUB bootloader configuration and management" "cmd_grub"
