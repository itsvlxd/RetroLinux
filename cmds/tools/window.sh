#!/bin/bash

source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/variable.sh"

cmd_wm() {
    local window_core="$RETRO_DIR/scripts/window_core.sh"
    local action="${1,,}"
    local arg1="$2"
    local arg2="$3"

    case "$action" in
        "fullscreen")
            hyprctl dispatch 'hl.dsp.window.fullscreen()'
            ;;

        "list")
            local raw_rules=$(bash "$window_core" --list)

            if [[ $raw_rules == "NONE" ]]; then
                rx_table_header "󰨇" "Window Rules"
                rx_table_simple "󰄪" "No custom rules defined" "$PINK"
                rx_table_separator
                rx_table_spacer
                return 0
            fi

            rx_table_header "󰨇" "Custom Window Rules"

            while IFS='|' read -r rtype rname; do
                [[ -z $rtype && -z $rname ]] && continue

                if [[ $rtype == "window" ]]; then
                    rx_table_simple "󰍱" "$rname" "$PINK"
                elif [[ $rtype == "layer" ]]; then
                    rx_table_simple "󰨎" "$rname" "$PINK"
                fi
            done <<<"$raw_rules"

            rx_table_separator
            rx_table_spacer
            ;;

        "add")
            local name="$arg1"
            local rule="$arg2"

            if [[ -z $name ]]; then
                _interactive_add_rule
                return $?
            fi

            [[ -z $rule ]] && rx_log "error" "Usage: retro window add <name> <rule>" && return 1

            local result=$(bash "$window_core" --add "$name" "$rule")

            if [[ $result == "ERROR:exists" ]]; then
                rx_log "error" "Rule '${PINK}$name${RESET}' already exists."
                return 1
            elif [[ $result == "APPLIED" ]]; then
                rx_log "success" "Window rule '${PINK}$name${RESET}' added and applied."
            else
                rx_log "error" "Failed to add window rule."
                return 1
            fi
            ;;

        "add-anon")
            local rule="$arg1"

            [[ -z $rule ]] && rx_log "error" "Usage: retro window add-anon <rule>" && return 1

            local result=$(bash "$window_core" --add-anon "window" "$rule")

            if [[ $result == "APPLIED" ]]; then
                rx_log "success" "Anonymous window rule added and applied."
            else
                rx_log "error" "Failed to add anonymous window rule."
                return 1
            fi
            ;;

        "add-layer")
            local name="$arg1"
            local rule="$arg2"

            [[ -z $name ]] && rx_log "error" "Usage: retro window add-layer <name> <rule>" && return 1
            [[ -z $rule ]] && rx_log "error" "Usage: retro window add-layer <name> <rule>" && return 1

            local result=$(bash "$window_core" --add-layer "$name" "$rule")

            if [[ $result == "ERROR:exists" ]]; then
                rx_log "error" "Layer rule '${PINK}$name${RESET}' already exists."
                return 1
            elif [[ $result == "APPLIED" ]]; then
                rx_log "success" "Layer rule '${PINK}$name${RESET}' added and applied."
            else
                rx_log "error" "Failed to add layer rule."
                return 1
            fi
            ;;

        "add-layer-anon")
            local rule="$arg1"

            [[ -z $rule ]] && rx_log "error" "Usage: retro window add-layer-anon <rule>" && return 1

            local result=$(bash "$window_core" --add-anon "layer" "$rule")

            if [[ $result == "APPLIED" ]]; then
                rx_log "success" "Anonymous layer rule added and applied."
            else
                rx_log "error" "Failed to add anonymous layer rule."
                return 1
            fi
            ;;

        "remove")
            local name="$arg1"

            [[ -z $name ]] && rx_log "error" "Usage: retro window remove <name>" && return 1

            local result=$(bash "$window_core" --remove "$name")

            if [[ $result == "ERROR:not_found" ]]; then
                rx_log "error" "Rule '${PINK}$name${RESET}' not found."
                return 1
            elif [[ $result == "APPLIED" ]]; then
                rx_log "success" "Rule '${PINK}$name${RESET}' removed and applied."
            else
                rx_log "error" "Failed to remove rule."
                return 1
            fi
            ;;

        "apply")
            bash "$window_core" --apply
            rx_log "success" "Window rules applied via eval."
            ;;

        "show")
            local name="$arg1"

            [[ -z $name ]] && rx_log "error" "Usage: retro window show <name>" && return 1

            local content=$(bash "$window_core" --get "$name")

            if [[ -z $content ]]; then
                rx_log "error" "Rule '${PINK}$name${RESET}' not found."
                return 1
            fi

            rx_table_header "󰨇" "Rule: $name"
            echo -e "${GRAY}$content${RESET}"
            rx_table_separator
            rx_table_spacer
            ;;

        "blacklist")
            local blacklist=$(get_var "RETRO_WINDOW_BLACKLIST")

            : ${blacklist:="(none)"}

            rx_table_header "󰞵" "Blacklisted Classes"
            rx_table_row "󰍱" "Apps:" "$blacklist" "$PINK" "30"
            rx_table_separator
            rx_table_spacer

            rx_log "info" 'Manage with: retro variable set RETRO_WINDOW_BLACKLIST "app1|app2"'
            ;;

        "edit")
            local rules_file="$RETRO_CONFIG/windowrules.lua"
            local editor="${EDITOR:-${RETRO_EDITOR:-nano}}"

            if [[ ! -f $rules_file ]]; then
                rx_log "error" "Rules file not found at $rules_file"
                return 1
            fi

            $editor "$rules_file"

            rx_log "info" "Applying window rules..."
            bash "$window_core" --apply
            rx_log "success" "Window rules updated and applied via eval."
            ;;

        *)
            rx_help_usage "retro window <command>"
            rx_help_commands "Window Commands"
            rx_help_cmd "fullscreen" "Toggle fullscreen on active window"
            rx_help_cmd "list" "Show all custom window/layer rules"
            rx_help_cmd "add <name> <rule>" "Add named windowrule"
            rx_help_cmd "add-anon <rule>" "Add anonymous windowrule"
            rx_help_cmd "add-layer <name> <rule>" "Add named layerrule"
            rx_help_cmd "add-layer-anon <rule>" "Add anonymous layerrule"
            rx_help_cmd "remove <name>" "Remove rule by name"
            rx_help_cmd "show <name>" "Show rule details"
            rx_help_cmd "apply" "Reload rules without adding"
            rx_help_cmd "edit" "Edit rules file in editor"
            rx_help_cmd "blacklist" "Show blacklisted app classes"
            rx_help_examples
            rx_help_example "retro window add" "Interactive rule builder"
            rx_help_example "retro window add zen-opacity 'match = { class = \"zen\" }, opacity = \"1.0 0.8\"'" "Named windowrule"
            rx_help_example "retro window add-anon 'no_blur = true, match = { class = \"firefox\" }'" "Anonymous windowrule"
            rx_help_example "retro window add-layer mylayer 'match = { namespace = \"mylayer\" }, blur = true'" "Named layerrule"
            rx_help_example "retro window add-layer-anon 'blur = true, match = { namespace = \"waybar\" }'" "Anonymous layerrule"
            rx_help_example "retro window edit" 'Edit rules in $EDITOR'
            rx_help_example "retro window fullscreen" "Toggle fullscreen"
            rx_help_spacer
            ;;
    esac
}

# ============================================================
# Interactive rule builder (retro window add with no args)
# ============================================================

_WINDOW_MATCH_FIELDS=(
    "class:str:class (regex)"
    "title:str:title (regex)"
    "initial_class:str:initial class (regex)"
    "initial_title:str:initial title (regex)"
    "tag:str:tag"
    "xwayland:bool:Match xwayland windows"
    "float:bool:Match floating windows"
    "fullscreen:bool:Match fullscreen windows"
    "pin:bool:Match pinned windows"
    "focus:bool:Match focused windows"
    "group:bool:Match grouped windows"
    "modal:bool:Match modal windows"
    "fullscreen_state_client:int:fullscreen_state_client (0-3)"
    "fullscreen_state_internal:int:fullscreen_state_internal (0-3)"
    "workspace:str:workspace"
    "content:enum(none,photo,video,game):content type"
    "xdg_tag:str:xdg_tag (regex)"
)

_LAYER_MATCH_FIELDS=(
    "namespace:str:namespace (regex)"
)

_STATIC_EFFECTS=(
    "float:bool:Make the window float"
    "tile:bool:Make the window tile"
    "fullscreen:bool:Make the window fullscreen"
    "maximize:bool:Maximize the window"
    "fullscreen_state:str:fullscreen_state (0/1/2/3)"
    "move:str:move (e.g. 50 50)"
    "size:str:size (e.g. 50% 50%)"
    "center:bool:Center the window"
    "pseudo:bool:Set pseudo-tiling"
    "monitor:str:Move to monitor"
    "workspace:str:Move to workspace"
    "no_initial_focus:bool:Don't focus on open"
    "pin:bool:Pin the window"
    "group:str:Group behavior (set/new/bar...)"
    "suppress_event:str:Suppress event"
    "content:enum(none,photo,video,game):Content type"
    "no_close_for:int:Delay close (ms)"
    "scrolling_width:float:Scrolling width"
)

_DYNAMIC_EFFECTS=(
    "persistent_size:bool:Persistent size"
    "no_max_size:bool:Disable auto-maximize"
    "stay_focused:bool:Stay focused on click"
    "animation:str:Animation style"
    "border_color:str:Border color (rgba)"
    "idle_inhibit:enum(always,fullscreen,never,focus):Idle inhibit mode"
    "opacity:str:Opacity (e.g. 1.0 0.8)"
    "tag:str:Tag name"
    "max_size:str:Max size (e.g. 1920 1080)"
    "min_size:str:Min size (e.g. 800 600)"
    "border_size:int:Border size (px)"
    "rounding:int:Corner rounding (px)"
    "rounding_power:float:Rounding power"
    "allows_input:bool:Allow input events"
    "dim_around:bool:Dim around window"
    "decorate:bool:Show decorations"
    "focus_on_activate:bool:Focus on activate"
    "keep_aspect_ratio:bool:Keep aspect ratio"
    "nearest_neighbor:bool:Nearest neighbor filtering"
    "no_anim:bool:Disable animations"
    "no_blur:bool:Disable blur"
    "no_dim:bool:Disable dimming"
    "no_focus:bool:Don't focus"
    "no_follow_mouse:bool:Don't follow mouse"
    "no_shadow:bool:Disable shadows"
    "no_shortcuts_inhibit:bool:Don't inhibit shortcuts"
    "no_screen_share:bool:Block screen sharing"
    "no_vrr:bool:Disable VRR"
    "no_auto_hdr:bool:Disable auto HDR"
    "opaque:bool:Force opaque"
    "force_rgbx:bool:Force RGBX format"
    "sync_fullscreen:bool:Sync fullscreen state"
    "immediate:bool:Immediate rendering"
    "xray:bool:Xray / click-through"
    "render_unfocused:bool:Render when unfocused"
    "scroll_mouse:float:Mouse scroll speed multiplier"
    "scroll_touchpad:float:Touchpad scroll speed multiplier"
    "confine_pointer:bool:Confine pointer"
)

_LAYER_EFFECTS=(
    "no_anim:bool:Disable animation"
    "blur:bool:Enable blur"
    "blur_popups:bool:Blur popups"
    "ignore_alpha:float:Ignore alpha threshold"
    "dim_around:bool:Dim around"
    "xray:bool:Xray / click-through"
    "animation:str:Animation style"
    "order:int:Z-order"
    "above_lock:int:Above lock screen level"
    "no_screen_share:bool:Block screen sharing"
)

_prompt_fields() {
    local current_content="$1"
    shift
    local fields=("$@")
    local result=""

    for field_def in "${fields[@]}"; do
        local key="${field_def%%:*}"
        local rest="${field_def#*:}"
        local type="${rest%%:*}"
        local hint="${rest#*:}"

        case "$type" in
            bool)
                local cur=$(echo "$current_content" | grep -c "^${key} = true$")
                if rx_yesno "${hint}?"; then
                    result+="${key} = true"$'\n'
                fi
                ;;
            str)
                local cur=$(echo "$current_content" | sed -n "s/^${key} = \"\(.*\)\"$/\1/p")
                local val=$(rx_input "${hint}:" "$cur")
                [[ -n $val ]] && result+="${key} = \"${val}\""$'\n'
                ;;
            int)
                local val=$(rx_input "${hint} (Enter to skip):" "")
                if [[ -n $val ]]; then
                    if [[ $val =~ ^-?[0-9]+$ ]]; then
                        local min="" max=""
                        [[ $key == "fullscreen_state_client" || $key == "fullscreen_state_internal" || $key == "order" || $key == "above_lock" ]] && min="0"
                        [[ $key == "fullscreen_state_client" || $key == "fullscreen_state_internal" ]] && max="3"
                        if [[ -n $min && $val -lt $min ]]; then
                            rx_log "warn" "Minimum is $min, skipping"
                        elif [[ -n $max && $val -gt $max ]]; then
                            rx_log "warn" "Maximum is $max, skipping"
                        else
                            result+="${key} = ${val}"$'\n'
                        fi
                    else
                        rx_log "warn" "Invalid number, skipping"
                    fi
                fi
                ;;
            float)
                local cur=$(echo "$current_content" | sed -n "s/^${key} = \([0-9.]*\)$/\1/p")
                local val=$(rx_input "${hint}:" "$cur")
                if [[ -n $val ]]; then
                    if [[ $val =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
                        result+="${key} = ${val}"$'\n'
                    else
                        rx_log "warn" "Invalid number, skipping"
                    fi
                fi
                ;;
            enum*)
                local opts="${type#enum(}"
                opts="${opts%)}"
                local cur=$(echo "$current_content" | sed -n "s/^${key} = \"\(.*\)\"$/\1/p")
                IFS=',' read -ra opt_arr <<< "$opts"
                local opt_list=("skip")
                opt_list+=("${opt_arr[@]}")
                local val=$(rx_menu "󰋩" "${hint}:" "${opt_list[@]}")
                [[ -n $val && $val != "skip" ]] && result+="${key} = \"${val}\""$'\n'
                ;;
        esac
    done

    printf "%s" "$result"
}

_preview_and_save() {
    local rule_type="$1"
    local rule_name="$2"
    local match_content="$3"
    local effect_content="$4"

    rx_table_header "󰨇" "Rule Preview"

    echo "hl.${rule_type}_rule({"
    if [[ -n $rule_name ]]; then
        echo "    name = \"${rule_name}\","
    fi
    if [[ -n $match_content ]]; then
        echo "    match = {"
        while IFS= read -r line; do
            [[ -n $line ]] && echo "        ${line},"
        done <<< "$match_content"
        echo "    },"
    fi
    if [[ -n $effect_content ]]; then
        while IFS= read -r line; do
            [[ -n $line ]] && echo "    ${line},"
        done <<< "$effect_content"
    fi
    echo "})"

    rx_table_separator

    if ! rx_confirm "Save this rule?" "Y"; then
        return 1
    fi

    local body=""
    if [[ -n $match_content ]]; then
        body+="match = {"$'\n'
        while IFS= read -r line; do
            [[ -n $line ]] && body+="    ${line},"$'\n'
        done <<< "$match_content"
        body+="},"$'\n'
    fi
    if [[ -n $effect_content ]]; then
        while IFS= read -r line; do
            [[ -n $line ]] && body+="${line},"$'\n'
        done <<< "$effect_content"
    fi

    local window_core="$RETRO_DIR/scripts/window_core.sh"
    local result
    if [[ -n $rule_name ]]; then
        result=$(bash "$window_core" --add "$rule_name" "$body")
    else
        result=$(bash "$window_core" --add-anon "$rule_type" "$body")
    fi

    if [[ $result == "ERROR:exists" ]]; then
        rx_log "error" "Rule '${PINK}$rule_name${RESET}' already exists."
        return 1
    elif [[ $result == "APPLIED" ]]; then
        rx_log "success" "Rule added and applied."
        return 0
    else
        rx_log "error" "Failed to add rule."
        return 1
    fi
}

_interactive_add_rule() {
    local rule_type
    local rule_name=""
    local match_content=""
    local effect_content=""

    rule_type=$(rx_menu "󰨇" "Select rule type:" "window" "layer")
    local type_display
    [[ $rule_type == "window" ]] && type_display="Window Rule" || type_display="Layer Rule"

    rule_name=$(rx_input "Rule name (Enter for anonymous):" "")

    while true; do
        local menu_options=("Match Properties")
        if [[ $rule_type == "window" ]]; then
            menu_options+=("Static Effects" "Dynamic Effects")
        else
            menu_options+=("Layer Effects")
        fi
        menu_options+=("Preview and Save" "Cancel")

        local choice
        choice=$(rx_menu "󰨇" "${type_display} — Select category:" "${menu_options[@]}")

        case "$choice" in
            "Match Properties")
                if [[ $rule_type == "window" ]]; then
                    match_content=$(_prompt_fields "$match_content" "${_WINDOW_MATCH_FIELDS[@]}")
                else
                    match_content=$(_prompt_fields "$match_content" "${_LAYER_MATCH_FIELDS[@]}")
                fi
                ;;
            "Static Effects")
                effect_content=$(_prompt_fields "$effect_content" "${_STATIC_EFFECTS[@]}")
                ;;
            "Dynamic Effects")
                effect_content=$(_prompt_fields "$effect_content" "${_DYNAMIC_EFFECTS[@]}")
                ;;
            "Layer Effects")
                effect_content=$(_prompt_fields "$effect_content" "${_LAYER_EFFECTS[@]}")
                ;;
            "Preview and Save")
                _preview_and_save "$rule_type" "$rule_name" "$match_content" "$effect_content"
                local ret=$?
                if [[ $ret -eq 0 ]]; then
                    return 0
                fi
                ;;
            "Cancel")
                rx_log "info" "Cancelled."
                return 0
                ;;
        esac
    done
}

register_command "TOOLS" "window" "Manage window rules and layer rules" "cmd_wm"
