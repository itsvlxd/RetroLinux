#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "driver"

RETRO_DIR="${RETRO_DIR:-$(dirname "$(dirname "$(readlink -f "$0")")")}"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/helpers.sh"

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

_net_vendor_name() {
    local vendor_id="$1"
    case "$vendor_id" in
        8086) echo "intel" ;;
        10ec) echo "realtek" ;;
        14e4) echo "broadcom" ;;
        14c3) echo "mediatek" ;;
        1814) echo "mediatek" ;;
        168c) echo "atheros" ;;
        17cb) echo "qualcomm" ;;
        1969) echo "atheros" ;;
        1d6a) echo "qualcomm" ;;
        0bda) echo "realtek" ;;
        10df) echo "unknown" ;;
        *) echo "unknown" ;;
    esac
}

detect_network() {
    local networks=()
    if ! command -v lspci >/dev/null 2>&1; then
        return 1
    fi
    while IFS= read -r line; do
        local pci_id=$(echo "$line" | awk '{print $1}')
        local nn_line=$(lspci -nn -s "$pci_id" 2>/dev/null)
        local vd_pair=$(echo "$nn_line" | grep -oP '\[([0-9a-f]{4}):([0-9a-f]{4})\]' | tr -d '[]')
        local vendor_id="${vd_pair%%:*}"
        local device_id="${vd_pair##*:}"
        [[ -z $device_id ]] && continue
        local model=$(echo "$nn_line" | sed 's/.*\]://;s/\s*\[[0-9a-f]*:[0-9a-f]*\].*//' | xargs)
        local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        [[ -z $driver ]] && driver="none"
        local vendor=$(_net_vendor_name "$vendor_id")
        networks+=("wifi|${vendor}|${model}|${driver}|${device_id}")
    done < <(lspci 2>/dev/null | grep -iE "Network controller|Wireless" | grep -vi "Neural")
    while IFS= read -r line; do
        local pci_id=$(echo "$line" | awk '{print $1}')
        local nn_line=$(lspci -nn -s "$pci_id" 2>/dev/null)
        local vd_pair=$(echo "$nn_line" | grep -oP '\[([0-9a-f]{4}):([0-9a-f]{4})\]' | tr -d '[]')
        local vendor_id="${vd_pair%%:*}"
        local device_id="${vd_pair##*:}"
        [[ -z $device_id ]] && continue
        local model=$(echo "$nn_line" | sed 's/.*\]://;s/\s*\[[0-9a-f]*:[0-9a-f]*\].*//' | xargs)
        local driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        [[ -z $driver ]] && driver="none"
        local vendor=$(_net_vendor_name "$vendor_id")
        networks+=("ethernet|${vendor}|${model}|${driver}|${device_id}")
    done < <(lspci 2>/dev/null | grep -i "ethernet")
    if command -v lsusb >/dev/null 2>&1; then
        while IFS= read -r line; do
            local vid=$(echo "$line" | grep -oP 'ID [0-9a-f]{4}:[0-9a-f]{4}' | awk '{print $2}' | cut -d: -f1)
            local did=$(echo "$line" | grep -oP 'ID [0-9a-f]{4}:[0-9a-f]{4}' | awk '{print $2}' | cut -d: -f2)
            [[ -z $vid || -z $did ]] && continue
            local model=$(echo "$line" | sed 's/^.*ID [0-9a-f:]* //' | xargs)
            local vendor=$(_net_vendor_name "$vid")
            local driver="none"
            local ifname=$(ip -o link 2>/dev/null | grep -i "$vid" | head -1 | awk -F': ' '{print $2}')
            [[ -n $ifname ]] && driver="$ifname"
            networks+=("ethernet|${vendor}|${model}|${driver}|${did}")
        done < <(lsusb 2>/dev/null | grep -iE "RTL815[0-9]|RTL816[0-9]|AX8817[0-9]|AX88[12][0-9]|USB.*[Ee]thernet|[Ee]thernet.*USB|Network adapter|LAN adapter|2.5GbE|2\.5G" | grep -viE "bluetooth|hub|wireless")
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

_gpu_generation() {
    # Heuristic from the model string: returns "turing_plus" for GPUs that
    # work with nvidia-open-dkms, "legacy" otherwise.
    local model="$1"
    if echo "$model" | grep -qiE "RTX (20[0-9]{2}|30[0-9]{2}|40[0-9]{2}|50[0-9]{2}|16[0-9]{2})|GTX 16|Turing|Ampere|Ada|Blackwell"; then
        echo "turing_plus"
    else
        echo "legacy"
    fi
}

_nvidia_dkms_pkg() {
    # Prefer the proprietary dkms for legacy GPUs when available, else fall
    # back to the open driver so the list stays installable.
    if pacman -Si nvidia-dkms >/dev/null 2>&1; then
        echo "nvidia-dkms"
    else
        echo "nvidia-open-dkms"
    fi
}

get_gpu_ai_packages() {
    local vendor="$1"
    case "$vendor" in
        intel) echo "intel-compute-runtime level-zero-loader" ;;
        nvidia) echo "cuda cudnn nvidia-container-toolkit" ;;
        amd) echo "rocm-hip-sdk" ;;
        *) echo "" ;;
    esac
}

get_gpu_packages() {
    local vendor="$1"
    local model="$2"
    local driver="$3"
    case "$vendor" in
        intel)
            local pkgs="vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver intel-gpu-tools libva-utils"
            if echo "$model" | grep -qiE "HD Graphics [2-5]|UHD Graphics 6[0-2]"; then
                pkgs+=" xf86-video-intel"
            fi
            echo "$pkgs"
            ;;
        nvidia)
            local gen=$(_gpu_generation "$model")
            local pkgs=""
            if [[ $gen == "turing_plus" ]]; then
                pkgs="nvidia-open-dkms"
            else
                pkgs=$(_nvidia_dkms_pkg)
            fi
            pkgs+=" nvidia-utils lib32-nvidia-utils nvidia-settings nvidia-prime lib32-opencl-nvidia libva-utils vdpauinfo"
            echo "$pkgs"
            ;;
        amd)
            local pkgs="mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu libva-utils vdpauinfo radeontop"
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
    local device_id="$3"
    case "$type" in
        wifi)
            case "$vendor" in
                intel) echo "linux-firmware iwd" ;;
                realtek)
                    case "$device_id" in
                        b852|c852|b851|8852be) echo "8852be-dkms-git linux-firmware" ;;
                        c821) echo "rtl8821ce-dkms-git linux-firmware" ;;
                        c822|b822) echo "rtl88x2ce-dkms-git linux-firmware" ;;
                        b82c|c82c) echo "rtl88x2bu-dkms-git linux-firmware" ;;
                        b885|c885) echo "rtl8852au-dkms-git linux-firmware" ;;
                        8812|8814|881a|881b|8821|8811) echo "rtl8812au-openhd-dkms-git linux-firmware" ;;
                        8188|8189|818a|818b|818c) echo "rtl8188eu-dkms-git linux-firmware" ;;
                        *) echo "linux-firmware" ;;
                    esac
                    ;;
                broadcom) echo "broadcom-wl-dkms linux-firmware" ;;
                mediatek) echo "linux-firmware linux-firmware-mediatek" ;;
                atheros) echo "linux-firmware ath9k-htc-firmware" ;;
                qualcomm) echo "linux-firmware linux-firmware-qcom" ;;
                *) echo "linux-firmware iwd" ;;
            esac
            ;;
        ethernet)
            case "$vendor" in
                realtek)
                    case "$device_id" in
                        8125) echo "r8125-dkms linux-firmware" ;;
                        8168|8167|8169|8101|8111) echo "r8168-dkms linux-firmware" ;;
                        *) echo "linux-firmware" ;;
                    esac
                    ;;
                mediatek) echo "linux-firmware" ;;
                *) echo "" ;;
            esac
            ;;
    esac
}

get_network_driver_candidates() {
    local type="$1"
    local vendor="$2"
    local device_id="$3"
    case "$type" in
        ethernet)
            case "$vendor" in
                realtek)
                    case "$device_id" in
                        8125) echo "r8125-dkms|r8168-dkms" ;;
                        *) echo "r8168-dkms|r8125-dkms" ;;
                    esac
                    ;;
                *) echo "" ;;
            esac
            ;;
        wifi)
            case "$vendor" in
                realtek)
                    case "$device_id" in
                        b852|c852|b851|8852be) echo "8852be-dkms-git" ;;
                        c821) echo "rtl8821ce-dkms-git" ;;
                        c822|b822) echo "rtl88x2ce-dkms-git" ;;
                        b82c|c82c) echo "rtl88x2bu-dkms-git" ;;
                        b885|c885) echo "rtl8852au-dkms-git" ;;
                        8812|8814|881a|881b|8821|8811) echo "rtl8812au-openhd-dkms-git" ;;
                        8188|8189|818a|818b|818c) echo "rtl8188eu-dkms-git" ;;
                        *) echo "" ;;
                    esac
                    ;;
                broadcom) echo "broadcom-wl-dkms" ;;
                *) echo "" ;;
            esac
            ;;
    esac
}

aur_search_driver() {
    local term="$1"
    if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
        return 1
    fi
    local helper="yay"
    command -v paru >/dev/null 2>&1 && helper="paru"
    local out
    out=$($helper -Ss "$term" 2>/dev/null | grep -iE "dkms|driver" | awk '{print $1}' | head -3)
    echo "$out"
}

_aur_fetch_network_driver() {
    local model="$1"
    local device_id="$2"
    local helper="yay"
    command -v paru >/dev/null 2>&1 && helper="paru"
    command -v "$helper" >/dev/null 2>&1 || return 1
    local terms=()
    # Prefer searching by chip name from the model string (RTL8852BE -> rtl8852be-dkms).
    local chip=$(echo "$model" | grep -oiE "RTL[0-9]+[A-Z]*|MT[0-9]+|MT792[0-9]|AX[0-9]+" | head -1 | tr '[:upper:]' '[:lower:]')
    [[ -n $chip ]] && terms+=("${chip}-dkms" "${chip}")
    # Fall back to mapping known hex device ids to their package names.
    if [[ -n $device_id ]]; then
        local known=$(_realtek_wifi_pkg_by_id "$device_id")
        [[ -n $known ]] && terms+=("$known")
    fi
    local found=""
    for t in "${terms[@]}"; do
        found=$($helper -Ss "$t" 2>/dev/null | grep -iE "dkms" | awk '{print $1}' | grep -viE "firmware|bluetooth|openhd" | head -1)
        [[ -n $found ]] && break
    done
    echo "$found"
}

_realtek_wifi_pkg_by_id() {
    local device_id="$1"
    case "$device_id" in
        b852|c852|b851) echo "8852be-dkms-git" ;;
        c821) echo "rtl8821ce-dkms-git" ;;
        c82c) echo "rtl8821cu-dkms-git" ;;
        c822|b822) echo "rtl88x2ce-dkms-git" ;;
        b82c) echo "rtl88x2bu-dkms-git" ;;
        b885|c885) echo "rtl8852au-dkms-git" ;;
        8812|8814|881a|881b) echo "rtl8812au-openhd-dkms-git" ;;
        8188|8189|818a) echo "rtl8188eu-dkms-git" ;;
        *) echo "" ;;
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
    local pkgs="linux-firmware sof-firmware"
    # Vendor-specific firmware subpackages when matching hardware is present.
    local gpus=$(detect_gpus)
    if echo "$gpus" | grep -qE "^\S+\|\S+\|intel\|"; then
        pkgs+=" linux-firmware-intel"
    fi
    local nets=$(detect_network)
    if echo "$nets" | grep -qE "\|mediatek\|"; then
        pkgs+=" linux-firmware-mediatek"
    fi
    if echo "$nets" | grep -qE "\|qualcomm\||\|atheros\|"; then
        pkgs+=" linux-firmware-qcom"
    fi
    echo "$pkgs"
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
            # NPU drivers are optional extras; keep the row for display but
            # never count them among missing MAIN driver packages.
            results+="NPU|${vendor}|${model}|${driver}||\n"
        done <<<"$npus"
    fi
    local networks=$(detect_network)
    if [[ $networks != "NONE" && -n $networks ]]; then
        while IFS= read -r net; do
            IFS='|' read -r type vendor model driver device_id <<<"$net"
            local pkgs=$(get_network_packages "$type" "$vendor" "$device_id")
            local missing=""
            [[ -n $pkgs ]] && missing=$(_get_missing "$pkgs")
            results+="NET|${vendor}|${model}|${driver}|${pkgs}|${missing}|${device_id}\n"
            if [[ $driver == "none" ]]; then
                local hint=$(get_network_driver_candidates "$type" "$vendor" "$device_id")
                if [[ -n $hint ]]; then
                    results+="WARN|No driver bound for ${model} — install ${hint%%|*}||${hint}||\n"
                fi
            fi
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
    # GuC firmware check for Meteor Lake+
    local gpu_line=$(lspci -nn 2>/dev/null | grep -iE "VGA|3D|Display" | head -1)
    if echo "$gpu_line" | grep -qiE "meteor.*lake|Meteor|Arrow|Lunar|Battlemage"; then
        if [[ ! -d /lib/firmware/intel ]]; then
            results+="WARN|Intel GuC firmware not found — xe driver may fail. Install linux-firmware-intel.||||\n"
        fi
    fi
    echo -e "$results" | sed '/^$/d'
}

run_full_install() {
    local scan_data=$(run_full_scan)
    local missing_pkgs=""
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        IFS='|' read -r type vendor model driver pkgs missing device_id <<<"$line"
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
    local net_dkms=""
    local aur_extra=""
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        IFS='|' read -r type vendor model driver pkgs missing device_id <<<"$line"
        case "$type" in
            GPU)
                gpu_vendors_found+=("$vendor")
                [[ -n $missing ]] && missing_pkgs+=" $missing"
                ;;
            CPU | NPU | NET | BT | FW | OTHER)
                [[ -n $missing ]] && missing_pkgs+=" $missing"
                ;;
        esac
        if [[ $type == "NET" && $driver == "none" && -z $missing ]]; then
            local aur_pkg
            aur_pkg=$(_aur_fetch_network_driver "$model" "$device_id")
            if [[ -n $aur_pkg ]]; then
                missing_pkgs+=" $aur_pkg"
                aur_extra+=" $aur_pkg"
                net_dkms="$vendor"
            fi
        fi
        if [[ $type == "NET" && $missing == *"dkms"* ]]; then
            net_dkms="$vendor"
        fi
    done <<<"$scan_data"
    local unique_missing=$(echo "$missing_pkgs" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ')
    if [[ -z "$(echo "$unique_missing" | xargs)" ]]; then
        echo "ALL_DRIVERS_INSTALLED"
        return 0
    fi
    rx_log_file "info" "MISSING: $unique_missing"
    install_packages "$unique_missing"
    local install_status=$?
    if [[ $install_status -eq 0 ]]; then
        for vendor in "${gpu_vendors_found[@]}"; do
            case "$vendor" in
                nvidia)
                    configure_nvidia_drm >/dev/null
                    configure_ai_env "nvidia" >/dev/null
                    ;;
                intel)
                    configure_ai_env "intel" >/dev/null
                    ;;
                amd)
                    configure_ai_env "amd" >/dev/null
                    ;;
            esac
        done

        generate_hypr_env >/dev/null

        if echo "$unique_missing" | grep -qE "nvidia-open-dkms|nvidia"; then
            configure_mkinitcpio_nvidia >/dev/null
        fi

        if [[ -n $net_dkms ]]; then
            configure_network_driver "$net_dkms" "$unique_missing" >/dev/null
        fi

        if [[ -n $aur_extra ]]; then
            rx_log_file "info" "AUR_INSTALLED: $aur_extra"
        fi

        if echo "$unique_missing" | grep -qE "dkms|nvidia|cuda|rocm"; then
            rx_log_file "info" "INITRAMFS_UPDATE_NEEDED"
        fi
        rx_log_file "info" "INSTALL_COMPLETE"
        return 0
    else
        rx_log_file "error" "INSTALL_FAILED"
        return 1
    fi
}

_extra_driver_set() {
    # All optional/AI packages relevant to the detected hardware: per-GPU
    # compute stacks plus NPU accelerators. Prints space-separated names.
    local scan_data=$(run_full_scan)
    local extra_pkgs=""
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        IFS='|' read -r type vendor model driver pkgs missing device_id <<<"$line"
        if [[ $type == "GPU" ]]; then
            local ai_pkgs=$(get_gpu_ai_packages "$vendor")
            [[ -n $ai_pkgs ]] && extra_pkgs+=" $ai_pkgs"
        fi
    done <<<"$scan_data"
    local npus=$(detect_npu)
    if [[ $npus != "NONE" && -n $npus ]]; then
        while IFS= read -r npu; do
            IFS='|' read -r vendor model driver <<<"$npu"
            local npu_pkgs=$(get_npu_packages "$vendor")
            [[ -n $npu_pkgs ]] && extra_pkgs+=" $npu_pkgs"
        done <<<"$npus"
    fi
    echo "$extra_pkgs" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' '
}

run_extra_install() {
    # Optional/AI drivers only: CUDA/ROCm/oneAPI stacks plus other extras.
    # The base install (--install) never touches these.
    local scan_data=$(run_full_scan)
    local extra_pkgs=$(_extra_driver_set)
    local gpu_vendors_found=()
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        IFS='|' read -r type vendor model driver pkgs missing device_id <<<"$line"
        [[ $type == "GPU" ]] && gpu_vendors_found+=("$vendor")
    done <<<"$scan_data"

    if [[ -z "$(echo "$extra_pkgs" | xargs)" ]]; then
        echo "NO_EXTRA_DRIVERS"
        return 0
    fi
    echo "EXTRA_MISSING:$extra_pkgs"
    install_packages "$extra_pkgs"
    local install_status=$?
    if [[ $install_status -eq 0 ]]; then
        for vendor in "${gpu_vendors_found[@]}"; do
            configure_ai_env "$vendor" >/dev/null
        done
        generate_hypr_env >/dev/null
        if echo "$extra_pkgs" | grep -qE "rocm|intel-compute-runtime|level-zero"; then
            rx_log_file "info" "INITRAMFS_UPDATE_NEEDED"
        fi
        echo "EXTRA_INSTALL_COMPLETE"
    else
        echo "EXTRA_INSTALL_FAILED"
        return 1
    fi
}

list_extra_drivers() {
    # Report which optional/AI packages are missing (no install).
    local unique_extra=$(_extra_driver_set)
    if [[ -z "$(echo "$unique_extra" | xargs)" ]]; then
        echo "NONE"
        return 0
    fi
    local missing=""
    for p in $unique_extra; do
        _is_pkg_installed "$p" || missing+=" $p"
    done
    missing=$(echo "$missing" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ')
    if [[ -z "$(echo "$missing" | xargs)" ]]; then
        echo "NONE"
        return 0
    fi
    echo "$missing"
}

list_installed_extra_drivers() {
    # Report which optional/AI packages are installed (no changes).
    local unique_extra=$(_extra_driver_set)
    if [[ -z "$(echo "$unique_extra" | xargs)" ]]; then
        echo "NONE"
        return 0
    fi
    local installed=""
    for p in $unique_extra; do
        _is_pkg_installed "$p" && installed+=" $p"
    done
    installed=$(echo "$installed" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ')
    if [[ -z "$(echo "$installed" | xargs)" ]]; then
        echo "NONE"
        return 0
    fi
    echo "$installed"
}

run_extra_uninstall() {
    # Remove installed optional/AI drivers, with an interactive prompt.
    local installed=$(_extra_driver_set)
    local to_remove=""
    for p in $installed; do
        _is_pkg_installed "$p" && to_remove+=" $p"
    done
    to_remove=$(echo "$to_remove" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ')
    if [[ -z "$(echo "$to_remove" | xargs)" ]]; then
        echo "NO_EXTRA_DRIVERS_INSTALLED"
        return 0
    fi
    echo "EXTRA_UNINSTALL_PKGS:$to_remove"
    printf "Remove optional extra drivers? [y/N]: " >&2
    read -r confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "EXTRA_UNINSTALL_CANCELLED"
        return 0
    fi
    local helper="yay"
    command -v paru >/dev/null 2>&1 && helper="paru"
    if command -v "$helper" >/dev/null 2>&1; then
        $helper -Rns --noconfirm $to_remove 2>&1
    else
        sudo pacman -Rns --noconfirm $to_remove 2>&1
    fi
    local rm_status=$?
    if [[ $rm_status -eq 0 ]]; then
        generate_hypr_env >/dev/null
        echo "EXTRA_UNINSTALL_COMPLETE"
    else
        echo "EXTRA_UNINSTALL_FAILED"
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

_switch_driver() {
    local target="$1"
    local device_id=$(_get_intel_gpu_device_id)
    local current=$(_get_current_driver)

    local bl_type=$(bash "$RETRO_DIR/scripts/grub_core.sh" --detect-bootloader 2>/dev/null | cut -d'|' -f1)
    if [[ $bl_type == "unknown" || -z $bl_type ]]; then
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
        local params="i915.force_probe=!${device_id} xe.force_probe=${device_id}"
    elif [[ $target == "i915" ]]; then
        if [[ $current == "i915" ]]; then
            echo "ALREADY|i915"
            return 0
        fi
        local params=""
    fi

    bash "$RETRO_DIR/scripts/grub_core.sh" --apply-kernel-params "$params" >/dev/null
    set_var "DRIVER_KERNEL_PARAMS" "$params"

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

MODPROBE_DIR="/etc/modprobe.d"
MODULES_LOAD_DIR="/etc/modules-load.d"

_module_category() {
    local mod="$1"
    local kver=$(uname -r)
    local path=""
    if [[ -f /lib/modules/${kver}/modules.dep ]]; then
        path=$(awk -v m="$mod" '{t=$0; sub(/:.*$/, "", t); split(t, a, "/"); n=a[length(a)]; sub(/\.ko(\.(gz|xz|zst))?$/, "", n); if(n==m){print t; exit}}' /lib/modules/${kver}/modules.dep)
    fi
    [[ -z $path ]] && path=$(grep -E "(^|/)${mod}(\.ko(\.(gz|xz|zst))?)?$" /lib/modules/${kver}/modules.builtin 2>/dev/null | head -1)
    case "$path" in
        *drivers/net/*|*drivers/net/wireless/*) echo "network" ;;
        *drivers/net/ethernet/*) echo "network" ;;
        *drivers/gpu/*|*drivers/video/*|*drivers/gpu/drm/*) echo "display" ;;
        *drivers/media/*|*drivers/media/usb/*|*drivers/media/pci/*) echo "media" ;;
        *drivers/input/*) echo "input" ;;
        *drivers/audio/*|*sound/*) echo "audio" ;;
        *drivers/bluetooth/*|*net/bluetooth/*) echo "bluetooth" ;;
        *drivers/staging/*) echo "staging" ;;
        *drivers/usb/*|*drivers/usb/serial/*) echo "usb" ;;
        *drivers/char/*|*drivers/tty/*) echo "serial" ;;
        *drivers/md/*|*drivers/scsi/*|*drivers/ata/*|*drivers/nvme/*) echo "storage" ;;
        *drivers/mmc/*|*drivers/mtd/*) echo "storage" ;;
        *drivers/hid/*|*drivers/hid/usbhid/*) echo "hid" ;;
        *drivers/thermal/*) echo "thermal" ;;
        *arch/*|*kernel/arch/*) echo "arch" ;;
        *kernel/crypto/*|*crypto/*) echo "crypto" ;;
        *kernel/fs/*|*fs/*) echo "filesystem" ;;
        *updates/dkms/*|*extra/*) echo "dkms" ;;
        *) echo "other" ;;
    esac
}

_list_all_modules() {
    local kver=$(uname -r)
    local mod_dir="/lib/modules/${kver}"
    if [[ ! -f ${mod_dir}/modules.dep && ! -f ${mod_dir}/modules.builtin ]]; then
        return 0
    fi
    # Build a name -> full path map in a single awk pass (fast: one parse of
    # modules.dep) instead of grepping the file per module.
    local tmp
    tmp=$(mktemp)
    {
        [[ -f ${mod_dir}/modules.dep ]] && awk '{p=$0; sub(/:.*$/, "", p); split(p, a, "/"); n=a[length(a)]; sub(/\.ko(\.(gz|xz|zst))?$/, "", n); if(n!="") print n "\t" p}' "${mod_dir}/modules.dep"
        [[ -f ${mod_dir}/modules.builtin ]] && awk '{split($0, a, "/"); n=a[length(a)]; sub(/\.ko(\.(gz|xz|zst))?$/, "", n); if(n!="") print n "\t" $0}' "${mod_dir}/modules.builtin"
    } | sort -u >"$tmp"

    while IFS=$'\t' read -r mod path; do
        [[ -z $mod || $mod == *" "* ]] && continue
        local cat="other"
        case "$path" in
            *drivers/net/*|*drivers/net/wireless/*) cat="network" ;;
            *drivers/gpu/*|*drivers/video/*|*drivers/gpu/drm/*) cat="display" ;;
            *drivers/media/*) cat="media" ;;
            *drivers/input/*) cat="input" ;;
            *drivers/audio/*|*sound/*) cat="audio" ;;
            *drivers/bluetooth/*|*net/bluetooth/*) cat="bluetooth" ;;
            *drivers/staging/*) cat="staging" ;;
            *drivers/usb/*) cat="usb" ;;
            *drivers/char/*|*drivers/tty/*) cat="serial" ;;
            *drivers/md/*|*drivers/scsi/*|*drivers/ata/*|*drivers/nvme/*|*drivers/mmc/*|*drivers/mtd/*) cat="storage" ;;
            *drivers/hid/*) cat="hid" ;;
            *drivers/thermal/*) cat="thermal" ;;
            *arch/*|*kernel/arch/*) cat="arch" ;;
            *crypto/*) cat="crypto" ;;
            *fs/*) cat="filesystem" ;;
            *updates/dkms/*|*extra/*) cat="dkms" ;;
        esac
        echo "MODULE|${mod}|${cat}"
    done <"$tmp"
    rm -f "$tmp"
}

_module_descs() {
    # Batch descriptions for many modules in ONE subprocess invocation.
    # Reads all module names from argv and prints DESC|<name>|<description>
    # for each, reusing the builtin modinfo blob where possible.
    local kver=$(uname -r)
    local mod_dir="/lib/modules/${kver}"
    local blob=""
    if [[ -f ${mod_dir}/modules.builtin.modinfo ]]; then
        blob=$(tr '\0' '\n' < "${mod_dir}/modules.builtin.modinfo" 2>/dev/null | grep -E "\.description=" | sed -E 's/\.description=/\t/')
    fi
    local mod
    for mod in "$@"; do
        [[ -z $mod ]] && continue
        if [[ -n $blob ]]; then
            local desc=""
            desc=$(echo "$blob" | awk -F'\t' -v m="$mod" '$1==m{print $2; exit}')
            if [[ -n $desc ]]; then
                echo "DESC|${mod}|${desc}"
                continue
            fi
        fi
        local d=""
        d=$(modinfo -F description "$mod" 2>/dev/null)
        echo "DESC|${mod}|${d}"
    done
}

_module_info() {
    local mod="$1"
    [[ -z $mod ]] && { echo "ERROR|missing_module"; return 1; }
    if [[ ! $mod =~ ^[A-Za-z0-9_-]+$ ]]; then        echo "ERROR|invalid_module|${mod}"
        return 1
    fi
    local kver=$(uname -r)
    local desc=""
    if [[ -f /lib/modules/${kver}/modules.builtin.modinfo ]]; then
        desc=$(tr '\0' '\n' < /lib/modules/${kver}/modules.builtin.modinfo 2>/dev/null | grep -E "^${mod}\.description=" | head -1 | cut -d= -f2-)
    fi
    [[ -z $desc ]] && desc=$(modinfo -F description "$mod" 2>/dev/null)
    local author=$(modinfo -F author "$mod" 2>/dev/null)
    local license=$(modinfo -F license "$mod" 2>/dev/null)
    local version=$(modinfo -F version "$mod" 2>/dev/null)
    local depends=$(modinfo -F depends "$mod" 2>/dev/null)
    local firmware=$(modinfo -F firmware "$mod" 2>/dev/null | head -1)
    local builtin="no"
    if grep -qE "(^|/)${mod}(\.ko(\.(gz|xz|zst))?)?$" /lib/modules/${kver}/modules.builtin 2>/dev/null; then
        builtin="yes"
    fi
    echo "DESC|${desc}"
    echo "AUTHOR|${author}"
    echo "LICENSE|${license}"
    echo "VERSION|${version}"
    echo "DEPENDS|${depends}"
    echo "FIRMWARE|${firmware}"
    echo "BUILTIN|${builtin}"
    echo "CATEGORY|$(_module_category "$mod")"
}

_list_modprobe_files() {
    if [[ ! -d $MODPROBE_DIR ]]; then
        return 0
    fi
    for f in "$MODPROBE_DIR"/*.conf; do
        [[ -f $f ]] || continue
        echo "FILE|$(basename "$f")"
        while IFS= read -r line; do
            echo "CONTENT|${line}"
        done <"$f"
    done
}

_list_blacklisted() {
    if [[ ! -d $MODPROBE_DIR ]]; then
        return 0
    fi
    grep -rhE "^\s*blacklist\s+" "$MODPROBE_DIR" 2>/dev/null | awk '{print $2}' | sort -u | while read -r mod; do
        echo "BLACKLIST|${mod}"
    done
}

_modprobe_blacklist_add() {
    local module="$1"
    [[ -z $module ]] && { echo "ERROR|missing_module"; return 1; }
    if [[ ! $module =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR|invalid_module|${module}"
        return 1
    fi
    local exists
    exists=$(_module_exists "$module")
    if [[ $exists != EXISTS* ]]; then
        echo "ERROR|module_not_found|${module}"
        return 1
    fi
    local conf="${MODPROBE_DIR}/blacklist-${module}.conf"
    if grep -qE "^\s*blacklist\s+${module}\b" "$conf" 2>/dev/null; then
        echo "ALREADY|${module}"
        return 0
    fi
    echo "blacklist ${module}" | sudo tee "$conf" >/dev/null
    echo "ADDED|${module}"
}

_modprobe_blacklist_remove() {
    local module="$1"
    [[ -z $module ]] && { echo "ERROR|missing_module"; return 1; }
    local conf="${MODPROBE_DIR}/blacklist-${module}.conf"
    if [[ -f $conf ]]; then
        sudo rm -f "$conf"
    fi
    echo "REMOVED|${module}"
}

_list_modules_load() {
    if [[ ! -d $MODULES_LOAD_DIR ]]; then
        return 0
    fi
    grep -rhE "^\s*[a-zA-Z0-9_]+" "$MODULES_LOAD_DIR" 2>/dev/null | awk '{print $1}' | sort -u | while read -r mod; do
        echo "LOAD|${mod}"
    done
}

_module_exists() {
    local module="$1"
    [[ -z $module ]] && { echo "ERROR|missing_module"; return 1; }
    if [[ ! $module =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR|invalid_module|${module}"
        return 1
    fi
    local canonical
    canonical=$(modinfo -F name "$module" 2>/dev/null)
    if [[ -z $canonical ]]; then
        canonical=$(modinfo -k "$(uname -r)" -F name "$module" 2>/dev/null)
    fi
    if [[ -n $canonical ]]; then
        echo "EXISTS|${canonical}"
        return 0
    fi
    echo "NOT_FOUND|${module}"
    return 1
}

_modules_load_add() {
    local module="$1"
    [[ -z $module ]] && { echo "ERROR|missing_module"; return 1; }
    if [[ ! $module =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR|invalid_module|${module}"
        return 1
    fi
    local exists
    exists=$(_module_exists "$module")
    if [[ $exists != EXISTS* ]]; then
        echo "ERROR|module_not_found|${module}"
        return 1
    fi
    local conf="${MODULES_LOAD_DIR}/${module}.conf"
    if grep -qE "^\s*${module}\b" "$conf" 2>/dev/null; then
        echo "ALREADY|${module}"
        return 0
    fi
    echo "${module}" | sudo tee "$conf" >/dev/null
    echo "ADDED|${module}"
}

_modules_load_remove() {
    local module="$1"
    [[ -z $module ]] && { echo "ERROR|missing_module"; return 1; }
    local conf="${MODULES_LOAD_DIR}/${module}.conf"
    if [[ -f $conf ]]; then
        sudo rm -f "$conf"
    fi
    echo "REMOVED|${module}"
}

_module_state() {
    local module="$1"
    [[ -z $module ]] && { echo "ERROR|missing_module"; return 1; }
    if lsmod 2>/dev/null | awk '{print $1}' | grep -qx "$module"; then
        echo "LOADED|${module}"
    else
        echo "NOT_LOADED|${module}"
    fi
}

_module_load() {
    local module="$1"
    [[ -z $module ]] && { echo "ERROR|missing_module"; return 1; }
    sudo modprobe "$module" 2>&1
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "LOADED|${module}"
    else
        echo "ERROR|${module}"
    fi
    return $rc
}

_module_unload() {
    local module="$1"
    [[ -z $module ]] && { echo "ERROR|missing_module"; return 1; }
    sudo modprobe -r "$module" 2>&1
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "UNLOADED|${module}"
    else
        echo "ERROR|${module}"
    fi
    return $rc
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

_hardware_specs() {
    # CPU cores/threads
    local cpu_cores=$(grep -m1 "cpu cores" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')
    local cpu_threads=$(grep -m1 "siblings" /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')
    [[ -n $cpu_cores && -n $cpu_threads ]] && echo "CPU|${cpu_cores}|${cpu_threads}"

    # GPU compute units via device ID mapping
    local gpu_line=$(lspci -nn 2>/dev/null | grep -iE "VGA|3D|Display" | head -1)
    if [[ -n $gpu_line ]]; then
        local pci_id=$(echo "$gpu_line" | awk '{print $1}')
        local raw_model=$(echo "$gpu_line" | sed 's/^[0-9a-f:.]* //;s/ *\[[0-9a-f]*\] *//g;s/ *\[[0-9a-f]*:[0-9a-f]*\].*//;s/ (rev [0-9a-f]*)//;s/^[^:]*: //' | xargs)
        local nn_line=$(lspci -nn -s "$pci_id" 2>/dev/null)
        local vd_pair=$(echo "$nn_line" | grep -oP '\[([0-9a-f]{4}):([0-9a-f]{4})\]' | tr -d '[]')
        local vendor_id="${vd_pair%%:*}"
        local gpu_device="${vd_pair##*:}"
        local vendor=""
        case "$vendor_id" in
            8086) vendor="intel" ;;
            10de) vendor="nvidia" ;;
            1002) vendor="amd" ;;
        esac

        if [[ $vendor == "intel" && -n $gpu_device ]]; then
            local xe_cores=""
            case "$gpu_device" in
                7d45|7d55|7d40|7d60) xe_cores="8" ;;  # Meteor/Arrow Lake integrated
                7d67|7d68) xe_cores="8" ;;             # Lunar Lake integrated
                56a0|56a1) xe_cores="32" ;;             # Arc A770
                56a2|56a3) xe_cores="28" ;;             # Arc A750
                56b0|56b1) xe_cores="16" ;;             # Arc A580
                56b2|56b3) xe_cores="8" ;;              # Arc A380
                56c0|56c1) xe_cores="8" ;;              # Arc A310
                *) xe_cores="" ;;
            esac
            echo "GPU|${vendor}|${xe_cores}|Xe Cores|${gpu_device}|${raw_model}"
        elif [[ $vendor == "nvidia" && -n $gpu_device ]]; then
            local cuda_cores=""
            if command -v nvidia-smi >/dev/null 2>&1; then
                local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
                [[ -z $gpu_name ]] && gpu_name="$raw_model"
                case "$gpu_name" in
                    *RTX*4090*) cuda_cores="16384" ;; *RTX*4080*) cuda_cores="9728" ;;
                    *RTX*4070*) cuda_cores="5888" ;;  *RTX*4060*) cuda_cores="3072" ;;
                    *RTX*3090*) cuda_cores="10496" ;; *RTX*3080*) cuda_cores="8704" ;;
                    *RTX*3070*) cuda_cores="5888" ;;  *RTX*3060*) cuda_cores="3584" ;;
                    *RTX*2080*) cuda_cores="4352" ;;  *RTX*2070*) cuda_cores="2304" ;;
                    *RTX*2060*) cuda_cores="2176" ;;  *GTX*1660*) cuda_cores="1408" ;;
                    *GTX*1650*) cuda_cores="896" ;;
                esac
            fi
            [[ -z $cuda_cores ]] || echo "GPU|${vendor}|${cuda_cores}|CUDA Cores|${gpu_device}|${raw_model}"
        elif [[ $vendor == "amd" && -n $gpu_device ]]; then
            local sp_count=""
            case "$gpu_device" in
                164e|164f|1650) sp_count="512" ;;  # RX 6400/6500
                73df|73ff|743f) sp_count="2304" ;; # RX 7600
                744c) sp_count="3840" ;;           # RX 7700 XT
                747e) sp_count="5376" ;;           # RX 7800 XT
                7643|74b5) sp_count="6144" ;;      # RX 7900 GRE
            esac
            [[ -z $sp_count ]] || echo "GPU|${vendor}|${sp_count}|Stream Processors|${gpu_device}|${raw_model}"
        fi
    fi

    # NPU TOPS — prefer vpu driver or Processing accelerators class
    local npu_line=$(lspci 2>/dev/null | grep -iE "Processing accelerators" | head -1)
    if [[ -z $npu_line ]]; then
        npu_line=$(lspci 2>/dev/null | grep -iE "NPU" | head -1)
    fi
    if [[ -n $npu_line ]]; then
        local npu_desc=$(echo "$npu_line" | sed 's/^[0-9a-f:]* //;s/ (rev [0-9a-f]*)//;s/.*: //' | xargs)
        local npu_tops="11"
        if echo "$npu_desc" | grep -qi "lunar\|lnl\|258V\|268V\|288V"; then
            npu_tops="48"
        elif echo "$npu_desc" | grep -qi "200H\|200V\|arrow"; then
            npu_tops="13"
        fi
        echo "NPU|${npu_tops}|TOPS|${npu_desc}"
    fi
}

_list_recommended_packages() {
    local scan_data=$(run_full_scan)
    local seen=""
    while IFS= read -r line; do
        [[ -z $line ]] && continue
        IFS='|' read -r type vendor model driver pkgs missing device_id <<<"$line"
        [[ -z $pkgs ]] && continue
        for p in $pkgs; do
            if ! echo " $seen " | grep -q " $p "; then
                seen+=" $p"
                local ver=$(pacman -Q "$p" 2>/dev/null | awk '{print $2}')
                if [[ -n $ver ]]; then
                    echo "PKG|${type}|${p}|${ver}|installed"
                else
                    echo "PKG|${type}|${p}||missing"
                fi
            fi
        done
    done <<<"$scan_data"
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
    local env_file="$RETRO_CONFIG/env.lua"
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

    # Ensure file exists with header
    if [[ ! -f $env_file ]]; then
        echo "-- GPU driver environment (generated by retro driver)" > "$env_file"
    fi

    # Strip old GPU env lines and surrounding blank/comment lines
    for var in LIBVA_DRIVER_NAME __GLX_VENDOR_LIBRARY_NAME GBM_BACKEND NVD_BACKEND VDPAU_DRIVER mesa_glthread; do
        sed -i "/hl.env(\"${var}\"/d" "$env_file" 2>/dev/null
    done
    sed -i '/^-- .*GPU.*$/d' "$env_file" 2>/dev/null
    sed -i '/^$/N;/^\n$/D' "$env_file" 2>/dev/null

    # Build new GPU section
    local new_section=""
    local result_line=""
    if $is_hybrid; then
        new_section+="-- Intel + NVIDIA Hybrid\n"
        new_section+='hl.env("LIBVA_DRIVER_NAME", "iHD")\n'
        new_section+='hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")\n'
        new_section+='hl.env("GBM_BACKEND", "nvidia-drm")\n'
        new_section+='hl.env("INTEL_DEBUG", "norbc")\n'
        result_line="result=success|type=hybrid"
    elif $has_nvidia; then
        new_section+="-- NVIDIA GPU\n"
        new_section+='hl.env("GBM_BACKEND", "nvidia-drm")\n'
        new_section+='hl.env("LIBVA_DRIVER_NAME", "nvidia")\n'
        new_section+='hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")\n'
        new_section+='hl.env("NVD_BACKEND", "direct")\n'
        result_line="result=success|type=nvidia"
    elif $has_amd; then
        new_section+="-- AMD GPU\n"
        new_section+='hl.env("LIBVA_DRIVER_NAME", "radeonsi")\n'
        new_section+='hl.env("VDPAU_DRIVER", "radeonsi")\n'
        new_section+='hl.env("mesa_glthread", "true")\n'
        result_line="result=success|type=amd"
    elif $has_intel; then
        new_section+="-- Intel GPU\n"
        new_section+='hl.env("LIBVA_DRIVER_NAME", "iHD")\n'
        new_section+='hl.env("VDPAU_DRIVER", "va_gl")\n'
        new_section+='hl.env("mesa_glthread", "true")\n'
        new_section+='hl.env("INTEL_DEBUG", "norbc")\n'
        result_line="result=success|type=intel"
    else
        new_section+="-- No GPU detected - using default settings\n"
        new_section+='hl.env("LIBVA_DRIVER_NAME", "iHD")\n'
        new_section+='hl.env("mesa_glthread", "true")\n'
        new_section+='hl.env("INTEL_DEBUG", "norbc")\n'
        result_line="result=warn|no_gpu_detected"
    fi

    # Insert GPU section after the first line (header), before remaining content
    local tmp=$(mktemp)
    {
        sed -n '1p' "$env_file"
        echo ""
        echo -e "$new_section"
        sed -n '2,$p' "$env_file" | awk 'NF{found=1} found' | awk '!NF && !blank{blank=1; print ""; next} NF{blank=0; print}'
    } > "$tmp"
    mv "$tmp" "$env_file"

    echo "$result_line"
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

configure_network_driver() {
    local vendor="$1"
    local installed_pkgs="$2"
    if [[ $vendor != "realtek" ]]; then
        echo "result=skipped|reason=no_blacklist_needed"
        return 0
    fi

    if echo "$installed_pkgs" | grep -qE "r8125-dkms"; then
        local bl="/etc/modprobe.d/blacklist-r8169.conf"
        if ! grep -q "blacklist r8169" "$bl" 2>/dev/null; then
            echo "blacklist r8169" | sudo tee "$bl" >/dev/null
            echo "result=blacklist_r8169"
        else
            echo "result=blacklist_already_set"
        fi
        local load="/etc/modules-load.d/r8125.conf"
        if ! grep -q "^r8125" "$load" 2>/dev/null; then
            echo "r8125" | sudo tee "$load" >/dev/null
        fi
    elif echo "$installed_pkgs" | grep -qE "r8168-dkms"; then
        local bl="/etc/modprobe.d/blacklist-r8169.conf"
        if ! grep -q "blacklist r8169" "$bl" 2>/dev/null; then
            echo "blacklist r8169" | sudo tee "$bl" >/dev/null
            echo "result=blacklist_r8169"
        fi
        local load="/etc/modules-load.d/r8168.conf"
        if ! grep -q "^r8168" "$load" 2>/dev/null; then
            echo "r8168" | sudo tee "$load" >/dev/null
        fi
    fi

    if command -v mkinitcpio >/dev/null 2>&1; then
        sudo mkinitcpio -P 2>&1 | head -5
    fi
    echo "result=network_driver_configured"
}

_net_driver_blacklist() {
    local target="$1"
    local bl="/etc/modprobe.d/blacklist-r8169.conf"
    case "$target" in
        r8125)
            echo "blacklist r8169" | sudo tee "$bl" >/dev/null
            echo "r8125" | sudo tee /etc/modules-load.d/r8125.conf >/dev/null
            sudo modprobe -r r8169 2>/dev/null
            sudo modprobe r8125 2>/dev/null
            echo "SWITCHED|r8125"
            ;;
        r8168)
            echo "blacklist r8169" | sudo tee "$bl" >/dev/null
            echo "r8168" | sudo tee /etc/modules-load.d/r8168.conf >/dev/null
            sudo modprobe -r r8169 2>/dev/null
            sudo modprobe r8168 2>/dev/null
            echo "SWITCHED|r8168"
            ;;
        r8169)
            sudo rm -f "$bl" 2>/dev/null
            sudo rm -f /etc/modules-load.d/r8125.conf /etc/modules-load.d/r8168.conf 2>/dev/null
            sudo modprobe -r r8125 r8168 2>/dev/null
            sudo modprobe r8169 2>/dev/null
            echo "SWITCHED|r8169"
            ;;
        *) echo "ERROR|invalid_network_driver" ;;
    esac
}

show_hypr_env() {
    local env_file="$RETRO_CONFIG/env.lua"

    if [[ -f $env_file ]]; then
        echo "result=success|path=$env_file"
    else
        echo "result=error|reason=env_file_not_found"
        return 1
    fi
}

_generate_hw_cmdline() {
    local gpu_vendors=()
    local cpu_vendor=""
    local cmdline=""

    if [[ -f /proc/cpuinfo ]]; then
        local vendor_id=$(grep -m1 "vendor_id" /proc/cpuinfo | awk -F': ' '{print $2}')
        case "$vendor_id" in
            *Intel*) cpu_vendor="intel" ;;
            *AMD*) cpu_vendor="amd" ;;
        esac
    fi

    local gpus=$(detect_gpus)
    if [[ $gpus != "NONE" && -n $gpus ]]; then
        while IFS= read -r gpu; do
            IFS='|' read -r pci_id vendor_id vendor model driver <<<"$gpu"
            gpu_vendors+=("$vendor")
        done <<<"$gpus"
    fi

    if [[ " ${gpu_vendors[*]} " =~ " intel" ]]; then
        cmdline+=" i915.enable_psr=1 i915.enable_fbc=1 i915.enable_guc=3"
    fi

    if [[ $cpu_vendor == "intel" ]]; then
        cmdline+=" intel_iommu=on iommu=pt"
    fi

    if [[ " ${gpu_vendors[*]} " =~ " amd" ]]; then
        cmdline+=" amdgpu.sg=0"
    fi

    if [[ $cpu_vendor == "amd" ]]; then
        cmdline+=" amd_iommu=on iommu=pt"
    fi

    if [[ " ${gpu_vendors[*]} " =~ " nvidia" ]]; then
        cmdline+=" nvidia-drm.modeset=1 fbdev=1"
    fi

    echo "$cmdline"
}

_thermal_readings() {
    local cpu_temp=""
    local gpu_temp=""
    local npu_temp=""

    # CPU — x86_pkg_temp or similar
    local cpu_zone=$(find /sys/class/thermal -maxdepth 1 -name "thermal_zone*" 2>/dev/null | while read z; do
        [[ $(cat "$z/type" 2>/dev/null) == "x86_pkg_temp" ]] && echo "$z" && break
    done)
    [[ -z $cpu_zone ]] && cpu_zone=$(find /sys/class/thermal -maxdepth 1 -name "thermal_zone*" 2>/dev/null | while read z; do
        [[ $(cat "$z/type" 2>/dev/null) == "cpu-thermal" ]] && echo "$z" && break
    done)
    if [[ -n $cpu_zone && -f $cpu_zone/temp ]]; then
        cpu_temp=$(($(cat "$cpu_zone/temp") / 1000))
    fi
    [[ -n $cpu_temp ]] && echo "CPU|${cpu_temp}"

    # GPU — DRM hwmon
    local gpu_hwmon=$(find /sys/class/drm -maxdepth 2 -path "*/hwmon/hwmon*/temp1_input" 2>/dev/null | head -1)
    if [[ -z $gpu_hwmon ]]; then
        gpu_hwmon=$(find /sys/class/drm -maxdepth 3 -path "*/device/hwmon/hwmon*/temp1_input" 2>/dev/null | head -1)
    fi
    if [[ -n $gpu_hwmon ]]; then
        gpu_temp=$(($(cat "$gpu_hwmon") / 1000))
    elif command -v nvidia-smi >/dev/null 2>&1; then
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1)
    fi
    [[ -n $gpu_temp ]] && echo "GPU|${gpu_temp}"

    # NPU — look for thermal zone with npu/vpu in type name
    local npu_zone=$(find /sys/class/thermal -maxdepth 1 -name "thermal_zone*" 2>/dev/null | while read z; do
        local t=$(cat "$z/type" 2>/dev/null)
        [[ $t == *"npu"* || $t == *"vpu"* || $t == *"NPU"* ]] && echo "$z" && break
    done)
    if [[ -n $npu_zone && -f $npu_zone/temp ]]; then
        npu_temp=$(($(cat "$npu_zone/temp") / 1000))
    fi
    [[ -n $npu_temp ]] && echo "NPU|${npu_temp}"
}

_check_updates() {
    local all_pkgs=$(_list_recommended_packages | awk -F'|' '{print $3}')
    local updatable=""
    local count=0
    for p in $all_pkgs; do
        if pacman -Qu "$p" 2>/dev/null | grep -q "^$p "; then
            updatable+=" $p"
            ((count++))
        fi
    done
    if [[ $count -gt 0 ]]; then
        echo "UPDATES|${count}|${updatable}"
    else
        echo "UPDATES|0|"
    fi
}

_configure_intel() {
    local device_id=$(_get_intel_gpu_device_id)
    [[ -z $device_id ]] && echo "ERROR|no_intel_gpu" && return 1

    local conf_file="/usr/lib/modprobe.d/intel.conf"
    local conf_dir=$(dirname "$conf_file")
    if [[ ! -d $conf_dir ]]; then
        sudo mkdir -p "$conf_dir" 2>/dev/null || { echo "ERROR|mkdir_failed"; return 1; }
    fi
    echo "options i915 force_probe=!${device_id}" | sudo tee "$conf_file" >/dev/null
    echo "options xe force_probe=${device_id}" | sudo tee -a "$conf_file" >/dev/null
    echo "MODPROBE_CONFIGURED|${device_id}"

    # Set INTEL_DEBUG=norbc globally
    local env_file="/etc/environment"
    if grep -q "^INTEL_DEBUG=" "$env_file" 2>/dev/null; then
        sudo sed -i "s|^INTEL_DEBUG=.*|INTEL_DEBUG=norbc|" "$env_file"
    else
        echo "INTEL_DEBUG=norbc" | sudo tee -a "$env_file" >/dev/null
    fi
    echo "INTEL_DEBUG_SET|norbc"

    # Ensure firmware is installed
    if ! _is_pkg_installed "linux-firmware-intel" && ! ls /lib/firmware/intel/*.bin 2>/dev/null | head -1 | grep -q .; then
        echo "WARN|linux-firmware-intel recommended for xe driver"
    fi

    echo "CONFIGURE_COMPLETE"
}

_check_env() {
    local env_file="$RETRO_CONFIG/env.lua"
    if [[ ! -f $env_file ]]; then
        echo "ENV|missing"
        return
    fi
    if grep -qE "LIBVA_DRIVER_NAME|GBM_BACKEND|__GLX_VENDOR_LIBRARY_NAME|NVD_BACKEND|VDPAU_DRIVER|mesa_glthread" "$env_file" 2>/dev/null; then
        echo "ENV|ok"
    else
        echo "ENV|stale"
    fi
}

case "$1" in
    "--scan") run_full_scan ;;
    "--install") run_full_install ;;
    "--install-confirmed") run_full_install_confirmed ;;
    "--install-extra") run_extra_install ;;
    "--extra-list") list_extra_drivers ;;
    "--extra-installed") list_installed_extra_drivers ;;
    "--extra-uninstall") run_extra_uninstall ;;
    "--verify") verify_install "$2" ;;
    "--info") show_device_info "$2" ;;
    "--services") get_service_hints ;;
    "--sys-ai-env") sys_check_ai_env ;;
    "--kernel-warn") _kernel_warnings ;;
    "--switch") _switch_driver "$2" ;;
    "--net-switch") _net_driver_blacklist "$2" ;;
    "--net-configure") configure_network_driver "$2" "$3" ;;
    "--net-drivers") get_network_driver_candidates "$2" "$3" "$4" ;;
    "--modules") _list_module_params "${@:2}" ;;
    "--modules-set") _set_module_param "$2" "$3" "$4" ;;
    "--modprobe-files") _list_modprobe_files ;;
    "--blacklist-list") _list_blacklisted ;;
    "--blacklist-add") _modprobe_blacklist_add "$2" ;;
    "--blacklist-remove") _modprobe_blacklist_remove "$2" ;;
    "--modules-load-list") _list_modules_load ;;
    "--modules-load-add") _modules_load_add "$2" ;;
    "--modules-load-remove") _modules_load_remove "$2" ;;
    "--module-state") _module_state "$2" ;;
    "--module-load") _module_load "$2" ;;
    "--module-unload") _module_unload "$2" ;;
    "--module-exists") _module_exists "$2" ;;
    "--module-list") _list_all_modules ;;
    "--module-info") _module_info "$2" ;;
    "--module-descs") _module_descs "${@:2}" ;;
    "--conflicts") _check_driver_conflicts ;;
    "--dual-gpu") _detect_dual_gpu ;;
    "--optimus") _setup_optimus ;;
    "--hybrid-amd") _setup_hybrid_amd ;;
    "--gpu-status") _get_gpu_status ;;
    "--device-id") _get_intel_gpu_device_id ;;
    "--current-driver") _get_current_driver ;;
    "--profile") get_profile_packages "$2" ;;
    "--temps") _thermal_readings ;;
    "--configure-intel") _configure_intel ;;
    "--check-updates") _check_updates ;;
    "--check-env") _check_env ;;
    "--packages") _list_recommended_packages ;;
    "--hardware-specs") _hardware_specs ;;
    "--firmware-scan") _fwupd_scan ;;
    "--firmware-install") _fwupd_install ;;
    "--firmware-status") _fwupd_status ;;
    "--hypr") generate_hypr_env "$2" ;;
    "--hypr-env") generate_hypr_env "$2" ;;
    "--hypr-show") show_hypr_env ;;
    "--hypr-env-show") show_hypr_env ;;
    "--mkinit") configure_mkinitcpio_nvidia ;;
    "--hw-cmdline") _generate_hw_cmdline ;;
esac
