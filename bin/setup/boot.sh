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

    if [[ -z $BOOT_VIDEO_GRUB ]]; then
        rx_load_state

        local res_x="${DISPLAY_RES_X}"
        local res_y="${DISPLAY_RES_Y}"

        if [[ -z $res_x || -z $res_y || $res_x == "0" || $res_y == "0" ]]; then
            res_x=1920
            res_y=1080
        fi

        BOOT_VIDEO_GRUB="${res_x}x${res_y}"
    fi

    local res_x=${DISPLAY_RES_X:-1920}
    local res_y=${DISPLAY_RES_Y:-1080}

    if [[ ! "$res_x" =~ ^[0-9]+$ ]] || [[ ! "$res_y" =~ ^[0-9]+$ ]]; then
        res_x=1920
        res_y=1080
    fi

    rx_generate_resolution_options() {
        local native="$1x$2"
        local options="$native (Native)"

        local scales="50 75 100 125 150 200 250 300 400"
        for scale in $scales; do
            local new_x=$((res_x * scale / 100))
            local new_y=$((res_y * scale / 100))
            [[ $new_x -lt 320 || $new_y -lt 240 ]] && continue
            local gcd=1 a=$new_x b=$new_y
            while [[ $b -ne 0 ]]; do
                t=$b
                b=$((a % b))
                a=$t
            done
            [[ $a -eq 0 ]] && continue
            local gw=$((new_x / a)) gh=$((new_y / a))
            local ratio="${gw}:${gh}"

            case "$ratio" in
                16:9 | 16:10 | 4:3 | 5:4 | 21:9)
                    local label=""
                    case "$ratio" in 16:9) label="16:9" ;; 16:10) label="16:10" ;; 4:3) label="4:3" ;; 5:4) label="5:4" ;; 21:9) label="21:9" ;; esac
                    options="$options
${new_x}x${new_y} (${label})"
                    ;;
            esac
        done

        options="$options
Custom (Enter manually)"
        echo "$options"
    }

    local resolution_options
    resolution_options=$(rx_generate_resolution_options "$res_x" "$res_y")

    local native="${res_x}x${res_y}"

    local selected_resolution=$(echo "$resolution_options" | gum choose --height 10 --selected "$native" --header "Select GRUB Framebuffer Resolution" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "2" "Resolution selection failed"
        selected_resolution="$BOOT_VIDEO_GRUB"
    }

    if [[ $selected_resolution == "Custom"* || $selected_resolution == "Enter"* ]]; then
        rx_clear_logo
        rx_step "Let's configure your bootloader..."

        local custom_res
        custom_res=$(gum input --placeholder "1920x1080" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --prompt "Resolution (WxH)> " --value "$BOOT_VIDEO_GRUB" --padding "$GUM_INPUT_PADDING") || {
            selected_resolution="$BOOT_VIDEO_GRUB"
        }
        [[ -n $custom_res ]] && selected_resolution="$custom_res"
    fi

    BOOT_VIDEO_GRUB=$(echo "$selected_resolution" | cut -d' ' -f1)

    rx_clear_logo
    rx_step "Let's configure your bootloader..."

    gum style --foreground 7 "Detect and add other operating systems (Windows, other Linux distros)"
    echo

    if gum confirm --affirmative "Yes, enable OS probing" --negative "No, skip OS probing" "OS Probing" --default="${GRUB_OS_PROBER:-true}" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        GRUB_OS_PROBER="true"
    else
        GRUB_OS_PROBER="false"
    fi

    rx_clear_logo
    rx_step "Let's configure your bootloader..."

    gum style --foreground 7 "Include BTRFS snapshots in GRUB boot menu for easy rollback"
    echo

    if gum confirm --affirmative "Yes, enable snapshots" --negative "No, disable snapshots" "Snapshot Boot" --default="${GRUB_SNAPSHOTS_ENABLED:-true}" $GUM_CONFIRM_STYLE --padding "$GUM_CONFIRM_PADDING"; then
        GRUB_SNAPSHOTS_ENABLED="true"
    else
        GRUB_SNAPSHOTS_ENABLED="false"
    fi

    rx_clear_logo
    rx_step "Let's configure your bootloader..."

    local timeout_input
    timeout_input=$(gum input --placeholder "10" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --prompt "Boot timeout (seconds)> " --value "${GRUB_TIMEOUT:-10}" --padding "$GUM_INPUT_PADDING") || {
        timeout_input="10"
    }

    if [[ "$timeout_input" =~ ^[0-9]+$ ]]; then
        GRUB_TIMEOUT="$timeout_input"
    else
        GRUB_TIMEOUT="10"
    fi

    rx_save_state
    return 0
}

if ! setup_boot; then
    rx_setup_fail "Boot"
fi
