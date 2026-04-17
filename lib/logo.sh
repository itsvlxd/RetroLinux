#!/bin/bash

random_int() {
    echo $((RANDOM % ($2 - $1 + 1) + $1))
}

apply_terminal_gradient() {
    local text="$1"
    local angle_deg="$2"
    shift 2
    local colors=("$@")
    local num_colors=${#colors[@]}

    IFS=$'\n' read -rd '' -a lines <<<"$text" || true
    local height=${#lines[@]}
    local width=0
    for line in "${lines[@]}"; do
        ((${#line} > width)) && width=${#line}
    done

    local pi=$(echo "scale=10; 4*a(1)" | bc -l)
    local rad=$(echo "scale=10; $angle_deg * $pi / 180" | bc -l)
    local cos=$(echo "scale=10; c($rad) * 1000 / 1" | bc -l | cut -d. -f1)
    local sin=$(echo "scale=10; s($rad) * 1000 / 1" | bc -l | cut -d. -f1)

    local projections=()
    for x in 0 $width; do
        for y in 0 $height; do
            projections+=($((x * cos + y * sin)))
        done
    done

    local min_p=${projections[0]}
    local max_p=${projections[0]}
    for p in "${projections[@]}"; do
        ((p < min_p)) && min_p=$p
        ((p > max_p)) && max_p=$p
    done

    local range=$((max_p - min_p))
    [[ $range -eq 0 ]] && range=1

    for ((y = 0; y < height; y++)); do
        local line="${lines[$y]}"
        local len=${#line}
        for ((x = 0; x < len; x++)); do
            local p=$((x * cos + y * sin))

            local color_idx=$(((p - min_p) * (num_colors - 1) / range))

            ((color_idx < 0)) && color_idx=0
            ((color_idx >= num_colors)) && color_idx=$((num_colors - 1))

            printf "\e[%dm%s" "${colors[$color_idx]}" "${line:x:1}"
        done
        echo -e "\e[0m"
    done
}

pad() {
    printf "%$1s" ""
}

get_width() {
    local max=0
    while IFS= read -r line; do
        ((${#line} > max)) && max=${#line}
    done <<<"$1"
    echo "$max"
}

LOGO_1=$(
    cat <<'EOF'
██████╗ ███████╗████████╗██████╗  ██████╗     ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗
██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔═══██╗    ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝
██████╔╝█████╗     ██║   ██████╔╝██║   ██║    ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ 
██╔══██╗██╔══╝     ██║   ██╔══██╗██║   ██║    ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ 
██║  ██║███████╗   ██║   ██║  ██║╚██████╔╝    ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗
╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝     ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
EOF
)

LOGO_2=$(
    cat <<'EOF'
    ____  ________________  ____     __    _____   ____  ___  __
   / __ \/ ____/_  __/ __ \/ __ \   / /   /  _/ | / / / / / |/ /
  / /_/ / __/   / / / /_/ / / / /  / /    / //  |/ / / / /|   / 
 / _, _/ /___  / / / _, _/ /_/ /  / /____/ // /|  / /_/ //   |  
/_/ |_/_____/ /_/ /_/ |_|\____/  /_____/___/_/ |_/\____//_/|_|   
EOF
)

rx_logo() {
    local input="${1:-}"

    if [[ -t 1 ]] && [[ -z "${CI:-}" ]]; then
        clear
    fi

    local version=$(rx_git_version)
    local branch=$(rx_git_branch)

    local active_logo
    if [[ -n "$input" ]]; then
        if [[ -f "$input" ]]; then
            active_logo=$(cat "$input")
        else
            active_logo="$input"
        fi
    else
        local logo_choice=$(random_int 1 2)
        [[ $logo_choice -eq 1 ]] && active_logo="$LOGO_1" || active_logo="$LOGO_2"
    fi

    local angle=$(random_int 0 360)
    local logo_choice=$(random_int 1 2)
    if [[ $logo_choice -eq 1 || -n "$input" ]]; then
        apply_terminal_gradient "$active_logo" "$angle" 32
    else
        apply_terminal_gradient "$active_logo" "$angle" 35 32 33 31
    fi

    local logo_w=$(get_width "$active_logo")

    local tag_text="󰯉 Just another midnight override | ${version} 󰘬 ${branch}"

    local tag_w=$((${#tag_text} + 2))

    local base_pad=$(((logo_w - tag_w) / 2))

    local final_pad=$((base_pad))

    [[ $final_pad -lt 0 ]] && final_pad=0

    echo -e "$(pad $final_pad)${PINK}󰯉 ${RESET}Just another midnight override ${PINK}| ${GRAY}${version} ${PINK}󰘬 ${GRAY}${branch}${RESET}\n"
}
