#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_boot() {
    rx_load_state
    rx_clear_logo
    rx_step "Let's configure your bootloader..."

    local theme_options="retropunk
retrolinux"

    local current_theme="retropunk"
    case "$GRUB_THEME_CHOICE" in
        retrolinux) current_theme="retrolinux" ;;
        retropunk) current_theme="retropunk" ;;
    esac

    GRUB_THEME_CHOICE=$(echo "$theme_options" | gum choose --height 2 --selected "$current_theme" --header "Select GRUB Theme" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "2" "Theme selection failed"
        GRUB_THEME_CHOICE="retropunk"
    }

    rx_clear_logo
    rx_step "Let's configure your bootloader..."

    local resolution_options="auto (Detect automatically)
1920x1080 (Full HD)
1280x720 (HD)
1366x768 (Laptop)
1600x900 (HD+)
2560x1440 (2K)
3840x2160 (4K)"

    local current_resolution="1920x1080 (Full HD)"
    case "$BOOT_VIDEO_GRUB" in
        "auto") current_resolution="auto (Detect automatically)" ;;
        "1920x1080") current_resolution="1920x1080 (Full HD)" ;;
        "1280x720") current_resolution="1280x720 (HD)" ;;
        "1366x768") current_resolution="1366x768 (Laptop)" ;;
        "1600x900") current_resolution="1600x900 (HD+)" ;;
        "2560x1440") current_resolution="2560x1440 (2K)" ;;
        "3840x2160") current_resolution="3840x2160 (4K)" ;;
    esac

    local selected_resolution=$(echo "$resolution_options" | gum choose --height 7 --selected "$current_resolution" --header "Select GRUB Framebuffer Resolution" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "2" "Resolution selection failed"
        selected_resolution="1920x1080 (Full HD)"
    }

    BOOT_VIDEO_GRUB=$(echo "$selected_resolution" | cut -d' ' -f1)

    rx_clear_logo
    rx_step "Let's configure your bootloader..."

    gum style --foreground 7 "Detect and add other operating systems (Windows, other Linux distros)"
    echo

    if gum confirm --affirmative "Yes, enable OS probing" --negative "No, skip OS probing" "OS Probing" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        GRUB_OS_PROBER="true"
    else
        GRUB_OS_PROBER="false"
    fi

    rx_save_state
    return 0
}

if ! setup_boot; then
    rx_setup_fail "Boot"
fi
