#!/bin/bash

source "$RETRO_INSTALL/lib/setup_lib.sh"

setup_mirrors() {
    rx_load_state
    rx_step "Let's setup mirror regions..."

    local regions='Australia
Austria
Bangladesh
Belarus
Belgium
Brazil
Canada
Chile
China
Colombia
Croatia
Czech Republic
Denmark
Estonia
Finland
France
Germany
Greece
Hong Kong
Hungary
India
Indonesia
Iran
Ireland
Israel
Italy
Japan
Kazakhstan
Kenya
Lithuania
Luxembourg
Macedonia
Netherlands
New Zealand
Norway
Pakistan
Poland
Portugal
Romania
Russia
Singapore
Slovakia
Slovenia
South Africa
South Korea
Spain
Sweden
Switzerland
Taiwan
Turkey
Ukraine
United Kingdom
United States'

    gum style --padding "0 0 0 $PADDING_LEFT" "Select your mirror regions (space to select multiple):"
    gum style --padding "0 0 0 $PADDING_LEFT" "Leave empty for auto-detection"
    echo

    local current_region=""
    if [[ -n "$MIRROR_REGIONS" ]]; then
        current_region="$MIRROR_REGIONS"
    fi

    local selected_regions
    selected_regions=$(echo "$regions" | gum filter --height "$GUM_FILTER_HEIGHT" "${GUM_FILTER_STYLE[@]}" --value "$current_region" --prompt "Region> " --placeholder "Select a region or leave empty" --padding "$GUM_FILTER_PADDING") || {
        rx_step_error "7" "Mirror region selection cancelled"
        rx_retry_or_exit "Mirror region selection is required" || rx_abort
        return 1
    }

    # shellcheck disable=SC2034
    MIRROR_REGIONS="$selected_regions"

    echo
    gum style --padding "0 0 0 $PADDING_LEFT" "Add custom mirror URL? (leave empty to skip)"
    echo

    local custom_mirror
    custom_mirror=$(gum input --placeholder "https://mirror.example.com/\$repo/os/\$arch" --placeholder.foreground 8 --prompt.foreground "#ff79c6" --prompt "Custom URL> " --padding "$GUM_INPUT_PADDING") || {
        rx_step_error "7" "Custom mirror input cancelled"
        rx_retry_or_exit "Custom mirror input" || rx_abort
        return 1
    }

    if [[ -n "$custom_mirror" ]]; then
        # shellcheck disable=SC2034
        CUSTOM_MIRRORS="$custom_mirror"
    else
        # shellcheck disable=SC2034
        CUSTOM_MIRRORS=""
    fi

    rx_save_state
    return 0
}

if ! setup_mirrors; then
    rx_setup_fail "Mirrors"
fi