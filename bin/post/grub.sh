#!/bin/bash

source /opt/retrolinux/bin/lib/setup_lib.sh

GRUB_THEMES=(retropunk retrolinux)

rx_post_grub() {
    rx_clear_logo
    gum style --foreground 5 "GRUB Configuration" --padding "1 0 1 $PADDING_LEFT"
    gum style --foreground 7 "Select your bootloader theme:" --padding "1 0 1 $PADDING_LEFT"
    gum style --foreground 8 "Choose a visual style for the GRUB boot menu" --padding "1 0 1 $PADDING_LEFT"
    echo

    local themes_str
    themes_str=$(printf '%s\n' "${GRUB_THEMES[@]}")
    local selected_theme
    selected_theme=$(echo "$themes_str" | gum choose --cursor ">" --selected.background 5 --selected.foreground 7 --header " GRUB Theme ")

    if [[ -z $selected_theme ]]; then
        gum style --foreground 3 "No theme selected, using retropunk as default" --padding "1 0 1 $PADDING_LEFT"
        selected_theme="retropunk"
    fi

    local source_theme_dir="/run/archiso/airootfs/usr/share/grub/themes/$selected_theme"
    if [[ ! -d $source_theme_dir ]]; then
        source_theme_dir="/usr/share/grub/themes/$selected_theme"
    fi

    gum style --foreground 7 "Source theme: $source_theme_dir" --padding "1 0 1 $PADDING_LEFT"

    if [[ ! -d $source_theme_dir ]]; then
        gum style --foreground 3 "GRUB theme not found at $source_theme_dir, skipping theme copy" --padding "1 0 1 $PADDING_LEFT"
    else
        local dest_theme_dir="/mnt/boot/grub/themes/$selected_theme"
        gum style --foreground 7 "Installing $selected_theme GRUB theme..." --padding "1 0 1 $PADDING_LEFT"

        mkdir -p /mnt/boot/grub/themes
        if cp -rf "$source_theme_dir"/* "$dest_theme_dir/"; then
            gum style --foreground 2 "  Theme copied successfully" --padding "1 0 1 $PADDING_LEFT"
        else
            gum style --foreground 3 "  Warning: Could not copy theme files" --padding "1 0 1 $PADDING_LEFT"
        fi
    fi

    local grub_defaults="/mnt/etc/default/grub"
    if [[ -f $grub_defaults ]]; then
        if grep -q "^GRUB_DISTRIBUTOR=" "$grub_defaults"; then
            sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="RetroLinux"|' "$grub_defaults"
        else
            echo 'GRUB_DISTRIBUTOR="RetroLinux"' >>"$grub_defaults"
        fi

        if grep -q "^GRUB_THEME=" "$grub_defaults"; then
            sed -i "s|^GRUB_THEME=.*|GRUB_THEME=/boot/grub/themes/$selected_theme/theme.txt|" "$grub_defaults"
        else
            echo "GRUB_THEME=/boot/grub/themes/$selected_theme/theme.txt" >>"$grub_defaults"
        fi
        gum style --foreground 2 "  GRUB distributor and theme configured" --padding "1 0 1 $PADDING_LEFT"
    fi

    gum style --foreground 7 "Regenerating GRUB config..." --padding "1 0 1 $PADDING_LEFT"
    if arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tee /tmp/grub-mkconfig.log | gum spin --spinner line --title "Generating GRUB config..." --passive "Done"; then
        gum style --foreground 2 "GRUB config regenerated successfully" --padding "1 0 1 $PADDING_LEFT"
    else
        gum style --foreground 3 "Warning: GRUB config regeneration had issues" --padding "1 0 1 $PADDING_LEFT"
        if [[ -f /tmp/grub-mkconfig.log ]]; then
            gum style --foreground 1 "Error output:" --padding "1 0 1 $PADDING_LEFT"
            tail -5 /tmp/grub-mkconfig.log | while read -r line; do
                gum style --foreground 1 "  $line" --padding "1 0 1 $PADDING_LEFT"
            done
        fi
    fi

    gum style --foreground 2 "GRUB configuration complete" --padding "1 0 1 $PADDING_LEFT"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    rx_post_grub "$@"
fi

