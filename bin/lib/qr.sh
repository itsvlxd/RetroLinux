#!/bin/bash

rx_gather_system_info() {
    local info=""

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        info+="OS: $PRETTY_NAME\n"
    else
        info+="OS: RetroLinux (unknown version)\n"
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

    local wifi_driver wifi_card eth_driver eth_card

    wifi_card=$(ip link show 2>/dev/null | grep -E "^[0-9]+: wlan[0-9]+" | awk -F': ' '{print $2}' | head -n1)
    if [[ -n $wifi_card ]]; then
        wifi_driver=$(ethtool -i "$wifi_card" 2>/dev/null | grep driver | cut -d: -f2 | xargs)
        [[ -z $wifi_driver ]] && wifi_driver="unknown"
        info+="WiFi: $wifi_card (driver: $wifi_driver)\n"
    fi

    eth_card=$(ip link show 2>/dev/null | grep -E "^[0-9]+: (eth|en)" | awk -F': ' '{print $2}' | head -n1)
    if [[ -n $eth_card ]]; then
        eth_driver=$(ethtool -i "$eth_card" 2>/dev/null | grep driver | cut -d: -f2 | xargs)
        [[ -z $eth_driver ]] && eth_driver="unknown"
        info+="Ethernet: $eth_card (driver: $eth_driver)\n"
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
        log_content=$(tail -c 6000 "$RETRO_INSTALL_LOG_FILE" 2>/dev/null | tr '\n' '.' | sed 's/^\.+//;s/\.\+/ /g')
    fi

    local issue_body="Installer failed during RetroLinux setup.

=== SYSTEM SPECS ===
$system_specs
=== ERROR LOG ===
$log_content

Please describe what happened below:"

    local encoded_title encoded_body

    if command -v jq &>/dev/null; then
        encoded_title=$(echo "$issue_title" | jq -Rs '@uri' 2>/dev/null)
        encoded_title="${encoded_title//'%'/%25}"
        encoded_body=$(printf '%s' "$issue_body" | jq -Rs '@uri' 2>/dev/null)
    fi

    if [[ -z $encoded_title ]]; then
        encoded_title="${issue_title// /+}"
    fi

    if [[ -z $encoded_body ]]; then
        encoded_body="${issue_body}"
        encoded_body="${encoded_body//%/%25}"
        encoded_body="${encoded_body//$'\n'/%0A}"
        encoded_body="${encoded_body// /%20}"
        encoded_body="${encoded_body//!/%21}"
        encoded_body="${encoded_body//#/%23}"
        encoded_body="${encoded_body//\$/%24}"
        encoded_body="${encoded_body//&/%26}"
        encoded_body="${encoded_body//\'/%27}"
        encoded_body="${encoded_body//(/%28}"
        encoded_body="${encoded_body//)/%29}"
        encoded_body="${encoded_body//*/%2A}"
        encoded_body="${encoded_body//+/%2B}"
        encoded_body="${encoded_body//,/%2C}"
        encoded_body="${encoded_body///%2F}"
        encoded_body="${encoded_body//:/%3A}"
        encoded_body="${encoded_body//;/%3B}"
        encoded_body="${encoded_body//=/%3D}"
        encoded_body="${encoded_body//\?/%3F}"
        encoded_body="${encoded_body//@/%40}"
        encoded_body="${encoded_body//\[/%5B}"
        encoded_body="${encoded_body//\]/%5D}"
    fi

    local full_url="https://${repo_url}?title=${encoded_title}&body=${encoded_body}"

    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 "$full_url" 2>/dev/null || true
    else
        echo
        gum style --foreground 5 --padding "1 0 1 $PADDING_LEFT" "Scan QR code or visit:"
        echo
        gum style --foreground 6 --padding "1 0 1 $PADDING_LEFT" "https://${repo_url}"
        echo
    fi
}