#!/bin/bash

source "$RETRO_DIR/lib/helpers.sh"

rx_optimize_cpu() {
    local pwr_script="$RETRO_DIR/scripts/power_core.sh"

    local raw_match=$(bash "$pwr_script" --optimize)
    IFS='|' read -r c_name ac_csv bat_csv <<<"$raw_match"

    IFS=',' read -r s_ac b_ac p_ac <<<"$ac_csv"
    IFS=',' read -r s_bat b_bat p_bat <<<"$bat_csv"

    local cur_s_ac=$(get_var "PWR_AC_SAVER")
    local cur_b_ac=$(get_var "PWR_AC_BALANCED")
    local cur_p_ac=$(get_var "PWR_AC_PERFORMANCE")
    local cur_s_bat=$(get_var "PWR_BAT_SAVER")
    local cur_b_bat=$(get_var "PWR_BAT_BALANCED")
    local cur_p_bat=$(get_var "PWR_BAT_PERFORMANCE")

    local is_default=false
    if [[ ($cur_s_bat == "7" || $cur_s_bat == "null" || -z $cur_s_bat) &&
        ($cur_b_bat == "14" || $cur_b_bat == "null" || -z $cur_b_bat) &&
        ($cur_p_bat == "35" || $cur_p_bat == "null" || -z $cur_p_bat) &&
        ($cur_s_ac == "15" || $cur_s_ac == "null" || -z $cur_s_ac) &&
        ($cur_b_ac == "28" || $cur_b_ac == "null" || -z $cur_b_ac) &&
        ($cur_p_ac == "65" || $cur_p_ac == "null" || -z $cur_p_ac) ]]; then
        is_default=true
    fi

    [[ $is_default == "false" ]] && return 0

    rx_log "info" "Would you like to apply optimized settings for ${PINK}$c_name${RESET}? ${PINK}[y/N]${RESET}: "
    read -r allow

    if [[ ! $allow =~ ^[Yy]$ ]]; then
        rx_log "info" "Optimization skipped. Keeping current defaults."
        return 0
    fi

    bash "$RETRO_DIR/retro.sh" --power "optimize"
}
