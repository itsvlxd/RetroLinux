#!/bin/bash

source "$RETRO_DIR/lib/log.sh"
source "$RETRO_DIR/lib/colors.sh"

declare -g RX_SETUP_MODE="interactive"
declare -g RX_SETUP_OPTIONS=""
declare -g RX_SETUP_NEEDED=false
declare -A RX_SETUP_OPTS

rx_setup_parse() {
    RX_SETUP_MODE="interactive"
    RX_SETUP_OPTIONS=""
    RX_SETUP_OPTIONS_RAW=""
    RX_SETUP_NEEDED=false
    unset RX_SETUP_OPTS
    declare -gA RX_SETUP_OPTS

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--options)
                RX_SETUP_MODE="non-interactive"
                RX_SETUP_OPTIONS_RAW="${2:-}"
                if [[ -n $2 ]]; then
                    RX_SETUP_OPTIONS="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --needed)
                RX_SETUP_NEEDED=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ $RX_SETUP_MODE == "non-interactive" && -n $RX_SETUP_OPTIONS ]]; then
        IFS=',' read -ra opts_array <<< "$RX_SETUP_OPTIONS"
        for pair in "${opts_array[@]}"; do
            local key="${pair%%=*}"
            local val="${pair#*=}"
            [[ -n $key ]] && RX_SETUP_OPTS["$key"]="$val"
        done
    fi
}

rx_setup_validate() {
    local valid_keys="$1"
    local validation_rules="${2:-}"

    if [[ $RX_SETUP_MODE == "non-interactive" && -z $RX_SETUP_OPTIONS ]]; then
        rx_log "error" "Empty options. Valid keys: ${PINK}${valid_keys}${RESET}"
        return 1
    fi

    if [[ -n $validation_rules ]]; then
        IFS='|' read -ra rules_array <<< "$validation_rules"
        for rule in "${rules_array[@]}"; do
            local key="${rule%%:*}"
            local rules="${rule#*:}"
            local value="${RX_SETUP_OPTS[$key]:-}"

            IFS='|' read -ra key_rules <<< "$rules"
            for kr in "${key_rules[@]}"; do
                case "$kr" in
                    required)
                        if [[ -z $value ]]; then
                            rx_log "error" "Missing required option: ${PINK}${key}${RESET}"
                            return 1
                        fi
                        ;;
                    numeric)
                        if [[ -n $value && ! $value =~ ^-?[0-9]+$ ]]; then
                            rx_log "error" "Option ${PINK}${key}=${value}${RESET} must be numeric"
                            return 1
                        fi
                        ;;
                    min=*)
                        local min_val="${kr#min=}"
                        if [[ -n $value && $value =~ ^-?[0-9]+$ && $value -lt $min_val ]]; then
                            rx_log "error" "Option ${PINK}${key}=${value}${RESET} must be >= ${min_val}"
                            return 1
                        fi
                        ;;
                    max=*)
                        local max_val="${kr#max=}"
                        if [[ -n $value && $value =~ ^-?[0-9]+$ && $value -gt $max_val ]]; then
                            rx_log "error" "Option ${PINK}${key}=${value}${RESET} must be <= ${max_val}"
                            return 1
                        fi
                        ;;
                    pattern=*)
                        local pat="${kr#pattern=}"
                        if [[ -n $value && ! $value =~ $pat ]]; then
                            rx_log "error" "Option ${PINK}${key}=${value}${RESET} does not match pattern: ${pat}"
                            return 1
                        fi
                        ;;
                    in=*)
                        local in_vals="${kr#in=}"
                        local found=false
                        IFS=',' read -ra in_array <<< "$in_vals"
                        for iv in "${in_array[@]}"; do
                            [[ "$value" == "$iv" ]] && found=true && break
                        done
                        if [[ -n $value && $found == false ]]; then
                            rx_log "error" "Option ${PINK}${key}=${value}${RESET} must be one of: ${in_vals}"
                            return 1
                        fi
                        ;;
                    eq=*)
                        local eq_val="${kr#eq=}"
                        if [[ -n $value && "$value" != "$eq_val" ]]; then
                            rx_log "error" "Option ${PINK}${key}=${value}${RESET} must equal: ${eq_val}"
                            return 1
                        fi
                        ;;
                    ne=*)
                        local ne_val="${kr#ne=}"
                        if [[ -n $value && "$value" == "$ne_val" ]]; then
                            rx_log "error" "Option ${PINK}${key}=${value}${RESET} must not equal: ${ne_val}"
                            return 1
                        fi
                        ;;
                esac
            done
        done
    fi

    if [[ $RX_SETUP_MODE == "non-interactive" && ${#RX_SETUP_OPTS[@]} -gt 0 ]]; then
        IFS=',' read -ra valid_array <<< "$valid_keys"
        for key in "${!RX_SETUP_OPTS[@]}"; do
            local found=false
            for vk in "${valid_array[@]}"; do
                [[ "$key" == "$vk" ]] && found=true && break
            done
            if [[ $found == false ]]; then
                rx_log "warn" "Unknown option: ${PINK}${key}${RESET} (valid: ${PINK}${valid_keys}${RESET})"
            fi
        done
    fi
}

rx_setup_get_opt() {
    local key="$1"
    local default="${2:-}"
    echo "${RX_SETUP_OPTS[$key]:-$default}"
}

rx_setup_current() {
    local icon="$1"
    local title="$2"
    shift 2

    local has_config=false
    local -a rows=()

    while [[ $# -ge 2 ]]; do
        local label="$1"
        local value="$2"
        shift 2

        local display_value="$value"
        local row_color="$PINK"

        case "$value" in
            ""|"Not configured"|"N/A"|"Not set"|"null")
                display_value="${MUTE}Not configured${RESET}"
                row_color="$MUTE"
                ;;                                
            *)
                has_config=true
                ;;
        esac

        rows+=("$icon" "$label:" "$display_value" "$row_color")
    done

    if [[ $has_config == true ]]; then
        rx_table_header "$icon" "$title"
        local idx=0
        while [[ $idx -lt ${#rows[@]} ]]; do
            local r_icon="${rows[$idx]}"
            local r_label="${rows[$((idx+1))]}"
            local r_value="${rows[$((idx+2))]}"
            local r_color="${rows[$((idx+3))]}"
            rx_table_row "$r_icon" "$r_label" "$r_value" "$r_color" "22"
            idx=$((idx+4))
        done
        rx_table_separator
        rx_table_spacer
    fi

    [[ $has_config == true ]] && return 0 || return 1
}

rx_setup_check_needed() {
    local config_exists="$1"
    if [[ $RX_SETUP_NEEDED == true && $config_exists == true ]]; then
        return 0
    fi
    return 1
}



rx_setup_prompt_reconfigure() {
    local icon="$1"
    local title="$2"
    shift 2

    rx_setup_current "$icon" "$title" "$@"
    local current_status=$?

    if [[ $current_status -eq 1 ]]; then
        return 0
    fi

    if ! rx_confirm "Reconfigure?" "N"; then
        rx_log "info" "Setup cancelled."
        return 1
    fi

    return 0
}

rx_setup_summary() {
    local icon="$1"
    local title="$2"
    shift 2

    rx_table_header "$icon" "$title"
    while [[ $# -ge 2 ]]; do
        local label="$1"
        local value="$2"
        shift 2
        rx_table_row "$icon" "$label:" "$value" "$PINK" "22"
    done
    rx_table_separator
    rx_table_spacer
}

rx_setup_confirm() {
    if ! rx_confirm "Apply these settings?" "N"; then
        rx_log "info" "Setup cancelled."
        return 1
    fi
    return 0
}

rx_setup_success() {
    local icon="$1"
    local title="$2"
    shift 2

    rx_table_header "$icon" "$title"
    while [[ $# -ge 2 ]]; do
        local label="$1"
        local value="$2"
        shift 2
        rx_table_row "$icon" "$label:" "$value" "$PINK" "22"
    done
    rx_table_separator
    rx_table_spacer

    rx_log "success" "Setup complete"
}

rx_input() {
    local label="$1"
    local default="${2:-}"
    local pattern="${3:-}"
    local error_msg="${4:-Invalid input}"

    while true; do
        rx_log "info" "${label} ${MUTE}[${default}]${RESET}: "

        local input
        read -r input

        [[ -z $input ]] && input="$default"

        if [[ -n $pattern ]]; then
            if [[ ! $input =~ $pattern ]]; then
                rx_log "error" "${error_msg}"
                continue
            fi
        fi

        echo "$input"
        return 0
    done
}

rx_input_numeric() {
    local label="$1"
    local default="${2:-}"
    local min="${3:-}"
    local max="${4:-}"

    while true; do
        rx_log "info" "${label} ${MUTE}[${default}]${RESET}: "

        local input
        read -r input

        [[ -z $input ]] && input="$default"

        if [[ ! $input =~ ^-?[0-9]+$ ]]; then
            rx_log "error" "Must be a number"
            continue
        fi

        if [[ -n $min && $input -lt $min ]]; then
            rx_log "error" "Must be >= ${min}"
            continue
        fi

        if [[ -n $max && $input -gt $max ]]; then
            rx_log "error" "Must be <= ${max}"
            continue
        fi

        echo "$input"
        return 0
    done
}

rx_input_choice() {
    local icon="$1"
    local label="$2"
    local default="${3:-}"
    shift 3

    local options=("$@")
    local num_options=${#options[@]}

    rx_log "info" "${icon}  ${label}"

    for i in "${!options[@]}"; do
        local num=$((i + 1))
        printf "  ${PINK}${num})${RESET} ${options[$i]}\n" >&2
    done

    while true; do
        rx_log "info" "Select ${MUTE}[1-${num_options}]${RESET} (default: ${default}): "
        read -r choice

        [[ -z $choice ]] && choice="$default"

        if [[ $choice =~ ^[0-9]+$ && $choice -ge 1 && $choice -le $num_options ]]; then
            echo "${options[$((choice - 1))]}"
            return 0
        fi

        rx_log "warn" "Invalid selection"
    done
}