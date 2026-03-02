#!/bin/bash

STATE_FILE="$HOME/.cache/retro/last_wallpaper"
DEFAULT_WALL="$HOME/.config/hypr/wallpapers/retrowave-gtr-wallpaper.jpg"
PICKER="$HOME/.config/hypr/scripts/theme-picker.sh"

if ! pgrep -x "awww-daemon" >/dev/null; then
    echo "Starting awww-daemon..."
    awww-daemon &
    sleep 0.5
fi

if [ -n "$1" ]; then
    WALLPAPER="$1"
elif [ -f "$STATE_FILE" ]; then
    WALLPAPER=$(cat "$STATE_FILE")
else
    WALLPAPER="$DEFAULT_WALL"
fi

mkdir -p "$(dirname "$STATE_FILE")"
echo "$WALLPAPER" >"$STATE_FILE"

if [ -f "$PICKER" ]; then
    bash "$PICKER" "$WALLPAPER"
else
    echo "Error: Theme engine not found at $PICKER"
fi
