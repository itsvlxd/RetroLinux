#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETRO_DIR="${SCRIPT_DIR%/scripts}"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/helpers.sh"

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