#!/bin/bash

rx_gather_system_info() {
    local info=""

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        info+="OS: $PRETTY_NAME\n"
    else
        info+="OS: RetroLinux (unknown version)\n"
    fi

    if [[ -f /sys/class/dmi/id/product_name ]]; then
        local product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        [[ -n $product_name ]] && info+="Product: $product_name\n"
    fi

    if command -v uname &>/dev/null; then
        info+="Kernel: $(uname -r)\n"
    fi

    if command -v lscpu &>/dev/null; then
        local cpu_model=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
        [[ -z $cpu_model ]] && cpu_model=$(lscpu | grep "Model:" | cut -d: -f2 | xargs)
        info+="CPU: $cpu_model\n"
    fi

    if [[ -f /proc/meminfo ]]; then
        local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local mem_gb=$((mem_kb / 1024 / 1024))
        info+="RAM: ${mem_gb}GB\n"
    fi

    if command -v lsblk &>/dev/null; then
        local storage=$(lsblk -dno NAME,SIZE,TYPE | grep disk | awk '{print $1 " (" $2 ")"}' | tr '\n' ', ')
        storage="${storage%,}"
        [[ -n $storage ]] && info+="Storage: $storage\n"
    fi

    if command -v lspci &>/dev/null; then
        local pci_count=$(lspci 2>/dev/null | wc -l)
        info+="PCI Devices: ${pci_count}\n"

        local gpu_model=$(lspci 2>/dev/null | grep -iE "vga|3d|display" | head -n1 | sed 's/^[0-9a-f:.]* //; s/^[A-Za-z0-9 ]*controller: //; s/^[A-Za-z0-9 ]*display controller: //')
        [[ -n $gpu_model ]] && info+="GPU: $gpu_model\n"
    fi

    if command -v lsusb &>/dev/null; then
        local usb_count=$(lsusb 2>/dev/null | wc -l)
        info+="USB Devices: ${usb_count}\n"

        if lsusb 2>/dev/null | grep -qi "bluetooth"; then
            info+="Bluetooth: Yes\n"
        else
            info+="Bluetooth: No\n"
        fi
    fi

    if [[ -d /sys/class/dmi/id ]]; then
        local board_vendor=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)
        local board_name=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
        if [[ -n $board_vendor && -n $board_name ]]; then
            info+="Motherboard: ${board_vendor} ${board_name}\n"
        fi

        local bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null)
        local bios_version=$(cat /sys/class/dmi/id/bios_version 2>/dev/null)
        if [[ -n $bios_vendor && -n $bios_version ]]; then
            info+="BIOS: ${bios_vendor} ${bios_version}\n"
        fi
    fi

    if [[ -d /sys/firmware/efi ]]; then
        info+="Firmware: UEFI\n"
    else
        info+="Firmware: BIOS\n"
    fi

    local wifi_driver wifi_card eth_driver eth_card

    wifi_card=$(rx_get_wifi_iface)
    if [[ -n $wifi_card ]]; then
        wifi_driver=$(ethtool -i "$wifi_card" 2>/dev/null | grep driver | cut -d: -f2 | xargs)
        [[ -z $wifi_driver ]] && wifi_driver="unknown"
        info+="WiFi: $wifi_card (driver: $wifi_driver)\n"
    else
        info+="WiFi: none\n"
    fi

    eth_card=$(rx_get_ethernet_iface)
    if [[ -n $eth_card ]]; then
        eth_driver=$(ethtool -i "$eth_card" 2>/dev/null | grep driver | cut -d: -f2 | xargs)
        [[ -z $eth_driver ]] && eth_driver="unknown"
        info+="Ethernet: $eth_card (driver: $eth_driver)\n"
    else
        info+="Ethernet: none\n"
    fi

    echo -e "$info"
}

rx_generate_error_qr() {
    local exit_code=$1

    local repo_url="github.com/itsvlxd/RetroLinux/issues/new"
    local issue_title="Installation Halt - Exit Code $exit_code"
    local system_specs

    system_specs=$(rx_gather_system_info)

    local log_content=""
    if [[ -f $RETRO_INSTALL_LOG_FILE ]]; then
        log_content=$(tail -c 2000 "$RETRO_INSTALL_LOG_FILE" 2>/dev/null | tr '\n' '.' | sed 's/^\.+//;s/\.\+/ /g')
    fi

    local issue_body="Installer failed during RetroLinux setup.

=== SYSTEM SPECS ===
$system_specs
=== ERROR LOG ===
$log_content

Please describe what happened below:"

    rx_encode_url() {
        local text="$1"
        local encoded=""
        if command -v jq &>/dev/null; then
            encoded=$(printf '%s' "$text" | jq -Rs '@uri' 2>/dev/null)
            encoded="${encoded%\"}"
            encoded="${encoded#\"}"
        fi
        if [[ -z $encoded || $encoded == '""' ]]; then
            encoded="${text}"
            encoded="${encoded//%/%25}"
            encoded="${encoded//$'\n'/%0A}"
            encoded="${encoded// /%20}"
            encoded="${encoded//!/%21}"
            encoded="${encoded//#/%23}"
            encoded="${encoded//\$/%24}"
            encoded="${encoded//&/%26}"
            encoded="${encoded//\'/%27}"
            encoded="${encoded//(/%28}"
            encoded="${encoded//)/%29}"
            encoded="${encoded//\*/%2A}"
            encoded="${encoded//+/%2B}"
            encoded="${encoded//,/%2C}"
            encoded="${encoded//\//%2F}"
            encoded="${encoded//:/%3A}"
            encoded="${encoded//;/%3B}"
            encoded="${encoded//=/%3D}"
            encoded="${encoded//\?/%3F}"
            encoded="${encoded//@/%40}"
            encoded="${encoded//\[/%5B}"
            encoded="${encoded//\]/%5D}"
        fi
        echo "$encoded"
    }

    local encoded_title encoded_body full_url
    encoded_title=$(rx_encode_url "$issue_title")

    local body_max=800
    encoded_body=$(rx_encode_url "${issue_body:0:body_max}")
    full_url="https://${repo_url}?title=${encoded_title}&body=${encoded_body}"

    if [[ ${#full_url} -gt 2800 ]]; then
        encoded_body=$(rx_encode_url "${issue_body:0:500}")
        full_url="https://${repo_url}?title=${encoded_title}&body=${encoded_body}"
    fi

    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 -s 1 -m 1 "$full_url" 2>/dev/null || true
    fi
}