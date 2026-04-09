#!/bin/bash

cmd_audio() {
    local audio_core="$RETRO_DIR/scripts/audio_core.sh"
    local action="$1"
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
            if [[ "$sink_mute" == "true" ]]; then
                mute_icon="󰝡"
                mute_state="Muted"
            fi

            local mic_mute_icon="󰍬"
            local mic_mute_state="Active"
            if [[ "$source_mute" == "true" ]]; then
                mic_mute_icon="󰝠"
                mic_mute_state="Muted"
            fi

            local ee_icon="󰛴"
            local ee_color="$PINK"
            if [[ "$ee_status" == "Running" ]]; then
                ee_icon="󰴑"
                ee_color="$SUCCESS"
            fi

            local sink_name=$(bash "$audio_core" --get-sink-name "$sink" 2>/dev/null || echo "$sink")
            local source_name=$(bash "$audio_core" --get-source-name "$source" 2>/dev/null || echo "$source")

            echo -e "\n ${PINK}󰑊 Audio Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"
            printf " ${PINK}󰿅${RESET} %-14s ${GRAY}%s${RESET}\n" "PipeWire:" "$pw_ver"
            printf " ${PINK}󰛫${RESET} %-14s ${GRAY}%s${RESET}\n" "WirePlumber:" "$wp_ver"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"
            printf " ${PINK}󰝥${RESET} %-14s ${PINK}%s%%${RESET} (${mute_state})\n" "Volume:" "$sink_vol"
            printf " ${PINK}${mute_icon}${RESET} %-14s ${GRAY}%s${RESET}\n" "Output:" "${sink_name:0:35}"
            printf " ${PINK}${mic_mute_icon}${RESET} %-14s ${GRAY}%s${RESET}\n" "Input:" "${source_name:0:35}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"
            printf " ${PINK}${ee_icon}${RESET} %-14s ${ee_color}%s${RESET}\n" "EasyEffects:" "$ee_status"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "set")
            [[ -z $val1 ]] && rx_log "error" "Usage: retro audio set <0-100>" && return 1
            if ! [[ "$val1" =~ ^[0-9]+$ ]] || ((val1 < 0 || val1 > 100)); then
                rx_log "error" "Volume must be between 0 and 100" && return 1
            fi
            bash "$audio_core" --set-volume "$val1" >/dev/null
            rx_log "success" "Volume set to ${PINK}${val1}%${RESET}"
            ;;

        "up")
            local step="${val1:-5}"
            if ! [[ "$step" =~ ^[0-9]+$ ]]; then
                rx_log "error" "Step must be a number" && return 1
            fi
            local new_vol=$(bash "$audio_core" --volume-up "$step")
            rx_log "success" "Volume increased to ${PINK}${new_vol}%${RESET}"
            ;;

        "down")
            local step="${val1:-5}"
            if ! [[ "$step" =~ ^[0-9]+$ ]]; then
                rx_log "error" "Step must be a number" && return 1
            fi
            local new_vol=$(bash "$audio_core" --volume-down "$step")
            rx_log "success" "Volume decreased to ${PINK}${new_vol}%${RESET}"
            ;;

        "mute")
            local mute_state=$(bash "$audio_core" --toggle-mute)
            if [[ "$mute_state" == "true" ]]; then
                rx_log "info" "Output muted"
            else
                rx_log "success" "Output unmuted"
            fi
            ;;

        "mic-mute"|"mic")
            local mute_state=$(bash "$audio_core" --toggle-mic-mute)
            if [[ "$mute_state" == "true" ]]; then
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

            echo -e "\n ${PINK}󰑊 Select Output Device${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

            local idx=0
            for s in "${sinks[@]}"; do
                local s_name=$(bash "$audio_core" --get-sink-name "$s" 2>/dev/null || echo "$s")
                local marker="  "
                if [[ "$s" == "$current_sink" ]]; then
                    marker="${PINK}󰤨${RESET}"
                fi
                printf " ${PINK}%d)${RESET} %s %s\n" "$((idx + 1))" "$marker" "${s_name:0:40}"
                ((idx++))
            done

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

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

            echo -e "\n ${PINK}󰑊 Audio Devices${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"
            echo -e " ${PINK}󰝥  Outputs (Sinks):${RESET}"

            while IFS= read -r s; do
                [[ -n $s ]] || continue
                local s_name=$(bash "$audio_core" --get-sink-name "$s" 2>/dev/null || echo "$s")
                local marker="   "
                [[ "$s" == "$current_sink" ]] && marker="${PINK}󰤨${RESET}"
                printf " ${marker} %s\n" "${s_name:0:45}"
            done <<<"$sinks_raw"

            echo -e ""
            echo -e " ${PINK}󰍬  Inputs (Sources):${RESET}"

            while IFS= read -r s; do
                [[ -n $s ]] || continue
                local s_name=$(bash "$audio_core" --get-source-name "$s" 2>/dev/null || echo "$s")
                local marker="   "
                [[ "$s" == "$current_source" ]] && marker="${PINK}󰤨${RESET}"
                printf " ${marker} %s\n" "${s_name:0:45}"
            done <<<"$sources_raw"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        "eq")
            local eq_action="$val1"
            shift 2
            local eq_val="$*"

            case "$eq_action" in
                "list"|"download"|"delete"|"delete-all"|"list-remote"|"remote"|"open")
                    ;;
                "")
                    rx_log "info" "Usage: retro audio eq <command>"
                    echo -e ""
                    echo -e " ${PINK}  ${RESET}EQ commands${GRAY}:${RESET}"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list" "List installed EQ profiles"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list-remote" "List available remote profiles"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "download <repo>" "Download presets from GitHub"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "<name>" "Apply EQ profile by name"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "delete <name>" "Delete an EQ profile"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "delete-all" "Delete all EQ profiles"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "open" "Open EasyEffects GUI"
                    echo ""
                    echo -e " ${PINK}Examples${GRAY}:${RESET}"
                    printf " ${GRAY}%-30s${RESET} %s\n" "retro audio eq list" "List all profiles"
                    printf " ${GRAY}%-30s${RESET} %s\n" "retro audio eq Boosted" "Apply Boosted profile"
                    printf " ${GRAY}%-30s${RESET} %s\n" "retro audio eq Boosted.json" "Apply with .json"
                    printf " ${GRAY}%-30s${RESET} %s\n" "retro audio eq download JackHack96" "Download presets"
                    printf " ${GRAY}%-30s${RESET} %s\n" "retro audio eq delete Boosted" "Delete profile"
                    echo ""
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
                    echo -e "\n ${PINK}󰑊 EQ Profiles${RESET}"
                    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

                    if [[ -z "$profiles" ]]; then
                        echo -e " ${GRAY}No EQ profiles found${RESET}"
                    else
                        while IFS= read -r p; do
                            [[ -n $p ]] && printf " ${PINK}󰾰${RESET} %s\n" "$p"
                        done <<<"$profiles"
                    fi

                    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
                    ;;

                "download")
                    [[ -z $eq_val ]] && rx_log "error" "Usage: retro audio eq download <repo>" && return 1

                    local valid_repos=("JackHack96" "wwmm" "Bundy01" "Digitalone1")
                    local valid=false
                    for r in "${valid_repos[@]}"; do
                        [[ "$eq_val" == "$r" ]] && valid=true && break
                    done

                    if [[ "$valid" == "false" ]]; then
                        rx_log "error" "Unknown repo: ${PINK}${eq_val}${RESET}"
                        rx_log "info" "Available repos: ${valid_repos[*]}"
                        return 1
                    fi

                    rx_log "info" "Downloading presets from ${PINK}${eq_val}${RESET}..."
                    bash "$audio_core" --eq-download "$eq_val"
                    rx_log "success" "Download complete"
                    ;;

                "list-remote"|"remote")
                    local repos=$(bash "$audio_core" --eq-list-remote)
                    
                    echo -e "\n ${PINK}󰑊 Available Preset Repositories${RESET}"
                    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

                    while IFS='|' read -r name url desc; do
                        printf " ${PINK}󰾰${RESET} ${PINK}%s${RESET}\n" "$name"
                        [[ -n "$desc" ]] && printf "   ${GRAY}%s${RESET}\n" "$desc"
                        echo ""
                    done <<<"$repos"

                    echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
                    ;;

                "apply")
                    [[ -z $eq_val ]] && rx_log "error" "Usage: retro audio eq <profile-name>" && return 1

                    local profile_path=$(bash "$audio_core" --eq-apply "$eq_val")
                    if [[ -f "$profile_path" ]]; then
                        local profile_name=$(basename "$profile_path" .json)
                        
                        if command -v easyeffects >/dev/null 2>&1; then
                            easyeffects -l "$profile_name" 2>/dev/null
                            rx_log "success" "Profile ${PINK}${profile_name}${RESET} applied"
                        else
                            rx_log "success" "Profile ${PINK}${profile_name}${RESET} ready"
                            rx_log "info" "EasyEffects not running. Start it to use the preset."
                        fi
                    else
                        rx_log "error" "Profile not found: ${PINK}${eq_val}${RESET}"
                        rx_log "info" "Use 'retro audio eq list' to see available profiles"
                    fi
                    ;;

                "delete")
                    [[ -z $eq_val ]] && rx_log "error" "Usage: retro audio eq delete <profile-name>" && return 1
                    
                    local profile_path=$(bash "$audio_core" --eq-apply "$eq_val")
                    if [[ -f "$profile_path" ]]; then
                        rx_log "info" "Deleting ${PINK}${eq_val}${RESET}..."
                        rm -f "$profile_path"
                        rx_log "success" "Profile deleted"
                    else
                        rx_log "error" "Profile not found: ${PINK}${eq_val}${RESET}"
                    fi
                    ;;

                "delete-all")
                    local eq_dir="$HOME/.local/share/easyeffects/output"
                    if [[ -d "$eq_dir" ]]; then
                        local count=$(ls -1 "$eq_dir" 2>/dev/null | wc -l)
                        if ((count > 0)); then
                            rx_log "warn" "This will delete all ${count} EQ profiles from $eq_dir"
                            echo -ne " ${PINK}󰄾 ${RESET}Confirm? ${PINK}[y/N]${RESET}: "
                            read -r confirm
                            if [[ $confirm =~ ^[Yy]$ ]]; then
                                rm -f "$eq_dir"/*
                                rx_log "success" "All EQ profiles deleted"
                            else
                                rx_log "info" "Cancelled"
                            fi
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
                    rx_log "info" "Usage: retro audio eq <command>"
                    echo -e ""
                    echo -e " ${PINK}  ${RESET}EQ commands${GRAY}:${RESET}"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list" "List installed EQ profiles"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list-remote" "List available remote profiles"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "download <repo>" "Download presets from GitHub"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "<name>" "Apply EQ profile by name"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "delete <name>" "Delete an EQ profile"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "delete-all" "Delete all EQ profiles"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "open" "Open EasyEffects GUI"
                    echo ""
                    ;;
            esac
            ;;

        "easyeffects"|"ee")
            local ee_action="$val1"

            case "$ee_action" in
                "start")
                    local status=$(bash "$audio_core" --ee-start)
                    if [[ "$status" == "Started" ]]; then
                        rx_log "success" "EasyEffects daemon started"
                    elif [[ "$status" == "Already running" ]]; then
                        rx_log "info" "EasyEffects is already running"
                    else
                        rx_log "error" "Failed to start EasyEffects"
                    fi
                    ;;
                "stop")
                    local status=$(bash "$audio_core" --ee-stop)
                    if [[ "$status" == "Stopped" ]]; then
                        rx_log "success" "EasyEffects daemon stopped"
                    elif [[ "$status" == "Not running" ]]; then
                        rx_log "info" "EasyEffects is not running"
                    else
                        rx_log "error" "Failed to stop EasyEffects"
                    fi
                    ;;
                "status")
                    local ee_status=$(bash "$audio_core" --status | grep "^easyeffects:" | cut -d: -f2)
                    if [[ "$ee_status" == "Running" ]]; then
                        rx_log "success" "EasyEffects is running"
                    else
                        rx_log "info" "EasyEffects is stopped"
                    fi
                    ;;
                "restart")
                    bash "$audio_core" --ee-stop >/dev/null 2>&1
                    sleep 1
                    local status=$(bash "$audio_core" --ee-start)
                    if [[ "$status" == "Started" ]]; then
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
                    rx_log "info" "Usage: retro audio easyeffects <command>"
                    echo -e ""
                    echo -e " ${PINK}  ${RESET}EasyEffects commands${GRAY}:${RESET}"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "start" "Start EasyEffects daemon"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "stop" "Stop EasyEffects daemon"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "restart" "Restart EasyEffects daemon"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Check EasyEffects status"
                    printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "open" "Open EasyEffects GUI"
                    echo ""
                    echo -e " ${PINK}Examples${GRAY}:${RESET}"
                    printf " ${GRAY}%-30s${RESET} %s\n" "retro audio easyeffects start" "Start daemon"
                    printf " ${GRAY}%-30s${RESET} %s\n" "retro audio easyeffects restart" "Restart daemon"
                    printf " ${GRAY}%-30s${RESET} %s\n" "retro audio easyeffects open" "Open GUI"
                    echo ""
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

        "sources"|"inputs")
            local sources_raw=$(bash "$audio_core" --get-sources)
            local current_source=$(bash "$audio_core" --status | grep "^source:" | cut -d: -f2)

            echo -e "\n ${PINK}󰑊 Input Devices${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"

            while IFS= read -r s; do
                [[ -n $s ]] || continue
                local s_name=$(bash "$audio_core" --get-source-name "$s" 2>/dev/null || echo "$s")
                local marker="   "
                [[ "$s" == "$current_source" ]] && marker="${PINK}󰤨${RESET}"
                printf " ${marker} %s\n" "${s_name:0:45}"
            done <<<"$sources_raw"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}\n"
            ;;

        *)
            rx_log "info" "Usage: retro audio <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Available commands${GRAY}:${RESET}"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "status" "Show audio status and info"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "set <0-100>" "Set volume level"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "up [step]" "Increase volume (default 5%)"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "down [step]" "Decrease volume (default 5%)"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "mute" "Toggle output mute"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "mic-mute" "Toggle microphone mute"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "switch" "Switch output device"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "list-devices" "List all audio devices"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "set-sink <name>" "Set default output"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "set-source <name>" "Set default input"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "eq [args]" "EQ profile management"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "easyeffects [cmd]" "Control EasyEffects"
            printf " ${PINK}%-18s${GRAY}- ${RESET}%s\n" "fix-stutter" "Fix audio crackling"
            echo ""
            echo -e " ${PINK}Examples${GRAY}:${RESET}"
            printf " ${GRAY}%-30s${RESET} %s\n" "retro audio set 50" "Set volume to 50%"
            printf " ${GRAY}%-30s${RESET} %s\n" "retro audio up 10" "Increase volume by 10%"
            printf " ${GRAY}%-30s${RESET} %s\n" "retro audio mute" "Toggle mute"
            printf " ${GRAY}%-30s${RESET} %s\n" "retro audio eq list" "List EQ profiles"
            printf " ${GRAY}%-30s${RESET} %s\n" "retro audio eq Boosted" "Apply Boosted profile"
            echo ""
            ;;
    esac
}

register_command "TOOLS" "audio" "Audio management with PipeWire/WirePlumber" "cmd_audio"