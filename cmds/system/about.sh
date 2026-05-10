#!/bin/bash
# RetroLinux About Module

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/help.sh"

BOLD="\033[1m"

fetch_contributors() {
    rx_table_header "" "Thanks to our Contributors"

    local repo="itsvlxd/RetroLinux"

    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        local contributors=$(curl -m 3 -s "https://api.github.com/repos/$repo/contributors" |
            jq --arg p "$PINK" --arg r "$RESET" --arg g "$GRAY" --arg m "$MUTE" \
                -r '.[] | select(.type == "User") | "  \($p)•\($r) \(.login) \($m)[\(.contributions) commits]\($r) \($g)(\(.html_url))\($r)"')

        if [[ -n $contributors && $contributors != "null" ]]; then
            echo -e "$contributors"
        else
            rx_table_simple "•" "itsvlxd [Creator] (https://github.com/itsvlxd)" "$MUTE"
        fi
    else
        rx_table_simple "•" "itsvlxd [Creator] (https://github.com/itsvlxd)" "$MUTE"
    fi

    rx_table_separator
}

cmd_about() {
    echo -e "\n ${PINK}󰯉 About RetroLinux${RESET}"
    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

    echo -e " I built RetroLinux because I got sick of the extremes in"
    echo -e " modern Linux. Traditional DEs like ${BOLD}GNOME, KDE,${RESET} and ${BOLD}Cinnamon${RESET}"
    echo -e " are bloated, eating up your CPU cycles before you even"
    echo -e ' launch an app. On the other hand, most "minimal" Hyprland'
    echo -e " setups force you to duct-tape thousands of packages together."
    echo -e " And if you don't maintain those dotfiles? They crack and shatter."
    echo -e " "
    echo -e " I wanted bleeding-edge features, but with unbreakable stability."
    echo -e " That's why I built ${PINK}RetroLinux${RESET}—a full, standalone Arch-based"
    echo -e " distribution. And to control it, I built the ${PINK}retro CLI${RESET} a"
    echo -e " unified, one-stop command center to manage the entire system."
    echo -e " Fast, fully customizable, and built so anyone can use it."
    echo -e " I also got bored, that's why I wanted to build a more "
    echo -e " 'professional' project and codebase."
    echo -e " "
    echo -e " ${PINK}󰒓 The Vibe${RESET}"
    echo -e " Straight out of an 80s/90s synthwave commercial. Neon pinks,"
    echo -e " wireframes, and retro-futurism. It’s designed to emulate a"
    echo -e " very specific feeling: you're alone, driving a black Ford"
    echo -e " Mustang into a neon-lit gas station at 2 AM. It's dark,"
    echo -e " cozy, and dialed in. That's exactly what our headline,"
    echo -e " ${PINK}\"Just another midnight override,\"${RESET} actually means."
    echo -e " "
    echo -e " ${PINK} Built For${RESET}"
    echo -e "  ${PINK}•${RESET} ${BOLD}Developers${RESET} ${GRAY}:${RESET} A blazing fast, terminal-centric workflow."
    echo -e "  ${PINK}•${RESET} ${BOLD}Gamers${RESET}     ${GRAY}:${RESET} Zero background bloat for maximum FPS."
    echo -e "  ${PINK}•${RESET} ${BOLD}Ricers${RESET}     ${GRAY}:${RESET} An ingenious modular OS. It detects your"
    echo -e "                 manual tweaks and adapts. Customizing"
    echo -e "                 won't break your system."
    echo -e " "
    echo -e " ${PINK}󰘬 Repository :${RESET} ${GRAY}https://github.com/itsvlxd/RetroLinux${RESET}"

    fetch_contributors
}

register_command "SYSTEM" "-a|--about" "About RetroLinux" "cmd_about"
