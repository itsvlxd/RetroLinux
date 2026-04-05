#!/bin/bash

cmd_benchmark() {
    local VAR_SCRIPT="$RETRO_DIR/scripts/variable_core.sh"
    local bench_script="$RETRO_DIR/scripts/benchmark_core.sh"
    local power_script="$RETRO_DIR/scripts/power_core.sh"
    local action="${1,,}"
    local silent_tables="${2,,}"

    [[ -z $action ]] && rx_log "info" "Usage: retro benchmark [stats|cpu|gpu|ram|disk|net|all|hud]" && return 1

    sync_mangohud() {
        local profile=$(bash "$VAR_SCRIPT" --get "MANGOHUD_PROFILE")
        : ${profile:="advanced"}
        local state=$(bash "$VAR_SCRIPT" --get "MANGOHUD_STATE")
        : ${state:="on"}
        local conf_dir="$HOME/.config/MangoHud"
        local conf_file="$conf_dir/MangoHud.conf"
        local target_conf="$conf_dir/${profile}.conf"

        mkdir -p "$conf_dir"

        if [[ -f $target_conf ]]; then
            ln -sf "$target_conf" "$conf_file"
        fi

        if [[ -f $target_conf ]]; then
            sed -i '/^no_display$/d' "$target_conf"
            [[ $state == "off" ]] && echo "no_display" >>"$target_conf"
        fi
    }
    if [[ $action != "stats" && $action != "hud" && $silent_tables != "silent" ]]; then
        local on_bat=$(bash "$power_script" --source)
        local current_pwr=$(bash "$power_script" --get)

        if [[ $current_pwr != "performance" ]]; then
            rx_log "warn" "You are in ${PINK}${current_pwr^^}${RESET} mode. Scores will be artificially limited!"
        fi

        if [[ $on_bat == "true" ]]; then
            echo ""
            rx_log "warn" "Running heavy benchmarks on battery can cause rapid discharge and excessive heat."
            echo -ne " ${PINK}󰄾 ${RESET}Are you sure you want to continue? ${PINK}[y/N]${RESET}: "
            read -r allow
            [[ ! $allow =~ ^[Yy]$ ]] && rx_log "info" "Benchmark safely aborted." && return 0
            echo ""
        fi
    fi

    mark_run() { bash "$VAR_SCRIPT" --set "BENCH_LAST_RUN" "$(date +'%b %d, %H:%M')"; }

    case "$action" in
        "hud")
            check_dep "mangohud" "mangohud lib32-mangohud" || return 1

            local hud_cmd="${2,,}"
            local hud_val="${3,,}"

            case "$hud_cmd" in
                "set")
                    if [[ -z $hud_val ]]; then
                        echo -e "\n ${PINK}󰢮 MangoHud Configs${RESET}"
                        echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────${RESET}"
                        for conf in "$HOME/.config/MangoHud/"*.conf; do
                            [[ -e $conf ]] || continue
                            local name=$(basename "$conf" .conf)
                            [[ $name != "MangoHud" ]] && echo -e " ${PINK}󰓅${RESET} $name"
                        done
                        echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────${RESET}\n"
                        rx_log "info" "Apply one using: retro benchmark hud set <name>"
                        return 0
                    fi

                    if [[ -f "$HOME/.config/MangoHud/${hud_val}.conf" ]]; then
                        bash "$VAR_SCRIPT" --set "MANGOHUD_PROFILE" "$hud_val"
                        sync_mangohud
                        rx_log "success" "MangoHud profile symlinked to: ${PINK}${hud_val}.conf${RESET}"
                    else
                        rx_log "error" "Config '${hud_val}.conf' not found in ~/.config/MangoHud/"
                        rx_log "info" "Run 'retro benchmark hud set' to see available profiles."
                    fi
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
                    local run_cmd="${@:3}"
                    [[ -z $run_cmd ]] && rx_log "error" "Provide an app to run (e.g., retro benchmark hud run vkmark)" && return 1

                    if [[ ${run_cmd,,} == *".exe"* || ${run_cmd,,} == *".exe "* ]]; then
                        rx_log "info" "Windows Executable detected."

                        if [[ ${run_cmd,,} == wine\ * ]]; then
                            rx_log "info" "Injecting MangoHud..."
                            env MANGOHUD=1 mangohud $run_cmd
                        else
                            rx_log "info" "Injecting MangoHud via Wine..."
                            env MANGOHUD=1 mangohud wine $run_cmd
                        fi
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
                    rx_log "info" "Usage: retro benchmark hud [status|set|on|off|auto|run|test]"
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

        *) rx_log "info" "Usage: retro benchmark [status|cpu|gpu|ram|disk|net|all|hud]" ;;
    esac
}
register_command "TOOLS" "benchmark" "Benchmark utiltiy for hardware diagnostics and scoring" "cmd_benchmark"
