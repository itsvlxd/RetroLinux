#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"

cmd_benchmark() {
    local bench_script="$RETRO_DIR/scripts/benchmark_core.sh"
    local action="${1,,}"
    local silent_tables="${2,,}"

    mark_run() { set_var "BENCH_LAST_RUN" "$(date +'%b %d, %H:%M')"; }

    sync_mangohud() {
        local s_hud=$(get_var "MANGOHUD_STATE")
        : ${s_hud:="on"}
        local config_file="$HOME/.config/MangoHud/MangoHud.conf"

        if [[ -f "$config_file" ]]; then
            if [[ $s_hud == "off" ]]; then
                if ! grep -q "^no_display=1" "$config_file" 2>/dev/null; then
                    echo "no_display=1" >> "$config_file"
                fi
            else
                sed -i '/^no_display=/d' "$config_file" 2>/dev/null
            fi
        fi

        if [[ $s_hud == "on" ]]; then
            hyprctl keyword env MANGOHUD,1 >/dev/null 2>&1
        else
            hyprctl keyword env MANGOHUD,0 >/dev/null 2>&1
        fi
    }

    case "$action" in
        "hud")
            local hud_cmd="${2,,}"
            local hud_val="${3,,}"

            case "$hud_cmd" in
                "set")
                    [[ -z $hud_val ]] && rx_log "error" "Provide a preset name (e.g. minimal, full)" && return 1
                    if bash "$bench_script" --hud-set "$hud_val"; then
                        rx_log "success" "MangoHud preset set to: ${PINK}${hud_val}${RESET}"
                    else
                        rx_log "error" "Failed to set preset: ${PINK}${hud_val}${RESET}"
                    fi
                    ;;
                "auto")
                    local current_auto=$(get_var "MANGOHUD_AUTO")
                    if [[ $current_auto == "on" ]]; then
                        set_var "MANGOHUD_AUTO" "off"
                        hyprctl keyword env MANGOHUD,0 >/dev/null
                        hyprctl keyword env ENABLE_FGMOD,0 >/dev/null 2>&1
                        rx_log "success" "Global MangoHud: ${GRAY}DISABLED${RESET}"
                    else
                        set_var "MANGOHUD_AUTO" "on"
                        hyprctl keyword env MANGOHUD,1 >/dev/null
                        hyprctl keyword env ENABLE_FGMOD,1 >/dev/null 2>&1
                        rx_log "success" "Global MangoHud: ${PINK}ENABLED${RESET} (Applies to new apps)"
                    fi
                    ;;
                "run")
                    local run_cmd="${*:3}"
                    [[ -z $run_cmd ]] && rx_log "error" "Provide an app to run (e.g., retro benchmark hud run vkmark)" && return 1
                    if [[ ${run_cmd,,} == *".exe"* || ${run_cmd,,} == *".exe "* ]]; then
                        rx_log "info" "Windows Executable detected. Injecting MangoHud via Wine..."
                        nohup env MANGOHUD=1 mangohud wine $run_cmd >/dev/null 2>&1 &
                    else
                        rx_log "info" "Launching native Linux app with MangoHud: ${GRAY}$run_cmd${RESET}"
                        nohup env MANGOHUD=1 mangohud $run_cmd >/dev/null 2>&1 &
                    fi
                    ;;
                "test")
                    check_dep "vkcube" "vulkan-tools" || return 1
                    rx_log "info" "Spawning floating vkcube to test overlay..."
                    nohup env MANGOHUD=1 vkcube >/dev/null 2>&1 &
                    ;;
                "on" | "off")
                    set_var "MANGOHUD_STATE" "$hud_cmd"
                    sync_mangohud
                    local p_hud=$(get_var "MANGOHUD_PROFILE")
                    : ${p_hud:="advanced"}
                    local target_conf="$HOME/.config/MangoHud/${p_hud}.conf"
                    local current_key="Not set"
                    if [[ -f "$target_conf" ]]; then
                        local parsed_key=$(grep "^toggle_hud=" "$target_conf" 2>/dev/null | cut -d'=' -f2 | tr -d '\r' | xargs)
                        if [[ -n "$parsed_key" && "$parsed_key" != "none" ]]; then
                            current_key="$parsed_key"
                        fi
                    fi
                    if [[ $hud_cmd == "on" ]]; then
                        rx_log "success" "MangoHud default state: ${PINK}VISIBLE${RESET} (Press ${current_key} to hide)"
                    else
                        rx_log "success" "MangoHud default state: ${GRAY}HIDDEN${RESET} (Press ${current_key} to show)"
                    fi
                    ;;
                "load")
                    local current_auto=$(get_var "MANGOHUD_AUTO")
                    if [[ $current_auto == "on" ]]; then
                        hyprctl keyword env MANGOHUD,1 >/dev/null 2>&1
                        hyprctl keyword env ENABLE_FGMOD,1 >/dev/null 2>&1
                    else
                        hyprctl keyword env MANGOHUD,0 >/dev/null 2>&1
                        hyprctl keyword env ENABLE_FGMOD,0 >/dev/null 2>&1
                    fi
                    return 0
                    ;;
                "status")
                    local p_hud=$(get_var "MANGOHUD_PROFILE")
                    : ${p_hud:="advanced"}
                    local s_hud=$(get_var "MANGOHUD_STATE")
                    : ${s_hud:="on"}
                    local a_hud=$(get_var "MANGOHUD_AUTO")
                    : ${a_hud:="off"}
                    local target_conf="$HOME/.config/MangoHud/${p_hud}.conf"
                    local current_key="Not set"
                    if [[ -f "$target_conf" ]]; then
                        local parsed_key=$(grep "^toggle_hud=" "$target_conf" 2>/dev/null | cut -d'=' -f2 | tr -d '\r' | xargs)
                        if [[ -n "$parsed_key" && "$parsed_key" != "none" ]]; then
                            current_key="$parsed_key"
                        fi
                    fi
                    rx_table_header "󰢮" "RetroHUD Configuration Status"
                    rx_table_row "󰈐" "Overlay Style:" "${p_hud^^}" "$PINK" "22"
                    rx_table_row "󰈐" "Default Visibility:" "${s_hud^^} (Toggle: ${current_key})" "$PINK" "22"
                    local auto_color="${GRAY}"
                    [[ $a_hud == "on" ]] && auto_color="${PINK}"
                    rx_table_row "󰈐" "Global Auto-Inject:" "${a_hud^^}" "$auto_color" "22"
                    rx_table_separator
                    rx_table_spacer
                    ;;
                "toggle")
                    if [[ -z $hud_val ]]; then
                        rx_log "error" "Please specify a key (e.g., F11 or Shift_L+F12)"
                        return 1
                    fi

                    local valid_key=false
                    if [[ "$hud_val" =~ ^[A-Za-z_]+[+-][A-Za-z0-9]+$ ]] || [[ "$hud_val" =~ ^[A-Za-z0-9]+$ ]]; then
                        valid_key=true
                    fi

                    if [[ $valid_key == "false" ]]; then
                        rx_log "error" "Invalid key format. Use format like 'F11' or 'Shift_L+F12'"
                        return 1
                    fi

                    local current_prof=$(get_var "MANGOHUD_PROFILE")
                    : ${current_prof:="advanced"}
                    local target_conf="$HOME/.config/MangoHud/${current_prof}.conf"
                    if [[ -f "$target_conf" ]]; then
                        sed -i '/^toggle_hud=/d' "$target_conf"
                        echo "toggle_hud=$hud_val" >>"$target_conf"
                        cp "$target_conf" "$HOME/.config/MangoHud/MangoHud.conf"
                        rx_log "success" "HUD toggle key set to ${PINK}$hud_val${RESET} in ${current_prof}.conf"
                    else
                        rx_log "error" "Active config '$target_conf' not found."
                    fi
                    ;;
                "test")
                    check_dep "vkcube" "vulkan-tools" || return 1
                    rx_log "info" "Spawning floating vkcube to test overlay..."
                    hyprctl dispatch exec "[float; size 800 600; center] env MANGOHUD=1 vkcube" >/dev/null 2>&1 || env MANGOHUD=1 vkcube &
                    ;;
                *)
                    rx_help_usage "retro benchmark hud <command>"
                    rx_help_commands "Available commands"
                    rx_help_cmd "set <preset>" "Apply a HUD layout preset (minimal, full, etc)"
                    rx_help_cmd "auto" "Toggle global auto-inject for new apps"
                    rx_help_cmd "run <cmd>" "Launch a specific app with MangoHud overlay"
                    rx_help_cmd "on" "Set MangoHud default state to visible"
                    rx_help_cmd "off" "Set MangoHud default state to hidden"
                    rx_help_cmd "load" "Reload MangoHud env vars into Hyprland"
                    rx_help_cmd "status" "Show RetroHUD configuration status"
                    rx_help_cmd "toggle <key>" "Set keyboard shortcut to toggle overlay"
                    rx_help_cmd "test" "Launch vkcube to preview HUD"
                    rx_help_spacer
                    ;;
            esac
            ;;

        "status")
            local c_hw=$(bash "$bench_script" --hw-cpu)
            IFS='|' read -r c_name c_ucode c_arch c_threads <<<"$c_hw"
            local g_hw=$(bash "$bench_script" --hw-gpu)
            IFS='|' read -r g_name g_drv <<<"$g_hw"
            local r_tot=$(bash "$bench_script" --hw-ram)
            local d_hw=$(bash "$bench_script" --hw-disk)
            IFS='|' read -r d_model d_type <<<"$d_hw"
            local n_hw=$(bash "$bench_script" --hw-net)

            local s_cpu=$(get_var "BENCH_CPU")
            : ${s_cpu:="Not Tested"}
            local s_gpu=$(get_var "BENCH_GPU")
            : ${s_gpu:="Not Tested"}
            local s_ram=$(get_var "BENCH_RAM")
            : ${s_ram:="Not Tested"}
            local s_dsk=$(get_var "BENCH_DISK")
            : ${s_dsk:="Not Tested"}
            local s_net=$(get_var "BENCH_NET")
            : ${s_net:="Not Tested"}
            local last_run=$(get_var "BENCH_LAST_RUN")
            : ${last_run:="Never"}

            echo -e "${PINK}"
            cat <<'EOF'
   ___  _____________  ____  ___  _____  _________ __
  / _ \/ __/_  __/ _ \/ __ \/ _ )/ __/ |/ / ___/ // /
 / , _/ _/  / / / , _/ /_/ / _  / _//    / /__/ _  / 
/_/|_/___/ /_/ /_/|_|\____/____/___/_/|_/\___/_//_/  
EOF
            rx_table_simple "" "Last Benchmark: $last_run" "$GRAY"
            rx_help_separator
            printf " ${PINK}󰻠 ${RESET} %-36s ${PINK}%-28s ${GRAY}%s %s${RESET}\n" "${c_name:0:35}" "$s_cpu" "$c_arch" "$c_ucode"
            printf " ${PINK}󰢮 ${RESET} %-36s ${PINK}%-28s ${GRAY}%s (Vulkan API)${RESET}\n" "${g_name:0:35}" "$s_gpu" "$g_drv"
            printf " ${PINK}󰘚 ${RESET} %-36s ${PINK}%-28s\n" "$r_tot" "$s_ram"
            printf " ${PINK}󰋊 ${RESET} %-36s ${PINK}%-28s ${GRAY}%s${RESET}\n" "${d_model:0:35}" "$s_dsk" "$d_type"
            printf " ${PINK}󰀂 ${RESET} %-36s ${PINK}%s${RESET}\n" "${n_hw:0:35}" "$s_net"
            rx_help_separator
            rx_help_spacer
            ;;

        "cpu")
            check_dep "sysbench" "sysbench" || return 1

            local c_hw=$(bash "$bench_script" --hw-cpu)
            IFS='|' read -r c_name c_ucode c_arch c_threads <<<"$c_hw"
            rx_log "info" "CPU: ${PINK}$c_name${RESET}"
            rx_log "info" "Running prime-number calculation (Please wait 10s)..."

            local raw_score=$(bash "$bench_script" --cpu)
            IFS='|' read -r score min avg max <<<"$raw_score"

            set_var "BENCH_CPU" "${score%.*} Events/sec"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                rx_table_header "󰻠" "CPU Benchmark Results"
                rx_table_row "󰈐" "Final Score:" "${score%.*} Events/sec" "$PINK" "20"
                rx_table_row_gray "󰔚" "Min Latency:" "$min ms" "20"
                rx_table_row_gray "󰔚" "Avg Latency:" "$avg ms" "20"
                rx_table_row_gray "󰔚" "Max Latency:" "$max ms" "20"
                rx_table_separator
                rx_table_spacer
            fi
            ;;

        "gpu")
            check_dep "vkmark" "vkmark" || return 1

            local g_hw=$(bash "$bench_script" --hw-gpu)
            IFS='|' read -r g_name g_drv <<<"$g_hw"
            rx_log "info" "GPU: ${PINK}$g_name${RESET} (Driver: $g_drv)"
            rx_log "info" "Launching Vulkan 3D Render Test (Window will appear)..."

            local score=$(bash "$bench_script" --gpu)
            [[ $score == "Missing_VKMark" ]] && rx_log "error" "Install vkmark: sudo pacman -S vkmark" && return 1

            set_var "BENCH_GPU" "$score (VKMark)"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                rx_table_header "󰢮" "GPU Benchmark Results"
                rx_table_row "󰈐" "Final Score:" "$score (VKMark)" "$PINK" "20"
                rx_table_separator
                rx_table_spacer
            fi
            ;;

        "ram")
            check_dep "sysbench" "sysbench" || return 1

            local r_tot=$(bash "$bench_script" --hw-ram)
            rx_log "info" "RAM: ${PINK}$r_tot${RESET}"
            rx_log "info" "Running Memory Throughput Test (10GB Transfer)..."

            local raw_score=$(bash "$bench_script" --ram)
            IFS='|' read -r score min avg max <<<"$raw_score"

            set_var "BENCH_RAM" "${score} MiB/sec"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                rx_table_header "󰘚" "RAM Benchmark Results"
                rx_table_row "󰈐" "Throughput:" "$score MiB/sec" "$PINK" "20"
                rx_table_row_gray "󰔚" "Min Latency:" "$min ms" "20"
                rx_table_row_gray "󰔚" "Avg Latency:" "$avg ms" "20"
                rx_table_row_gray "󰔚" "Max Latency:" "$max ms" "20"
                rx_table_separator
                rx_table_spacer
            fi
            ;;

        "disk")
            local d_hw=$(bash "$bench_script" --hw-disk)
            IFS='|' read -r d_model d_type <<<"$d_hw"
            rx_log "info" "Disk: ${PINK}$d_model${RESET} ${GRAY}($d_type)${RESET}"
            rx_log "info" "Running Sequential I/O Test (Watch progress below)..."
            sudo -v

            local score=$(bash "$bench_script" --disk)
            IFS='|' read -r w_spd r_spd <<<"$score"

            set_var "BENCH_DISK" "󰈈 $r_spd 󰏫 $w_spd"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                rx_table_header "󰋊" "Disk Benchmark Results"
                rx_table_row "󰈐" "Read Speed:" "$r_spd" "$PINK" "20"
                rx_table_row "󰈐" "Write Speed:" "$w_spd" "$PINK" "20"
                rx_table_separator
                rx_table_spacer
            fi
            ;;

        "net")
            check_dep "speedtest-cli" "speedtest-cli" || return 1

            rx_log "info" "Pinging nearest speedtest servers (May take 30s)..."
            local score=$(bash "$bench_script" --internet)
            [[ $score == "Missing_Speedtest" ]] && rx_log "error" "Install speedtest-cli: sudo pacman -S speedtest-cli" && return 1

            IFS='|' read -r ping down up <<<"$score"
            set_var "BENCH_NET" "󰇚 $down 󰕒 $up 󰾆 $ping"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                rx_table_header "󰀂" "Network Benchmark Results"
                rx_table_row "󰈐" "Ping:" "$ping" "$PINK" "20"
                rx_table_row "󰈐" "Download:" "$down" "$PINK" "20"
                rx_table_row "󰈐" "Upload:" "$up" "$PINK" "20"
                rx_table_separator
                rx_table_spacer
            fi
            ;;

        "all")
            cmd_benchmark "cpu" "silent"
            cmd_benchmark "gpu" "silent"
            cmd_benchmark "ram" "silent"
            cmd_benchmark "disk" "silent"
            cmd_benchmark "net" "silent"

            cmd_benchmark "status"
            rx_log "success" "RetroBench Full Suite Completed and Saved."
            ;;

        *)
            rx_help_usage "retro benchmark <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show benchmark scores and hardware"
            rx_help_cmd "cpu" "Run CPU prime benchmark"
            rx_help_cmd "gpu" "Run Vulkan 3D render benchmark"
            rx_help_cmd "ram" "Run memory throughput test"
            rx_help_cmd "disk" "Run sequential I/O test"
            rx_help_cmd "net" "Run network speed test"
            rx_help_cmd "all" "Run all benchmarks silently"
            rx_help_cmd "hud" "MangoHud overlay management"
            rx_help_spacer
            ;;
    esac
}
register_command "TOOLS" "benchmark" "Benchmark utiltiy for hardware diagnostics and scoring" "cmd_benchmark"
