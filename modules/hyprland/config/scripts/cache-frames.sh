#!/bin/bash
WALL_DIR="$HOME/.config/hypr/wallpapers"
FRAME_CACHE="$HOME/.cache/retro/wallpaper_frames"
mkdir -p "$FRAME_CACHE"

if [ -n "$1" ]; then
    filename=$(basename "$1")
    if [ ! -f "$FRAME_CACHE/$filename.png" ]; then
        ffmpeg -i "$1" -frames:v 1 "$FRAME_CACHE/$filename.png" -y -loglevel quiet
    fi
else
    for vid in "$WALL_DIR"/*.{mp4,mkv,webm}; do
        [ -e "$vid" ] || continue
        filename=$(basename "$vid")
        [ ! -f "$FRAME_CACHE/$filename.png" ] && ffmpeg -i "$vid" -frames:v 1 "$FRAME_CACHE/$filename.png" -y -loglevel quiet
    done
fi
