#!/bin/bash

RETRO_DIR="${RETRO_DIR:-$(dirname "$(dirname "$(readlink -f "$0")")")}"
source "$RETRO_DIR/lib/colors.sh"

_is_pkg_installed() {
    pacman -Qq "$1" >/dev/null 2>&1
}

_get_missing() {
    local pkgs="$1"
    local missing=()
    for p in $pkgs; do
        _is_pkg_installed "$p" || missing+=("$p")
    done
    echo "${missing[*]}"
}

_set_env_var() {
    local key="$1"
    local val="$2"
    local env_file="/etc/environment"
    if grep -q "^${key}=" "$env_file" 2>/dev/null; then
        sudo sed -i "s|^${key}=.*|${key}=${val}|" "$env_file"
    else
        echo "${key}=${val}" | sudo tee -a "$env_file" >/dev/null
    fi
}

_kernel_version_ge() {
    local major="$1"
    local minor="$2"
    local kver=$(uname -r | cut -d. -f1,2)
    local k_major=${kver%%.*}
    local k_minor=${kver##*.}
    ((k_major > major || (k_major == major && k_minor >= minor)))
}

_check_multilib() {
    if grep -q '^\[multilib\]' /etc/pacman.conf; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

_check_rebar() {
    if dmesg 2>/dev/null | grep -qi "rebar\|above 4g"; then
        echo "enabled"
    else
        echo "unknown"
    fi
}

_kernel_warnings() {
    local warnings=""
    if ! _kernel_version_ge 6 8; then
        warnings+="kernel < 6.8: Intel Arc xe driver not available, upgrade kernel for full GPU support"
    fi
    echo "$warnings"
}

detect_gpus() {
    local gpus=()
    if ! command -v lspci >/dev/null 2>&1; then
        echo "ERROR:lspci_missing"
        return 1
    fi
    while IFS= read -r line; do
        local pci_id=$(echo "$line" | awk '{print $1}')
        local nn_line=$(lspci -nn -s "$pci_id" 2>/dev/null)
        local vd_pair=$(echo "$nn_line" | grep -oP '\[([0-9a-f]{4}):([0-9a-f]{4})\]' | tr -d '[]')
        local vendor_id="${vd_pair%%:*}"
        local model=$(echo "$nn_line" | sed 's/.*\]://;s/\s*\[[0-9a-f]*:[0-9a-f]*\].*//' | xargs)
        local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        local vendor="unknown"
        case "$vendor_id" in
            10de) vendor="nvidia" ;;
            1002) vendor="amd" ;;
            8086) vendor="intel" ;;
        esac
        gpus+=("${pci_id}|${vendor_id}|${vendor}|${model}|${driver}")
    done < <(lspci | grep -iE "VGA|3D|Display")
    if [[ ${#gpus[@]} -eq 0 ]]; then
        echo "NONE"
        return 1
    fi
    for g in "${gpus[@]}"; do
        echo "$g"
    done
}

detect_cpu() {
    if [[ ! -f /proc/cpuinfo ]]; then
        echo "ERROR:cpuinfo_missing"
        return 1
    fi
    local vendor_id=$(grep -m1 "vendor_id" /proc/cpuinfo | awk -F': ' '{print $2}')
    local model_name=$(grep -m1 "model name" /proc/cpuinfo | awk -F': ' '{print $2}')
    local vendor="unknown"
    case "$vendor_id" in
        *Intel*) vendor="intel" ;;
        *AMD*) vendor="amd" ;;
    esac
    echo "${vendor}|${model_name}"
}

detect_npu() {
    local npus=()
    if ! command -v lspci >/dev/null 2>&1; then
        return 1
    fi
    while IFS= read -r line; do
        local pci_id=$(echo "$line" | awk '{print $1}')
        local nn_line=$(lspci -nn -s "$pci_id" 2>/dev/null)
        local vd_pair=$(echo "$nn_line" | grep -oP '\[([0-9a-f]{4}):([0-9a-f]{4})\]' | tr -d '[]')
        local vendor_id="${vd_pair%%:*}"
        local model=$(echo "$nn_line" | sed 's/.*\]://;s/\s*\[[0-9a-f]*:[0-9a-f]*\].*//' | xargs)
        local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        if [[ $vendor_id == "8086" ]]; then
            npus+=("intel|${model}|${driver}")
        elif [[ $vendor_id == "1002" ]]; then
            npus+=("amd|${model}|${driver}")
        fi
    done < <(lspci | grep -iE "Processing accelerators|NPU|Ryzen.*AI")
    if [[ ${#npus[@]} -eq 0 ]]; then
        echo "NONE"
        return 1
    fi
    for n in "${npus[@]}"; do
        echo "$n"
    done
}

detect_network() {
    local networks=()
    local wifi=$(lspci 2>/dev/null | grep -iE "Network controller|Wireless" | grep -vi "Neural" | head -1)
    if [[ -n $wifi ]]; then
        local pci_id=$(echo "$wifi" | awk '{print $1}')
        local nn_line=$(lspci -nn -s "$pci_id" 2>/dev/null)
        local vd_pair=$(echo "$nn_line" | grep -oP '\[([0-9a-f]{4}):([0-9a-f]{4})\]' | tr -d '[]')
        local vendor_id="${vd_pair%%:*}"
        local model=$(echo "$nn_line" | sed 's/.*\]://;s/\s*\[[0-9a-f]*:[0-9a-f]*\].*//' | xargs)
        local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        local vendor="unknown"
        case "$vendor_id" in
            8086) vendor="intel" ;;
            10ec) vendor="realtek" ;;
            14e4) vendor="broadcom" ;;
            1814) vendor="mediatek" ;;
            168c) vendor="atheros" ;;
        esac
        networks+=("wifi|${vendor}|${model}|${driver}")
    fi
    local eth=$(lspci 2>/dev/null | grep -i "ethernet" | head -1)
    if [[ -n $eth ]]; then
        local pci_id=$(echo "$eth" | awk '{print $1}')
        local nn_line=$(lspci -nn -s "$pci_id" 2>/dev/null)
        local vd_pair=$(echo "$nn_line" | grep -oP '\[([0-9a-f]{4}):([0-9a-f]{4})\]' | tr -d '[]')
        local vendor_id="${vd_pair%%:*}"
        local model=$(echo "$nn_line" | sed 's/.*\]://;s/\s*\[[0-9a-f]*:[0-9a-f]*\].*//' | xargs)
        local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        local vendor="unknown"
        case "$vendor_id" in
            8086) vendor="intel" ;;
            10ec) vendor="realtek" ;;
            14e4) vendor="broadcom" ;;
        esac
        networks+=("ethernet|${vendor}|${model}|${driver}")
    fi
    if [[ ${#networks[@]} -eq 0 ]]; then
        echo "NONE"
        return 1
    fi
    for n in "${networks[@]}"; do
        echo "$n"
    done
}

detect_audio() {
    local devices=()
    while IFS= read -r line; do
        local pci_id=$(echo "$line" | awk '{print $1}')
        local model=$(echo "$line" | sed 's/.*Audio device: //;s/.*Multimedia audio controller: //')
        local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        devices+=("pci|${model}|${driver}")
    done < <(lspci | grep -iE "Audio device|Multimedia audio controller")
    if [[ ${#devices[@]} -eq 0 ]]; then
        echo "NONE"
        return 1
    fi
    for d in "${devices[@]}"; do
        echo "$d"
    done
}

detect_bluetooth() {
    local bt=$(lspci 2>/dev/null | grep -i "bluetooth" | head -1)
    if [[ -z $bt ]]; then
        bt=$(lsusb 2>/dev/null | grep -i "bluetooth" | head -1)
    fi
    if [[ -n $bt ]]; then
        echo "present|${bt}"
    else
        echo "NONE"
        return 1
    fi
}

detect_other() {
    local others=()
    if ! command -v lspci >/dev/null 2>&1; then
        return 1
    fi
    while IFS= read -r line; do
        local pci_id=$(echo "$line" | awk '{print $1}')
        local nn_line=$(lspci -nn -s "$pci_id" 2>/dev/null)
        local model=$(echo "$nn_line" | sed 's/.*\]://;s/\s*\[[0-9a-f]*:[0-9a-f]*\].*//' | xargs)
        local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        others+=("webcam|${model}|${driver}")
    done < <(lspci | grep -iE "webcam|camera|video capture")
    if command -v lsusb >/dev/null 2>&1; then
        while IFS= read -r line; do
            others+=("webcam|${line}|")
        done < <(lsusb 2>/dev/null | grep -iE "camera|webcam")
    fi
    if command -v lsusb >/dev/null 2>&1; then
        while IFS= read -r line; do
            others+=("fingerprint|${line}|")
        done < <(lsusb 2>/dev/null | grep -iE "fingerprint|biometric")
    fi
    if command -v lsusb >/dev/null 2>&1; then
        while IFS= read -r line; do
            others+=("touchscreen|${line}|")
        done < <(lsusb 2>/dev/null | grep -iE "touchscreen|touch panel")
    fi
    while IFS= read -r line; do
        local pci_id=$(echo "$line" | awk '{print $1}')
        local nn_line=$(lspci -nn -s "$pci_id" 2>/dev/null)
        local model=$(echo "$nn_line" | sed 's/.*\]://;s/\s*\[[0-9a-f]*:[0-9a-f]*\].*//' | xargs)
        local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        others+=("cardreader|${model}|${driver}")
    done < <(lspci | grep -iE "SD host|card reader|MMC")
    if [[ ${#others[@]} -eq 0 ]]; then
        echo "NONE"
        return 1
    fi
    for o in "${others[@]}"; do
        echo "$o"
    done
}

get_gpu_packages() {
    local vendor="$1"
    local model="$2"
    local driver="$3"
    case "$vendor" in
        intel)
            local pkgs="vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver intel-gpu-tools libva-utils"
            if _kernel_version_ge 6 8; then
                if echo "$model" | grep -qiE "arc|meteor|lunar|battlemage"; then
                    pkgs+=" level-zero-loader intel-compute-runtime"
                fi
            fi
            if echo "$model" | grep -qiE "HD Graphics [2-5]|UHD Graphics 6[0-2]"; then
                pkgs+=" xf86-video-intel"
            fi
            echo "$pkgs"
            ;;
        nvidia)
            local pkgs="nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings lib32-opencl-nvidia"
            pkgs+=" cuda cudnn nvidia-container-toolkit"
            pkgs+=" libva-utils vdpauinfo"
            echo "$pkgs"
            ;;
        amd)
            local pkgs="mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu libva-utils vdpauinfo radeontop"
            pkgs+=" rocm-hip-sdk"
            echo "$pkgs"
            ;;
        *)
            echo "mesa lib32-mesa"
            ;;
    esac
}

get_npu_packages() {
    local vendor="$1"
    case "$vendor" in
        intel) echo "intel-npu-driver" ;;
        amd) echo "ryzenadj-git" ;;
        *) echo "" ;;
    esac
}

get_network_packages() {
    local type="$1"
    local vendor="$2"
    case "$type" in
        wifi)
            case "$vendor" in
                intel) echo "iwd linux-firmware" ;;
                realtek) echo "linux-firmware rtl88xxau-aircrack-dkms-git" ;;
                broadcom) echo "broadcom-wl-dkms linux-firmware" ;;
                mediatek) echo "linux-firmware" ;;
                atheros) echo "linux-firmware ath9k-htc-firmware" ;;
                *) echo "linux-firmware iwd" ;;
            esac
            ;;
        ethernet)
            case "$vendor" in
                realtek) echo "r8168-dkms" ;;
                *) echo "" ;;
            esac
            ;;
    esac
}

get_other_packages() {
    local type="$1"
    case "$type" in
        fingerprint) echo "fprintd libfprint" ;;
        webcam) echo "" ;;
        touchscreen) echo "libinput xf86-input-libinput" ;;
        cardreader) echo "" ;;
        *) echo "" ;;
    esac
}

get_firmware_packages() {
    echo "linux-firmware sof-firmware"
}

get_profile_packages() {
    local profile="$1"
    local gpus=$(detect_gpus)
    local gpu_vendor="unknown"
    if [[ -n $gpus && $gpus != "NONE" ]]; then
        local first=$(echo "$gpus" | head -1)
        IFS='|' read -r pci_id vendor_id vendor model driver <<<"$first"
        gpu_vendor="$vendor"
    fi

    case "$profile" in
        gaming)
            local pkgs="gamemode gamescope mangohud vulkan-tools lib32-gamemode"
            case "$gpu_vendor" in
                intel) pkgs+=" vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver" ;;
                nvidia) pkgs+=" nvidia-utils lib32-nvidia-utils lib32-opencl-nvidia" ;;
                amd) pkgs+=" vulkan-radeon lib32-vulkan-radeon radeontop" ;;
            esac
            echo "$pkgs"
            ;;
        ai)
            local pkgs="ollama python-pytorch"
            if _kernel_version_ge 6 8; then
                pkgs+=" level-zero-loader intel-compute-runtime"
            fi
            case "$gpu_vendor" in
                nvidia) pkgs+=" cuda cudnn nvidia-container-toolkit" ;;
                amd) pkgs+=" rocm-hip-sdk" ;;
            esac
            echo "$pkgs"
            ;;
        minimal)
            local pkgs="linux-firmware"
            case "$gpu_vendor" in
                intel) pkgs+=" vulkan-intel" ;;
                nvidia) pkgs+=" nvidia-utils" ;;
                amd) pkgs+=" mesa vulkan-radeon" ;;
            esac
            echo "$pkgs"
            ;;
        workstation)
            local pkgs="blender gimp kdenlive libreoffice-fresh virt-manager docker"
            case "$gpu_vendor" in
                intel) pkgs+=" vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver intel-gpu-tools level-zero-loader intel-compute-runtime" ;;
                nvidia) pkgs+=" nvidia-utils lib32-nvidia-utils cuda cudnn nvidia-container-toolkit" ;;
                amd) pkgs+=" mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon rocm-hip-sdk radeontop" ;;
            esac
            echo "$pkgs"
            ;;
    esac
}

get_service_hints() {
    local services=""
    pacman -Qq bluez >/dev/null 2>&1 && ! systemctl is-active --quiet bluetooth && services+="bluetooth.service (not running)\n"
    pacman -Qq iwd >/dev/null 2>&1 && ! systemctl is-active --quiet iwd && services+="iwd.service (not running)\n"
    pacman -Qq NetworkManager >/dev/null 2>&1 && ! systemctl is-active --quiet NetworkManager && services+="NetworkManager.service (not running)\n"
    echo -e "$services" | sed '/^$/d'
}

install_packages() {
    local pkgs="$1"
    local missing=$(_get_missing "$pkgs")
    if [[ -z $missing ]]; then
        return 0
    fi
    local helper="yay"
    command -v paru >/dev/null 2>&1 && helper="paru"
    if command -v "$helper" >/dev/null 2>&1; then
        $helper -S --needed --noconfirm $missing 2>&1
    else
        sudo pacman -S --needed --noconfirm $missing 2>&1
    fi
    return $?
}

configure_nvidia_drm() {
    local conf="/etc/modprobe.d/nvidia-drm.conf"
    if ! grep -q "nvidia-drm.modeset=1" "$conf" 2>/dev/null; then
        echo "options nvidia-drm modeset=1 fbdev=1" | sudo tee "$conf" >/dev/null
        echo "NVIDIA_DRM_CONFIGURED"
    else
        echo "NVIDIA_DRM_ALREADY_SET"
    fi
}

configure_ai_env() {
    local vendor="$1"
    case "$vendor" in
        intel)
            _set_env_var "ONEAPI_DEVICE_SELECTOR" "level_zero:0"
            _set_env_var "ZES_ENABLE_SYSMAN" "1"
            echo "AI_ENV_INTEL_SET"
            ;;
        nvidia)
            _set_env_var "CUDA_VISIBLE_DEVICES" "0"
            echo "AI_ENV_NVIDIA_SET"
            ;;
        amd)
            _set_env_var "HSA_OVERRIDE_GFX_VERSION" "11.0.0"
            echo "AI_ENV_AMD_SET"
            ;;
    esac
}

run_full_scan() {
    local results=""
    local gpus=$(detect_gpus)
    if [[ $gpus != "NONE" && -n $gpus ]]; then
        while IFS= read -r gpu; do
            IFS='|' read -r pci_id vendor_id vendor model driver <<<"$gpu"
            local pkgs=$(get_gpu_packages "$vendor" "$model" "$driver")
            local missing=$(_get_missing "$pkgs")
            results+="GPU|${vendor}|${model}|${driver}|${pkgs}|${missing}\n"
        done <<<"$gpus"
    fi
    local cpu=$(detect_cpu)
    if [[ -n $cpu ]]; then
        IFS='|' read -r vendor model <<<"$cpu"
        local ucode_pkg=""
        [[ $vendor == "intel" ]] && ucode_pkg="intel-ucode"
        [[ $vendor == "amd" ]] && ucode_pkg="amd-ucode"
        local ucode_missing=""
        [[ -n $ucode_pkg ]] && ucode_missing=$(_get_missing "$ucode_pkg")
        results+="CPU|${vendor}|${model}||${ucode_pkg}|${ucode_missing}\n"
    fi
    local npus=$(detect_npu)
    if [[ $npus != "NONE" && -n $npus ]]; then
        while IFS= read -r npu; do
            IFS='|' read -r vendor model driver <<<"$npu"
            local pkgs=$(get_npu_packages "$vendor")
            local missing=$(_get_missing "$pkgs")
            results+="NPU|${vendor}|${model}|${driver}|${pkgs}|${missing}\n"
        done <<<"$npus"
    fi
    local networks=$(detect_network)
    if [[ $networks != "NONE" && -n $networks ]]; then
        while IFS= read -r net; do
            IFS='|' read -r type vendor model driver <<<"$net"
            local pkgs=$(get_network_packages "$type" "$vendor")
            local missing=""
            [[ -n $pkgs ]] && missing=$(_get_missing "$pkgs")
            results+="NET|${vendor}|${model}|${driver}|${pkgs}|${missing}\n"
        done <<<"$networks"
    fi
    local audio=$(detect_audio)
    if [[ $audio != "NONE" && -n $audio ]]; then
        while IFS= read -r dev; do
            IFS='|' read -r type model driver <<<"$dev"
            results+="AUDIO||${model}|${driver}||\n"
        done <<<"$audio"
    fi
    local bt=$(detect_bluetooth)
    if [[ $bt != "NONE" && -n $bt ]]; then
        local bt_pkgs="bluez bluez-utils"
        local bt_missing=$(_get_missing "$bt_pkgs")
        results+="BT||Bluetooth Device||${bt_pkgs}|${bt_missing}\n"
    fi
    local others=$(detect_other)
    if [[ $others != "NONE" && -n $others ]]; then
        while IFS= read -r other; do
            IFS='|' read -r type model driver <<<"$other"
            local pkgs=$(get_other_packages "$type")
            local missing=""
            [[ -n $pkgs ]] && missing=$(_get_missing "$pkgs")
            results+="OTHER|${type}|${model}|${driver}|${pkgs}|${missing}\n"
        done <<<"$others"
    fi
    local fw_pkgs=$(get_firmware_packages)
    local fw_missing=$(_get_missing "$fw_pkgs")
    results+="FW||System Firmware||${fw_pkgs}|${fw_missing}\n"
    local multilib=$(_check_multilib)
    local rebar=$(_check_rebar)
    results+="SYS|multilib|${multilib}|||\n"
    results+="SYS|rebar|${rebar}|||\n"
    local kern_warn=$(_kernel_warnings)
    [[ -n $kern_warn ]] && results+="WARN|${kern_warn}||||\n"
    echo -e "$results" | sed '/^$/d'
}

run_full_install() {
    local scan_data=$(run_full_scan)
    local missing_pkgs=""
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        IFS='|' read -r type vendor model driver pkgs missing <<<"$line"
        case "$type" in
            GPU | CPU | NPU | NET | BT | FW | OTHER)
                [[ -n $missing ]] && missing_pkgs+=" $missing"
                ;;
        esac
    done <<<"$scan_data"
    local unique_missing=$(echo "$missing_pkgs" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ')
    if [[ -z "$(echo "$unique_missing" | xargs)" ]]; then
        echo "ALL_DRIVERS_INSTALLED"
        return 0
    fi
    echo "MISSING:$unique_missing"
}

run_full_install_confirmed() {
    local scan_data=$(run_full_scan)
    local missing_pkgs=""
    local gpu_vendors_found=()
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        IFS='|' read -r type vendor model driver pkgs missing <<<"$line"
        case "$type" in
            GPU)
                gpu_vendors_found+=("$vendor")
                [[ -n $missing ]] && missing_pkgs+=" $missing"
                ;;
            CPU | NPU | NET | BT | FW | OTHER)
                [[ -n $missing ]] && missing_pkgs+=" $missing"
                ;;
        esac
    done <<<"$scan_data"
    local unique_missing=$(echo "$missing_pkgs" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ')
    if [[ -z "$(echo "$unique_missing" | xargs)" ]]; then
        echo "ALL_DRIVERS_INSTALLED"
        return 0
    fi
    echo "MISSING:$unique_missing"
    install_packages "$unique_missing"
    local install_status=$?
    if [[ $install_status -eq 0 ]]; then
        for vendor in "${gpu_vendors_found[@]}"; do
            case "$vendor" in
                nvidia)
                    configure_nvidia_drm
                    configure_ai_env "nvidia"
                    ;;
                intel)
                    configure_ai_env "intel"
                    ;;
                amd)
                    configure_ai_env "amd"
                    ;;
            esac
        done

        generate_hypr_env

        if echo "$unique_missing" | grep -qE "nvidia-open-dkms|nvidia"; then
            configure_mkinitcpio_nvidia
        fi

        if echo "$unique_missing" | grep -qE "dkms|nvidia|cuda|rocm"; then
            echo "INITRAMFS_UPDATE_NEEDED"
        fi
        echo "INSTALL_COMPLETE"
    else
        echo "INSTALL_FAILED"
        return 1
    fi
}

verify_install() {
    local pkgs="$1"
    local still_missing=""
    for p in $pkgs; do
        _is_pkg_installed "$p" || still_missing+=" $p"
    done
    if [[ -z $still_missing ]]; then
        echo "ALL_VERIFIED"
    else
        echo "STILL_MISSING:$still_missing"
    fi
}

show_device_info() {
    local target="$1"
    if ! command -v lspci >/dev/null 2>&1; then
        echo "ERROR:lspci_missing"
        return 1
    fi
    local found=false
    while IFS= read -r line; do
        local pci_id=$(echo "$line" | awk '{print $1}')
        local model=$(echo "$line" | sed 's/^[0-9a-f:]* //')
        if echo "$model" | grep -qi "$target"; then
            found=true
            echo "DEVICE|${model}"
            lspci -v -s "$pci_id" 2>/dev/null | sed 's/^/DETAIL|/'
            local modules=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel modules:" | awk -F': ' '{print $2}')
            local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
            echo "MODULES|${modules}"
            echo "DRIVER|${driver}"
        fi
    done < <(lspci)
    if [[ $found == false ]]; then
        echo "NOT_FOUND"
    fi
}

sys_check_ai_env() {
    local env_file="/etc/environment"
    local intel_env=$(grep "^ONEAPI_DEVICE_SELECTOR=" "$env_file" 2>/dev/null | cut -d= -f2)
    local nvidia_env=$(grep "^CUDA_VISIBLE_DEVICES=" "$env_file" 2>/dev/null | cut -d= -f2)
    local amd_env=$(grep "^HSA_OVERRIDE_GFX_VERSION=" "$env_file" 2>/dev/null | cut -d= -f2)
    echo "intel:${intel_env:-not_set}|nvidia:${nvidia_env:-not_set}|amd:${amd_env:-not_set}"
}

_detect_bootloader() {
    if [[ -f /boot/grub/grub.cfg ]]; then
        echo "grub|/etc/default/grub|GRUB_CMDLINE_LINUX_DEFAULT|grub-mkconfig -o /boot/grub/grub.cfg"
    elif [[ -d /boot/loader/entries ]]; then
        local entry=$(ls /boot/loader/entries/*.conf 2>/dev/null | head -1)
        echo "systemd-boot|${entry}|options|systemctl reboot"
    elif [[ -f /boot/refind_linux.conf ]]; then
        echo 'refind|/boot/refind_linux.conf|"Boot with standard options"|refind-install'
    else
        echo "unknown|||"
    fi
}

_get_intel_gpu_device_id() {
    local device_id=$(lspci -nn -d 8086: 2>/dev/null | grep -iE "VGA|3D|Display" | grep -oP '\[([0-9a-f]{4}):([0-9a-f]{4})\]' | head -1 | tr -d '[]' | cut -d: -f2)
    echo "$device_id"
}

_get_current_driver() {
    local device_id=$(_get_intel_gpu_device_id)
    [[ -z $device_id ]] && return 1
    local pci_id=$(lspci -nn -d 8086: 2>/dev/null | grep -iE "VGA|3D|Display" | awk '{print $1}')
    lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}'
}

_get_kernel_params() {
    local bl_info=$(_detect_bootloader)
    IFS='|' read -r bl_type bl_file bl_key bl_update_cmd <<<"$bl_info"
    if [[ $bl_type == "grub" && -f $bl_file ]]; then
        grep "^${bl_key}=" "$bl_file" | cut -d'"' -f2
    elif [[ $bl_type == "systemd-boot" && -n $bl_file ]]; then
        grep "^options " "$bl_file" | sed 's/^options //'
    elif [[ $bl_type == "refind" && -f $bl_file ]]; then
        grep '^"' "$bl_file" | head -1 | sed 's/^[^"]*"\([^"]*\)".*/\1/'
    fi
}

_switch_driver() {
    local target="$1"
    local device_id=$(_get_intel_gpu_device_id)
    local current=$(_get_current_driver)
    local bl_info=$(_detect_bootloader)
    IFS='|' read -r bl_type bl_file bl_key bl_update_cmd <<<"$bl_info"

    if [[ $bl_type == "unknown" ]]; then
        echo "ERROR|bootloader_not_detected"
        return 1
    fi

    if [[ $target == "xe" ]]; then
        if ! _kernel_version_ge 6 8; then
            echo "ERROR|kernel_too_old"
            return 1
        fi
        if [[ $current == "xe" ]]; then
            echo "ALREADY|xe"
            return 0
        fi
        local params=$(_get_kernel_params)
        params=$(echo "$params" | sed 's/xe\.force_probe=[^ ]*//g; s/i915\.force_probe=[^ ]*//g' | xargs)
        params+=" i915.force_probe=!${device_id} xe.force_probe=${device_id}"
    elif [[ $target == "i915" ]]; then
        if [[ $current == "i915" ]]; then
            echo "ALREADY|i915"
            return 0
        fi
        local params=$(_get_kernel_params)
        params=$(echo "$params" | sed 's/xe\.force_probe=[^ ]*//g; s/i915\.force_probe=[^ ]*//g' | xargs)
    fi

    if [[ $bl_type == "grub" ]]; then
        sudo sed -i "s|^${bl_key}=.*|${bl_key}=\"${params}\"|" "$bl_file"
        sudo $bl_update_cmd >/dev/null 2>&1
    elif [[ $bl_type == "systemd-boot" ]]; then
        for f in /boot/loader/entries/*.conf; do
            sudo sed -i "s|^options .*|options ${params}|" "$f"
        done
    elif [[ $bl_type == "refind" ]]; then
        sudo sed -i "s|^\"[^\"]*\"|\"Boot with standard options\" \"${params}\"|" "$bl_file"
    fi

    echo "SUCCESS|${target}|${device_id}|reboot_required"
}

_list_module_params() {
    local modules=("$@")
    [[ ${#modules[@]} -eq 0 ]] && modules=(i915 xe nvidia nvidia_drm amdgpu)
    for mod in "${modules[@]}"; do
        if [[ -d /sys/module/$mod/parameters ]]; then
            echo "MODULE|${mod}"
            for param in /sys/module/$mod/parameters/*; do
                local name=$(basename "$param")
                local val=$(cat "$param" 2>/dev/null | tr '\n' ' ')
                echo "PARAM|${name}|${val}"
            done
        fi
    done
}

_set_module_param() {
    local module="$1"
    local param="$2"
    local value="$3"
    local conf_file="/etc/modprobe.d/${module}.conf"
    if grep -q "^options ${module} " "$conf_file" 2>/dev/null; then
        if grep -q "${param}=" "$conf_file" 2>/dev/null; then
            sudo sed -i "s/${param}=[^ ]*/${param}=${value}/" "$conf_file"
        else
            sudo sed -i "s|^options ${module} |options ${module} ${param}=${value} |" "$conf_file"
        fi
    else
        echo "options ${module} ${param}=${value}" | sudo tee "$conf_file" >/dev/null
    fi
    echo "SET|${module}|${param}=${value}"
}

_check_driver_conflicts() {
    local conflicts=""
    if pacman -Qq nvidia >/dev/null 2>&1 && pacman -Qq xf86-video-nouveau >/dev/null 2>&1; then
        conflicts+="nvidia + xf86-video-nouveau (remove xf86-video-nouveau)\n"
    fi
    if pacman -Qq xf86-video-intel >/dev/null 2>&1; then
        local kver=$(uname -r | cut -d. -f1)
        if [[ $kver -ge 6 ]]; then
            conflicts+="xf86-video-intel (unneeded on kernel 6+, causes issues with modesetting)\n"
        fi
    fi
    if pacman -Qq xf86-video-amdgpu >/dev/null 2>&1 && pacman -Qq mesa >/dev/null 2>&1; then
        conflicts+="xf86-video-amdgpu (conflicts with modesetting, use mesa only)\n"
    fi
    if pacman -Qq vulkan-intel >/dev/null 2>&1 && pacman -Qq vulkan-anv >/dev/null 2>&1; then
        conflicts+="vulkan-intel + vulkan-anv (duplicate Vulkan drivers)\n"
    fi
    echo -e "$conflicts" | sed '/^$/d'
}

_detect_dual_gpu() {
    local all_gpus=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display")
    local intel_count=$(echo "$all_gpus" | grep -ic "intel")
    local nvidia_count=$(echo "$all_gpus" | grep -ic "nvidia")
    local amd_count=$(echo "$all_gpus" | grep -icE "Advanced Micro Devices|ATI Technologies|AMD")

    if [[ $intel_count -gt 0 && $nvidia_count -gt 0 ]]; then
        local intel_model=$(echo "$all_gpus" | grep -i "intel" | head -1 | sed 's/^[0-9a-f:]* //')
        local nvidia_model=$(echo "$all_gpus" | grep -i "nvidia" | head -1 | sed 's/^[0-9a-f:]* //')
        local intel_pci=$(echo "$all_gpus" | grep -i "intel" | head -1 | awk '{print $1}')
        local nvidia_pci=$(echo "$all_gpus" | grep -i "nvidia" | head -1 | awk '{print $1}')
        local intel_driver=$(lspci -k -s "$intel_pci" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        local nvidia_driver=$(lspci -k -s "$nvidia_pci" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        echo "intel-nvidia|${intel_model}|${nvidia_model}|${intel_driver}|${nvidia_driver}"
    elif [[ $intel_count -gt 0 && $amd_count -gt 0 ]]; then
        local intel_model=$(echo "$all_gpus" | grep -i "intel" | head -1 | sed 's/^[0-9a-f:]* //')
        local amd_model=$(echo "$all_gpus" | grep -iE "Advanced Micro Devices|ATI Technologies|AMD" | head -1 | sed 's/^[0-9a-f:]* //')
        local intel_pci=$(echo "$all_gpus" | grep -i "intel" | head -1 | awk '{print $1}')
        local amd_pci=$(echo "$all_gpus" | grep -iE "Advanced Micro Devices|ATI Technologies|AMD" | head -1 | awk '{print $1}')
        local intel_driver=$(lspci -k -s "$intel_pci" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        local amd_driver=$(lspci -k -s "$amd_pci" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        echo "intel-amd|${intel_model}|${amd_model}|${intel_driver}|${amd_driver}"
    elif [[ $nvidia_count -gt 0 && $amd_count -gt 0 ]]; then
        local nvidia_model=$(echo "$all_gpus" | grep -i "nvidia" | head -1 | sed 's/^[0-9a-f:]* //')
        local amd_model=$(echo "$all_gpus" | grep -iE "Advanced Micro Devices|ATI Technologies|AMD" | head -1 | sed 's/^[0-9a-f:]* //')
        local nvidia_pci=$(echo "$all_gpus" | grep -i "nvidia" | head -1 | awk '{print $1}')
        local amd_pci=$(echo "$all_gpus" | grep -iE "Advanced Micro Devices|ATI Technologies|AMD" | head -1 | awk '{print $1}')
        local nvidia_driver=$(lspci -k -s "$nvidia_pci" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        local amd_driver=$(lspci -k -s "$amd_pci" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        echo "nvidia-amd|${nvidia_model}|${amd_model}|${nvidia_driver}|${amd_driver}"
    else
        echo "single"
    fi
}

_setup_optimus() {
    local pkgs="nvidia-prime nvidia-utils lib32-nvidia-utils"
    local missing=$(_get_missing "$pkgs")

    if [[ -z $missing ]]; then
        echo "ALREADY_INSTALLED"
        return 0
    fi

    echo "MISSING:$missing"

    local helper="yay"
    command -v paru >/dev/null 2>&1 && helper="paru"
    if command -v "$helper" >/dev/null 2>&1; then
        $helper -S --needed --noconfirm $missing 2>&1
    else
        sudo pacman -S --needed --noconfirm $missing 2>&1
    fi

    local status=$?
    if [[ $status -eq 0 ]]; then
        echo "INSTALL_SUCCESS"
    else
        echo "INSTALL_FAILED"
    fi
    return $status
}

_setup_hybrid_amd() {
    local pkgs="vulkan-radeon lib32-vulkan-radeon mesa lib32-mesa"
    local missing=$(_get_missing "$pkgs")

    if [[ -z $missing ]]; then
        echo "ALREADY_INSTALLED"
        return 0
    fi

    echo "MISSING:$missing"

    local helper="yay"
    command -v paru >/dev/null 2>&1 && helper="paru"
    if command -v "$helper" >/dev/null 2>&1; then
        $helper -S --needed --noconfirm $missing 2>&1
    else
        sudo pacman -S --needed --noconfirm $missing 2>&1
    fi

    local status=$?
    if [[ $status -eq 0 ]]; then
        echo "INSTALL_SUCCESS"
    else
        echo "INSTALL_FAILED"
    fi
    return $status
}

_get_gpu_status() {
    local gpus=$(detect_gpus)
    if [[ $gpus == "NONE" || -z $gpus ]]; then
        echo "NO_GPU"
        return 1
    fi

    local active_gpu=""
    local inactive_gpus=""

    while IFS= read -r gpu; do
        IFS='|' read -r pci_id vendor_id vendor model driver <<<"$gpu"
        if [[ -n $driver ]]; then
            active_gpu="${vendor}|${model}|${driver}"
        else
            inactive_gpus+="${vendor}|${model}|no_driver\n"
        fi
    done <<<"$gpus"

    echo "ACTIVE|${active_gpu}"
    if [[ -n $inactive_gpus ]]; then
        echo -e "INACTIVE|${inactive_gpus}" | sed '/^$/d'
    fi
}

_fwupd_scan() {
    if ! command -v fwupdmgr >/dev/null 2>&1; then
        echo "ERROR:fwupdmgr_missing"
        return 1
    fi

    local devices=$(fwupdmgr get-devices --json 2>/dev/null)
    local updates=$(fwupdmgr get-updates --json 2>/dev/null)

    local device_count=$(echo "$devices" | grep -c '"DeviceId"' 2>/dev/null)
    local update_count=$(echo "$updates" | grep -c '"DeviceId"' 2>/dev/null)

    echo "SCAN|${device_count}|${update_count}"
}

_fwupd_install() {
    if ! command -v fwupdmgr >/dev/null 2>&1; then
        echo "ERROR:fwupdmgr_missing"
        return 1
    fi

    local updates=$(fwupdmgr get-updates 2>/dev/null)
    if echo "$updates" | grep -q "No updatable devices"; then
        echo "NO_UPDATES"
        return 0
    fi

    fwupdmgr update 2>&1
    local status=$?

    if [[ $status -eq 0 ]]; then
        echo "INSTALL_SUCCESS"
    else
        echo "INSTALL_FAILED"
    fi
    return $status
}

_fwupd_status() {
    if ! command -v fwupdmgr >/dev/null 2>&1; then
        echo "ERROR:fwupdmgr_missing"
        return 1
    fi

    local daemon_version=$(fwupdmgr --version 2>/dev/null | grep "org.freedesktop.fwupd" | head -1 | awk '{print $3}')
    local devices=$(fwupdmgr get-devices --json 2>/dev/null)
    local device_count=$(echo "$devices" | grep -c '"DeviceId"' 2>/dev/null)

    echo "STATUS|${daemon_version}|${device_count}"
}

generate_hypr_env() {
    local force_vendor="$1"
    local env_file="$RETRO_CONFIG/env.conf"
    mkdir -p "$(dirname "$env_file")"

    local has_nvidia=false
    local has_amd=false
    local has_intel=false
    local is_hybrid=false

    if [[ -z $force_vendor ]]; then
        local gpus=$(detect_gpus)
        if [[ $gpus != "NONE" && -n $gpus ]]; then
            while IFS= read -r line; do
                [[ -z $line ]] && continue
                IFS='|' read -r pci_id vendor_id vendor model driver <<<"$line"
                case "$vendor" in
                    nvidia) has_nvidia=true ;;
                    amd) has_amd=true ;;
                    intel) has_intel=true ;;
                esac
            done <<<"$gpus"
        fi

        if $has_nvidia && $has_intel; then
            is_hybrid=true
        fi
    else
        case "${force_vendor,,}" in
            nvidia) has_nvidia=true ;;
            amd) has_amd=true ;;
            intel) has_intel=true ;;
        esac
    fi

    cat >"$env_file" <<'ENDOFENV'
###################################
### RETRO ENVIRONMENT VARIABLES ###
###################################

# This file has been generated by retro driver

ENDOFENV

    if $is_hybrid; then
        cat >>"$env_file" <<'ENDOFENV'
# Intel + NVIDIA Hybrid
env = LIBVA_DRIVER_NAME,iHD
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = GBM_BACKEND,nvidia-drm

ENDOFENV
        echo "result=success|type=hybrid"
    elif $has_nvidia; then
        cat >>"$env_file" <<'ENDOFENV'
# NVIDIA GPU
env = GBM_BACKEND,nvidia-drm
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = NVD_BACKEND,direct

ENDOFENV
        echo "result=success|type=nvidia"
    elif $has_amd; then
        cat >>"$env_file" <<'ENDOFENV'
# AMD GPU
env = LIBVA_DRIVER_NAME,radeonsi
env = VDPAU_DRIVER,radeonsi
env = mesa_glthread,true

ENDOFENV
        echo "result=success|type=amd"
    elif $has_intel; then
        cat >>"$env_file" <<'ENDOFENV'
# Intel GPU
env = LIBVA_DRIVER_NAME,iHD
env = VDPAU_DRIVER,va_gl
env = mesa_glthread,true

ENDOFENV
        echo "result=success|type=intel"
    else
        cat >>"$env_file" <<'ENDOFENV'
# No GPU detected - using default settings
env = LIBVA_DRIVER_NAME,iHD
env = mesa_glthread,true

ENDOFENV
        echo "result=warn|no_gpu_detected"
    fi

    echo "$env_file"
}

configure_mkinitcpio_nvidia() {
    local mkinit_conf="/etc/mkinitcpio.conf"
    local backup="${mkinit_conf}.bak.$(date +%Y%m%d%H%M%S)"

    if [[ ! -f $mkinit_conf ]]; then
        echo "result=error|reason=mkinit_conf_not_found"
        return 1
    fi

    if ! _is_pkg_installed "nvidia-open-dkms" && ! _is_pkg_installed "nvidia"; then
        echo "result=skipped|reason=nvidia_not_installed"
        return 0
    fi

    sudo cp "$mkinit_conf" "$backup"
    echo "result=backup_created|backup=$backup"

    if grep -q "^MODULES=" "$mkinit_conf"; then
        if ! grep "^MODULES=" "$mkinit_conf" | grep -q "nvidia"; then
            sudo sed -i 's|^MODULES=\(.*\)|MODULES=\1 nvidia nvidia_drm nvidia_modeset|' "$mkinit_conf"
        fi
    else
        echo 'MODULES="nvidia nvidia_drm nvidia_modeset"' | sudo tee -a "$mkinit_conf" >/dev/null
    fi

    if command -v mkinitcpio >/dev/null 2>&1; then
        sudo mkinitcpio -P 2>&1 | head -20
        echo "result=initramfs_regenerated"
    fi

    echo "result=success|action=mkinit_configured"
}

show_hypr_env() {
    local env_file="$RETRO_CONFIG/env.conf"

    if [[ -f $env_file ]]; then
        echo "result=success|path=$env_file"
    else
        echo "result=error|reason=env_file_not_found"
        return 1
    fi
}

case "$1" in
    "--scan") run_full_scan ;;
    "--install") run_full_install ;;
    "--install-confirmed") run_full_install_confirmed ;;
    "--verify") verify_install "$2" ;;
    "--info") show_device_info "$2" ;;
    "--services") get_service_hints ;;
    "--sys-ai-env") sys_check_ai_env ;;
    "--kernel-warn") _kernel_warnings ;;
    "--bootloader") _detect_bootloader ;;
    "--switch") _switch_driver "$2" ;;
    "--modules") _list_module_params "${@:2}" ;;
    "--modules-set") _set_module_param "$2" "$3" "$4" ;;
    "--conflicts") _check_driver_conflicts ;;
    "--dual-gpu") _detect_dual_gpu ;;
    "--optimus") _setup_optimus ;;
    "--hybrid-amd") _setup_hybrid_amd ;;
    "--gpu-status") _get_gpu_status ;;
    "--device-id") _get_intel_gpu_device_id ;;
    "--current-driver") _get_current_driver ;;
    "--profile") get_profile_packages "$2" ;;
    "--firmware-scan") _fwupd_scan ;;
    "--firmware-install") _fwupd_install ;;
    "--firmware-status") _fwupd_status ;;
    "--hypr") generate_hypr_env "$2" ;;
    "--hypr-env") generate_hypr_env "$2" ;;
    "--hypr-show") show_hypr_env ;;
    "--hypr-env-show") show_hypr_env ;;
    "--mkinit") configure_mkinitcpio_nvidia ;;
esac
