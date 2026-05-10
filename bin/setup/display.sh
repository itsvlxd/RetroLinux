#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

rx_detect_display_modes() {
    local modes=""
    local detected=""

    if [[ -d /sys/class/drm ]]; then
        for card in /sys/class/drm/card*; do
            [[ -d $card ]] || continue
            local card_modes=$(cat "$card/modes" 2>/dev/null)
            if [[ -n $card_modes ]]; then
                modes="$modes $card_modes"
            fi
        done
    fi

    if [[ -z $modes ]]; then
        local fbinfo=$(fbset -i 2>/dev/null)
        if [[ -n $fbinfo ]]; then
            local fb_res=$(echo "$fbinfo" | grep -oE '[0-9]+x[0-9]+' | head -1)
            [[ -n $fb_res ]] && modes="$fb_res"
        fi
    fi

    [[ -n $modes ]] && echo "$modes"
}

rx_get_aspect_ratio() {
    local res="$1"
    local w=${res%x*}
    local h=${res#*x}

    [[ $w -eq 0 ]] && return

    local gcd=1
    local a=$w b=$h
    while [[ $b -ne 0 ]]; do
        local t=$b
        b=$((a % b))
        a=$t
    done
    gcd=$a

    local gw=$((w / gcd))
    local gh=$((h / gcd))
    echo "${gw}:${gh}"
}

setup_display() {
    rx_load_state
    rx_clear_logo
    rx_step "Let's configure your display settings..."

    local aspect_options="16:9 (Widescreen)
16:10 (Productivity)
21:9 (Ultrawide)
4:3 (Legacy)
Custom (Enter manually)"

    local current_aspect="16:9 (Widescreen)"
    case "$DISPLAY_ASPECT_RATIO" in
        16:9) current_aspect="16:9 (Widescreen)" ;;
        16:10) current_aspect="16:10 (Productivity)" ;;
        21:9) current_aspect="21:9 (Ultrawide)" ;;
        4:3) current_aspect="4:3 (Legacy)" ;;
    esac

    DISPLAY_ASPECT_RATIO=$(echo "$aspect_options" | gum choose --height 6 --selected "$current_aspect" --header "Select your monitor's aspect ratio" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "2" "Aspect ratio selection failed"
        rx_retry_or_exit "Display configuration required" || rx_abort
    }

    DISPLAY_ASPECT_RATIO="${DISPLAY_ASPECT_RATIO%% *}"

    if [[ $DISPLAY_ASPECT_RATIO == "Custom" ]]; then
        rx_clear_logo
        rx_step "Let's configure your display settings..."

        local custom_ratio
        custom_ratio=$(gum input --placeholder "16:9, 16:10, 21:9, 32:9, etc." --placeholder.foreground 8 --prompt.foreground "#ff79c6" --prompt "Aspect Ratio> " --padding "$GUM_INPUT_PADDING") || {
            DISPLAY_ASPECT_RATIO="16:9"
        }
        [[ -n $custom_ratio ]] && DISPLAY_ASPECT_RATIO="$custom_ratio"
    fi

    rx_clear_logo
    rx_step "Let's configure your display settings..."

    local resolutions=""
    local label=""

    case "$DISPLAY_ASPECT_RATIO" in
        16:9)
            resolutions="1920x1080 (Full HD)
2560x1440 (QHD)
3840x2160 (4K UHD)
1280x720 (HD)
1600x900 (HD+)
2880x1800 (MacBook/High Res)
2560x1080 (Ultrawide HD)
3440x1440 (Ultrawide QHD)
1366x768 (Laptop)
1360x768"
            ;;
        16:10)
            resolutions="1920x1200 (WUXGA)
2560x1600 (WQXGA)
1440x900 (WXGA+)
1680x1050 (WSXGA+)
1280x800 (WXGA)
2560x1080 (Ultrawide)"
            ;;
        21:9)
            resolutions="2560x1080 (UW-FHD)
3440x1440 (UW-QHD)
5120x2160 (UW-4K)
1920x810 (UW-HD)
3840x1620"
            ;;
        4:3)
            resolutions="1024x768 (XGA)
1280x960 (SXGA-)
1400x1050 (SXGA+)
1600x1200 (UXGA)"
            ;;
        *)
            resolutions="1920x1080 (Full HD)
2560x1440 (QHD)
1920x1200
2560x1600
Custom"
            ;;
    esac

    resolutions="$resolutions
Auto (Detect from system)"

    local detected_modes
    detected_modes=$(rx_detect_display_modes)
    local detected_option=""
    [[ -n $detected_modes ]] && detected_option="Detected: $(echo $detected_modes | tr ' ' '\n' | head -3 | tr '\n' ', ')"

    if [[ -n $detected_option ]]; then
        resolutions="$detected_option
$resolutions"
    fi

    local current_res=""
    [[ -n $BOOT_VIDEO_GRUB ]] && current_res="$BOOT_VIDEO_GRUB"

    local display_res
    display_res=$(echo "$resolutions" | gum choose --height 10 --header "Select display resolution" --padding "$GUM_CHOOSE_PADDING") || {
        rx_step_error "2" "Resolution selection failed"
        rx_retry_or_exit "Display configuration required" || rx_abort
    }

    if [[ $display_res == "Auto"* || $display_res == "Detected"* ]]; then
        if [[ -n $detected_modes ]]; then
            local first_mode=$(echo "$detected_modes" | tr ' ' '\n' | head -1)
            display_res="$first_mode"
        else
            display_res="1920x1080"
        fi
    fi

    if [[ $display_res == "Custom"* ]]; then
        rx_clear_logo
        rx_step "Let's configure your display settings..."

        local custom_res
        custom_res=$(gum input --placeholder "1920x1080" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --prompt "Resolution (WxH)> " --padding "$GUM_INPUT_PADDING") || {
            display_res="1920x1080"
        }
        [[ -n $custom_res ]] && display_res="$custom_res"
    fi

    BOOT_VIDEO_GRUB=$(echo "$display_res" | cut -d' ' -f1)

    local res_x=${BOOT_VIDEO_GRUB%x*}
    local res_y=${BOOT_VIDEO_GRUB#*x}

    if [[ ! "$res_x" =~ ^[0-9]+$ ]] || [[ ! "$res_y" =~ ^[0-9]+$ ]]; then
        res_x=1920
        res_y=1080
    fi

    DISPLAY_RES_X="$res_x"
    DISPLAY_RES_Y="$res_y"
    BOOT_VIDEO_GRUB="${res_x}x${res_y}"

    if [[ $DISPLAY_ASPECT_RATIO == "Custom" ]]; then
        DISPLAY_ASPECT_RATIO=$(rx_get_aspect_ratio "$BOOT_VIDEO_GRUB")
    fi

    rx_save_state
    rx_log "info" "Display: ${BOOT_VIDEO_GRUB} (${DISPLAY_ASPECT_RATIO:-16:9})"
    return 0
}

if ! setup_display; then
    rx_setup_fail "Display"
fi