#!/bin/bash

source "$RETRO_DIR/lib/menu.sh"
source "$RETRO_DIR/lib/colors.sh"
source "$RETRO_DIR/lib/log.sh"

setup_audio() {
    local audio_core="$RETRO_DIR/scripts/audio_core.sh"

    rx_log "info" "Setting up audio device priorities..."

    local sink_ids=()
    local sink_labels=()
    while IFS= read -r id; do
        [[ -z $id ]] && continue
        local name=$(bash "$audio_core" --get-sink-name "$id" 2>/dev/null)
        local pw=$(bash "$audio_core" --get-sink-persistent-name "$id" 2>/dev/null)
        sink_ids+=("$id")
        if [[ -n $pw ]]; then
            sink_labels+=("$name [$pw]")
        else
            sink_labels+=("$name")
        fi
    done <<<"$(bash "$audio_core" --get-sinks)"

    local source_ids=()
    local source_labels=()
    while IFS= read -r id; do
        [[ -z $id ]] && continue
        local name=$(bash "$audio_core" --get-source-name "$id" 2>/dev/null)
        local pw=$(bash "$audio_core" --get-source-persistent-name "$id" 2>/dev/null)
        source_ids+=("$id")
        if [[ -n $pw ]]; then
            source_labels+=("$name [$pw]")
        else
            source_labels+=("$name")
        fi
    done <<<"$(bash "$audio_core" --get-sources)"

    if [[ ${#sink_labels[@]} -eq 0 ]]; then
        rx_log "warn" "No audio sinks found, skipping audio setup"
        return 0
    fi

    local primary_sink_label=$(rx_menu "󰕿" "Select primary output device:" "${sink_labels[@]}")
    local primary_sink_idx=-1
    for i in "${!sink_labels[@]}"; do
        [[ "${sink_labels[$i]}" == "$primary_sink_label" ]] && primary_sink_idx=$i && break
    done
    local primary_sink_pw=$(bash "$audio_core" --get-sink-persistent-name "${sink_ids[$primary_sink_idx]}" 2>/dev/null)

    local fallback_options=("None (no fallback)" "${sink_labels[@]}")
    local fallback_sink_label=$(rx_menu "󰕿" "Select fallback output device:" "${fallback_options[@]}")
    local fallback_sink_pw=""
    if [[ "$fallback_sink_label" != "None (no fallback)" ]]; then
        for i in "${!sink_labels[@]}"; do
            [[ "${sink_labels[$i]}" == "$fallback_sink_label" ]] && fallback_sink_pw=$(bash "$audio_core" --get-sink-persistent-name "${sink_ids[$i]}" 2>/dev/null) && break
        done
    fi

    if [[ ${#source_labels[@]} -gt 0 ]]; then
        local primary_source_label=$(rx_menu "󰍬" "Select primary input device:" "${source_labels[@]}")
        local primary_source_idx=-1
        for i in "${!source_labels[@]}"; do
            [[ "${source_labels[$i]}" == "$primary_source_label" ]] && primary_source_idx=$i && break
        done
        local primary_source_pw=$(bash "$audio_core" --get-source-persistent-name "${source_ids[$primary_source_idx]}" 2>/dev/null)

        local fallback_source_options=("None (no fallback)" "${source_labels[@]}")
        local fallback_source_label=$(rx_menu "󰍬" "Select fallback input device:" "${fallback_source_options[@]}")
        local fallback_source_pw=""
        if [[ "$fallback_source_label" != "None (no fallback)" ]]; then
            for i in "${!source_labels[@]}"; do
                [[ "${source_labels[$i]}" == "$fallback_source_label" ]] && fallback_source_pw=$(bash "$audio_core" --get-source-persistent-name "${source_ids[$i]}" 2>/dev/null) && break
            done
        fi
    fi

    if [[ -n $primary_sink_pw ]]; then
        if [[ -n $fallback_sink_pw ]]; then
            bash "$audio_core" --audio-priority-set "sink" "$primary_sink_pw" "$fallback_sink_pw" >/dev/null
        else
            bash "$audio_core" --audio-priority-set "sink" "$primary_sink_pw" "" >/dev/null
        fi
        rx_log "success" "Sink priority set: $primary_sink_pw"
    fi

    if [[ -n $primary_source_pw ]]; then
        if [[ -n $fallback_source_pw ]]; then
            bash "$audio_core" --audio-priority-set "source" "$primary_source_pw" "$fallback_source_pw" >/dev/null
        else
            bash "$audio_core" --audio-priority-set "source" "$primary_source_pw" "" >/dev/null
        fi
        rx_log "success" "Source priority set: $primary_source_pw"
    fi
}
