#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_network() {
    rx_clear_logo
    rx_step "Configuring network connection..."
    
    arch-chroot /mnt systemctl enable NetworkManager.service >/dev/null 2>&1
    arch-chroot /mnt systemctl start NetworkManager.service >/dev/null 2>&1
    
    sleep 3
    
    local wifi_iface=""
    local eth_iface=""
    
    eth_iface=$(arch-chroot /mnt nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep ":ethernet$" | cut -d: -f1 | head -1)
    wifi_iface=$(arch-chroot /mnt nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep ":wifi$" | cut -d: -f1 | head -1)
    
    if [[ -n "$eth_iface" ]]; then
        gum style "Ethernet detected: ${eth_iface}"
        echo
        
        arch-chroot /mnt nmcli connection add type ethernet ifname "$eth_iface" con-name "ethernet-connection" >/dev/null 2>&1
        arch-chroot /mnt nmcli connection up "ethernet-connection" >/dev/null 2>&1
        
        if [[ $? -eq 0 ]]; then
            gum style --foreground 2 "Ethernet configured"
        else
            gum style --foreground 3 "Warning: Ethernet configuration failed"
        fi
        echo
        return 0
    fi
    
    if [[ -n "$wifi_iface" ]]; then
        gum style "WiFi adapter detected: ${wifi_iface}"
        echo
        
        arch-chroot /mnt nmcli device wifi rescan >/dev/null 2>&1
        sleep 2
        
        local ssid_list=$(arch-chroot /mnt nmcli -t -f SSID device wifi list 2>/dev/null | grep -v "^$" | sort -u)
        
        if [[ -n "$ssid_list" ]]; then
            local selected_ssid=$(echo "$ssid_list" | gum choose --header "Select WiFi network" --padding "$GUM_CHOOSE_PADDING")
            
            if [[ -n "$selected_ssid" ]]; then
                echo
                local wifi_password=$(gum input --placeholder "Enter WiFi password" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --password --prompt "Password> " --padding "$GUM_INPUT_PADDING")
                
                if [[ -n "$wifi_password" ]]; then
                    arch-chroot /mnt nmcli device wifi connect "$selected_ssid" password "$wifi_password" >/dev/null 2>&1
                    
                    if [[ $? -eq 0 ]]; then
                        gum style --foreground 2 "WiFi connected: ${selected_ssid}"
                    else
                        gum style --foreground 3 "Warning: WiFi connection failed"
                    fi
                else
                    gum style --foreground 3 "No password entered, skipping WiFi"
                fi
            else
                gum style --foreground 3 "No network selected, skipping WiFi"
            fi
        else
            gum style --foreground 3 "No WiFi networks found"
        fi
        echo
        return 0
    fi
    
    gum style --foreground 3 "No network adapters detected"
    echo
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rx_post_network "$@"
fi
