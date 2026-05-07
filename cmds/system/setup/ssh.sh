#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

setup_ssh() {
    [[ "$SSH_ENABLED" != "true" ]] && return 0

    sudo -v
    rx_log "info" "Configuring SSH..."
    
    command -v ssh &>/dev/null || sudo pacman -S --noconfirm openssh 2>&1 | tail -3
    
    [[ -f /etc/ssh/sshd_config ]] || return 1
    
    sudo sed -i "s/^#*Port.*/Port ${SSH_PORT:-22}/" /etc/ssh/sshd_config
    sudo sed -i "s/^#*ListenAddress.*/ListenAddress 0.0.0.0/" /etc/ssh/sshd_config
    
    [[ "$SSH_PASSWORD_LOGIN" == "true" ]] && sudo sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config || sudo sed -i "s/^#*PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
    
    [[ "$SSH_KEY_LOGIN" == "true" ]] && sudo sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" /etc/ssh/sshd_config || sudo sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication no/" /etc/ssh/sshd_config
    
    [[ "$SSH_ROOT_LOGIN" == "true" ]] && sudo sed -i "s/^#*PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config || sudo sed -i "s/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/" /etc/ssh/sshd_config
    
    sudo systemctl enable sshd 2>&1
    sudo systemctl start sshd 2>&1
    
    [[ ! -f "$HOME/.ssh/id_ed25519" ]] && mkdir -p "$HOME/.ssh" && ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" 2>&1
    
    rx_log "success" "SSH configured (port ${SSH_PORT:-22})"
}