#!/bin/bash

source "$RETRO_DIR/scripts/log_core.sh"
source "$RETRO_DIR/lib/helpers.sh"
rx_log_register "keyring"

if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi


_detect_dm() {
    if pgrep -x sddm >/dev/null 2>&1; then
        echo "sddm"
    elif pgrep -x greetd >/dev/null 2>&1; then
        echo "greetd"
    elif pgrep -x login >/dev/null 2>&1; then
        echo "login"
    else
        echo "login"
    fi
}

_pam_file_for_dm() {
    local dm="$1"
    case "$dm" in
        sddm) echo "/etc/pam.d/sddm" ;;
        greetd) echo "/etc/pam.d/greetd" ;;
        login) echo "/etc/pam.d/login" ;;
        *) echo "/etc/pam.d/login" ;;
    esac
}

case "$1" in
    --status)
        service_gk="inactive"
        pkg_gk="missing"
        pkg_ls="missing"
        pam_auth="missing"
        pam_session="missing"
        keyring_state="unknown"
        item_count=0

        if systemctl --user is-active gnome-keyring-daemon.service &>/dev/null; then
            service_gk="active"
        fi

        if pacman -Qi gnome-keyring &>/dev/null; then
            pkg_gk="installed"
        fi
        if pacman -Qi libsecret &>/dev/null; then
            pkg_ls="installed"
        fi

        dm=$(_detect_dm)
        pam_file=$(_pam_file_for_dm "$dm")
        if [[ -f $pam_file ]]; then
            grep -q "pam_gnome_keyring.so" "$pam_file" 2>/dev/null && pam_auth="configured" && pam_session="configured"
        fi

        if [[ $service_gk == "active" ]]; then
            if test_result=$(secret-tool search --all xdg:schema org.retrolinux.GenericSecret 2>&1); then
                keyring_state="unlocked"
                item_count=$(echo "$test_result" | grep -c "^label = " 2>/dev/null || true)
            else
                keyring_state="locked"
            fi
        fi

        echo "service_gnome_keyring=${service_gk}"
        echo "pkg_gnome_keyring=${pkg_gk}"
        echo "pkg_libsecret=${pkg_ls}"
        echo "pam_file=${pam_file}"
        echo "pam_auth=${pam_auth}"
        echo "pam_session=${pam_session}"
        echo "keyring_state=${keyring_state}"
        echo "item_count=${item_count}"
        rx_log_file "info" "Status check: ${service_gk} | PAM: ${pam_auth} | keyring: ${keyring_state} | items: ${item_count}"
        ;;

    --lock)
        rx_log_file "info" "Locking keyring..."
        if systemctl --user is-active gnome-keyring-daemon.service &>/dev/null; then
            systemctl --user stop gnome-keyring-daemon.service 2>&1
            rx_log_file "success" "Keyring locked (daemon stopped)"
            echo "OK|locked"
        else
            rx_log_file "warn" "Keyring daemon not running"
            echo "OK|already_locked"
        fi
        ;;

    --unlock)
        rx_log_file "info" "Unlocking keyring..."
        if ! systemctl --user is-active gnome-keyring-daemon.service &>/dev/null; then
            systemctl --user start gnome-keyring-daemon.service 2>&1
            sleep 0.5
        fi

        if secret-tool search --all xdg:schema org.retrolinux.GenericSecret &>/dev/null; then
            rx_log_file "success" "Keyring unlocked"
            echo "OK|unlocked"
        else
            rx_log_file "error" "Keyring still locked"
            echo "result=error|reason=still_locked"
            exit 1
        fi
        ;;

    --list)
        rx_log_file "info" "Listing stored secrets..."
         output
        if output=$(secret-tool search --all xdg:schema org.retrolinux.GenericSecret 2>&1) && [[ -n $output ]]; then
            echo "$output"
            rx_log_file "info" "Listed secrets successfully"
        else
            rx_log_file "warn" "No secrets found"
        fi
        ;;

    --store)
         label="$2"
        shift 2
        if [[ -z $label ]]; then
            echo "result=error|reason=no_label"
            rx_log_file "error" "Store failed: no label provided"
            exit 1
        fi
        rx_log_file "info" "Storing secret: ${label}"
         secret
        read -r secret
        if [[ -z $secret ]]; then
            echo "result=error|reason=no_secret"
            rx_log_file "error" "Store failed: no secret on stdin"
            exit 1
        fi
        schema="org.retrolinux.GenericSecret"
        attrs=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -a)
                    shift
                    attr_pair="$1"
                    attr_key="${attr_pair%%=*}"
                    attr_val="${attr_pair#*=}"
                    if [[ $attr_key == "xdg:schema" ]]; then
                        schema="$attr_val"
                    else
                        attrs+=("$attr_key" "$attr_val")
                    fi
                    shift
                    ;;
                *)
                    echo "result=error|reason=unknown_flag|flag=$1"
                    rx_log_file "error" "Store failed: unknown flag $1"
                    exit 1
                    ;;
            esac
        done
        if echo -n "$secret" | secret-tool store --label="$label" xdg:schema "$schema" "${attrs[@]}" 2>&1; then
            echo "OK|stored|label=${label}"
            rx_log_file "success" "Secret stored: ${label} (schema: ${schema})"
        else
            echo "result=error|reason=store_failed"
            rx_log_file "error" "Store failed for: ${label}"
            exit 1
        fi
        ;;

    --retrieve)
         attr="$2"
         value="$3"
        if [[ -z $attr || -z $value ]]; then
            echo "result=error|reason=missing_attr_or_value"
            rx_log_file "error" "Retrieve failed: missing attribute or value"
            exit 1
        fi
        rx_log_file "info" "Retrieving secret: ${attr}=${value}"
        if secret=$(secret-tool lookup "$attr" "$value" 2>&1) && [[ -n $secret ]]; then
            echo "$secret"
            rx_log_file "success" "Secret retrieved: ${attr}=${value}"
        else
            echo "result=error|reason=not_found|attr=${attr}|value=${value}"
            rx_log_file "error" "Secret not found: ${attr}=${value}"
            exit 1
        fi
        ;;

    --delete)
         attr="$2"
         value="$3"
        if [[ -z $attr || -z $value ]]; then
            echo "result=error|reason=missing_attr_or_value"
            rx_log_file "error" "Delete failed: missing attribute or value"
            exit 1
        fi
        rx_log_file "info" "Deleting secret: ${attr}=${value}"
        if secret-tool clear "$attr" "$value" 2>&1; then
            echo "OK|deleted|${attr}=${value}"
            rx_log_file "success" "Secret deleted: ${attr}=${value}"
        else
            echo "result=error|reason=delete_failed"
            rx_log_file "error" "Delete failed for: ${attr}=${value}"
            exit 1
        fi
        ;;

    --pam-status)
         dm=$(_detect_dm)
         pam_file=$(_pam_file_for_dm "$dm")
         configured="missing"

        if [[ -f $pam_file ]]; then
            if grep -q "pam_gnome_keyring.so" "$pam_file" 2>/dev/null; then
                configured="configured"
            fi
        fi

        echo "dm=${dm}"
        echo "pam_file=${pam_file}"
        echo "pam_gnome_keyring=${configured}"
        rx_log_file "info" "PAM status: ${dm} ${pam_file} = ${configured}"
        ;;

    --pam-configure)
         dm=$(_detect_dm)
         pam_file=$(_pam_file_for_dm "$dm")
         backup="${pam_file}.bak"

        if [[ ! -f $pam_file ]]; then
            echo "result=error|reason=pam_file_not_found|file=${pam_file}"
            rx_log_file "error" "PAM configure failed: ${pam_file} not found"
            exit 1
        fi

        if grep -q "pam_gnome_keyring.so" "$pam_file" 2>/dev/null; then
            echo "OK|already_configured"
            rx_log_file "info" "PAM already configured for ${dm}"
            exit 0
        fi

        rx_log_file "info" "Configuring PAM for ${dm}..."

        $SUDO_CMD cp "$pam_file" "$backup"
        # shellcheck disable=SC2064
        trap "$SUDO_CMD mv '$backup' '$pam_file'; rx_log_file 'error' 'PAM edit interrupted, rolled back'; exit 1" INT TERM EXIT

        $SUDO_CMD sed -i '/^auth.*include.*system-login/ a -auth       optional    pam_gnome_keyring.so' "$pam_file"
        $SUDO_CMD sed -i '/^password.*include.*system-login/ a -password   optional    pam_gnome_keyring.so    use_authtok' "$pam_file"
        $SUDO_CMD sed -i '/^session.*include.*system-login/ a -session    optional    pam_gnome_keyring.so    auto_start' "$pam_file"

        $SUDO_CMD rm -f "$backup"
        trap - INT TERM EXIT

        if grep -q "pam_gnome_keyring.so" "$pam_file" 2>/dev/null; then
            echo "OK|configured|${pam_file}"
            rx_log_file "success" "PAM configured: ${pam_file}"
        else
            echo "result=error|reason=write_failed"
            rx_log_file "error" "PAM configure failed: could not write to ${pam_file}"
            exit 1
        fi
        ;;

    *)
        echo "result=error|reason=unknown_flag|flag=$1"
        echo "Usage: $0 <--status|--lock|--unlock|--list|--store|--retrieve|--delete|--pam-status|--pam-configure>"
        exit 1
        ;;
esac
