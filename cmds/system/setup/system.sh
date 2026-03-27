#!/bin/bash

# TODO: Add maybe a notification on system startup to let the user know
# they got some updates todo and their system is outdated

setup_system() {
    if grep -q '^ID=retrolinux' /etc/os-release 2>/dev/null; then
        return 0
    fi

    local current_hostname=$(cat /etc/hostname)

    if [[ $current_hostname == "archlinux" ]]; then
        echo "retrolinux" | sudo tee /etc/hostname >/dev/null
        sudo hostnamectl set-hostname retrolinux
        current_hostname="retrolinux"
    fi

    rx_log "info" "The current hostname is '${PINK}$current_hostname${RESET}', would you like to change it? ${PINK}[y/N]${RESET}: "
    read -r change_host
    if [[ $change_host =~ ^[Yy]$ ]]; then
        rx_log "info" "Enter new hostname: "
        read -r new_host
        if [[ -n $new_host ]]; then
            echo "$new_host" | sudo tee /etc/hostname >/dev/null
            sudo hostnamectl set-hostname "$new_host"
            current_hostname="$new_host"
            rx_log "success" "Hostname updated to $new_host"
        fi
    fi

    sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$current_hostname/g" /etc/hosts

    sudo bash -c 'cat <<EOF > /etc/os-release
NAME="Retro Linux"
PRETTY_NAME="Retro Linux"
ID=retrolinux
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;245;194;231"
HOME_URL="https://archlinux.org/"
DOCUMENTATION_URL="https://wiki.archlinux.org/"
SUPPORT_URL="https://bbs.archlinux.org/"
BUG_REPORT_URL="https://gitlab.archlinux.org/groups/archlinux/-/issues"
PRIVACY_POLICY_URL="https://terms.archlinux.org/docs/privacy-policy/"
LOGO=retrolinux-logo
EOF'
}
