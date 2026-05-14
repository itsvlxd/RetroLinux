#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/variable.sh"

# TODO: add priority for some device and fallback in easyeffects

cmd_audio() {
    local audio_core="$RETRO_DIR/scripts/audio_core.sh"
    local action="${1,,}"
    local val1="$2"
    local val2="$3"

    case "$action" in
        "status")
            local status_output=$(bash "$audio_core" --status)

            local pw_ver=""
            local wp_ver=""
            local sink=""
            local sink_vol=""
            local sink_mute=""
            local source=""
            local source_mute=""
            local ee_status=""

            while IFS=: read -r key val; do
                case "$key" in
                    "pipewire") pw_ver="$val" ;;
                    "wireplumber") wp_ver="$val" ;;
                    "sink") sink="$val" ;;
                    "sink_volume") sink_vol="$val" ;;
                    "sink_mute") sink_mute="$val" ;;
                    "source") source="$val" ;;
                    "source_mute") source_mute="$val" ;;
                    "easyeffects") ee_status="$val" ;;
                esac
            done <<<"$status_output"

            local mute_icon="󰝟"
            local mute_state="Active"
            if [[ $sink_mute == "true" ]]; then
                mute_icon="󰝡"
                mute_state="Muted"
            fi

            local mic_mute_icon="󰍬"
            local mic_mute_state="Active"
            if [[ $source_mute == "true" ]]; then
                mic_mute_icon="󰝠"
                mic_mute_state="Muted"
            fi

            local ee_icon="󰛴"
            local ee_color="$PINK"
            if [[ $ee_status == "Running" ]]; then
                ee_icon="󰴑"
                ee_color="$SUCCESS"
            fi

            local sink_name=$(bash "$audio_core" --get-sink-name "$sink" 2>/dev/null || echo "$sink")
            local source_name=$(bash "$audio_core" --get-source-name "$source" 2>/dev/null || echo "$source")

            rx_table_header "" "Audio Status"
            rx_table_row "󰿅" "PipeWire:" "$pw_ver" "$GRAY" "14"
            rx_table_row "󰛫" "WirePlumber:" "$wp_ver" "$GRAY" "14"
            rx_table_separator
            rx_table_row "󰝥" "Volume:" "${sink_vol}%" "$PINK" "14"
            rx_table_row "󰕿" "Output:" "${sink_name:0:35}" "$GRAY" "14"
            rx_table_row "󰍬" "Input:" "${source_name:0:35}" "$GRAY" "14"
            rx_table_separator
            rx_table_row "󰊽" "EasyEffects:" "$ee_status" "$ee_color" "14"

            local current_eq=$(get_var "AUDIO_EQ_PRESET" "")
            [[ -z $current_eq ]] && current_eq="None"
            local eq_icon="󰛴"
            local eq_color="$GRAY"
            if [[ $current_eq != "None" ]]; then
                eq_icon="󰾰"
                eq_color="$PINK"
            fi
            rx_table_row "$eq_icon" "EQ:" "$current_eq" "$eq_color" "14"
            rx_table_separator
            rx_table_spacer
            ;;

        "set")
            [[ -z $val1 ]] && rx_log "error" "Usage: retro audio set <0-100>" && return 1
            if ! [[ $val1 =~ ^[0-9]+$ ]] || ((val1 < 0 || val1 > 100)); then
                rx_log "error" "Volume must be between 0 and 100" && return 1
            fi
            bash "$audio_core" --set-volume "$val1" >/dev/null
            rx_log "success" "Volume set to ${PINK}${val1}%${RESET}"
            ;;

        "up")
            local step="${val1:-5}"
            if ! [[ $step =~ ^[0-9]+$ ]]; then
                rx_log "error" "Step must be a number" && return 1
            fi
            local new_vol=$(bash "$audio_core" --volume-up "$step")
            rx_log "success" "Volume increased to ${PINK}${new_vol}%${RESET}"
            ;;

        "down")
            local step="${val1:-5}"
            if ! [[ $step =~ ^[0-9]+$ ]]; then
                rx_log "error" "Step must be a number" && return 1
            fi
            local new_vol=$(bash "$audio_core" --volume-down "$step")
            rx_log "success" "Volume decreased to ${PINK}${new_vol}%${RESET}"
            ;;

        "mute")
            local mute_state=$(bash "$audio_core" --toggle-mute)
            if [[ $mute_state == "true" ]]; then
                rx_log "info" "Output muted"
            else
                rx_log "success" "Output unmuted"
            fi
            ;;

        "mic-mute" | "mic")
            local mute_state=$(bash "$audio_core" --toggle-mic-mute)
            if [[ $mute_state == "true" ]]; then
                rx_log "info" "Microphone muted"
            else
                rx_log "success" "Microphone unmuted"
            fi
            ;;

        "switch")
            local sinks_raw=$(bash "$audio_core" --get-sinks)
            local current_sink=$(bash "$audio_core" --status | grep "^sink:" | cut -d: -f2)

            local sinks=()
            while IFS= read -r s; do
                [[ -n $s ]] && sinks+=("$s")
            done <<<"$sinks_raw"

            if [[ ${#sinks[@]} -eq 0 ]]; then
                rx_log "error" "No audio sinks found" && return 1
            fi

            rx_help_header "" "Select Output Device"

            local idx=0
            for s in "${sinks[@]}"; do
                local s_name=$(bash "$audio_core" --get-sink-name "$s" 2>/dev/null || echo "$s")
                local marker="  "
                if [[ $s == "$current_sink" ]]; then
                    marker="${PINK}󰤨${RESET}"
                fi
                printf " ${PINK}%d)${RESET} %s %s\n" "$((idx + 1))" "$marker" "${s_name:0:40}"
                ((idx++))
            done

            rx_table_separator

            echo -ne "\n ${PINK}󰄾 ${RESET}Selection [1-${#sinks[@]}]: "
            read -r choice

            if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#sinks[@]})); then
                local selected="${sinks[$((choice - 1))]}"
                bash "$audio_core" --set-sink "$selected" >/dev/null
                local s_name=$(bash "$audio_core" --get-sink-name "$selected" 2>/dev/null || echo "$selected")
                rx_log "success" "Output set to ${PINK}${s_name}${RESET}"
            else
                rx_log "info" "No changes made"
            fi
            ;;

        "set-sink")
            [[ -z $val1 ]] && rx_log "error" "Usage: retro audio set-sink <name>" && return 1
            bash "$audio_core" --set-sink "$val1" >/dev/null
            rx_log "success" "Output set to ${PINK}${val1}${RESET}"
            ;;

        "set-source")
            [[ -z $val1 ]] && rx_log "error" "Usage: retro audio set-source <name>" && return 1
            bash "$audio_core" --set-source "$val1" >/dev/null
            rx_log "success" "Input set to ${PINK}${val1}${RESET}"
            ;;

        "list-devices")
            local sinks_raw=$(bash "$audio_core" --get-sinks)
            local sources_raw=$(bash "$audio_core" --get-sources)
            local current_sink=$(bash "$audio_core" --status | grep "^sink:" | cut -d: -f2)
            local current_source=$(bash "$audio_core" --status | grep "^source:" | cut -d: -f2)

            rx_table_header "" "Audio Devices"
            rx_table_simple "󰕿" "Outputs (Sinks):" "$GRAY"

            while IFS= read -r s; do
                [[ -n $s ]] || continue
                local s_name=$(bash "$audio_core" --get-sink-name "$s" 2>/dev/null || echo "$s")
                local marker="   "
                [[ $s == "$current_sink" ]] && marker="${PINK}󰤨${RESET}"
                printf " ${marker} %s\n" "${s_name:0:45}"
            done <<<"$sinks_raw"

            echo ""
            rx_table_simple "󰍬" "Inputs (Sources):" "$GRAY"

            while IFS= read -r s; do
                [[ -n $s ]] || continue
                local s_name=$(bash "$audio_core" --get-source-name "$s" 2>/dev/null || echo "$s")
                local marker="   "
                [[ $s == "$current_source" ]] && marker="${PINK}󰤨${RESET}"
                printf " ${marker} %s\n" "${s_name:0:45}"
            done <<<"$sources_raw"

            rx_table_separator
            rx_table_spacer
            ;;

        "eq")
            local eq_action="$val1"
            shift 2
            local eq_val="$*"

            case "$eq_action" in
                "list" | "download" | "delete" | "delete-all" | "list-remote" | "remote" | "open")
                    ;;
                "")
                    rx_help_usage "retro audio eq <command>"
                    rx_help_commands "EQ commands"
                    rx_help_cmd "list" "List installed EQ profiles"
                    rx_help_cmd "list-remote" "List available remote profiles"
                    rx_help_cmd "download <repo>" "Download presets from GitHub"
                    rx_help_cmd "<name>" "Apply EQ profile by name"
                    rx_help_cmd "delete <name>" "Delete an EQ profile"
                    rx_help_cmd "delete-all" "Delete all EQ profiles"
                    rx_help_cmd "open" "Open EasyEffects GUI"
                    rx_help_examples
                    rx_help_example "retro audio eq list" "List all profiles"
                    rx_help_example "retro audio eq Boosted" "Apply Boosted profile"
                    rx_help_example "retro audio eq Boosted.json" "Apply with .json"
                    rx_help_example "retro audio eq download JackHack96" "Download presets"
                    rx_help_example "retro audio eq delete Boosted" "Delete profile"
                    rx_help_spacer
                    return 0
                    ;;
                *)
                    eq_val="$eq_action $eq_val"
                    eq_action="apply"
                    ;;
            esac

            case "$eq_action" in
                "list")
                    local profiles=$(bash "$audio_core" --eq-list)
                    rx_table_header "" "EQ Profiles"

                    if [[ -z $profiles ]]; then
                        rx_table_simple "󰾰" "No EQ profiles found" "$GRAY"
                    else
                        while IFS= read -r p; do
                            [[ -n $p ]] && rx_table_simple "󰾰" "$p" "$RESET"
                        done <<<"$profiles"
                    fi

                    rx_table_separator
                    rx_table_spacer
                    ;;

                "download")
                    [[ -z $eq_val ]] && rx_log "error" "Usage: retro audio eq download <repo>" && return 1

                    local valid_repos=("JackHack96" "wwmm" "Bundy01" "Digitalone1")
                    local valid=false
                    for r in "${valid_repos[@]}"; do
                        [[ $eq_val == "$r" ]] && valid=true && break
                    done

                    if [[ $valid == "false" ]]; then
                        rx_log "error" "Unknown repo: ${PINK}${eq_val}${RESET}"
                        rx_log "info" "Available repos: ${valid_repos[*]}"
                        return 1
                    fi

                    rx_log "info" "Downloading presets from ${PINK}${eq_val}${RESET}..."
                    bash "$audio_core" --eq-download "$eq_val"
                    rx_log "success" "Download complete"
                    ;;

                "list-remote" | "remote")
                    local repos=$(bash "$audio_core" --eq-list-remote)

                    rx_table_header "" "Available Preset Repositories"

                    while IFS='|' read -r name url desc; do
                        rx_table_simple "󰾰" "$name" "$PINK"
                        [[ -n $desc ]] && rx_help_wrap "$desc" 45
                        echo ""
                    done <<<"$repos"

                    rx_table_separator
                    rx_table_spacer
                    ;;

                "apply")
                    [[ -z $eq_val ]] && rx_log "error" "Usage: retro audio eq <profile-name>" && return 1

                    local profile_path=$(bash "$audio_core" --eq-apply "$eq_val")
                    if [[ -f $profile_path ]]; then
                        local profile_name=$(basename "$profile_path" .json)

                        if command -v easyeffects >/dev/null 2>&1; then
                            easyeffects -l "$profile_name" 2>/dev/null
                            rx_log "success" "Profile ${PINK}${profile_name}${RESET} applied"
                        else
                            rx_log "success" "Profile ${PINK}${profile_name}${RESET} ready"
                            rx_log "info" "EasyEffects not running. Start it to use the preset."
                        fi

                        set_var "AUDIO_EQ_PRESET" "$profile_name"
                    else
                        rx_log "error" "Profile not found: ${PINK}${eq_val}${RESET}"
                        rx_log "info" "Use 'retro audio eq list' to see available profiles"
                    fi
                    ;;

                "delete")
                    [[ -z $eq_val ]] && rx_log "error" "Usage: retro audio eq delete <profile-name>" && return 1

                    local profile_path=$(bash "$audio_core" --eq-apply "$eq_val")
                    if [[ -f $profile_path ]]; then
                        rx_log "info" "Deleting ${PINK}${eq_val}${RESET}..."
                        rm -f "$profile_path"
                        rx_log "success" "Profile deleted"
                    else
                        rx_log "error" "Profile not found: ${PINK}${eq_val}${RESET}"
                    fi
                    ;;

                "delete-all")
                    local eq_dir="$HOME/.local/share/easyeffects/output"
                    if [[ -d $eq_dir ]]; then
                        local count=$(ls -1 "$eq_dir" 2>/dev/null | wc -l)
                        if ((count > 0)); then
                            rx_log "warn" "This will delete all ${count} EQ profiles from $eq_dir"
                            rx_confirm "Confirm?" "N" || {
                                rx_log "info" "Cancelled"
                                return 0
                            }
                            rm -f "$eq_dir"/*
                            rx_log "success" "All EQ profiles deleted"
                        else
                            rx_log "info" "No profiles to delete"
                        fi
                    else
                        rx_log "info" "No EQ profiles directory found"
                    fi
                    ;;

                "open")
                    if command -v easyeffects >/dev/null 2>&1; then
                        nohup easyeffects >/dev/null 2>&1 &
                        rx_log "success" "EasyEffects GUI opened"
                    else
                        rx_log "error" "EasyEffects not installed"
                    fi
                    ;;

                *)
                    rx_help_usage "retro audio eq <command>"
                    rx_help_commands "EQ commands"
                    rx_help_cmd "list" "List installed EQ profiles"
                    rx_help_cmd "list-remote" "List available remote profiles"
                    rx_help_cmd "download <repo>" "Download presets from GitHub"
                    rx_help_cmd "<name>" "Apply EQ profile by name"
                    rx_help_cmd "delete <name>" "Delete an EQ profile"
                    rx_help_cmd "delete-all" "Delete all EQ profiles"
                    rx_help_cmd "open" "Open EasyEffects GUI"
                    ;;
            esac
            ;;

        "easyeffects" | "ee")
            local ee_action="$val1"

            case "$ee_action" in
                "start")
                    local status=$(bash "$audio_core" --ee-start)
                    if [[ $status == "Started" ]]; then
                        rx_log "success" "EasyEffects daemon started"
                    elif [[ $status == "Already running" ]]; then
                        rx_log "info" "EasyEffects is already running"
                    else
                        rx_log "error" "Failed to start EasyEffects"
                    fi
                    ;;
                "stop")
                    local status=$(bash "$audio_core" --ee-stop)
                    if [[ $status == "Stopped" ]]; then
                        rx_log "success" "EasyEffects daemon stopped"
                    elif [[ $status == "Not running" ]]; then
                        rx_log "info" "EasyEffects is not running"
                    else
                        rx_log "error" "Failed to stop EasyEffects"
                    fi
                    ;;
                "status")
                    local ee_status=$(bash "$audio_core" --status | grep "^easyeffects:" | cut -d: -f2)
                    if [[ $ee_status == "Running" ]]; then
                        rx_log "success" "EasyEffects is running"
                    else
                        rx_log "info" "EasyEffects is stopped"
                    fi
                    ;;
                "restart")
                    bash "$audio_core" --ee-stop >/dev/null 2>&1
                    sleep 1
                    local status=$(bash "$audio_core" --ee-start)
                    if [[ $status == "Started" ]]; then
                        rx_log "success" "EasyEffects daemon restarted"
                    else
                        rx_log "error" "Failed to restart EasyEffects"
                    fi
                    ;;
                "open")
                    if command -v easyeffects >/dev/null 2>&1; then
                        nohup easyeffects >/dev/null 2>&1 &
                        rx_log "success" "EasyEffects GUI opened"
                    else
                        rx_log "error" "EasyEffects not installed"
                    fi
                    ;;
                *)
                    rx_help_usage "retro audio easyeffects <command>"
                    rx_help_commands "EasyEffects commands"
                    rx_help_cmd "start" "Start EasyEffects daemon"
                    rx_help_cmd "stop" "Stop EasyEffects daemon"
                    rx_help_cmd "restart" "Restart EasyEffects daemon"
                    rx_help_cmd "status" "Check EasyEffects status"
                    rx_help_cmd "open" "Open EasyEffects GUI"
                    rx_help_examples
                    rx_help_example "retro audio easyeffects start" "Start daemon"
                    rx_help_example "retro audio easyeffects restart" "Restart daemon"
                    rx_help_example "retro audio easyeffects open" "Open GUI"
                    rx_help_spacer
                    ;;
            esac
            ;;

        "fix-stutter")
            rx_log "info" "Fixing audio stutter (CPU affinity)..."

            local result=$(bash "$audio_core" --fix-stutter)
            rx_log "success" "Applied CPU affinity: ${PINK}${result}${RESET}"
            rx_log "info" "Audio services have been restarted with P-core affinity"

            bash "$audio_core" --ee-start >/dev/null 2>&1
            rx_log "success" "EasyEffects daemon started"
            ;;

        "sources" | "inputs")
            local sources_raw=$(bash "$audio_core" --get-sources)
            local current_source=$(bash "$audio_core" --status | grep "^source:" | cut -d: -f2)

            rx_table_header "󰑊" "Input Devices"

            while IFS= read -r s; do
                [[ -n $s ]] || continue
                local s_name=$(bash "$audio_core" --get-source-name "$s" 2>/dev/null || echo "$s")
                local marker="   "
                [[ $s == "$current_source" ]] && marker="${PINK}󰤨${RESET}"
                printf " ${marker} %s\n" "${s_name:0:45}"
            done <<<"$sources_raw"

            rx_table_separator
            ;;

        *)
            rx_help_usage "retro audio <command>"
            rx_help_commands "Available commands"
            rx_help_cmd "status" "Show audio status and info"
            rx_help_cmd "set <0-100>" "Set volume level"
            rx_help_cmd "up [step]" "Increase volume (default 5%)"
            rx_help_cmd "down [step]" "Decrease volume (default 5%)"
            rx_help_cmd "mute" "Toggle output mute"
            rx_help_cmd "mic-mute" "Toggle microphone mute"
            rx_help_cmd "switch" "Switch output device"
            rx_help_cmd "list-devices" "List all audio devices"
            rx_help_cmd "set-sink <name>" "Set default output"
            rx_help_cmd "set-source <name>" "Set default input"
            rx_help_cmd "eq [args]" "EQ profile management"
            rx_help_cmd "easyeffects [cmd]" "Control EasyEffects"
            rx_help_cmd "fix-stutter" "Fix audio crackling"
            rx_help_examples
            rx_help_example "retro audio set 50" "Set volume to 50%"
            rx_help_example "retro audio up 10" "Increase volume by 10%"
            rx_help_example "retro audio mute" "Toggle mute"
            rx_help_example "retro audio eq list" "List EQ profiles"
            rx_help_example "retro audio eq Boosted" "Apply Boosted profile"
            rx_help_spacer
            ;;
    esac
}

register_command "TOOLS" "audio" "Audio management with PipeWire/WirePlumber" "cmd_audio"
