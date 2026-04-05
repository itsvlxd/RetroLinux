#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/log.sh"

rx_detect_gpu() {
    local gpus=()
    local gpu_info=""

    if ! command -v lspci >/dev/null 2>&1; then
        rx_log "ERROR" "lspci not found. Install pciutils."
        return 1
    fi

    while IFS= read -r line; do
        local vendor=""
        local model=""
        local driver=""
        local packages=""

        model=$(echo "$line" | sed 's/.*VGA compatible controller: //;s/.*3D controller: //;s/.*Display controller: //')

        if echo "$model" | grep -qi "nvidia"; then
            vendor="nvidia"
        elif echo "$model" | grep -qi "amd\|advanced micro devices\|ati\|radeon"; then
            vendor="amd"
        elif echo "$model" | grep -qi "intel"; then
            vendor="intel"
        else
            vendor="unknown"
        fi

        local pci_id=$(echo "$line" | grep -oP '^[0-9a-f:]+')
        if [[ -n $pci_id ]]; then
            driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')
        fi

        case "$vendor" in
            nvidia)
                local gpu_type="discrete"
                echo "$model" | grep -qi "optimus\|laptop\|notebook" && gpu_type="hybrid"

                local prefer_prop=$(get_var "DRIVER_GPU_PREFER" 2>/dev/null)
                if [[ $prefer_prop == "opensource" ]]; then
                    packages="nouveau"
                else
                    local kernel=$(uname -r)
                    if [[ $kernel == *"zen"* ]]; then
                        packages="nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils"
                    else
                        packages="nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils"
                    fi

                    [[ $gpu_type == "hybrid" ]] && packages+=" nvidia-prime"
                fi
                ;;
            amd)
                packages="mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon"
                ;;
            intel)
                packages="mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver"
                ;;
            *)
                packages="mesa lib32-mesa"
                ;;
        esac

        gpus+=("$vendor|$model|$driver|$packages")
    done < <(lspci | grep -E "VGA|3D|Display")

    if [[ ${#gpus[@]} -eq 0 ]]; then
        rx_log "WARN" "No GPU detected"
        return 1
    fi

    for gpu in "${gpus[@]}"; do
        echo "$gpu"
    done
}

rx_detect_network() {
    local networks=()

    local wifi_device=$(lspci 2>/dev/null | grep -i "network\|wireless" | head -1)
    local wifi_vendor=""
    local wifi_model=""
    local wifi_packages=""

    if [[ -n $wifi_device ]]; then
        wifi_model=$(echo "$wifi_device" | sed 's/.*Network controller: //;s/.*Wireless controller: //')

        if echo "$wifi_model" | grep -qi "intel"; then
            wifi_vendor="intel"
            wifi_packages="iwlwifi-firmware linux-firmware"
        elif echo "$wifi_model" | grep -qi "realtek\|rtl"; then
            wifi_vendor="realtek"
            wifi_packages="rtl88xxau-aircrack-dkms-git linux-firmware"
        elif echo "$wifi_model" | grep -qi "broadcom\|bcm"; then
            wifi_vendor="broadcom"
            wifi_packages="broadcom-wl-dkms"
        elif echo "$wifi_model" | grep -qi "mediatek\|mtk"; then
            wifi_vendor="mediatek"
            wifi_packages="linux-firmware"
        elif echo "$wifi_model" | grep -qi "qualcomm\|atheros\|ath"; then
            wifi_vendor="atheros"
            wifi_packages="linux-firmware ath9k-htc-firmware"
        else
            wifi_vendor="unknown"
            wifi_packages="linux-firmware"
        fi

        local wifi_driver=""
        local wifi_pci=$(echo "$wifi_device" | grep -oP '^[0-9a-f:]+')
        [[ -n $wifi_pci ]] && wifi_driver=$(lspci -k -s "$wifi_pci" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')

        networks+=("wifi|$wifi_vendor|$wifi_model|$wifi_driver|$wifi_packages")
    fi

    # Ethernet
    local eth_device=$(lspci 2>/dev/null | grep -i "ethernet" | head -1)
    local eth_vendor=""
    local eth_model=""
    local eth_packages=""

    if [[ -n $eth_device ]]; then
        eth_model=$(echo "$eth_device" | sed 's/.*Ethernet controller: //')

        if echo "$eth_model" | grep -qi "intel\|e1000\|igb\|ixgbe"; then
            eth_vendor="intel"
            eth_packages=""
        elif echo "$eth_model" | grep -qi "realtek\|rtl81"; then
            eth_vendor="realtek"
            eth_packages="r8168-dkms"
        elif echo "$eth_model" | grep -qi "broadcom\|tg3"; then
            eth_vendor="broadcom"
            eth_packages=""
        elif echo "$eth_model" | grep -qi "killer"; then
            eth_vendor="killer"
            eth_packages=""
        else
            eth_vendor="unknown"
            eth_packages=""
        fi

        local eth_driver=""
        local eth_pci=$(echo "$eth_device" | grep -oP '^[0-9a-f:]+')
        [[ -n $eth_pci ]] && eth_driver=$(lspci -k -s "$eth_pci" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')

        networks+=("ethernet|$eth_vendor|$eth_model|$eth_driver|$eth_packages")
    fi

    if command -v lsusb >/dev/null 2>&1; then
        local usb_wifi=$(lsusb 2>/dev/null | grep -i "wireless\|wifi\|802.11" | head -1)
        if [[ -n $usb_wifi ]]; then
            networks+=("usb_wifi|unknown|$usb_wifi||linux-firmware")
        fi
    fi

    if [[ ${#networks[@]} -eq 0 ]]; then
        rx_log "WARN" "No network devices detected"
        return 1
    fi

    for net in "${networks[@]}"; do
        echo "$net"
    done
}

rx_detect_audio() {
    local audio_devices=()

    if ! command -v lspci >/dev/null 2>&1; then
        rx_log "ERROR" "lspci not found"
        return 1
    fi

    while IFS= read -r line; do
        local model=$(echo "$line" | sed 's/.*Audio device: //;s/.*Multimedia audio controller: //')
        local vendor="unknown"

        echo "$model" | grep -qi "intel" && vendor="intel"
        echo "$model" | grep -qi "amd\|ati" && vendor="amd"
        echo "$model" | grep -qi "nvidia" && vendor="nvidia"
        echo "$model" | grep -qi "realtek" && vendor="realtek"
        echo "$model" | grep -qi "creative" && vendor="creative"

        local pci_id=$(echo "$line" | grep -oP '^[0-9a-f:]+')
        local driver=""
        [[ -n $pci_id ]] && driver=$(lspci -k -s "$pci_id" 2>/dev/null | grep "Kernel driver in use:" | awk -F': ' '{print $2}')

        audio_devices+=("pci|$vendor|$model|$driver")
    done < <(lspci | grep -i "audio\|multimedia")

    if command -v lsusb >/dev/null 2>&1; then
        while IFS= read -r line; do
            audio_devices+=("usb|unknown|$line|")
        done < <(lsusb 2>/dev/null | grep -i "audio")
    fi

    if [[ ${#audio_devices[@]} -eq 0 ]]; then
        rx_log "WARN" "No audio devices detected"
        return 1
    fi

    for dev in "${audio_devices[@]}"; do
        echo "$dev"
    done
}

rx_detect_bluetooth() {
    local bt_packages="bluez bluez-utils"

    if command -v lsusb >/dev/null 2>&1; then
        local usb_bt=$(lsusb 2>/dev/null | grep -i "bluetooth")
        if [[ -n $usb_bt ]]; then
            echo "usb|unknown|$usb_bt||$bt_packages"
            return 0
        fi
    fi

    if command -v lspci >/dev/null 2>&1; then
        local pci_bt=$(lspci 2>/dev/null | grep -i "bluetooth")
        if [[ -n $pci_bt ]]; then
            local model=$(echo "$pci_bt" | sed 's/.*Communication controller: //')
            local vendor="unknown"
            echo "$model" | grep -qi "intel" && vendor="intel"
            echo "$model" | grep -qi "realtek" && vendor="realtek"

            echo "pci|$vendor|$model||$bt_packages"
            return 0
        fi
    fi

    rx_log "WARN" "No Bluetooth device detected"
    return 1
}

rx_detect_cpu() {
    if [[ ! -f /proc/cpuinfo ]]; then
        rx_log "ERROR" "/proc/cpuinfo not found"
        return 1
    fi

    local vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | awk -F': ' '{print $2}')
    local model=$(grep -m1 "model name" /proc/cpuinfo | awk -F': ' '{print $2}')
    local packages=""

    case "$vendor" in
        *Intel*)
            packages="intel-ucode"
            ;;
        *AMD*)
            packages="amd-ucode"
            ;;
        *)
            rx_log "WARN" "Unknown CPU vendor: $vendor"
            return 1
            ;;
    esac

    echo "$vendor|$model|$packages"
}

rx_detect_input() {
    local input_packages=""

    local has_touchpad=false
    local has_touchscreen=false
    local has_gamepad=false

    if command -v libinput >/dev/null 2>&1 || ls /proc/bus/input/devices 2>/dev/null | grep -qi "touchpad"; then
        has_touchpad=true
    fi

    if lsusb 2>/dev/null | grep -qi "touchscreen"; then
        has_touchscreen=true
    fi

    if lsusb 2>/dev/null | grep -qi "gamepad\|joystick\|controller"; then
        has_gamepad=true
    fi

    local packages="libinput xf86-input-libinput"
    [[ $has_gamepad == true ]] && packages+=" joyutils"

    echo "input|mixed|Input Devices||$packages"
}

rx_detect_storage() {
    local storage_packages=""

    if command -v lspci >/dev/null 2>&1; then
        local nvme=$(lspci 2>/dev/null | grep -i "nvme")
        local sata=$(lspci 2>/dev/null | grep -i "sata\|ide")

        [[ -n $nvme ]] && storage_packages+="nvme-cli "

        local raid=$(lspci 2>/dev/null | grep -i "raid")
        if [[ -n $raid ]]; then
            if echo "$raid" | grep -qi "intel"; then
                storage_packages+="intel-vmd"
            elif echo "$raid" | grep -qi "lsi\|megaraid"; then
                storage_packages+="megaraid-utils"
            fi
        fi
    fi

    [[ -z $storage_packages ]] && storage_packages="none"
    echo "storage|mixed|Storage Controllers||$storage_packages"
}

rx_get_firmware_packages() {
    echo "linux-firmware sof-firmware"
}

rx_is_pkg_installed() {
    pacman -Qq "$1" >/dev/null 2>&1
}

rx_get_missing_packages() {
    local packages="$1"
    local missing=()

    for pkg in $packages; do
        [[ $pkg == "none" || -z $pkg ]] && continue
        if ! rx_is_pkg_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done

    echo "${missing[*]}"
}
