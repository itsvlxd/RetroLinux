#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/helpers.sh"

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

            rx_table_header "󰢮" "Driver Status"
            [[ -n $cpu_name ]] && rx_table_row "󰻠" "${cpu_name:0:35}" "$cpu_info" "$PINK" "36"
            if [[ -n $gpu_name ]]; then
                if [[ -n $gpu_miss ]]; then
                    printf " ${PINK}󰢮${RESET} %-36s ${PINK}%-16s${RESET} ${GRAY}%s${RESET}\n" "${gpu_name:0:35}" "$gpu_drv" "$gpu_miss"
                else
                    rx_table_row "󰢮" "${gpu_name:0:35}" "$gpu_drv" "$PINK" "36"
                fi
            fi
            if [[ -n $npu_name ]]; then
                if [[ -n $npu_miss ]]; then
                    printf " ${PINK}󰓅${RESET} %-36s ${PINK}%-16s${RESET} ${GRAY}%s${RESET}\n" "${npu_name:0:35}" "$npu_drv" "$npu_miss"
                else
                    rx_table_row "󰓅" "${npu_name:0:35}" "$npu_drv" "$PINK" "36"
                fi
            fi
            if [[ -n $net_name ]]; then
                if [[ -n $net_miss ]]; then
                    printf " ${PINK}󰤨${RESET} %-36s ${PINK}%-16s${RESET} ${GRAY}%s${RESET}\n" "${net_name:0:35}" "$net_drv" "$net_miss"
                else
                    rx_table_row "󰤨" "${net_name:0:35}" "$net_drv" "$PINK" "36"
                fi
            fi
            [[ -n $audio_name ]] && rx_table_row "󰥲" "${audio_name:0:35}" "$audio_drv" "$PINK" "36"
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
                    rx_table_row "󰓅" "$o_type" "$o_miss" "$PINK" "36"
                else
                    rx_table_row "󰓅" "$o_type" "$o_model" "$PINK" "36"
                fi
            done
            rx_table_separator
            [[ -n $ml_status ]] && rx_table_row_gray "󰓅" "Multilib" "$ml_status" "36"
            [[ -n $rb_status ]] && rx_table_row_gray "󰓅" "Resizable BAR" "$rb_status" "36"
            if [[ -n $kernel_warn ]]; then
                rx_table_simple "󰅸" "$kernel_warn" "$PINK"
            fi

            local conflicts=$(bash "$driver_script" --conflicts)
            if [[ -n $conflicts ]]; then
                rx_table_separator
                while IFS= read -r conflict; do
                    rx_table_simple "󰅸" "$conflict" "$PINK"
                done <<<"$conflicts"
            fi
            local services=$(bash "$driver_script" --services)
            if [[ -n $services ]]; then
                while IFS= read -r svc; do
                    rx_table_simple "󰓅" "$svc" "$PINK"
                done <<<"$services"
            fi

            if [[ $has_npu == true ]]; then
                local intel_env=$(bash "$driver_script" --sys-ai-env)
                IFS='|' read -r ie ne ae <<<"$intel_env"
                local iv="${ie#intel:}"
                if [[ $iv != "not_set" ]]; then
                    rx_table_row "󰓅" "NPU" "$iv" "$SUCCESS" "36"
                fi
            fi
            rx_table_separator
            rx_table_spacer

            if [[ $missing_count -gt 0 ]]; then
                rx_log "warn" "$missing_count component(s) have missing drivers"
                rx_log "warn" "Missing: ${PINK}$tagged_missing${RESET}"
                rx_log "info" "Run ${PINK}retro driver install${RESET} to fix"
            fi
            rx_table_spacer
            ;;

        "install")
            check_dep "lspci" "pciutils" || return 1

            if [[ $flag == "--yes" || $flag == "-y" ]]; then
                export SKIP_PROMPT=true
            fi

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

            if [[ $SKIP_PROMPT != "true" ]]; then
                rx_log "info" "Continue? ${PINK}[y/N]${RESET}: "
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
            [[ -z $ai_env ]] && rx_log "error" "Failed to read GPU compute environment" && return 1
            IFS='|' read -r intel_env nvidia_env amd_env <<<"$ai_env"

            local intel_val="${intel_env#intel:}"
            local nvidia_val="${nvidia_env#nvidia:}"
            local amd_val="${amd_env#amd:}"

            local zes
            zes=$(grep "^ZES_ENABLE_SYSMAN=" /etc/environment 2>/dev/null | cut -d= -f2)
            : ${zes:="not_set"}

            rx_table_header "󰓅" "GPU Compute Environment"
            rx_table_row "󰏗" "ONEAPI_DEVICE_SELECTOR" "${intel_val}" "$PINK" "22"
            rx_table_row "󰏗" "ZES_ENABLE_SYSMAN" "${zes}" "$PINK" "22"
            rx_table_row "󰏗" "CUDA_VISIBLE_DEVICES" "${nvidia_val}" "$PINK" "22"
            rx_table_row "󰏗" "HSA_OVERRIDE_GFX_VERSION" "${amd_val}" "$PINK" "22"
            rx_table_separator
            rx_table_spacer
            ;;

        "info")
            check_dep "lspci" "pciutils" || return 1
            [[ -z $flag ]] && rx_log "info" "Usage: retro driver info <keyword>" && return 1

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

            rx_table_header "󰢮" "Device Info: ${dev_name}"
            [[ -n $driver ]] && rx_table_simple "󰓡" "Driver: $driver" "$PINK"
            [[ -n $modules ]] && rx_table_simple "󰓅" "Modules: $modules" "$PINK"
            for detail in "${details[@]}"; do
                rx_table_simple "$detail" ""
            done
            rx_table_separator
            rx_table_spacer
            ;;

        "switch")
            local target="${2,,}"
            [[ -z $target ]] && rx_log "info" "Usage: retro driver switch [xe|i915]" && return 1

            local device_id=$(bash "$driver_script" --device-id)
            local current=$(bash "$driver_script" --current-driver)
            local bl_info=$(bash "$driver_script" --bootloader)
            IFS='|' read -r bl_type bl_file bl_key bl_cmd <<<"$bl_info"

            rx_table_header "󰢮" "Kernel Driver Switch"
            rx_table_simple "󰏗" "Bootloader: ${bl_type^^}" "$PINK"
            rx_table_simple "󰏗" "Device ID: $device_id"
            printf " ${PINK}󰏗${RESET} ${PINK}Current driver:${RESET} %s\n" "$current"
            printf " ${PINK}󰏗${RESET} ${PINK}Target driver:${RESET} %s\n" "${target^^}"
            rx_table_separator

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

            if [[ $SKIP_PROMPT != "true" ]]; then
                rx_log "info" "Continue? ${PINK}[y/N]${RESET}: "
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
            rx_table_spacer
            ;;

        "modules")
            local mod_list=("${@:2}")
            local mod_data=$(bash "$driver_script" --modules "${mod_list[@]}")

            rx_table_header "󰓅" "Kernel Module Parameters"

            local current_mod=""
            while IFS= read -r line; do
                IFS='|' read -r key p_name p_val <<<"$line"
                case "$key" in
                    MODULE)
                        current_mod="$p_name"
                        rx_table_simple "󰓅" "$current_mod" "$PINK"
                        ;;
                    PARAM)
                        rx_table_row_gray "󰓅" "$p_name" "${p_val:-<empty>}" "24"
                        ;;
                esac
            done <<<"$mod_data"
            rx_table_separator
            ;;

        "modules-set")
            local module="$2"
            local param="$3"
            local value="$4"
            [[ -z $module || -z $param || -z $value ]] && rx_log "info" "Usage: retro driver modules-set <module> <param> <value>" && return 1

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

            rx_table_header "󰅸" "Driver Conflict Check"

            if [[ -z $conflicts ]]; then
                rx_table_simple "󰄪" "No conflicts detected" "$SUCCESS"
            else
                while IFS= read -r conflict; do
                    rx_table_simple "󰅸" "$conflict" "$PINK"
                done <<<"$conflicts"
            fi
            rx_table_separator
            ;;

        "fix-conflicts")
            local conflicts=$(bash "$driver_script" --conflicts)

            if [[ -z $conflicts ]]; then
                rx_log "success" "No conflicts to fix"
                return 0
            fi

            rx_table_header "󰅸" "Fixing Driver Conflicts"

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

            rx_table_separator
            rx_log "success" "Conflicts resolved. Reboot recommended."
            rx_table_spacer
            ;;

        "optimus")
            local dual_info=$(bash "$driver_script" --dual-gpu)
            if [[ $dual_info != "intel-nvidia"* ]]; then
                rx_log "error" "No Intel+NVIDIA dual GPU setup detected"
                return 1
            fi

            IFS='|' read -r setup intel_model nvidia_model intel_drv nvidia_drv <<<"$dual_info"

            rx_table_header "󰢮" "NVIDIA Optimus Setup"
            rx_table_simple "󰢮" "Intel GPU: ${intel_model}" "$PINK"
            rx_table_simple "󰢮" "NVIDIA GPU: ${nvidia_model}" "$PINK"
            rx_table_separator

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
                    if [[ $SKIP_PROMPT != "true" ]]; then
                        rx_log "info" "Continue? ${PINK}[y/N]${RESET}: "
                        read -r confirm
                        [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Aborted." && return 0
                    fi
                    bash "$driver_script" --optimus
                    ;;
            esac
            rx_table_spacer
            ;;

        "hybrid-amd")
            local dual_info=$(bash "$driver_script" --dual-gpu)
            if [[ $dual_info != "intel-amd"* ]]; then
                rx_log "error" "No Intel+AMD dual GPU setup detected"
                return 1
            fi

            IFS='|' read -r setup intel_model amd_model intel_drv amd_drv <<<"$dual_info"

            rx_table_header "󰢮" "AMD Hybrid Graphics Setup"
            rx_table_simple "󰢮" "Intel GPU: ${intel_model}" "$PINK"
            rx_table_simple "󰢮" "AMD GPU: ${amd_model}" "$PINK"
            rx_table_separator

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
                    if [[ $SKIP_PROMPT != "true" ]]; then
                        rx_log "info" "Continue? ${PINK}[y/N]${RESET}: "
                        read -r confirm
                        [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Aborted." && return 0
                    fi
                    bash "$driver_script" --hybrid-amd
                    ;;
            esac
            rx_table_spacer
            ;;

        "gpu-status")
            local gpu_data=$(bash "$driver_script" --gpu-status)

            if [[ $gpu_data == "NO_GPU" ]]; then
                rx_log "error" "No GPU detected"
                return 1
            fi

            rx_table_header "󰢮" "GPU Status"

            while IFS= read -r line; do
                IFS='|' read -r state vendor model driver <<<"$line"
                if [[ $state == "ACTIVE" ]]; then
                    rx_table_simple "󰢮" "$model ($driver)" "$PINK"
                elif [[ $state == "INACTIVE" ]]; then
                    rx_table_simple "󰢮" "$model ($driver)" "$GRAY"
                fi
            done <<<"$gpu_data"
            rx_table_separator
            ;;

        "profile")
            local profile="${2,,}"
            [[ -z $profile ]] && rx_log "info" "Usage: retro driver profile [gaming|ai|minimal|workstation]" && return 1

            local pkgs=$(bash "$driver_script" --profile "$profile")
            [[ -z $pkgs ]] && rx_log "error" "Unknown profile: ${profile}" && return 1

            local missing=$(_get_missing_local "$pkgs")
            if [[ -z $missing ]]; then
                rx_log "success" "All ${profile} profile packages already installed"
                return 0
            fi

            local tagged=$(_tag_missing "$missing")
            rx_table_header "󰓅" "${profile^} Profile"
            rx_table_simple "󰏦" "Packages: ${pkgs}" "$PINK"
            rx_table_simple "󰄪" "Missing: $tagged" "$PINK"
            rx_table_separator

            rx_log "info" "Continue? ${PINK}[y/N]${RESET}: "
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
            rx_table_spacer
            ;;

        "firmware")
            local subcmd="${2,,}"
            [[ -z $subcmd ]] && rx_log "info" "Usage: retro driver firmware [scan|install|status]" && return 1

            case "$subcmd" in
                scan)
                    local fw_data=$(bash "$driver_script" --firmware-scan)
                    if [[ $fw_data == *"ERROR"* ]]; then
                        rx_log "info" "fwupdmgr is not installed. Would you like to install it? ${PINK}[y/N]${RESET}: "
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

                    rx_table_header "󰓅" "Firmware Updates"
                    rx_table_row "󰏗" "Devices:" "$dev_count" "$PINK" "20"
                    rx_table_row "󰏗" "Updates:" "$upd_count" "$PINK" "20"
                    rx_table_separator

                    if [[ $upd_count -gt 0 ]]; then
                        rx_log "warn" "Firmware updates available. Run ${PINK}retro driver firmware install${RESET}"
                    else
                        rx_log "success" "No firmware updates available"
                    fi
                    rx_table_spacer
                    ;;

                install)
                    local fw_data=$(bash "$driver_script" --firmware-install)
                    if [[ $fw_data == *"ERROR"* ]]; then
                        rx_log "info" "fwupdmgr is not installed. Would you like to install it? ${PINK}[y/N]${RESET}: "
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
                        rx_log "info" "fwupdmgr is not installed. Would you like to install it? ${PINK}[y/N]${RESET}: "
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

                    rx_table_header "󰓅" "Firmware Status"
                    rx_table_row "󰏗" "Daemon:" "$daemon_ver" "$PINK" "20"
                    rx_table_row "󰏗" "Devices:" "$dev_count" "$PINK" "20"
                    rx_table_separator
                    ;;
            esac
            ;;

        hypr | hyprenv)
            local force_vendor="$2"
            local hypr_result=$(bash "$driver_script" --hypr "$force_vendor")

            local result_type=$(echo "$hypr_result" | grep -oP "result=\K[^|]+")
            local gpu_type=$(echo "$hypr_result" | grep -oP "type=\K[^|]+")

            if [[ $result_type == "success" ]]; then
                rx_log "success" "Generated ${gpu_type^^} env.conf"
            elif [[ $result_type == "warn" ]]; then
                rx_log "warn" "No GPU detected, generated generic env.conf"
            fi

            local show_result=$(bash "$driver_script" --hypr-show)
            if echo "$show_result" | grep -q "result=success"; then
                local env_path=$(echo "$show_result" | grep -oP "path=\K[^|]+")
                rx_table_header "󰢮" "Hyprland GPU Environment"
                cat "$env_path" | sed 's/^/ /'
                rx_table_separator
                rx_table_simple "󰈐" "Location: $env_path" "$GRAY"
                rx_table_simple "󰈐" "Source in Hyprland: source = ~/.config/retro/env.conf" "$GRAY"
                rx_table_spacer
            else
                rx_log "error" "env.conf not found. Run: retro driver hypr"
            fi
            ;;

        mkinit)
            local mkinit_result=$(bash "$driver_script" --mkinit)

            if echo "$mkinit_result" | grep -q "result=error"; then
                local reason=$(echo "$mkinit_result" | grep -oP "reason=\K[^|]+")
                if [[ $reason == "mkinit_conf_not_found" ]]; then
                    rx_log "error" "mkinitcpio.conf not found"
                fi
                return 1
            fi

            if echo "$mkinit_result" | grep -q "result=skipped"; then
                rx_log "info" "NVIDIA driver not installed, skipping mkinitcpio config"
                return 0
            fi

            local backup=$(echo "$mkinit_result" | grep -oP "backup=\K[^|]+")
            if [[ -n $backup ]]; then
                rx_log "info" "Backup created: $backup"
            fi

            if echo "$mkinit_result" | grep -q "initramfs_regenerated"; then
                rx_log "info" "Regenerating initramfs..."
            fi

            rx_log "success" "NVIDIA mkinitcpio configured. Reboot to apply."
            ;;

        *)
            rx_help_usage "retro driver <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Scan hardware and report driver status"
            rx_help_cmd "install [--yes|-y]" "Install missing drivers"
            rx_help_cmd "env" "Show GPU compute env (CUDA/ONEAPI/RADV)"
            rx_help_cmd "info <keyword>" "Show detailed device info"
            rx_help_cmd "switch [xe|i915]" "Switch Intel GPU kernel driver"
            rx_help_cmd "modules [names...]" "List kernel module parameters"
            rx_help_cmd "modules-set" "Set a kernel module parameter"
            rx_help_cmd "conflicts" "Check for driver conflicts"
            rx_help_cmd "fix-conflicts" "Auto-resolve driver conflicts"
            rx_help_cmd "optimus" "Setup NVIDIA Optimus dual GPU"
            rx_help_cmd "hybrid-amd" "Setup AMD hybrid graphics"
            rx_help_cmd "gpu-status" "List all detected GPUs"
            rx_help_cmd "profile [name]" "Install driver profile packages"
            rx_help_cmd "firmware" "Manage firmware updates"
            rx_help_cmd "hypr [nvidia|amd|intel]" "Generate Hyprland GPU env"
            rx_help_cmd "mkinit" "Configure mkinitcpio for NVIDIA"
            rx_help_examples
            rx_help_example "retro driver hypr" "Auto-detect GPU and generate env"
            rx_help_example "retro driver hypr nvidia" "Force NVIDIA env generation"
            rx_help_example "retro driver hypr amd" "Force AMD env generation"
            rx_help_example "retro driver hypr intel" "Force Intel env generation"
            rx_help_example "retro driver env" "Show compute environment vars"
            rx_help_example "retro driver gpu-status" "List all detected GPUs"
            rx_help_example "retro driver info nvidia" "Show NVIDIA device details"
            rx_help_example "retro driver mkinit" "Configure NVIDIA in initramfs"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "driver" "Scan hardware, install drivers, and manage kernel modules" "cmd_driver"
