#!/bin/bash

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
    local cache_dir="$HOME/.config"
    local total=0
    if [[ -d $cache_dir ]]; then
        for d in "$cache_dir"/*/; do
            [[ -d $d && "$(basename "$d")" != "retro" && "$(basename "$d")" != ".retroweb" ]] && total=$(($(du -sb "$d" 2>/dev/null | cut -f1) + total))
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

get_status_data() {
    echo "disk_root=$(get_disk_usage /)"
    echo "disk_home=$(get_disk_usage /home)"
    echo "mem=$(get_mem_usage)"
    echo "boot=$(get_boot_size)"
    echo "logs=$(get_log_size)"
    echo "cache=$(get_cache_size)"
    echo "pacman_cache=$(get_pacman_cache_size)"
}

clean_caches() {
    local cache_dir="$HOME/.cache"
    local before=""
    local result="failed"

    if [[ -d $cache_dir ]]; then
        before=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
        find "$cache_dir" -mindepth 1 -maxdepth 1 -not -name "retro" -not -name ".retroweb" -exec rm -rf {} + 2>/dev/null
        result="success"
    fi

    echo "action=clean_caches|result=$result|before=$before"
}

clean_thumbnails() {
    local thumb_dir="$HOME/.config/thumbnails"
    local thumb_dir_alt="$HOME/.thumbnails"
    local before=""
    local result="none"

    if [[ -d $thumb_dir ]]; then
        before=$(du -sh "$thumb_dir" 2>/dev/null | cut -f1)
        rm -rf "$thumb_dir"/* 2>/dev/null
        result="success"
    elif [[ -d $thumb_dir_alt ]]; then
        before=$(du -sh "$thumb_dir_alt" 2>/dev/null | cut -f1)
        rm -rf "$thumb_dir_alt"/* 2>/dev/null
        result="success"
    fi

    echo "action=clean_thumbnails|result=$result|before=$before"
}

clean_logs() {
    local keep="${1:-7}"
    local before=""
    local result="failed"
    local after="N/A"

    if command -v journalctl >/dev/null 2>&1; then
        before=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+\w+' | head -1)
        journalctl --vacuum-time="${keep}days" 2>/dev/null
        after=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+\w+' | head -1)
        result="success"
    fi

    echo "action=clean_logs|result=$result|before=${before:-N/A}|after=$after|keep_days=$keep"
}

clean_pacman_cache() {
    local before=""
    local result="failed"
    local after="0B"

    if [[ -d "/var/cache/pacman/pkg" ]]; then
        before=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)

        if command -v yay >/dev/null 2>&1; then
            yay -Scc --noconfirm 2>/dev/null
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -Scc --noconfirm 2>/dev/null
        fi

        after=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
        result="success"
    fi

    echo "action=clean_pacman_cache|result=$result|before=$before|after=${after:-0B}"
}

clean_orphans() {
    local orphans=0
    local result="none"

    if command -v yay >/dev/null 2>&1; then
        yay -Y --devel --save 2>/dev/null
        orphans=$(yay -Qdtq 2>/dev/null | wc -l)
        if [[ $orphans -gt 0 ]]; then
            yay -Rs $(yay -Qdtq) --noconfirm 2>/dev/null
            result="removed"
        fi
    elif command -v pacman >/dev/null 2>&1; then
        orphans=$(pacman -Qdtq 2>/dev/null | wc -l)
        if [[ $orphans -gt 0 ]]; then
            sudo pacman -Rs $(pacman -Qdtq) --noconfirm 2>/dev/null
            result="removed"
        fi
    fi

    echo "action=clean_orphans|result=$result|count=$orphans"
}

clean_temp() {
    local temp_dirs=("/tmp" "$HOME/.local/share/Trash")
    local total_cleaned=0

    for dir in "${temp_dirs[@]}"; do
        if [[ -d $dir ]]; then
            local before_num=$(du -sh "$dir" 2>/dev/null | grep -oP '\d+' | head -1)
            find "$dir" -type f -atime +7 -delete 2>/dev/null
            local after_num=$(du -sh "$dir" 2>/dev/null | grep -oP '\d+' | head -1)
            total_cleaned=$((total_cleaned + before_num - after_num))
        fi
    done

    echo "action=clean_temp|result=success|cleaned=$total_cleaned"
}

clean_all() {
    local total_cleaned=0

    clean_caches >/dev/null
    clean_thumbnails >/dev/null
    clean_logs "7" >/dev/null
    clean_temp >/dev/null

    echo "action=clean_all|result=success"
}

case "$1" in
    "--status") get_status_data ;;
    "--clean-caches") clean_caches ;;
    "--clean-thumbnails") clean_thumbnails ;;
    "--clean-logs") clean_logs "$2" ;;
    "--clean-pacman") clean_pacman_cache ;;
    "--clean-orphans") clean_orphans ;;
    "--clean-temp") clean_temp ;;
    "--clean-all") clean_all ;;
esac

