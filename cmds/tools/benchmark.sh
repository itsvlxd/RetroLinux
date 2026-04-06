#!/bin/bash

cmd_benchmark() {
    local VAR_SCRIPT="$RETRO_DIR/scripts/variable_core.sh"
    local bench_script="$RETRO_DIR/scripts/benchmark_core.sh"
    local power_script="$RETRO_DIR/scripts/power_core.sh"
    local action="${1,,}"
    local silent_tables="${2,,}"

    mark_run() { bash "$VAR_SCRIPT" --set "BENCH_LAST_RUN" "$(date +'%b %d, %H:%M')"; }

    case "$action" in
        "hud")
            local hud_cmd="${3,,}"
            local hud_val="${4,,}"

            case "$hud_cmd" in
                "set")
                    [[ -z $hud_val ]] && rx_log "error" "Provide a preset name (e.g. minimal, full)" && return 1
                    bash "$bench_script" --hud-set "$hud_val"
                    [[ $? -eq 0 ]] && rx_log "success" "MangoHud set to preset: ${PINK}${hud_val}${RESET}" || rx_log "error" "Preset not found"
                    ;;
                "auto")
                    local current_auto=$(bash "$VAR_SCRIPT" --get "MANGOHUD_AUTO")
                    if [[ $current_auto == "on" ]]; then
                        bash "$VAR_SCRIPT" --set "MANGOHUD_AUTO" "off"
                        hyprctl keyword env MANGOHUD,0 >/dev/null
                        hyprctl keyword env ENABLE_FGMOD,0 >/dev/null 2>&1
                        rx_log "success" "Global MangoHud: ${GRAY}DISABLED${RESET}"
                    else
                        bash "$VAR_SCRIPT" --set "MANGOHUD_AUTO" "on"
                        hyprctl keyword env MANGOHUD,1 >/dev/null
                        hyprctl keyword env ENABLE_FGMOD,1 >/dev/null 2>&1
                        rx_log "success" "Global MangoHud: ${PINK}ENABLED${RESET} (Applies to new apps)"
                    fi
                    ;;
                "run")
                    local run_cmd="${@:4}"
                    [[ -z $run_cmd ]] && rx_log "error" "Provide an app to run (e.g., retro benchmark hud run vkmark)" && return 1
                    if [[ ${run_cmd,,} == *".exe"* || ${run_cmd,,} == *".exe "* ]]; then
                        rx_log "info" "Windows Executable detected. Injecting MangoHud via Wine..."
                        env MANGOHUD=1 mangohud wine $run_cmd
                    else
                        rx_log "info" "Launching native Linux app with MangoHud: ${GRAY}$run_cmd${RESET}"
                        env MANGOHUD=1 mangohud $run_cmd
                    fi
                    ;;
                "on" | "off")
                    bash "$VAR_SCRIPT" --set "MANGOHUD_STATE" "$hud_cmd"
                    sync_mangohud
                    local p_hud=$(bash "$VAR_SCRIPT" --get "MANGOHUD_PROFILE")
                    : ${p_hud:="advanced"}
                    local target_conf="$HOME/.config/MangoHud/${p_hud}.conf"
                    local current_key="F11"
                    if [[ -f $target_conf ]]; then
                        local parsed_key=$(grep "^toggle_hud" "$target_conf" | tail -n 1 | cut -d'=' -f2 | tr -d '\r' | xargs)
                        [[ -n $parsed_key ]] && current_key="$parsed_key"
                    fi
                    if [[ $hud_cmd == "on" ]]; then
                        rx_log "success" "MangoHud default state: ${PINK}VISIBLE${RESET} (Press ${current_key} to hide)"
                    else
                        rx_log "success" "MangoHud default state: ${GRAY}HIDDEN${RESET} (Press ${current_key} to show)"
                    fi
                    ;;
                "load")
                    local current_auto=$(bash "$VAR_SCRIPT" --get "MANGOHUD_AUTO")
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
                    local p_hud=$(bash "$VAR_SCRIPT" --get "MANGOHUD_PROFILE")
                    : ${p_hud:="advanced"}
                    local s_hud=$(bash "$VAR_SCRIPT" --get "MANGOHUD_STATE")
                    : ${s_hud:="on"}
                    local a_hud=$(bash "$VAR_SCRIPT" --get "MANGOHUD_AUTO")
                    : ${a_hud:="off"}
                    local target_conf="$HOME/.config/MangoHud/${p_hud}.conf"
                    local current_key="F11 (Default)"
                    if [[ -f $target_conf ]]; then
                        local parsed_key=$(grep "^toggle_hud=" "$target_conf" | cut -d'=' -f2)
                        [[ -n $parsed_key ]] && current_key="$parsed_key"
                    fi
                    echo -e "\n ${PINK}󰢮 RetroHUD Configuration Status${RESET}"
                    echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                    printf " ${PINK}󰈐${RESET} %-22s ${PINK}%s${RESET}\n" "Overlay Style:" "${p_hud^^}"
                    printf " ${PINK}󰈐${RESET} %-22s ${PINK}%s${RESET} ${GRAY}(Toggle: %s)${RESET}\n" "Default Visibility:" "${s_hud^^}" "$current_key"
                    local auto_color="${GRAY}"
                    [[ $a_hud == "on" ]] && auto_color="${PINK}"
                    printf " ${PINK}󰈐${RESET} %-22s ${auto_color}%s${RESET}\n" "Global Auto-Inject:" "${a_hud^^}"
                    echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
                    ;;
                "toggle")
                    if [[ -z $hud_val ]]; then
                        rx_log "error" "Please specify a key (e.g., F11 or Shift_R+F12)"
                        return 1
                    fi
                    local current_prof=$(bash "$VAR_SCRIPT" --get "MANGOHUD_PROFILE")
                    : ${current_prof:="advanced"}
                    local target_conf="$HOME/.config/MangoHud/${current_prof}.conf"
                    if [[ -f $target_conf ]]; then
                        sed -i '/^toggle_hud/d' "$target_conf"
                        echo "toggle_hud=$hud_val" >>"$target_conf"
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
                    rx_log "info" "Usage: retro benchmark hud <command>"
                    echo -e ""
                    echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "set <preset>" "Apply a HUD layout preset (minimal, full, etc)"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "auto" "Toggle global auto-inject for new apps"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "run <cmd>" "Launch a specific app with MangoHud overlay"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "on" "Set MangoHud default state to visible"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "off" "Set MangoHud default state to hidden"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "load" "Reload MangoHud env vars into Hyprland"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show RetroHUD configuration status"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "toggle <key>" "Set keyboard shortcut to toggle overlay"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "test" "Launch vkcube to preview HUD"
                    echo ""
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

            local s_cpu=$(bash "$VAR_SCRIPT" --get "BENCH_CPU")
            : ${s_cpu:="Not Tested"}
            local s_gpu=$(bash "$VAR_SCRIPT" --get "BENCH_GPU")
            : ${s_gpu:="Not Tested"}
            local s_ram=$(bash "$VAR_SCRIPT" --get "BENCH_RAM")
            : ${s_ram:="Not Tested"}
            local s_dsk=$(bash "$VAR_SCRIPT" --get "BENCH_DISK")
            : ${s_dsk:="Not Tested"}
            local s_net=$(bash "$VAR_SCRIPT" --get "BENCH_NET")
            : ${s_net:="Not Tested"}
            local last_run=$(bash "$VAR_SCRIPT" --get "BENCH_LAST_RUN")
            : ${last_run:="Never"}

            echo -e "${PINK}"
            cat <<'EOF'
   ___  _____________  ____  ___  _____  _________ __
  / _ \/ __/_  __/ _ \/ __ \/ _ )/ __/ |/ / ___/ // /
 / , _/ _/  / / / , _/ /_/ / _  / _//    / /__/ _  / 
/_/|_/___/ /_/ /_/|_|\____/____/___/_/|_/\___/_//_/  
EOF
            echo -e " ${GRAY}               Last Benchmark: $last_run${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────────────────────────────────────────────────"
            printf " ${PINK}󰻠 ${RESET} %-36s ${PINK}%-28s ${GRAY}%s %s${RESET}\n" "${c_name:0:35}" "$s_cpu" "$c_arch" "$c_ucode"
            printf " ${PINK}󰢮 ${RESET} %-36s ${PINK}%-28s ${GRAY}%s (Vulkan API)${RESET}\n" "${g_name:0:35}" "$s_gpu" "$g_drv"
            printf " ${PINK}󰘚 ${RESET} %-36s ${PINK}%-28s\n" "$r_tot" "$s_ram"
            printf " ${PINK}󰋊 ${RESET} %-36s ${PINK}%-28s ${GRAY}%s${RESET}\n" "${d_model:0:35}" "$s_dsk" "$d_type"
            printf " ${PINK}󰀂 ${RESET} %-36s ${PINK}%s${RESET}\n" "${n_hw:0:35}" "$s_net"
            echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────────────────────────────────────────────────${RESET}\n"
            ;;

        "cpu")
            check_dep "sysbench" "sysbench" || return 1

            local c_hw=$(bash "$bench_script" --hw-cpu)
            IFS='|' read -r c_name c_ucode c_arch c_threads <<<"$c_hw"
            rx_log "info" "CPU: ${PINK}$c_name${RESET}"
            rx_log "info" "Running prime-number calculation (Please wait 10s)..."

            local raw_score=$(bash "$bench_script" --cpu)
            IFS='|' read -r score min avg max <<<"$raw_score"

            bash "$VAR_SCRIPT" --set "BENCH_CPU" "${score%.*} Events/sec"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                echo -e "\n ${PINK}󰻠 CPU Benchmark Results${RESET}"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s${RESET}\n" "Final Score:" "${score%.*} Events/sec"
                printf " ${GRAY}󰔚${RESET} %-20s ${GRAY}%s ms${RESET}\n" "Min Latency:" "$min"
                printf " ${GRAY}󰔚${RESET} %-20s ${GRAY}%s ms${RESET}\n" "Avg Latency:" "$avg"
                printf " ${GRAY}󰔚${RESET} %-20s ${GRAY}%s ms${RESET}\n" "Max Latency:" "$max"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
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

            bash "$VAR_SCRIPT" --set "BENCH_GPU" "$score (VKMark)"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                echo -e "\n ${PINK}󰢮 GPU Benchmark Results${RESET}"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s${RESET}\n" "Final Score:" "$score (VKMark)"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
            fi
            ;;

        "ram")
            check_dep "sysbench" "sysbench" || return 1

            local r_tot=$(bash "$bench_script" --hw-ram)
            rx_log "info" "RAM: ${PINK}$r_tot${RESET}"
            rx_log "info" "Running Memory Throughput Test (10GB Transfer)..."

            local raw_score=$(bash "$bench_script" --ram)
            IFS='|' read -r score min avg max <<<"$raw_score"

            bash "$VAR_SCRIPT" --set "BENCH_RAM" "${score} MiB/sec"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                echo -e "\n ${PINK}󰘚 RAM Benchmark Results${RESET}"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s MiB/sec${RESET}\n" "Throughput:" "$score"
                printf " ${GRAY}󰔚${RESET} %-20s ${GRAY}%s ms${RESET}\n" "Min Latency:" "$min"
                printf " ${GRAY}󰔚${RESET} %-20s ${GRAY}%s ms${RESET}\n" "Avg Latency:" "$avg"
                printf " ${GRAY}󰔚${RESET} %-20s ${GRAY}%s ms${RESET}\n" "Max Latency:" "$max"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
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

            bash "$VAR_SCRIPT" --set "BENCH_DISK" "󰈈 $r_spd 󰏫 $w_spd"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                echo -e "\n ${PINK}󰋊 Disk Benchmark Results${RESET}"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s${RESET}\n" "Read Speed:" "$r_spd"
                printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s${RESET}\n" "Write Speed:" "$w_spd"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
            fi
            ;;

        "net")
            check_dep "speedtest-cli" "speedtest-cli" || return 1

            rx_log "info" "Pinging nearest speedtest servers (May take 30s)..."
            local score=$(bash "$bench_script" --internet)
            [[ $score == "Missing_Speedtest" ]] && rx_log "error" "Install speedtest-cli: sudo pacman -S speedtest-cli" && return 1

            IFS='|' read -r ping down up <<<"$score"
            bash "$VAR_SCRIPT" --set "BENCH_NET" "󰇚 $down 󰕒 $up 󰾆 $ping"
            mark_run

            if [[ $silent_tables != "silent" ]]; then
                echo -e "\n ${PINK}󰀂 Network Benchmark Results${RESET}"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s${RESET}\n" "Ping:" "$ping"
                printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s${RESET}\n" "Download:" "$down"
                printf " ${PINK}󰈐${RESET} %-20s ${PINK}%s${RESET}\n" "Upload:" "$up"
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
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
            rx_log "info" "Usage: retro benchmark <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show benchmark scores and hardware"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "cpu" "Run CPU prime benchmark"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "gpu" "Run Vulkan 3D render benchmark"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "ram" "Run memory throughput test"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "disk" "Run sequential I/O test"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "net" "Run network speed test"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "all" "Run all benchmarks silently"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "hud" "MangoHud overlay management"
            echo ""
            ;;
    esac
}
register_command "TOOLS" "benchmark" "Benchmark utiltiy for hardware diagnostics and scoring" "cmd_benchmark"
