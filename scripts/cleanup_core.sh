#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

get_disk_usage() {
    local path="${1:-/}"
    df -h "$path" 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}'
}

get_mem_usage() {
    free -h | awk 'NR==2 {print $3 " / " $2}'
}

get_boot_size() {
    local size=$(du -sh /boot 2>/dev/null | cut -f1)
    echo "${size:-N/A}"
}

get_log_size() {
    local size=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+\w+' | head -1)
    echo "${size:-N/A}"
}

get_cache_size() {
    local cache_dir="$HOME/.cache"
    local total=0
    if [[ -d "$cache_dir" ]]; then
        for d in "$cache_dir"/*/; do
            [[ -d "$d" && "$(basename "$d")" != "retro" && "$(basename "$d")" != ".retroweb" ]] && total=$(($(du -sb "$d" 2>/dev/null | cut -f1) + total))
        done
        if [[ $total -gt 1073741824 ]]; then
            echo "$((total / 1073741824))G"
        elif [[ $total -gt 1048576 ]]; then
            echo "$((total / 1048576))M"
        elif [[ $total -gt 1024 ]]; then
            echo "$((total / 1024))K"
        else
            echo "${total}B"
        fi
    else
        echo "0B"
    fi
}

get_pacman_cache_size() {
    if [[ -d "/var/cache/pacman/pkg" ]]; then
        du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1
    else
        echo "0B"
    fi
}

system_status() {
    echo -e "\n ${PINK}󰟓  System Health${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    printf " ${PINK}󰉌${RESET} %-20s ${GRAY}%s${RESET}\n" "Disk (/):" "$(get_disk_usage /)"
    printf " ${PINK}󰉌${RESET} %-20s ${GRAY}%s${RESET}\n" "Disk (/home):" "$(get_disk_usage /home)"
    printf " ${PINK}󰠮${RESET} %-20s ${GRAY}%s${RESET}\n" "Memory:" "$(get_mem_usage)"
    printf " ${PINK}󰕾${RESET} %-20s ${GRAY}%s${RESET}\n" "Boot partition:" "$(get_boot_size)"
    printf " ${PINK}󰶐${RESET} %-20s ${GRAY}%s${RESET}\n" "Journal logs:" "$(get_log_size)"
    printf " ${PINK}󰶐${RESET} %-20s ${GRAY}%s${RESET}\n" "User cache:" "$(get_cache_size)"
    printf " ${PINK}󰶐${RESET} %-20s ${GRAY}%s${RESET}\n" "Pacman pkg cache:" "$(get_pacman_cache_size)"

    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
}

clean_caches() {
    rx_log "info" "Cleaning user cache..."

    local cache_dir="$HOME/.cache"
    if [[ -d "$cache_dir" ]]; then
        local before=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
        
        find "$cache_dir" -mindepth 1 -maxdepth 1 -not -name "retro" -not -name ".retroweb" -exec rm -rf {} + 2>/dev/null
        
        rx_log "success" "Cleaned user cache: ${GRAY}$before${RESET}"
    else
        rx_log "warn" "No user cache found"
    fi
}

clean_thumbnails() {
    rx_log "info" "Cleaning thumbnails..."

    local thumb_dir="$HOME/.cache/thumbnails"
    local thumb_dir_alt="$HOME/.thumbnails"

    if [[ -d "$thumb_dir" ]]; then
        local before=$(du -sh "$thumb_dir" 2>/dev/null | cut -f1)
        rm -rf "$thumb_dir"/* 2>/dev/null
        rx_log "success" "Cleaned thumbnails: ${GRAY}$before${RESET}"
    elif [[ -d "$thumb_dir_alt" ]]; then
        local before=$(du -sh "$thumb_dir_alt" 2>/dev/null | cut -f1)
        rm -rf "$thumb_dir_alt"/* 2>/dev/null
        rx_log "success" "Cleaned thumbnails: ${GRAY}$before${RESET}"
    else
        rx_log "warn" "No thumbnails cache found"
    fi
}

clean_logs() {
    rx_log "info" "Cleaning journal logs..."

    local before=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+\w+' | head -1)
    local keep="${1:-7}"

    if command -v journalctl >/dev/null 2>&1; then
        journalctl --vacuum-time="${keep}days" 2>/dev/null
        local after=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+\w+' | head -1)
        rx_log "success" "Cleaned journal logs: ${GRAY}${before:-N/A}${RESET} -> ${PINK}${after:-N/A}${RESET}"
    else
        rx_log "warn" "journalctl not available"
    fi
}

clean_pacman_cache() {
    rx_log "info" "Cleaning pacman package cache..."

    if [[ -d "/var/cache/pacman/pkg" ]]; then
        local before=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
        
        if command -v yay >/dev/null 2>&1; then
            yay -Scc --noconfirm 2>/dev/null
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -Scc --noconfirm 2>/dev/null
        fi
        
        local after=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
        rx_log "success" "Cleaned pacman cache: ${GRAY}$before${RESET} -> ${PINK}${after:-0B}${RESET}"
    else
        rx_log "warn" "No pacman cache found"
    fi
}

clean_orphans() {
    rx_log "info" "Cleaning orphaned packages..."

    if command -v yay >/dev/null 2>&1; then
        yay -Y --devel --save 2>/dev/null
        local orphans=$(yay -Qdtq 2>/dev/null | wc -l)
        if [[ "$orphans" -gt 0 ]]; then
            yay -Rs $(yay -Qdtq) --noconfirm 2>/dev/null
            rx_log "success" "Removed ${PINK}$orphans${RESET} orphaned packages"
        else
            rx_log "info" "No orphaned packages found"
        fi
    elif command -v pacman >/dev/null 2>&1; then
        local orphans=$(pacman -Qdtq 2>/dev/null | wc -l)
        if [[ "$orphans" -gt 0 ]]; then
            sudo pacman -Rs $(pacman -Qdtq) --noconfirm 2>/dev/null
            rx_log "success" "Removed ${PINK}$orphans${RESET} orphaned packages"
        else
            rx_log "info" "No orphaned packages found"
        fi
    fi
}

clean_temp() {
    rx_log "info" "Cleaning temp files..."

    local temp_dirs=("/tmp" "$HOME/.local/share/Trash")
    local total_cleaned=0

    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local before=$(du -sh "$dir" 2>/dev/null | cut -f1)
            find "$dir" -type f -atime +7 -delete 2>/dev/null
            local after=$(du -sh "$dir" 2>/dev/null | cut -f1)
            
            local before_num=$(echo "$before" | grep -oP '\d+' | head -1)
            local after_num=$(echo "$after" | grep -oP '\d+' | head -1)
            
            total_cleaned=$((total_cleaned + before_num - after_num))
        fi
    done

    rx_log "success" "Cleaned temp files older than 7 days"
}

clean_all() {
    rx_log "info" "Running full system cleanup..."

    clean_caches
    clean_thumbnails
    clean_logs
    clean_temp
    
    if [[ "$EUID" -eq 0 ]]; then
        clean_pacman_cache
        clean_orphans
    else
        rx_log "warn" "Run as root to clean pacman cache and orphans"
    fi

    rx_log "success" "Cleanup complete!"
    system_status
}

case "$1" in
    "--status") system_status ;;
    "--clean-caches") clean_caches ;;
    "--clean-thumbnails") clean_thumbnails ;;
    "--clean-logs") clean_logs "$2" ;;
    "--clean-pacman") clean_pacman_cache ;;
    "--clean-orphans") clean_orphans ;;
    "--clean-temp") clean_temp ;;
    "--clean-all") clean_all ;;
esac
