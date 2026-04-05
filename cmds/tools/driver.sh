#!/bin/bash

_kernel_version_ge() {
    local major="$1"
    local minor="$2"
    local kver=$(uname -r | cut -d. -f1,2)
    local k_major=${kver%%.*}
    local k_minor=${kver##*.}
    ((k_major > major || (k_major == major && k_minor >= minor)))
}

_get_missing_local() {
    local pkgs="$1"
    local missing=()
    for p in $pkgs; do
        pacman -Qq "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    echo "${missing[*]}"
}

_is_aur_pkg() {
    local pkg="$1"
    pacman -Si "$pkg" >/dev/null 2>&1 && return 1
    yay -Si "$pkg" >/dev/null 2>&1 && return 0
    return 1
}

_tag_missing() {
    local pkgs="$1"
    local aur_pkgs=""
    local repo_pkgs=""
    for p in $pkgs; do
        if _is_aur_pkg "$p"; then
            aur_pkgs+=" $p"
        else
            repo_pkgs+=" $p"
        fi
    done
    if [[ -n $repo_pkgs && -n $aur_pkgs ]]; then
        echo "repo: ${repo_pkgs} | aur: ${aur_pkgs}"
    elif [[ -n $aur_pkgs ]]; then
        echo "aur: ${aur_pkgs}"
    else
        echo "$pkgs"
    fi
}

cmd_driver() {
    local driver_script="$RETRO_DIR/scripts/driver_core.sh"
    local action="${1,,}"
    local flag="${2,,}"

    case "$action" in
        "status")
            check_dep "lspci" "pciutils" || return 1

            local scan_data
            scan_data=$(bash "$driver_script" --scan)
            [[ -z $scan_data ]] && rx_log "error" "Failed to scan hardware" && return 1

            local missing_count=0
            local all_missing=""
            local has_npu=false
            local gpu_name="" gpu_drv="" gpu_miss=""
            local npu_name="" npu_drv="" npu_miss=""
            local cpu_name="" cpu_info="" cpu_miss=""
            local net_name="" net_drv="" net_miss=""
            local audio_name="" audio_drv=""
            local bt_info="" bt_miss=""
            local fw_miss=""
            local ml_status="" rb_status=""
            local other_entries=()
            local kernel_warn=""

            while IFS= read -r line; do
                [[ -z $line ]] && continue
                IFS='|' read -r type vendor model driver pkgs missing <<<"$line"

                case "$type" in
                    GPU)
                        gpu_name="${model}"
                        gpu_drv="${driver:-no driver}"
                        if [[ -n $missing ]]; then
                            gpu_miss="$missing"
                            all_missing+=" $missing"
                            ((missing_count++))
                        fi
                        ;;
                    NPU)
                        has_npu=true
                        npu_name="${model}"
                        npu_drv="${driver:-no driver}"
                        if [[ -n $missing ]]; then
                            npu_miss="$missing"
                            all_missing+=" $missing"
                            ((missing_count++))
                        fi
                        ;;
                    CPU)
                        cpu_name="${model}"
                        cpu_info="microcode installed"
                        if [[ -n $missing ]]; then
                            cpu_info="microcode missing"
                            cpu_miss="$missing"
                            all_missing+=" $missing"
                            ((missing_count++))
                        fi
                        ;;
                    NET)
                        net_name="${model}"
                        net_drv="${driver:-no driver}"
                        if [[ -n $missing ]]; then
                            net_miss="$missing"
                            all_missing+=" $missing"
                            ((missing_count++))
                        fi
                        ;;
                    AUDIO)
                        audio_name="${model}"
                        audio_drv="${driver:-generic}"
                        ;;
                    BT)
                        pacman -Qq bluez >/dev/null 2>&1 && bt_info="installed" || bt_info="not installed"
                        if [[ -n $missing ]]; then
                            bt_miss="$missing"
                            all_missing+=" $missing"
                            ((missing_count++))
                        fi
                        ;;
                    FW)
                        if [[ -n $missing ]]; then
                            fw_miss="$missing"
                            all_missing+=" $missing"
                            ((missing_count++))
                        fi
                        ;;
                    OTHER)
                        local type_label="${type^}"
                        local o_miss=""
                        if [[ -n $missing ]]; then
                            o_miss="$missing"
                            all_missing+=" $missing"
                            ((missing_count++))
                        fi
                        other_entries+=("${type_label}|${model}|${o_miss}")
                        ;;
                    SYS)
                        if [[ $vendor == "multilib" ]]; then
                            ml_status="${model}"
                        elif [[ $vendor == "rebar" ]]; then
                            rb_status="${model}"
                        fi
                        ;;
                    WARN)
                        kernel_warn="${model}"
                        ;;
                esac
            done <<<"$scan_data"

            local unique_all_missing=$(echo "$all_missing" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ' | xargs)
            local tagged_missing=$(_tag_missing "$unique_all_missing")

            echo -e "\n ${PINK}󰢮 Driver Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            [[ -n $cpu_name ]] && printf " ${PINK}󰻠${RESET} %-36s ${PINK}%s${RESET}\n" "${cpu_name:0:35}" "$cpu_info"
            if [[ -n $gpu_name ]]; then
                if [[ -n $gpu_miss ]]; then
                    printf " ${PINK}󰢮${RESET} %-36s ${PINK}%-16s${RESET} ${GRAY}%s${RESET}\n" "${gpu_name:0:35}" "$gpu_drv" "$gpu_miss"
                else
                    printf " ${PINK}󰢮${RESET} %-36s ${PINK}%s${RESET}\n" "${gpu_name:0:35}" "$gpu_drv"
                fi
            fi
            if [[ -n $npu_name ]]; then
                if [[ -n $npu_miss ]]; then
                    printf " ${PINK}󰓅${RESET} %-36s ${PINK}%-16s${RESET} ${GRAY}%s${RESET}\n" "${npu_name:0:35}" "$npu_drv" "$npu_miss"
                else
                    printf " ${PINK}󰓅${RESET} %-36s ${PINK}%s${RESET}\n" "${npu_name:0:35}" "$npu_drv"
                fi
            fi
            if [[ -n $net_name ]]; then
                if [[ -n $net_miss ]]; then
                    printf " ${PINK}󰤨${RESET} %-36s ${PINK}%-16s${RESET} ${GRAY}%s${RESET}\n" "${net_name:0:35}" "$net_drv" "$net_miss"
                else
                    printf " ${PINK}󰤨${RESET} %-36s ${PINK}%s${RESET}\n" "${net_name:0:35}" "$net_drv"
                fi
            fi
            [[ -n $audio_name ]] && printf " ${PINK}󰥲${RESET} %-36s ${PINK}%s${RESET}\n" "${audio_name:0:35}" "$audio_drv"
            if [[ -n $bt_info ]]; then
                if [[ -n $bt_miss ]]; then
                    printf " ${PINK}󰂯${RESET} %-36s ${PINK}%-16s${RESET} ${GRAY}%s${RESET}\n" "Bluetooth" "$bt_info" "$bt_miss"
                else
                    printf " ${PINK}󰂯${RESET} %-36s ${PINK}%s${RESET}\n" "Bluetooth" "$bt_info"
                fi
            fi
            if [[ -n $fw_miss ]]; then
                printf " ${PINK}󰓅${RESET} %-36s ${PINK}%s${RESET}\n" "System Firmware" "$fw_miss"
            else
                printf " ${PINK}󰓅${RESET} %-36s ${PINK}%s${RESET}\n" "System Firmware" "installed"
            fi
            for entry in "${other_entries[@]}"; do
                IFS='|' read -r o_type o_model o_miss <<<"$entry"
                if [[ -n $o_miss ]]; then
                    printf " ${PINK}󰓅${RESET} %-36s ${PINK}%s${RESET}\n" "$o_type" "$o_miss"
                else
                    printf " ${PINK}󰓅${RESET} %-36s ${PINK}%s${RESET}\n" "$o_type" "$o_model"
                fi
            done
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            [[ -n $ml_status ]] && printf " ${PINK}󰓅${RESET} %-36s ${GRAY}%s${RESET}\n" "Multilib" "$ml_status"
            [[ -n $rb_status ]] && printf " ${PINK}󰓅${RESET} %-36s ${GRAY}%s${RESET}\n" "Resizable BAR" "$rb_status"
            if [[ -n $kernel_warn ]]; then
                printf " ${PINK}󰅸${RESET} ${PINK}%s${RESET}\n" "$kernel_warn"
            fi

            local conflicts=$(bash "$driver_script" --conflicts)
            if [[ -n $conflicts ]]; then
                echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                while IFS= read -r conflict; do
                    printf " ${PINK}󰅸${RESET} ${PINK}%s${RESET}\n" "$conflict"
                done <<<"$conflicts"
            fi
            local services=$(bash "$driver_script" --services)
            if [[ -n $services ]]; then
                while IFS= read -r svc; do
                    printf " ${PINK}󰓅${RESET} ${PINK}%s${RESET}\n" "$svc"
                done <<<"$services"
            fi

            if [[ $has_npu == true ]]; then
                local intel_env=$(bash "$driver_script" --sys-ai-env)
                IFS='|' read -r ie ne ae <<<"$intel_env"
                local iv="${ie#intel:}"
                if [[ $iv != "not_set" ]]; then
                    printf " ${PINK}󰓅${RESET} %-36s ${SUCCESS}%s${RESET}\n" "NPU" "$iv"
                fi
            fi
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"

            if [[ $missing_count -gt 0 ]]; then
                rx_log "warn" "$missing_count component(s) have missing drivers"
                rx_log "warn" "Missing: ${PINK}$tagged_missing${RESET}"
                rx_log "info" "Run ${PINK}retro --driver install${RESET} to fix"
            fi
            echo ""
            ;;

        "install")
            check_dep "lspci" "pciutils" || return 1

            local first_pass
            first_pass=$(bash "$driver_script" --install)
            [[ -z $first_pass ]] && rx_log "error" "Failed to scan for missing drivers" && return 1

            local missing_pkgs=""

            while IFS= read -r line; do
                [[ -z $line ]] && continue
                case "$line" in
                    ALL_DRIVERS_INSTALLED)
                        rx_log "success" "All drivers are already installed!"
                        return 0
                        ;;
                    MISSING:*)
                        missing_pkgs="${line#MISSING:}"
                        ;;
                esac
            done <<<"$first_pass"

            [[ -z $missing_pkgs ]] && rx_log "error" "No packages found to install" && return 1

            local tagged=$(_tag_missing "$missing_pkgs")
            rx_log "info" "The following packages will be installed: ${PINK}$tagged${RESET}"

            if [[ $SKIP_PROMPT != true ]]; then
                rx_log "info" "Continue? [y/N] "
                read -r confirm
                if [[ ! $confirm =~ ^[Yy]$ ]]; then
                    rx_log "info" "Installation cancelled."
                    return 0
                fi
            fi

            bash "$driver_script" --install-confirmed
            local install_exit=$?

            if [[ $install_exit -eq 0 ]]; then
                local verify=$(bash "$driver_script" --verify "$missing_pkgs")
                if [[ $verify == "ALL_VERIFIED" ]]; then
                    rx_log "success" "All drivers have been installed and verified"
                else
                    local still="${verify#STILL_MISSING:}"
                    rx_log "warn" "Some packages still missing after install: ${PINK}$still${RESET}"
                fi
            else
                rx_log "error" "Installation failed"
            fi
            ;;

        "env")
            local ai_env
            ai_env=$(bash "$driver_script" --sys-ai-env)
            [[ -z $ai_env ]] && rx_log "error" "Failed to read AI environment variables" && return 1
            IFS='|' read -r intel_env nvidia_env amd_env <<<"$ai_env"

            local intel_val="${intel_env#intel:}"
            local nvidia_val="${nvidia_env#nvidia:}"
            local amd_val="${amd_env#amd:}"

            local zes
            zes=$(grep "^ZES_ENABLE_SYSMAN=" /etc/environment 2>/dev/null | cut -d= -f2)
            : ${zes:="not_set"}

            echo -e "\n ${PINK}󰓅 AI Environment Variables${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────"
            printf " ${PINK}󰏗${RESET} %-22s ${PINK}%s${RESET}\n" "ONEAPI_DEVICE_SELECTOR" "${intel_val}"
            printf " ${PINK}󰏗${RESET} %-22s ${PINK}%s${RESET}\n" "ZES_ENABLE_SYSMAN" "${zes}"
            printf " ${PINK}󰏗${RESET} %-22s ${PINK}%s${RESET}\n" "CUDA_VISIBLE_DEVICES" "${nvidia_val}"
            printf " ${PINK}󰏗${RESET} %-22s ${PINK}%s${RESET}\n" "HSA_OVERRIDE_GFX_VERSION" "${amd_val}"
            echo -e " ${PINK}󰇝${MUTE} ────────────────────────────────────────${RESET}\n"
            ;;

        "info")
            check_dep "lspci" "pciutils" || return 1
            [[ -z $flag ]] && rx_log "info" "Usage: retro --driver info <keyword>" && return 1

            local info_data=$(bash "$driver_script" --info "$flag")
            if [[ $info_data == "NOT_FOUND" ]]; then
                rx_log "error" "No device matching '${flag}' found"
                return 1
            fi

            local dev_name="" modules="" driver=""
            local details=()

            while IFS= read -r line; do
                IFS='|' read -r key val <<<"$line"
                case "$key" in
                    DEVICE) dev_name="$val" ;;
                    MODULES) modules="$val" ;;
                    DRIVER) driver="$val" ;;
                    DETAIL) details+=("$val") ;;
                esac
            done <<<"$info_data"

            echo -e "\n ${PINK}󰢮 Device Info: ${dev_name}${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            [[ -n $driver ]] && printf " ${PINK}󰓡${RESET} ${PINK}Driver:${RESET} %s\n" "$driver"
            [[ -n $modules ]] && printf " ${PINK}󰓅${RESET} ${PINK}Modules:${RESET} %s\n" "$modules"
            for detail in "${details[@]}"; do
                echo -e "   ${GRAY}${detail}${RESET}"
            done
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
            ;;

        "switch")
            local target="${2,,}"
            [[ -z $target ]] && rx_log "info" "Usage: retro --driver switch [xe|i915]" && return 1

            local device_id=$(bash "$driver_script" --device-id)
            local current=$(bash "$driver_script" --current-driver)
            local bl_info=$(bash "$driver_script" --bootloader)
            IFS='|' read -r bl_type bl_file bl_key bl_cmd <<<"$bl_info"

            echo -e "\n ${PINK}󰢮 Kernel Driver Switch${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            printf " ${PINK}󰏗${RESET} ${PINK}Bootloader:${RESET} %s\n" "${bl_type^^}"
            printf " ${PINK}󰏗${RESET} ${PINK}Device ID:${RESET} %s\n" "$device_id"
            printf " ${PINK}󰏗${RESET} ${PINK}Current driver:${RESET} %s\n" "$current"
            printf " ${PINK}󰏗${RESET} ${PINK}Target driver:${RESET} %s\n" "${target^^}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"

            if [[ $target != "xe" && $target != "i915" ]]; then
                rx_log "error" "Unknown driver: ${target}. Use xe or i915"
                return 1
            fi

            if [[ $target == "xe" ]]; then
                if ! _kernel_version_ge 6 8; then
                    rx_log "error" "Kernel 6.8+ required for xe driver. Current: $(uname -r)"
                    return 1
                fi
                if [[ $current == "xe" ]]; then
                    rx_log "success" "Already using xe driver"
                    return 0
                fi
            fi

            if [[ $SKIP_PROMPT != true ]]; then
                rx_log "info" "Continue? [y/N] "
                read -r confirm
                [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Aborted." && return 0
            fi

            local result=$(bash "$driver_script" --switch "$target")
            IFS='|' read -r status driver_name dev_id extra <<<"$result"

            case "$status" in
                SUCCESS)
                    rx_log "success" "Switched to ${driver_name} driver for device ${dev_id}"
                    rx_log "warn" "Reboot required for changes to take effect"
                    ;;
                ALREADY)
                    rx_log "success" "Already using ${driver_name} driver"
                    ;;
                ERROR)
                    case "$driver_name" in
                        bootloader_not_detected) rx_log "error" "Could not detect bootloader" ;;
                        kernel_too_old) rx_log "error" "Kernel 6.8+ required for xe driver" ;;
                    esac
                    return 1
                    ;;
            esac
            echo ""
            ;;

        "modules")
            local mod_list=("${@:2}")
            local mod_data=$(bash "$driver_script" --modules "${mod_list[@]}")

            echo -e "\n ${PINK}󰓅 Kernel Module Parameters${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"

            local current_mod=""
            while IFS= read -r line; do
                IFS='|' read -r key p_name p_val <<<"$line"
                case "$key" in
                    MODULE)
                        current_mod="$p_name"
                        printf " ${PINK}󰓅${RESET} ${PINK}%s${RESET}\n" "$current_mod"
                        ;;
                    PARAM)
                        printf "   ${GRAY}%-24s${RESET} %s\n" "$p_name" "${p_val:-<empty>}"
                        ;;
                esac
            done <<<"$mod_data"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
            ;;

        "modules-set")
            local module="$2"
            local param="$3"
            local value="$4"
            [[ -z $module || -z $param || -z $value ]] && rx_log "info" "Usage: retro --driver modules-set <module> <param> <value>" && return 1

            local result=$(bash "$driver_script" --modules-set "$module" "$param" "$value")
            IFS='|' read -r status mod_name param_val <<<"$result"

            if [[ $status == "SET" ]]; then
                rx_log "success" "Set ${mod_name} ${param_val}"
                rx_log "warn" "Reboot or run: sudo modprobe -r ${mod_name} && sudo modprobe ${mod_name}"
            else
                rx_log "error" "Failed to set module parameter"
            fi
            ;;

        "conflicts")
            local conflicts=$(bash "$driver_script" --conflicts)

            echo -e "\n ${PINK}󰅸 Driver Conflict Check${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"

            if [[ -z $conflicts ]]; then
                printf " ${SUCCESS}󰄪${RESET} ${SUCCESS}No conflicts detected${RESET}\n"
            else
                while IFS= read -r conflict; do
                    printf " ${PINK}󰅸${RESET} ${PINK}%s${RESET}\n" "$conflict"
                done <<<"$conflicts"
            fi
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
            ;;

        "fix-conflicts")
            local conflicts=$(bash "$driver_script" --conflicts)

            if [[ -z $conflicts ]]; then
                rx_log "success" "No conflicts to fix"
                return 0
            fi

            echo -e "\n ${PINK}󰅸 Fixing Driver Conflicts${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"

            while IFS= read -r conflict; do
                if echo "$conflict" | grep -q "xf86-video-intel"; then
                    rx_log "info" "Removing xf86-video-intel..."
                    sudo pacman -Rns --noconfirm xf86-video-intel 2>&1
                elif echo "$conflict" | grep -q "xf86-video-nouveau"; then
                    rx_log "info" "Blacklisting nouveau..."
                    echo "blacklist nouveau" | sudo tee /etc/modprobe.d/nouveau-blacklist.conf >/dev/null
                    sudo pacman -Rns --noconfirm xf86-video-nouveau 2>&1
                elif echo "$conflict" | grep -q "xf86-video-amdgpu"; then
                    rx_log "info" "Removing xf86-video-amdgpu (use modesetting)..."
                    sudo pacman -Rns --noconfirm xf86-video-amdgpu 2>&1
                elif echo "$conflict" | grep -q "vulkan-anv"; then
                    rx_log "info" "Removing duplicate vulkan-anv..."
                    sudo pacman -Rns --noconfirm vulkan-anv 2>&1
                fi
            done <<<"$conflicts"

            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            rx_log "success" "Conflicts resolved. Reboot recommended."
            echo ""
            ;;

        "optimus")
            local dual_info=$(bash "$driver_script" --dual-gpu)
            if [[ $dual_info != "intel-nvidia"* ]]; then
                rx_log "error" "No Intel+NVIDIA dual GPU setup detected"
                return 1
            fi

            IFS='|' read -r setup intel_model nvidia_model intel_drv nvidia_drv <<<"$dual_info"

            echo -e "\n ${PINK}󰢮 NVIDIA Optimus Setup${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            printf " ${PINK}󰢮${RESET} ${PINK}Intel GPU:${RESET} %s\n" "${intel_model}"
            printf " ${PINK}󰢮${RESET} ${PINK}NVIDIA GPU:${RESET} %s\n" "${nvidia_model}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"

            local result=$(bash "$driver_script" --optimus)
            IFS='|' read -r status <<<"$result"

            case "$status" in
                ALREADY_INSTALLED)
                    rx_log "success" "Optimus packages already installed"
                    ;;
                INSTALL_SUCCESS)
                    rx_log "success" "Optimus packages installed. Use prime-run <app> for GPU offloading"
                    ;;
                INSTALL_FAILED)
                    rx_log "error" "Failed to install Optimus packages"
                    return 1
                    ;;
                MISSING:*)
                    local missing="${status#MISSING:}"
                    rx_log "info" "Will install: ${PINK}$missing${RESET}"
                    if [[ $SKIP_PROMPT != true ]]; then
                        rx_log "info" "Continue? [y/N] "
                        read -r confirm
                        [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Aborted." && return 0
                    fi
                    bash "$driver_script" --optimus
                    ;;
            esac
            echo ""
            ;;

        "hybrid-amd")
            local dual_info=$(bash "$driver_script" --dual-gpu)
            if [[ $dual_info != "intel-amd"* ]]; then
                rx_log "error" "No Intel+AMD dual GPU setup detected"
                return 1
            fi

            IFS='|' read -r setup intel_model amd_model intel_drv amd_drv <<<"$dual_info"

            echo -e "\n ${PINK}󰢮 AMD Hybrid Graphics Setup${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            printf " ${PINK}󰢮${RESET} ${PINK}Intel GPU:${RESET} %s\n" "${intel_model}"
            printf " ${PINK}󰢮${RESET} ${PINK}AMD GPU:${RESET} %s\n" "${amd_model}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"

            local result=$(bash "$driver_script" --hybrid-amd)
            IFS='|' read -r status <<<"$result"

            case "$status" in
                ALREADY_INSTALLED)
                    rx_log "success" "AMD hybrid packages already installed"
                    ;;
                INSTALL_SUCCESS)
                    rx_log "success" "AMD hybrid packages installed. Use DRI_PRIME=1 <app> for GPU offloading"
                    ;;
                INSTALL_FAILED)
                    rx_log "error" "Failed to install AMD hybrid packages"
                    return 1
                    ;;
                MISSING:*)
                    local missing="${status#MISSING:}"
                    rx_log "info" "Will install: ${PINK}$missing${RESET}"
                    if [[ $SKIP_PROMPT != true ]]; then
                        rx_log "info" "Continue? [y/N] "
                        read -r confirm
                        [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Aborted." && return 0
                    fi
                    bash "$driver_script" --hybrid-amd
                    ;;
            esac
            echo ""
            ;;

        "gpu-status")
            local gpu_data=$(bash "$driver_script" --gpu-status)

            if [[ $gpu_data == "NO_GPU" ]]; then
                rx_log "error" "No GPU detected"
                return 1
            fi

            echo -e "\n ${PINK}󰢮 GPU Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"

            while IFS= read -r line; do
                IFS='|' read -r state vendor model driver <<<"$line"
                if [[ $state == "ACTIVE" ]]; then
                    printf " ${PINK}󰢮${RESET} %s  %s\n" "${model}" "${driver}"
                elif [[ $state == "INACTIVE" ]]; then
                    printf " ${GRAY}󰢮${RESET} %s  %s\n" "${model}" "${driver}"
                fi
            done <<<"$gpu_data"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
            ;;

        "profile")
            local profile="${2,,}"
            [[ -z $profile ]] && rx_log "info" "Usage: retro --driver profile [gaming|ai|minimal|workstation]" && return 1

            local pkgs=$(bash "$driver_script" --profile "$profile")
            [[ -z $pkgs ]] && rx_log "error" "Unknown profile: ${profile}" && return 1

            local missing=$(_get_missing_local "$pkgs")
            if [[ -z $missing ]]; then
                rx_log "success" "All ${profile} profile packages already installed"
                return 0
            fi

            local tagged=$(_tag_missing "$missing")
            echo -e "\n ${PINK}󰓅 ${profile^} Profile${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
            printf " ${PINK}󰏦${RESET} Packages %s\n" "${pkgs}"
            printf " ${PINK}󰄪${RESET} Missing %s\n" "$tagged"
            echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"

            rx_log "info" "Continue? [y/N] "
            read -r confirm
            [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Aborted." && return 0

            local helper="yay"
            command -v paru >/dev/null 2>&1 && helper="paru"
            if command -v "$helper" >/dev/null 2>&1; then
                $helper -S --needed --noconfirm $missing 2>&1
            else
                sudo pacman -S --needed --noconfirm $missing 2>&1
            fi

            if [[ $? -eq 0 ]]; then
                rx_log "success" "${profile^} profile packages installed successfully"
            else
                rx_log "error" "Failed to install some packages"
            fi
            echo ""
            ;;

        "firmware")
            local subcmd="${2,,}"
            [[ -z $subcmd ]] && rx_log "info" "Usage: retro --driver firmware [scan|install|status]" && return 1

            case "$subcmd" in
                scan)
                    local fw_data=$(bash "$driver_script" --firmware-scan)
                    if [[ $fw_data == *"ERROR"* ]]; then
                        rx_log "info" "fwupdmgr is not installed. Would you like to install it? [y/N] "
                        read -r confirm
                        if [[ $confirm =~ ^[Yy]$ ]]; then
                            local pkg_helper=$(bash "$RETRO_DIR/scripts/variable_core.sh" --get PKG_HELPER 2>/dev/null)
                            : ${pkg_helper:="yay"}
                            if command -v "$pkg_helper" >/dev/null 2>&1; then
                                $pkg_helper -S --needed --noconfirm fwupd 2>&1
                            else
                                sudo pacman -S --needed --noconfirm fwupd 2>&1
                            fi
                            if [[ $? -eq 0 ]]; then
                                rx_log "success" "fwupd installed successfully"
                            else
                                rx_log "error" "Failed to install fwupd"
                                return 1
                            fi
                        else
                            rx_log "info" "Aborted."
                            return 0
                        fi
                        fw_data=$(bash "$driver_script" --firmware-scan)
                    fi

                    IFS='|' read -r key dev_count upd_count <<<"$fw_data"

                    echo -e "\n ${PINK}󰓅 Firmware Updates${RESET}"
                    echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                    printf " ${PINK}󰏗${RESET} Devices: ${PINK}%s${RESET}\n" "$dev_count"
                    printf " ${PINK}󰏗${RESET} Updates: ${PINK}%s${RESET}\n" "$upd_count"
                    echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"

                    if [[ $upd_count -gt 0 ]]; then
                        rx_log "warn" "Firmware updates available. Run ${PINK}retro --driver firmware install${RESET}"
                    else
                        rx_log "success" "No firmware updates available"
                    fi
                    echo ""
                    ;;

                install)
                    local fw_data=$(bash "$driver_script" --firmware-install)
                    if [[ $fw_data == *"ERROR"* ]]; then
                        rx_log "info" "fwupdmgr is not installed. Would you like to install it? [y/N] "
                        read -r confirm
                        if [[ $confirm =~ ^[Yy]$ ]]; then
                            local pkg_helper=$(bash "$RETRO_DIR/scripts/variable_core.sh" --get PKG_HELPER 2>/dev/null)
                            : ${pkg_helper:="yay"}
                            if command -v "$pkg_helper" >/dev/null 2>&1; then
                                $pkg_helper -S --needed --noconfirm fwupd 2>&1
                            else
                                sudo pacman -S --needed --noconfirm fwupd 2>&1
                            fi
                            if [[ $? -eq 0 ]]; then
                                rx_log "success" "fwupd installed successfully"
                            else
                                rx_log "error" "Failed to install fwupd"
                                return 1
                            fi
                        else
                            rx_log "info" "Aborted."
                            return 0
                        fi
                        fw_data=$(bash "$driver_script" --firmware-install)
                    fi

                    if [[ $fw_data == "NO_UPDATES" ]]; then
                        rx_log "success" "No firmware updates available"
                        return 0
                    fi

                    if [[ $fw_data == *"INSTALL_SUCCESS"* ]]; then
                        rx_log "success" "Firmware updates installed. Reboot to apply."
                    else
                        rx_log "error" "Firmware update failed"
                    fi
                    ;;

                status)
                    local fw_data=$(bash "$driver_script" --firmware-status)
                    if [[ $fw_data == *"ERROR"* ]]; then
                        rx_log "info" "fwupdmgr is not installed. Would you like to install it? [y/N] "
                        read -r confirm
                        if [[ $confirm =~ ^[Yy]$ ]]; then
                            local pkg_helper=$(bash "$RETRO_DIR/scripts/variable_core.sh" --get PKG_HELPER 2>/dev/null)
                            : ${pkg_helper:="yay"}
                            if command -v "$pkg_helper" >/dev/null 2>&1; then
                                $pkg_helper -S --needed --noconfirm fwupd 2>&1
                            else
                                sudo pacman -S --needed --noconfirm fwupd 2>&1
                            fi
                            if [[ $? -eq 0 ]]; then
                                rx_log "success" "fwupd installed successfully"
                            else
                                rx_log "error" "Failed to install fwupd"
                                return 1
                            fi
                        else
                            rx_log "info" "Aborted."
                            return 0
                        fi
                        fw_data=$(bash "$driver_script" --firmware-status)
                    fi

                    IFS='|' read -r key daemon_ver dev_count <<<"$fw_data"

                    echo -e "\n ${PINK}󰓅 Firmware Status${RESET}"
                    echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────"
                    printf " ${PINK}󰏗${RESET} Daemon: ${PINK}%s${RESET}\n" "$daemon_ver"
                    printf " ${PINK}󰏗${RESET} Devices: ${PINK}%s${RESET}\n" "$dev_count"
                    echo -e " ${PINK}󰇝${MUTE} ──────────────────────────────────────────────────${RESET}\n"
                    ;;
            esac
            ;;

        *) rx_log "info" "Usage: retro --driver [status|install|env|info|switch|modules|modules-set|conflicts|fix-conflicts|optimus|hybrid-amd|gpu-status|profile|firmware] [--yes]" ;;
    esac
}

register_command "TOOLS" "-drv|--driver" "Hardware driver manager for Arch Linux (Gaming + AI)" "cmd_driver"
