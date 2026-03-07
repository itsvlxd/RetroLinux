rx_optimize_cpu_defaults() {
    local pwr_script="$RETRO_DIR/scripts/power_core.sh"
    local var_script="$RETRO_DIR/scripts/variable_core.sh"

    local raw_match=$(bash "$pwr_script" --optimize)
    IFS='|' read -r c_name ac_csv bat_csv <<<"$raw_match"

    IFS=',' read -r s_ac b_ac p_ac <<<"$ac_csv"
    IFS=',' read -r s_bat b_bat p_bat <<<"$bat_csv"

    local cur_s_ac=$(bash "$var_script" --get "PWR_AC_SAVER")
    local cur_b_ac=$(bash "$var_script" --get "PWR_AC_BALANCED")
    local cur_p_ac=$(bash "$var_script" --get "PWR_AC_PERFORMANCE")
    local cur_s_bat=$(bash "$var_script" --get "PWR_BAT_SAVER")
    local cur_b_bat=$(bash "$var_script" --get "PWR_BAT_BALANCED")
    local cur_p_bat=$(bash "$var_script" --get "PWR_BAT_PERFORMANCE")

    if [[ $s_ac == "$cur_s_ac" && $b_ac == "$cur_b_ac" && $p_ac == "$cur_p_ac" &&
        $s_bat == "$cur_s_bat" && $b_bat == "$cur_b_bat" && $p_bat == "$cur_p_bat" ]]; then
        return 0
    fi

    rx_log "info" "I found some power optimizations for your ${PINK}$c_name${RESET}."
    echo -ne " ${PINK}󰄾 ${RESET}Would you like to apply these settings? [y/N]: "
    read -r allow

    if [[ ! $allow =~ ^[Yy]$ ]]; then
        rx_log "info" "Optimization skipped. Keeping your current limits."
        return 0
    fi

    bash "$RETRO_DIR/retro.sh" --power optimize
}
