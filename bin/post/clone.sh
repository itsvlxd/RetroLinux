#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

rx_post_clone_repo() {
    rx_clear_logo
    rx_step "Copying RetroLinux repository..."
    
    local clone_dir="/opt/retrolinux"
    
    if [[ -d "/mnt$clone_dir/.git" ]]; then
        gum style --foreground 2 "RetroLinux repo already present"
        echo
        return 0
    fi
    
    if [[ -d "/opt/retrolinux" ]]; then
        gum style "Copying RetroLinux from live ISO..."
        echo
        
        local source_files=$(ls -la /opt/retrolinux/ | wc -l)
        gum style --foreground 7 "Found $source_files items in /opt/retrolinux/"
        
        mkdir -p "/mnt$clone_dir"
        cp -rf /opt/retrolinux/. "/mnt$clone_dir/"
        find "/mnt$clone_dir" -type f -name "*.sh" -exec chmod +x {} \;
        
        local dest_files=$(ls -la "/mnt$clone_dir/" | wc -l)
        gum style --foreground 7 "Copied $dest_files items to /mnt/opt/retrolinux/"
        
        if [[ -d "/mnt$clone_dir/.git" ]]; then
            gum style --foreground 2 ".git directory included"
        fi
        
        gum style --foreground 2 "RetroLinux copied from ISO"
        echo
        return 0
    fi
    
    gum style --foreground 1 "RetroLinux not found in live ISO at /opt/retrolinux/"
    echo
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rx_post_clone_repo "$@"
fi