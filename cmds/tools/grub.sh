#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/menu.sh"
source "$RETRO_DIR/lib/setup.sh"
source "$RETRO_DIR/scripts/grub_core.sh"

cmd_grub() {
    local driver_script="$RETRO_DIR/scripts/driver_core.sh"
    local action="${1,,}"
    shift
    local pending_file="/tmp/retro_grub_pending"

    _grub_add_pending() {
        local key="$1"
        local val="$2"
        local tmp_file="${pending_file}.tmp"
        if [[ -f $pending_file ]]; then
            grep -v "^${key}=" "$pending_file" >"$tmp_file" 2>/dev/null || true
            mv "$tmp_file" "$pending_file"
        fi
        echo "${key}=${val}" >>"$pending_file"
    }

    _grub_show_pending() {
        if [[ -f $pending_file ]]; then
            local changes=""
            while IFS= read -r line; do
                [[ -z $line ]] && continue
                if [[ -n $changes ]]; then
                    changes="${changes}, ${line}"
                else
                    changes="$line"
                fi
            done <"$pending_file"
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

            local current_kernel=$(uname -r)
            local current_pkg=""
            case "$current_kernel" in
                *zen*) current_pkg="linux-zen" ;;
                *lts*) current_pkg="linux-lts" ;;
                *hardened*) current_pkg="linux-hardened" ;;
                *) current_pkg="linux" ;;
            esac

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
                os_prober_status="Enabled"
                os_prober_color="$PINK"
            else
                os_prober_status="Disabled"
                os_prober_color="$MUTE"
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

            local gpu_model=$(bash "$driver_script" --gpu-status 2>/dev/null | grep "^ACTIVE|" | cut -d'|' -f2-)
            if [[ -n $gpu_model ]]; then
                IFS='|' read -r g_vendor g_model g_driver <<<"$gpu_model"
                gpu_vendor="${g_vendor^}"
                hw_info="${cpu_vendor} CPU + ${gpu_vendor} GPU (${g_model})"
            else
                hw_info="${cpu_vendor} CPU (GPU not detected)"
            fi

            local configured_kernel=$(get_var "GRUB_KERNEL" "linux")
            local kernel_display="${current_kernel} (${current_pkg})"
            if [[ $configured_kernel != "$current_pkg" ]]; then
                kernel_display="${kernel_display} → ${configured_kernel}"
            fi

            rx_table_header "󰂕" "GRUB Configuration Status"
            rx_table_row "󰂱" "Detected Hardware:" "$hw_info" "$PINK" "32"
            rx_table_row "󰏗" "Kernel:" "$kernel_display" "$PINK" "32"
            rx_table_row "󰈔" "Boot Cmdline:" "$cmdline" "$PINK" "32"
            rx_table_row "󰓅" "Boot Timeout:" "${timeout}s" "$PINK" "32"
            rx_table_row "󰉋" "Snapshot Daemon:" "$snapshot_status" "$snapshot_color" "32"
            rx_table_row "󰍹" "OS Prober:" "$os_prober_status" "$os_prober_color" "32"
            rx_table_row "󰈐" "Resolution:" "$gfxmode" "$PINK" "32"
            rx_table_row "󰀻" "Theme:" "${theme_name^}" "$PINK" "32"
            rx_table_row "󰆍" "Distributor:" "$distributor" "$PINK" "32"
            rx_table_separator

                local grub_cfg="/boot/grub/grub.cfg"
            if [[ -f $grub_cfg ]]; then
                local entries=()
                local entry_details=()
                local in_submenu=false
                local submenu_name=""
                local submenu_depth=0
                local indent="  "
                local next_is_vmlinuz=false
                local first_entry_kernel=""

                while IFS= read -r line; do
                    if [[ $line =~ ^[[:space:]]*submenu[[:space:]]+\'([^\']+)\' ]]; then
                        submenu_name="${BASH_REMATCH[1]}"
                        in_submenu=true
                        submenu_depth=0
                        entries+=("${submenu_name}")
                        entry_details+=("Submenu")
                        next_is_vmlinuz=false
                    elif [[ $line =~ ^[[:space:]]*menuentry[[:space:]]+\'([^\']+)\' ]]; then
                        local entry_name="${BASH_REMATCH[1]}"
                        local detail=""

                        if [[ $entry_name =~ ([0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*) ]]; then
                            detail="${BASH_REMATCH[1]}"
                        elif [[ $entry_name =~ (shutdown|restart|poweroff|reboot) ]]; then
                            detail="${BASH_REMATCH[1]^}"
                        elif [[ $entry_name =~ (snapshot|timeshift|btrfs) ]]; then
                            detail="Snapshots"
                        elif [[ $entry_name =~ (UEFI|firmware) ]]; then
                            detail="UEFI"
                        fi

                        if [[ $entry_name =~ (recovery|fallback|rescue) ]]; then
                            detail="${detail} (Recovery)"
                        fi

                        if [[ $in_submenu == true ]]; then
                            entries+=("${indent}${entry_name}")
                        else
                            entries+=("${entry_name}")
                            next_is_vmlinuz=true
                        fi
                        entry_details+=("${detail:---}")
                    elif [[ $line =~ ^[[:space:]]*menuentry[[:space:]]+\"([^\"]+)\" ]]; then
                        local entry_name="${BASH_REMATCH[1]}"
                        local detail=""

                        if [[ $entry_name =~ [Mm]emtest ]]; then
                            detail="Memtest86+"
                        elif [[ $entry_name =~ [Ww]indows ]]; then
                            detail="Windows"
                        elif [[ $entry_name =~ (UEFI|firmware) ]]; then
                            detail="UEFI"
                        fi

                        if [[ $in_submenu == true ]]; then
                            entries+=("${indent}${entry_name}")
                        else
                            entries+=("${entry_name}")
                        fi
                        entry_details+=("${detail:---}")
                    elif [[ $next_is_vmlinuz == true && -z $first_entry_kernel && $line =~ /vmlinuz-([^[:space:]]+) ]]; then
                        first_entry_kernel="${BASH_REMATCH[1]}"
                        next_is_vmlinuz=false
                    fi

                    if [[ $in_submenu == true ]]; then
                        local open_b=$(echo "$line" | tr -cd '{' | wc -c)
                        local close_b=$(echo "$line" | tr -cd '}' | wc -c)
                        submenu_depth=$((submenu_depth + open_b - close_b))
                        if [[ $submenu_depth -le 0 ]]; then
                            in_submenu=false
                            submenu_name=""
                        fi
                    fi
                done <"$grub_cfg"

                if [[ -n $first_entry_kernel ]]; then
                    entry_details[0]="$first_entry_kernel"
                fi

                for i in "${!entries[@]}"; do
                    local entry="${entries[$i]}"
                    local detail="${entry_details[$i]}"
                    local icon="󰓅"
                    local color="$PINK"
                    if [[ $entry == "${indent}"* ]]; then
                        icon="󰓅"
                        color="$GRAY"
                    fi
                    printf " ${PINK}${icon}${RESET} %-32s ${GRAY}%s${RESET}\n" "$entry" "$detail"
                done
                rx_table_separator
            fi
            rx_table_spacer
            ;;

        "theme")
            if [[ -z $1 ]]; then
                rx_log "error" "Please provide a theme name"

                rx_table_header "󰀻" "Available GRUB Themes"

                local theme_dir="$RETRO_DIR/modules/grub/files"
                for t in "$theme_dir"/*/; do
                    [[ -d $t ]] || continue
                    local tname=$(basename "$t")
                    local tpath="/boot/grub/themes/$tname"
                    local installed="No"
                    local status_color="$MUTE"
                    if [[ -d $tpath ]]; then
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
                    [[ -d $t ]] || continue
                    local tname=$(basename "$t")
                    local tpath="/boot/grub/themes/$tname"
                    local installed="No"
                    local status_color="$MUTE"
                    if [[ -d $tpath ]]; then
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

            if [[ -z $res ]]; then
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

            if [[ -z $secs ]]; then
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

            if [[ -z $mode ]]; then
                rx_log "error" "Please specify on or off"
                return 1
            fi

            local new_val="true"

            case "$mode" in
                on | true | enable) new_val="true" ;;
                off | false | disable) new_val="false" ;;
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

            if [[ -z $mode ]]; then
                rx_log "error" "Please specify on or off"
                return 1
            fi

            local new_val="true"

            case "$mode" in
                on | true | enable) new_val="true" ;;
                off | false | disable) new_val="false" ;;
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

        "kernel")
            local kname="${1:-}"

            if [[ $kname == "set" ]]; then
                kname="${2:-}"
            fi

            if [[ -z $kname ]]; then
                local current_kernel=$(uname -r)
                local current_pkg=""
                case "$current_kernel" in
                    *zen*) current_pkg="linux-zen" ;;
                    *lts*) current_pkg="linux-lts" ;;
                    *hardened*) current_pkg="linux-hardened" ;;
                    *) current_pkg="linux" ;;
                esac

                local configured_kernel=$(get_var "GRUB_KERNEL" "linux")

                rx_table_header "󰏗" "Available Kernels"
                rx_table_row "󰓅" "Running:" "${PINK}${current_kernel}${RESET} (${current_pkg})" "$PINK" "30"
                if [[ $configured_kernel != "$current_pkg" ]]; then
                    rx_table_row "󰓅" "Configured:" "${PINK}${configured_kernel}${RESET}" "$WARN" "30"
                fi
                rx_table_separator

                local kernels=("linux|Stable" "linux-zen|Zen" "linux-lts|LTS" "linux-hardened|Hardened")
                for entry in "${kernels[@]}"; do
                    local pkg="${entry%%|*}"
                    local label="${entry#*|}"
                    local installed="No"
                    local color="$MUTE"
                    if pacman -Qi "$pkg" &>/dev/null; then
                        if [[ $pkg == "$current_pkg" ]]; then
                            installed="Running"
                            color="$SUCCESS"
                        else
                            installed="Installed"
                            color="$PINK"
                        fi
                    fi
                    rx_table_row "󰏗" "${label} (${pkg})" "$installed" "$color" "30"
                done

                rx_table_separator
                rx_table_spacer
                return 0
            fi

            case "$kname" in
                linux | linux-zen | linux-lts | linux-hardened) ;;
                *)
                    rx_log "error" "Unknown kernel: ${PINK}${kname}${RESET}"
                    rx_log "info" "Available: linux, linux-zen, linux-lts, linux-hardened"
                    return 1
                    ;;
            esac

            local current_kernel=$(uname -r)
            local current_pkg=""
            case "$current_kernel" in
                *zen*) current_pkg="linux-zen" ;;
                *lts*) current_pkg="linux-lts" ;;
                *hardened*) current_pkg="linux-hardened" ;;
                *) current_pkg="linux" ;;
            esac

            if [[ $kname == "$current_pkg" ]]; then
                rx_log "warn" "Already running ${PINK}${kname}${RESET}"
                return 0
            fi

            set_var "GRUB_KERNEL" "$kname"
            rx_log "success" "Kernel set to: ${PINK}${kname}${RESET}"
            _grub_add_pending "kernel" "$kname"
            _grub_show_pending
            ;;

        "apply")
            local has_kernel=false
            local pending_kernel=""
            if [[ -f $pending_file ]]; then
                while IFS= read -r line; do
                    [[ -z $line ]] && continue
                    local key="${line%%=*}"
                    local val="${line#*=}"
                    if [[ $key == "kernel" ]]; then
                        has_kernel=true
                        pending_kernel="$val"
                        break
                    fi
                done <"$pending_file"
            fi

            rx_log "info" "Creating Timeshift backup..."
            create_timeshift_backup

            if [[ $has_kernel == true && -n $pending_kernel ]]; then
                rx_log "info" "Installing kernel: ${PINK}${pending_kernel}${RESET}"
                _grub_ensure_kernel "$pending_kernel" || {
                    rx_log "error" "Kernel installation failed"
                    return 1
                }
                rx_log "success" "Kernel ${PINK}${pending_kernel}${RESET} verified"
            fi

            if [[ -f $pending_file ]]; then
                rx_log "info" "Applying GRUB configuration:"
                while IFS= read -r line; do
                    [[ -z $line ]] && continue
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
                        kernel) rx_log "info" "Kernel: ${PINK}${val}${RESET}" ;;
                        *) rx_log "info" "${key}: ${PINK}${val}${RESET}" ;;
                    esac
                done <"$pending_file"
            else
                rx_log "info" "Applying GRUB configuration..."
            fi

            update_grub_config

            local snap_enabled=$(get_var "GRUB_SNAPSHOTS_ENABLED" "true")
            if [[ $snap_enabled == "false" ]]; then
                regenerate_grub true
            else
                regenerate_grub
            fi

            if [[ -f $pending_file ]]; then
                rm -f "$pending_file"
            fi
            ;;

        "setup")
            rx_setup_parse "$@"
            rx_setup_validate "theme,resolution,timeout,os-prober,snapshots,kernel" "theme:in=retropunk,retrolinux|resolution:in=1920x1080,1024x768,auto|timeout:numeric|os-prober:in=true,false|snapshots:in=true,false|kernel:in=linux,linux-zen,linux-lts,linux-hardened" || return 1

            local grub_theme=$(get_var "GRUB_THEME_CHOICE")
            local grub_resolution=$(get_var "BOOT_VIDEO_GRUB")
            local grub_timeout=$(get_var "GRUB_TIMEOUT")
            local grub_os_prober=$(get_var "GRUB_OS_PROBER")
            local grub_snapshots=$(get_var "GRUB_SNAPSHOTS_ENABLED")
            local grub_kernel=$(get_var "GRUB_KERNEL")
            local config_exists=false
            [[ -n $grub_theme || -n $grub_resolution || -n $grub_timeout ]] && config_exists=true

            rx_setup_check_needed "$config_exists" && return 0

            if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
                local theme=$(rx_setup_get_opt "theme" "retropunk")
                local resolution=$(rx_setup_get_opt "resolution" "1920x1080")
                local timeout=$(rx_setup_get_opt "timeout" "10")
                local os_prober=$(rx_setup_get_opt "os-prober")
                [[ -z $os_prober ]] && os_prober=$(rx_setup_get_opt "os_prober")
                local snapshots=$(rx_setup_get_opt "snapshots" "true")
                local kernel=$(rx_setup_get_opt "kernel" "")

                set_var "GRUB_THEME_CHOICE" "$theme"
                set_var "BOOT_VIDEO_GRUB" "$resolution"
                set_var "GRUB_TIMEOUT" "$timeout"
                [[ $os_prober == "true" || $os_prober == "on" ]] && os_prober="true" || os_prober="false"
                set_var "GRUB_OS_PROBER" "$os_prober"
                [[ $snapshots == "true" || $snapshots == "on" ]] && snapshots="true" || snapshots="false"
                set_var "GRUB_SNAPSHOTS_ENABLED" "$snapshots"
                [[ -n $kernel ]] && set_var "GRUB_KERNEL" "$kernel"

                rx_log "info" "Creating Timeshift backup..."
                create_timeshift_backup
                update_grub_config
                if [[ $snapshots == "false" ]]; then
                    regenerate_grub true
                else
                    regenerate_grub
                fi
                [[ -f $pending_file ]] && rm -f "$pending_file"
            else
                local current_theme=$(get_var "GRUB_THEME_CHOICE" "retropunk")

                if [[ $config_exists == true ]]; then
                    rx_setup_current "󰂕" "Current GRUB Configuration" \
                        "Theme" "${grub_theme^}" \
                        "Resolution" "$grub_resolution" \
                        "Timeout" "${grub_timeout}s" \
                        "OS Prober" "$([ "$grub_os_prober" == "true" ] && echo "Enabled" || echo "Disabled")" \
                        "Snapshots" "$([ "$grub_snapshots" == "true" ] && echo "Enabled" || echo "Disabled")" \
                        "Kernel" "$grub_kernel" || true

                    if ! rx_confirm "Reconfigure?" "N"; then
                        rx_log "info" "Setup cancelled."
                        return 0
                    fi
                fi

                local theme_choice=$(rx_menu "󰀻" "Select GRUB theme:" "retropunk" "retrolinux")
                set_var "GRUB_THEME_CHOICE" "$theme_choice"

                local res_x=1920 res_y=1080
                if command -v xrandr &>/dev/null; then
                    local detected_res=$(xrandr 2>/dev/null | grep '*' | head -1 | awk '{print $1}')
                    if [[ -n $detected_res && $detected_res =~ ^[0-9]+x[0-9]+$ ]]; then
                        res_x=${detected_res%%x*}
                        res_y=${detected_res##*x}
                    fi
                fi

                _gcd() { local a=$1 b=$2; while [[ $b -ne 0 ]]; do local t=$b; b=$((a % b)); a=$t; done; echo $a; }

                local gcd=$(_gcd $res_x $res_y)
                local ar_x=$((res_x / gcd)) ar_y=$((res_y / gcd))
                local aspect="${ar_x}:${ar_y}"

                local res_options=()
                for scale in 100 80 75 70 60 50 40; do
                    local sx=$((res_x * scale / 100)) sy=$((res_y * scale / 100))
                    [[ $sx -lt 320 || $sy -lt 240 ]] && continue
                    local g=$(_gcd $sx $sy)
                    [[ $((sx / g)) -eq $ar_x && $((sy / g)) -eq $ar_y ]] && res_options+=("${sx}x${sy}")
                done

                for alt in "1920x1080" "1280x720" "1024x768" "800x600"; do
                    local ax=${alt%%x*} ay=${alt##*x}
                    local g=$(_gcd $ax $ay)
                    local exists=false
                    for existing in "${res_options[@]}"; do [[ "$existing" == "$alt" ]] && exists=true && break; done
                    [[ $exists == false && $((ax / g)) -le 16 && $((ay / g)) -le 10 ]] && res_options+=("$alt")
                done

                local native="${res_x}x${res_y}"
                local final_options=("$native (Native)")
                for opt in "${res_options[@]}"; do
                    [[ "$opt" == "$native" ]] && continue
                    local g=$(_gcd ${opt%%x*} ${opt##*x})
                    final_options+=("$opt ($((${opt%%x*} / g)):$((${opt##*x} / g)))")
                done

                local selected_res=$(rx_menu "󰍹" "Select GRUB resolution (${aspect}):" "${final_options[@]}")
                local gfxmode=$(echo "$selected_res" | cut -d' ' -f1)
                set_var "BOOT_VIDEO_GRUB" "$gfxmode"

                if rx_confirm "Enable OS prober for dual-boot detection?"; then
                    set_var "GRUB_OS_PROBER" "true"
                else
                    set_var "GRUB_OS_PROBER" "false"
                fi

                if rx_confirm "Enable BTRFS snapshot boot for easy rollback?" "Y"; then
                    set_var "GRUB_SNAPSHOTS_ENABLED" "true"
                    sudo systemctl enable --now grub-btrfsd 2>/dev/null
                else
                    set_var "GRUB_SNAPSHOTS_ENABLED" "false"
                    sudo systemctl disable --now grub-btrfsd 2>/dev/null
                fi

                local timeout=$(rx_input_numeric "Boot timeout seconds" "10")
                set_var "GRUB_TIMEOUT" "$timeout"

                local kernel_options=("linux" "linux-zen" "linux-lts" "linux-hardened")
                local kernel_input=$(rx_menu "󰏗" "Select default kernel:" "${kernel_options[@]}")
                set_var "GRUB_KERNEL" "$kernel_input"
                _grub_add_pending "kernel" "$kernel_input"
                _grub_show_pending

                local os_prober_val=$(get_var "GRUB_OS_PROBER" "false")
                local snapshots_val=$(get_var "GRUB_SNAPSHOTS_ENABLED" "true")

                rx_setup_summary "󰂕" "GRUB Setup Summary" \
                    "Theme" "${theme_choice^}" \
                    "Resolution" "$gfxmode" \
                    "OS Prober" "$([ "$os_prober_val" == "true" ] && echo "Enabled" || echo "Disabled")" \
                    "Snapshots" "$([ "$snapshots_val" == "true" ] && echo "Enabled" || echo "Disabled")" \
                    "Timeout" "${timeout}s" \
                    "Kernel" "$kernel_input"

                rx_setup_confirm || return 0

                rx_log "info" "Creating Timeshift backup..."
                create_timeshift_backup
                rx_log "info" "Applying GRUB configuration..."
                update_grub_config
                regenerate_grub
            fi
            ;;

        *)
            rx_help_usage "retro grub <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "kernel [name]" "Show kernels or set default kernel"
            rx_help_cmd "status" "Show GRUB config and boot menu entries"
            rx_help_cmd "theme <name>" "Set GRUB theme (retropunk, retrolinux)"
            rx_help_cmd "resolution <WxH>" "Set GRUB resolution (e.g., 1920x1080)"
            rx_help_cmd "timeout <seconds>" "Set boot timeout"
            rx_help_cmd "os-prober <on|off>" "Enable/disable OS prober"
            rx_help_cmd "snapshots <on|off>" "Enable/disable grub-btrfs snapshots"
            rx_help_cmd "apply" "Backup, apply pending changes, regenerate GRUB"
            rx_help_cmd "setup" "Run GRUB setup wizard"
            rx_help_examples
            rx_help_example "retro grub kernel" "Show available kernels" "38"
            rx_help_example "retro grub kernel linux-zen" "Switch to zen kernel" "38"
            rx_help_example "retro grub status" "Show current GRUB config" "38"
            rx_help_example "retro grub theme retrolinux" "Switch to retrolinux theme" "38"
            rx_help_example "retro grub resolution 2560x1440" "Set 1440p resolution" "38"
            rx_help_example "retro grub os-prober on" "Enable dual-boot detection" "38"
            rx_help_example "retro grub snapshots off" "Disable snapshot boot" "38"
            rx_help_example "retro grub setup -o theme=retropunk,kernel=linux-zen" "Non-interactive setup" "38"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "grub" "GRUB bootloader configuration and management" "cmd_grub"
