#!/usr/bin/env bash

RETRO_INSTALL_LOG_FILE="${RETRO_INSTALL_LOG_FILE:-/var/log/retrolinux-install.log}"

TEMP_LOG=$(mktemp)
tail -n 100 "$RETRO_INSTALL_LOG_FILE" 2>/dev/null > "$TEMP_LOG" || echo "No log available" > "$TEMP_LOG"

echo "Uploading log..."
URL=$(curl -sF "file=@$TEMP_LOG" -Fexpires=72 https://0x0.st)

if (( $? == 0 )) && [[ -n $URL ]]; then
    echo
    gum style --foreground 76 "Log uploaded successfully!"
    echo
    gum style "Share this URL for support:"
    echo
    gum style --foreground 5 "$URL"
    echo
    gum style "This link will expire in 72 hours."
else
    gum style --foreground 1 "Failed to upload log"
    rm -f "$TEMP_LOG"
    exit 1
fi

rm -f "$TEMP_LOG"