#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETRO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/logo.sh"
source "$RETRO_DIR/lib/variable.sh"

count="$1"
shift
sample="$*"
helper="$(get_var "PKG_HELPER" "yay")"

build_logo=" ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
 ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
 ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  
 ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  
 ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝"

rx_logo "${PINK}$build_logo${RESET}"

echo -e "${PINK}[ INFO]${RESET} Updating $count packages, including: $sample"
echo -e "${PINK}[ INFO]${RESET} Syncing pacman repos..."
if ! sudo pacman -Syu --noconfirm; then
    echo -e "${ERROR}[󰅙 ERROR]${RESET} System update failed"
    echo
    read -rp "Press Enter to close." _
    exit 1
fi

echo -e "${PINK}[ INFO]${RESET} Syncing AUR packages ($helper)..."
if ! "$helper" -Sua --noconfirm; then
    echo -e "${ERROR}[󰅙 ERROR]${RESET} AUR update failed"
    echo
    read -rp "Press Enter to close." _
    exit 1
fi

echo -e "${SUCCESS}[ SUCCESS]${RESET} All updates complete. Press Enter to close."
read -r
