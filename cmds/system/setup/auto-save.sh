#!/bin/bash

rx_setup_session_service() {
    local existing_auto=$(get_var "RETRO_SESSION_AUTOSAVE")
    local existing_load=$(get_var "RETRO_SESSION_AUTOLOAD")

    if [[ -n $existing_auto && $existing_auto != "null" && -n $existing_load && $existing_load != "null" ]]; then
        return 0
    fi

    rx_log "info" "Would you like to configure the Retro Session Manager (Beta)?"
    rx_log "info" "This can auto-save your windows on shutdown and instantly restore them on startup."

    rx_log "info" "Enable automatic background SAVING on shutdown? ${PINK}[y/N]${RESET}: "
    read -r allow_save
    if [[ $allow_save =~ ^[Yy]$ ]]; then
        set_var "RETRO_SESSION_AUTOSAVE" "true"
    else
        set_var "RETRO_SESSION_AUTOSAVE" "false"
    fi

    rx_log "info" "Enable automatic session RESTORE on startup? ${PINK}[y/N]${RESET}: "
    read -r allow_load
    if [[ $allow_load =~ ^[Yy]$ ]]; then
        set_var "RETRO_SESSION_AUTOLOAD" "true"
        rx_log "info" "Auto-restore enabled."
    else
        set_var "RETRO_SESSION_AUTOLOAD" "false"
        rx_log "info" "Auto-restore disabled."
    fi

    if [[ $allow_save =~ ^[Yy]$ ]]; then
        local service_dir="$HOME/.config/systemd/user"
        local service_file="$service_dir/retro-session.service"
        local retro_bin=$(command -v retro)

        if [[ -z $retro_bin ]]; then
            rx_log "error" "Could not find the 'retro' executable in PATH. Setup aborted."
            return 1
        fi

        if ! command -v systemctl &>/dev/null; then
            rx_log "error" "systemd is not available on this system. Cannot configure auto-save."
            return 1
        fi

        rx_log "info" "Configuring Retro Session auto-save daemon..."

        mkdir -p "$service_dir"

        cat <<EOF >"$service_file"
[Unit]
Description=Retro Window Manager Auto-Save
PartOf=graphical-session.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/bin/true
ExecStop=/usr/bin/env bash -c "$retro_bin -wm daemon-save"

[Install]
WantedBy=graphical-session.target
EOF

        systemctl --user daemon-reload
        systemctl --user enable retro-session.service --now &>/dev/null

        if systemctl --user is-enabled retro-session.service &>/dev/null; then
            rx_log "success" "Retro Session auto-save is active. It will trigger on shutdown/logout."
        else
            rx_log "error" "Failed to enable the systemd user service."
        fi
    fi
}
