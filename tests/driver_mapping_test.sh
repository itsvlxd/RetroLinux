#!/bin/bash
# Description: Verify driver_core.sh device-id -> package mappings

if [[ -z $RETRO_DIR ]]; then
    export RETRO_DIR="$(dirname "$(readlink -f "$0")")"
else
    export RETRO_DIR="$RETRO_DIR"
fi

FAILED=0

check_pkg() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc -> expected '$expected', got '$actual'"
        FAILED=1
    fi
}

# Realtek WiFi hex device-ids (as extracted by detect_network from lspci)
check_pkg "RTL8852BE (b852)" "8852be-dkms-git linux-firmware" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_packages wifi realtek b852)"
check_pkg "RTL8852CE (c852)" "8852be-dkms-git linux-firmware" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_packages wifi realtek c852)"
check_pkg "RTL8821CE (c821)" "rtl8821ce-dkms-git linux-firmware" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_packages wifi realtek c821)"
check_pkg "RTL8822CE (c822)" "rtl88x2ce-dkms-git linux-firmware" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_packages wifi realtek c822)"
check_pkg "RTL8812AU (8812)" "rtl8812au-openhd-dkms-git linux-firmware" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_packages wifi realtek 8812)"

# Ethernet
check_pkg "RTL8125 (8125)" "r8125-dkms linux-firmware" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_packages ethernet realtek 8125)"
check_pkg "RTL8168 (8168)" "r8168-dkms linux-firmware" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_packages ethernet realtek 8168)"

# Vendor firmware
check_pkg "Qualcomm WiFi firmware" "linux-firmware linux-firmware-qcom" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_packages wifi qualcomm 1234)"
check_pkg "MediaTek WiFi firmware" "linux-firmware linux-firmware-mediatek" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_packages wifi mediatek 1234)"

# Driver candidates
check_pkg "candidate RTL8125" "r8125-dkms|r8168-dkms" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_driver_candidates ethernet realtek 8125)"
check_pkg "candidate RTL8852BE" "8852be-dkms-git" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_network_driver_candidates wifi realtek b852)"

# AI extras
check_pkg "nvidia AI extras" "cuda cudnn nvidia-container-toolkit" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_gpu_ai_packages nvidia)"
check_pkg "amd AI extras" "rocm-hip-sdk" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_gpu_ai_packages amd)"
check_pkg "intel AI extras" "intel-compute-runtime level-zero-loader" \
    "$(source "$RETRO_DIR/scripts/driver_core.sh"; get_gpu_ai_packages intel)"

# Extra-installed list never errors and returns either NONE or package names
extra_installed=$(bash "$RETRO_DIR/scripts/driver_core.sh" --extra-installed 2>/dev/null)
if [[ $extra_installed == "NONE" || -n $extra_installed ]]; then
    echo "PASS: extra-installed returns a valid value"
else
    echo "FAIL: extra-installed returned empty"
    FAILED=1
fi

if [[ $FAILED -eq 0 ]]; then
    echo "PASS: All driver mappings correct"
    exit 0
else
    exit 1
fi
