#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETRO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$RETRO_DIR/lib/colors.sh"

ALL_VARS=$(bash "$RETRO_DIR/scripts/variable_core.sh" --list 2>/dev/null)
get_var() {
    local val=$(echo "$ALL_VARS" | grep -m 1 "^$1=" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    echo "${val:-$2}"
}

count="$1"
shift
sample="$*"
helper="$(get_var "PKG_HELPER" "yay")"

echo -e "${PINK}
 ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
 ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
 ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗  
 ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝  
 ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝
${RESET}"
echo -e "${PINK}[ INFO]${RESET} Updating $count packages, including: $sample"
echo -e "${PINK}[ INFO]${RESET} Syncing pacman repos..."
sudo pacman -Syu
echo -e "${PINK}[ INFO]${RESET} Syncing AUR packages ($helper)..."
$helper -Sua
echo -e "${PINK}[ INFO]${RESET} All updates complete. Press Enter to close."
read

