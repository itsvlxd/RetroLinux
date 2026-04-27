# RetroLinux Coding Guidelines

A comprehensive guide to developing and extending the RetroLinux project.

---

## 1. Project Overview

RetroLinux is a full, standalone Arch-based Linux distribution built to provide bleeding-edge features with unbreakable stability. It was created as a response to the extremes in modern Linux - traditional desktop environments (GNOME, KDE, Cinnamon) are bloated, while most "minimal" Hyprland setups force users to duct-tape thousands of packages together.

The project provides the `retro` CLI - a unified command center to manage the entire system, from hardware drivers to audio, networking, power profiles, window sessions, and desktop environment configurations.

- **Philosophy**: Fast, fully customizable, modular OS that detects user tweaks and adapts
- **Target Users**: Developers (terminal-centric workflow), Gamers (zero background bloat), Ricers (customization without breaking the system)
- **Visual Style**: 80s/90s synthwave aesthetic - neon pinks, wireframes, retro-futurism
- **Architecture**: Source-based (no compilation), two-layer pattern (backend core + frontend UI)

---

## 2. Directory Structure

| Directory | Purpose |
|-----------|---------|
| `retro.sh` | Main entry point, command routing, global state |
| `lib/` | **Internal** core libraries (colors, logging, fs, driver detection, etc.) |
| `bin/` | **Installer** system (retroinstall, lib, setup) |
| `cmds/` | **User-facing** commands (tools, system, modules subdirectories) |
| `scripts/` | Backend automation scripts (core logic for each feature) |
| `scripts/events/` | Event hook modules (on_event_*) |
| `scripts/watchers/` | Background system monitors (start_watcher_*) |
| `modules/` | Desktop environment configurations (hyprland, ags, rofi, etc.) |
| `icons/` | Project icons and assets |
| `wallpapers/` | Wallpaper assets |

### Critical Rule

> **ALL lib files for anything should stay in `./lib/`** - this is the single source of truth for shared utilities.

---

## 3. File Naming Conventions

| Pattern | Location | Example |
|---------|----------|---------|
| Internal libraries | `lib/` | `colors.sh`, `log.sh`, `fs.sh`, `helpers.sh`, `battery.sh` |
| Installer libraries | `bin/lib/` | `display.sh`, `wifi.sh`, `errors.sh`, `gum.sh`, `disk.sh`, `handlers.sh`, `output.sh`, `debug.sh`, `setup.sh` |
| Backend core scripts | `scripts/` | `audio_core.sh`, `network_core.sh`, `driver_core.sh` |
| Event hooks | `scripts/events/` | `battery_events.sh`, `power_events.sh` |
| Watchers | `scripts/watchers/` | `battery.sh`, `bluetooth.sh`, `timers.sh` |
| Standalone scripts | `scripts/` | `system_update.sh` (UI, invoked from events) |
| Frontend commands | `cmds/tools/` | `audio.sh`, `network.sh`, `driver.sh` |
| System commands | `cmds/system/` | `load.sh`, `update.sh`, `setup.sh` |
| Module definitions | `modules/<name>/` | `modules/hyprland/`, `modules/ags/` |
| Helper modules | `cmds/tools/clipboard/` | Subdirectories for complex tools |
| Installer entry | `bin/` | `retroinstall` |

---

## 4. Code Style Rules

### General Rules

- **No comments** unless the logic is genuinely complex or non-obvious
- **No TODO comments** - either do it now or create an issue
- **Function naming**:
  - `cmd_` prefix for commands (e.g., `cmd_audio`, `cmd_network`)
  - `rx_` prefix for library functions (e.g., `rx_log`, `rx_get_json`)
  - `_` prefix for private helper functions (e.g., `_kernel_version_ge`)
- **Variable naming**: lowercase with underscores (e.g., `wifi_iface`, `action`)
- **Constants**: uppercase (e.g., `RETRO_DIR`, `RETRO_CACHE`)

### Shellcheck Compliance

All scripts must pass shellcheck before being merged. Run `shellcheck scripts/*.sh cmds/**/*.sh lib/*.sh bin/**/*.sh` locally to check.

Exceptions can be added inline for intentional cases:
```bash
# shellcheck disable=SC2086
local result=$myvar1$myvar2  # intentional concatenation
```

### Critical Rule: Never Duplicate Functions

> Before creating a new function, check `./lib/` or `./bin/lib/` first. If a function already exists that does what you need, use it.

If you need a utility that doesn't exist, add it to the appropriate lib file in `./lib/` or `./bin/lib/`, not in your command file.

### Example

```bash
# BAD - creating a new function that duplicates existing logic
my_get_json() {
    local file="$1"
    local key="$2"
    jq -r ".$key // empty" "$file"
}

# GOOD - using existing library function
local value=$(rx_get_json "$file" "$key" "default")
```

---

## 5. The Two-Layer Tool Pattern (MOST IMPORTANT)

Every tool in this project follows a strict two-layer architecture:

```
┌─────────────────────────────────────────────────────────────┐
│  FRONTEND (User Interface)                                  │
│  File: cmds/tools/name.sh                                   │
│  - rx_log for all output                                    │
│  - Prompts and user interaction                             │
│  - Table formatting with printf                             │
│  - Handles -y/--yes skip flag                               │
└─────────────────────────────────────────────────────────────┘
                               │
                               ▼ calls core script
                               ▼ parses output
                               ▼ formats for user
┌─────────────────────────────────────────────────────────────┐
│  BACKEND (Logic Layer)                                      │
│  File: scripts/name_core.sh                                 │
│  - Pure logic, NO rx_log                                    │
│  - NO user-facing echo                                      │
│  - CLI flags: --status, --get, --set, --scan, etc.          │
│  - Machine-parseable output (pipe-delimited)                │
└─────────────────────────────────────────────────────────────┘
```

### Why This Pattern?

- **Separation of concerns**: Core scripts can be used by other scripts without UI overhead
- **Testability**: Backend logic can be tested independently
- **Consistency**: Every tool follows the same pattern, making the codebase predictable

### Example: Adding a New Tool

```
1. Create scripts/newtool_core.sh   (backend - logic only)
2. Create cmds/tools/newtool.sh     (frontend - UI and rx_log)
3. Test with: retro newtool status
```

### The lib/ Directory

The `lib/` directory is the **single source of truth** for all shared utilities:
- **DO** put helper functions, color definitions, logging, battery helpers, etc. in `lib/`
- **DO NOT** create subdirectories like `scripts/lib/` - all libs go flat in `lib/`
- **DO** source from `lib/` in both scripts and commands
- **NEVER** duplicate functions - check `lib/` before creating new helpers

Example:
```bash
# In any script or command:
source "$RETRO_DIR/lib/helpers.sh"
source "$RETRO_DIR/lib/battery.sh"
source "$RETRO_DIR/lib/colors.sh"
```

---

## 6. Color and Logging System

### Available Color Variables

All colors are defined in `lib/colors.sh`:

| Variable | Purpose |
|----------|---------|
| `$PINK` | Primary accent (headings, icons, important values) |
| `$GRAY` | Secondary text (descriptions, labels) |
| `$MUTE` | Subtle text (separators, hints) |
| `$SUCCESS` | Success messages (green-ish) |
| `$WARNING` | Warning messages (yellow-ish) |
| `$ERROR` | Error messages (red-ish) |
| `$RESET` | Reset sequence `\033[0m` |

### Using rx_log

All user-facing output should go through `rx_log` (defined in `lib/log.sh`):

```bash
rx_log "success" "Operation completed"
rx_log "info" "Starting process..."
rx_log "warn" "Something might be wrong"
rx_log "error" "Operation failed"
```

**Important**: When using `rx_log "error"`, always `return 1` after it:

```bash
[[ -z $value ]] && rx_log "error" "Value is required" && return 1
```

### Direct Echo Patterns

For tables and formatted output, use direct `echo`/`printf` with color variables:

```bash
echo -e "${PINK}Header${RESET}"
printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "command" "description"
```

---

## 7. Design Rules and Examples

### Status Table Pattern (Use Centralized Functions)

The standard pattern for displaying status information - use centralized functions from `lib/help.sh`:

```bash
rx_table_header "󰑊" "Status Title"
rx_table_row "󰄾" "Label:" "Value" "$PINK" "36"
rx_table_row_gray "󰄾" "Description:" "gray value"
rx_table_separator
rx_table_spacer
```

**Real example** (from `cmds/tools/audio.sh`):

```bash
rx_table_header "󰑊" "Audio Status"
rx_table_row "󰿅" "PipeWire:" "$pw_ver" "$GRAY" "14"
rx_table_row "󰛫" "WirePlumber:" "$wp_ver" "$GRAY" "14"
rx_table_separator
rx_table_row "󰝥" "Volume:" "${sink_vol}%" "$PINK" "14"
rx_table_row_gray "󰈐" "Output:" "${sink_name:0:35}" "14"
rx_table_separator
rx_table_spacer
```

**Legacy pattern (AVOID - use centralized functions instead):**

```bash
echo -e "\n ${PINK}󰑊 Audio Status${RESET}"
echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"
printf " ${PINK}󰿅${RESET} %-14s ${GRAY}%s${RESET}\n" "PipeWire:" "$pw_ver"
# ... etc
```

### Help Message Pattern

For displaying command usage and sub-commands, use the centralized help functions from `lib/help.sh`:

```bash
rx_help_usage "retro tool <command>"
rx_help_commands "Subcommands"
rx_help_cmd 20 "status" "Show current status"
rx_help_cmd 20 "set <value>" "Set a value"
rx_help_cmd 20 "action" "Perform action"
rx_help_examples
rx_help_example 30 "retro tool status" "Show current status"
```

**Available Help Functions** (in `lib/help.sh`):

| Function | Purpose |
|----------|---------|
| `rx_help_usage "usage text"` | Shows usage line |
| `rx_help_commands "title"` | Shows "Commands:" header |
| `rx_help_cmd width "cmd" "desc"` | Prints a command line |
| `rx_help_examples` | Shows "Examples:" header |
| `rx_help_example width "cmd" "desc"` | Prints an example line |
| `rx_help_header "icon" "title"` | Shows section header with icon |
| `rx_help_separator` | Prints separator line |
| `rx_help_footer` | Prints footer with separator |

### Table and Status Display Functions

For displaying status information and tables, use the centralized table functions from `lib/help.sh`:

```bash
rx_table_header "󰑊" "Status Title"
rx_table_row "󰄾" "Label:" "Value" "$PINK" "36"
rx_table_row_gray "󰄾" "Gray:" "Value" "36"
rx_table_separator
rx_table_spacer
```

**Available Table Functions** (in `lib/help.sh`):

| Function | Purpose |
|----------|---------|
| `rx_table_separator` | Prints ───────────────────────────── |
| `rx_table_header "icon" "title"` | 󰑊 Title + separator |
| `rx_table_row "icon" "label" "value" [color] [width]` | Icon + key-value row |
| `rx_table_row_gray "icon" "label" "value" [width]` | Gray colored row |
| `rx_table_key_value "label" "value" [color]` | 󰄾 label + value |
| `rx_table_simple "icon" "value" [color]` | Just icon + text |
| `rx_table_spacer` | Empty row for spacing |
| `rx_table_list_header "icon" "c1" "c2" "c3"` | Table header row |
| `rx_table_list_row "icon" "c1" "c2" "c3" [colors]` | Multi-color table row |
| `rx_table_list_single "icon" "text" [color]` | Single column row |

**Confirmation Functions**:

| Function | Purpose |
|----------|---------|
| `rx_confirm "message"` | Yes/no prompt, returns 0 for yes |
| `rx_yesno "message"` | Yes/no with SKIP_PROMPT support |

### Section Separator Pattern

Use the icon + line combination for visual separation:

```bash
echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"
```

The line width should be:
- 34 chars for simpler tables (36 - 2 for padding)
- 50+ chars for complex tables

### Separator Spacer Rule

After the final `rx_table_separator` or `rx_help_separator` in any display block, you MUST add a spacer:

✅ CORRECT:
```bash
rx_table_separator
rx_table_spacer
```

❌ INCORRECT:
```bash
rx_table_separator
# Missing spacer - looks cramped!
```

This applies to:
- `rx_table_separator` → follow with `rx_table_spacer`
- `rx_help_separator` → follow with `rx_help_spacer`

### Icon System

Icons are Nerd Font glyphs. Common icons by category:

| Category | Icons |
|----------|-------|
| System | 󰒓 󰄾 󰇝 󰒋 |
| Tools | 󰑊 󰢮 󰓅 󰤨 |
| Status | 󰁹 󰂂 󰂁 󰝟 󰝡 |
| Actions | 󰇚 󰈚 󱇪 󱂷 |
| Hardware | 󰻠 󰥲 󰂯 |

---

## 8. Command System

### register_command

All commands must register themselves using `register_command`:

```bash
register_command "GROUP" "alias1|alias2" "Description" "cmd_function"
```

- **GROUP**: `SYSTEM`, `MODULES`, or `TOOLS`
- **alias1|alias2**: Primary alias and optional alternatives (pipe-separated)
- **Description**: Brief description shown in help
- **cmd_function**: The function to call

**Example** (from `cmds/tools/audio.sh`):

```bash
register_command "TOOLS" "audio|a" "Manage audio settings and EasyEffects" "cmd_audio"
```

### Command Function Pattern

```bash
cmd_toolname() {
    local action="${1,,}"  # lowercase for consistency
    local subarg1="$2"
    local subarg2="$3"

    case "$action" in
        status)
            # Show status
            ;;
        action1)
            [[ -z $subarg1 ]] && rx_log "error" "Usage: ..." && return 1
            # Do action1
            ;;
        help|"")
            rx_log "info" "Usage: retro toolname <command>"
            # Show help
            ;;
        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}
```

### Sub-Command Structure

For complex tools with nested commands (like `network wifi on`):

```bash
case "$action" in
    wifi)
        local wifi_action="${subarg1,,}"
        case "$wifi_action" in
            on)    bash "$RETRO_DIR/scripts/network_core.sh" --wifi-on "$iface" ;;
            off)   bash "$RETRO_DIR/scripts/network_core.sh" --wifi-off "$iface" ;;
            list)  bash "$RETRO_DIR/scripts/network_core.sh" --wifi-list "$iface" ;;
            *)     # Show wifi help ;;
        esac
        ;;
    ethernet)
        # Handle ethernet
        ;;
esac
```

---

## 9. Backend Core Scripts (scripts/*_core.sh)

### CLI Flags Pattern

Core scripts must accept CLI flags and produce machine-parseable output:

```bash
# scripts/example_core.sh
case "$1" in
    --status)
        # Output: key1=value1|key2=value2
        ;;
    --get-value)
        # Output: the value only
        ;;
    --set-value)
        # No output, just do the action
        ;;
    --scan)
        # Output: type|vendor|model|driver|packages
        # One line per device
        ;;
esac
```

### Output Formats

**Key-Value (for simple gets)**:
```bash
echo "sink=alsa_output.pci-0000_00_1f.3.analog-stereo"
echo "volume=75"
```

**Pipe-delimited (for lists)**:
```bash
echo "GPU|nvidia|NVIDIA GeForce RTX 3080|nvidia|driver-nvidia"
echo "CPU|intel|Intel Core i7-10870H|intel-ucode"
echo "NET|wifi|Realtek RTL8852AE|rtl88x2bu"
```

**Raw Data (for lists with multiple fields)**:
```bash
# For scanning: type|vendor|model|driver|packages|missing
echo "GPU|nvidia|NVIDIA GeForce RTX 3080|nvidia-open-dkms|nvidia-utils nvidia-settings lib32-nvidia-utils|"
```

### Critical Rules for Core Scripts

1. **NO rx_log** - Core scripts don't log
2. **NO user-facing echo** - No messages to stdout meant for users
3. **Only raw data output** - What the frontend parses
4. **Exit codes** - 0 for success, 1 for failure (frontend handles messaging)

---

## 10. Frontend Command Scripts (cmds/tools/*.sh)

### Calling Core Scripts

```bash
local core_script="$RETRO_DIR/scripts/name_core.sh"
local raw_output
raw_output=$(bash "$core_script" --status)
[[ -z $raw_output ]] && rx_log "error" "Failed to get status" && return 1
```

### Parsing Core Output

```bash
while IFS='|' read -r type vendor model driver packages; do
    case "$type" in
        GPU)
            gpu_name="$model"
            gpu_driver="$driver"
            ;;
        CPU)
            cpu_name="$model"
            ;;
    esac
done <<<"$raw_output"
```

### Handling User Prompts

```bash
if [[ $SKIP_PROMPT == "false" ]]; then
    rx_log "info" "Continue? ${PINK}[y/N]${RESET}: "
    read -r confirm
    [[ ! $confirm =~ ^[Yy]$ ]] && rx_log "info" "Cancelled." && return 0
fi
```

The `-y/--yes` flag sets `SKIP_PROMPT=true` globally (handled in `retro.sh`).

### Error Handling Pattern

```bash
# Validate input
[[ -z $value ]] && rx_log "error" "Usage: retro tool action <value>" && return 1

# Check command success
bash "$core_script" --do-something >/dev/null
if [[ $? -ne 0 ]]; then
    rx_log "error" "Action failed"
    return 1
fi

rx_log "success" "Action completed"
```

---

## 11. Module System

### Module Structure

```
modules/<name>/
├── install.sh      # Primary installation logic (required for custom install)
├── packages.sh    # List of packages to install (one per line)
├── targets.json   # Installation mapping
├── pre.sh         # Pre-installation hook (optional)
├── post.sh        # Post-installation hook (optional)
└── files/         # Configuration files to link/copy
```

### targets.json Format

```json
{
    "config": "files",
    "install": "~/.config/name"
}
```

- `config`: Relative path in module containing config files
- `install`: Target path in user's home

### Module Commands

- `retro module install <name>` - Link config files and install packages
- `retro module uninstall <name>` - Remove links and optionally packages
- `retro module mirror <name>` - Copy files instead of symlink
- `retro module pull <name>` - Pull system changes back to repo

---

## 12. Variable System

### Storage

Variables are stored in `$RETRO_CACHE/variables.sh` (typically `~/.cache/retro/variables.sh`).

### Usage

```bash
# Get a variable (wraps variable_core.sh)
get_var "KEY"
set_var "KEY" "value"

# Direct call to variable_core.sh
bash "$RETRO_DIR/scripts/variable_core.sh" --get "KEY"
bash "$RETRO_DIR/scripts/variable_core.sh" --set "KEY" "value"
bash "$RETRO_DIR/scripts/variable_core.sh" --toggle "KEY"
bash "$RETRO_DIR/scripts/variable_core.sh" --list
```

### Common Variables

| Variable | Purpose |
|----------|---------|
| `PKG_HELPER` | AUR helper (yay/paru) |
| `RETRO_SESSION_AUTOLOAD` | Auto-restore window session on login |
| `RETRO_CUSTOM_LOAD` | Custom startup tasks |
| `RETRO_OPACITY` | Global opacity multiplier |

---

## 13. Dependency Management

### check_dep Function

Use `check_dep` from `lib/helpers.sh` to prompt for missing dependencies:

```bash
check_dep "lspci" "pciutils" || return 1
check_dep "jq" "jq" || return 1
```

### Manual Package Check

```bash
rx_is_pkg_installed() {
    pacman -Qq "$1" >/dev/null 2>&1
}
```

---

## 14. Event System (Background Daemon)

### Overview

The **Event System** is a background daemon that continuously monitors system state and fires events when conditions change. It uses a **Plugin Architecture** where `event_core.sh` is a "dumb engine" that dynamically loads watchers from `scripts/watchers/`.

### File Structure

| File | Purpose |
|------|---------|
| `scripts/event_core.sh` | Dumb engine - loads watchers, dispatches events |
| `scripts/events/*.sh` | User event hooks (on_event_*) |
| `scripts/watchers/*.sh` | System monitors (start_watcher_*) |
| `cmds/tools/event.sh` | Frontend command to manage the daemon |

### The "Dumb Engine" Pattern

The engine (`event_core.sh`) knows nothing about hardware, USB, or Bluetooth. It just:

1. Sources all watchers from `scripts/watchers/`
2. Uses `declare -F | grep "^start_watcher_"` to find watchers dynamically
3. Spawns each watcher as a background process
4. Dispatches events when watchers call `broadcast_event`

```bash
# scripts/event_core.sh (simplified)
source "$RETRO_DIR/lib/battery.sh"
source "$RETRO_DIR/lib/helpers.sh"

EVENT_DIR="$RETRO_DIR/scripts/events"
WATCHER_DIR="$RETRO_DIR/scripts/watchers"

broadcast_event() {
    local event_name="$1"
    shift
    for hook_file in "$EVENT_DIR"/*.sh; do
        [[ -f $hook_file ]] || continue
        (
            source "$hook_file"
            if declare -f "$event_name" >/dev/null 2>&1; then
                "$event_name" "$@"
            fi
        )
    done
}

for watcher_file in "$WATCHER_DIR"/*.sh; do
    [[ -f $watcher_file ]] && source "$watcher_file"
done

run_event_loop() {
    broadcast_event "on_event_loop_start"
    local watchers=$(declare -F | awk '{print $3}' | grep "^start_watcher_")
    for watcher in $watchers; do
        "$watcher" &
        WATCHER_PIDS+=($!)
    done
    trap 'kill "${WATCHER_PIDS[@]}" 2>/dev/null; exit' INT TERM
    wait
}
```

### How It Works

1. **Engine** (`event_core.sh --loop`):
   - Sources all watchers from `scripts/watchers/`
   - Dynamically finds functions starting with `start_watcher_`
   - Spawns each as background process with its own PID
   - Crash isolation: one watcher crashing doesn't kill others

2. **Watchers** (`scripts/watchers/*.sh`):
   - Define function `start_watcher_<name>()`
   - Run infinite loop with sleep intervals
   - Call `broadcast_event "on_event_name"` to fire events

3. **Event Hooks** (`scripts/events/*.sh`):
   - Define functions like `on_event_name()`
   - Source automatically when event fires
   - Run in subshell - don't block watchers

4. **Event Commands**:
   - `retro event start` - Start the daemon in background
   - `retro event stop` - Stop the running daemon
   - `retro event status` - Show if daemon is running
   - `retro event trigger <name>` - Manually fire an event
   - `retro event list` - Show all available watchers

### Available Watchers (Examples)

| Watcher | File | Purpose |
|--------|------|---------|
| Battery Monitor | `watchers/battery.sh` | Battery state, saver mode, usage |
| Bluetooth Monitor | `watchers/bluetooth.sh` | Device connections, pairing |
| Timers | `watchers/timers.sh` | Package/Retro update checks |

### Available Events

| Event | Trigger |
|-------|---------|
| `on_event_loop_start` | Daemon starts |
| `on_power_disconnect` | AC power removed |
| `on_power_connect` | AC power connected |
| `on_battery_low` | Battery below threshold |
| `on_battery_critical` | Battery critically low |
| `on_battery_saver_enabled` | Saver mode activated |
| `on_battery_saver_disabled` | Saver mode deactivated |
| `on_power_profile_changed` | Power profile switched |
| `on_battery_usage_high` | High-usage app detected |
| `on_usb_connected` | USB device inserted |
| `on_usb_disconnected` | USB device removed |
| `on_pkg_updates_available` | System updates available |
| `on_retro_update_available` | RetroLinux update available |
| `on_bluetooth_pairing_request` | New BT device pairing |
| `on_bluetooth_connected` | BT device connected |
| `on_bluetooth_disconnected` | BT device disconnected |
| `on_slideshow_tick` | Wallpaper slideshow tick |

### Creating a New Watcher

1. Create a new file in `scripts/watchers/`:
```bash
#!/bin/bash
# scripts/watchers/mytemp.sh

check_temp_state() {
    local temp
    temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
    local temp_c=$((temp / 1000))

    if [[ $temp_c -ge 80 ]]; then
        broadcast_event "on_temperature_critical" "$temp_c"
    elif [[ $temp_c -ge 70 ]]; then
        broadcast_event "on_temperature_high" "$temp_c"
    fi
}

start_watcher_mytemp() {
    while true; do
        check_temp_state
        sleep 30
    done
}
```

2. The engine automatically finds and runs it:
   - Function must start with `start_watcher_`
   - Should contain infinite `while true` loop
   - Must have `sleep` to avoid blocking

### Variable Persistence in Watchers

Watchers run in separate processes - they don't share variables. Use `get_var`/`set_var`:

```bash
start_watcher_battery() {
    last_bat_saver=$(get_var "BAT_SAVER_ACTIVE" "false")
    last_notified_level=0

    while true; do
        if [[ $current_cap -le 20 && $last_notified_level -ne 20 ]]; then
            broadcast_event "on_battery_low" "20"
            set_var "BAT_LAST_NOTIFIED" "20"
        fi
        sleep 15
    done
}
```

### Crash Isolation

Each watcher runs as independent background process. If `timers.sh` crashes:
- `battery.sh` keeps monitoring
- `bluetooth.sh` keeps detecting devices
- The daemon stays alive

```bash
# In event_core.sh
for watcher in $watchers; do
    "$watcher" &
    WATCHER_PIDS+=($!)
done

# Clean shutdown on signal
trap 'kill "${WATCHER_PIDS[@]}" 2>/dev/null; exit' INT TERM
```

### Adding a New Event Handler

1. Create or edit a file in `scripts/events/`:
```bash
# scripts/events/my_hooks.sh
source "$RETRO_DIR/lib/helpers.sh"

on_power_disconnect() {
    local capacity="$1"
    rx_log "info" "Power disconnected at ${capacity}%"
}

on_battery_low() {
    local cap="$1"
    notify-send "Battery Low" "Only ${cap}% remaining"
}
```

2. The function name determines which event it handles:
   - `on_power_disconnect` → fires when AC power removed
   - `on_battery_low` → fires when battery below threshold

### Important Notes

- Watchers run in **background processes** - crash isolation guaranteed
- Event hooks run in **subshells** - they don't block watchers
- Use `get_var`/`set_var` for persistent state across restarts
- Always include `sleep` in watcher loops (blocks at 0% CPU)
- The daemon auto-starts on login (via `retro load`)

---

## 15. Walkthrough: Adding a New Tool

Now that you know ALL the rules, let's add a hypothetical `temperature` tool:

### Step 1: Create the Backend (scripts/temperature_core.sh)

```bash
#!/bin/bash

# scripts/temperature_core.sh - Backend logic only

CORE_SCRIPT="$0"

case "$1" in
    --status)
        # Output: zone|temp|critical
        for zone in /sys/class/thermal/thermal_zone*; do
            [[ -f "$zone/temp" ]] || continue
            local temp=$(cat "$zone/temp")
            local temp_c=$((temp / 1000))
            local type=$(cat "$zone/type" 2>/dev/null || echo "unknown")
            local critical=$(cat "$zone/trip_point_0_temp" 2>/dev/null || echo "0")
            echo "thermal|$type|${temp_c}C|${critical}"
        done
        ;;
    --current)
        local temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        echo $((temp / 1000))
        ;;
esac
```

### Step 2: Create the Frontend (cmds/tools/temperature.sh)

```bash
#!/bin/bash

cmd_temperature() {
    local action="${1,,}"
    local core="$RETRO_DIR/scripts/temperature_core.sh"

    case "$action" in
        status)
            local data
            data=$(bash "$core" --status)
            [[ -z $data ]] && rx_log "error" "Failed to read thermal data" && return 1

            rx_table_header "󰈐" "Temperature Status"
            while IFS='|' read -r zone type temp critical; do
                local zone_label="${zone:0:35}"
                rx_table_row "󰈐" "$zone_label" "$temp" "$PINK" "36"
            done <<<"$data"
            rx_table_separator
            rx_table_spacer
            ;;
        current)
            bash "$core" --current
            ;;
        help|"")
            rx_help_usage "retro temperature <command>"
            rx_help_commands "Available commands"
            rx_help_cmd 20 "status" "Show all thermal zones"
            rx_help_cmd 20 "current" "Show current CPU temp"
            rx_help_examples
            rx_help_example 30 "retro temperature status" "Show all thermal zones"
            rx_help_spacer
            ;;
        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}

register_command "TOOLS" "temperature|temp" "Monitor system temperatures" "cmd_temperature"
```

### Step 3: Test

```bash
./retro.sh temperature status
./retro.sh temperature help
```

---

## 16. Best Practices and Gotchas

### Do

- Use `rx_log` for all user-facing messages in frontend scripts
- Keep core scripts purely functional (no side effects, no user output)
- Use pipe-delimited output for structured data
- Handle `-y/--yes` flag by checking `$SKIP_PROMPT`
- Use icons consistently from the Nerd Font set
- Check existing lib functions before writing new ones

### Don't

- Don't put `rx_log` in core scripts
- Don't use `echo` for user messages in core scripts
- Don't duplicate existing library functions
- Don't skip the two-layer pattern (even for simple tools)
- Don't use TODO comments - either do it or don't
- Don't hardcode paths - use `$RETRO_DIR` and `$HOME`

### Common Gotchas

1. **Subshell variable scope**: When using `while IFS='|' read`, remember it's in a subshell. Use process substitution or capture output properly.

2. **Lowercase actions**: Always use `${action,,}` to lowercase user input for consistent case handling.

3. **Array handling**: Use `local arr=()` for local arrays to avoid polluting global state.

4. **Exit codes**: Core scripts should return 0 on success, 1 for failure. Frontend handles the messaging.

5. **Icon padding**: Always use `${PINK}icon${RESET}` pattern, never plain icon alone.

### Ctrl+C Trap (Graceful Exits)

If your script does destructive actions (moving files, installing packages, creating symlinks), use trap to handle user interruptions:

```bash
cleanup() {
    rm -f "$temp_file"
    # restore any backups
}
trap cleanup INT TERM

# ... your destructive code ...

trap - INT TERM  # clear trap on success
```

Failing to handle interrupts can leave the system in a broken state (half-installed packages, incomplete symlinks, broken database entries).

---

## 17. Installer System (bin/)

The Installer is a self-contained system that runs during initial system setup. It follows a **modular setup flow architecture**:

```
┌─────────────────────────────────────────────────────────────┐
│  retroinstall (parent process)                              │
│  - Holds all state variables                               │
│  - Exports RETRO_STATE="/tmp/retroinstall_state"           │
│  - Calls rx_load_state before each step                    │
│  - Calls rx_load_state after each step                      │
└─────────────────────────────────────────────────────────────┘
                               │
                               │ execs setup script
                               ▼
┌─────────────────────────────────────────────────────────────┐
│  setup/*.sh (child process)                                 │
│  - Sources lib/setup_lib.sh to load utilities               │
│  - Collects user input, modifies variables                  │
│  - Calls rx_save_state to write updated values              │
│  - Exits with success/failure code                         │
└─────────────────────────────────────────────────────────────┘
                               │
                               ▼ sources
┌─────────────────────────────────────────────────────────────┐
│  UTILITIES (bin/lib/*)                                     │
│  - Pure functions, no orchestration                         │
│  - display, errors, gum, wifi, locale, timezone, disk,      │
│    handlers, output, debug, progress, qr, setup_lib, setup  │
└─────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
bin/
├── retroinstall              # Main entry point
├── logo.txt                  # ASCII art logo (5-line, 74 chars wide)
├── lib/                      # Low-level utilities (14 files)
│   ├── debug.sh             # rx_debug conditional output
│   ├── disk.sh              # rx_get_disk_info, rx_get_available_disks, rx_write_configuration
│   ├── display.sh           # Terminal sizing, logo rendering, GUM_CONFIRM_STYLE, GUM_FILTER_STYLE
│   ├── errors.sh            # rx_retry_or_exit, rx_step_error, rx_abort
│   ├── gum.sh               # rx_notice (gum spin wrapper)
│   ├── handlers.sh          # rx_setup_traps, rx_catch_errors, rx_save_state, rx_load_state
│   ├── locale.sh            # Keyboard/layout names, LOCALE_LANG_NAMES, KEYBOARD_LAYOUT_NAMES arrays
│   ├── output.sh            # rx_start_log_output, rx_start_install_log, rx_run_logged
│   ├── progress.sh          # rx_step progress tracking [n/total]
│   ├── qr.sh                # rx_generate_error_qr, rx_gather_system_info
│   ├── setup_lib.sh        # Shared sourcing hub, rx_setup_fail
│   ├── setup.sh            # rx_chrootable_systemctl_enable wrapper
│   ├── timezone.sh          # rx_list_timezones, rx_get_current_timezone
│   └── wifi.sh              # WiFi setup functions (iwctl based), rx_check_internet, rx_select_wifi_network
└── setup/                    # Modular setup step scripts (14 scripts, unnumbered)
    ├── bluetooth.sh         # Bluetooth service enable toggle
    ├── config.sh           # Write user_configuration.json and user_credentials.json
    ├── disk.sh             # Disk selection, wipe confirmation, returns 42 on go-back
    ├── hostname.sh          # Machine hostname
    ├── kernel.sh            # Kernel selection (linux, linux-lts, linux-zen, linux-hardened)
    ├── keyboard.sh          # Keyboard layout selection (hardcoded list of 54 layouts)
    ├── locale.sh            # System language selection (filter from LOCALE_LANG_NAMES)
    ├── luks.sh              # LUKS encryption enable/password/iteration time
    ├── mirrors.sh           # Mirror region and custom mirror URL
    ├── network.sh           # Network connectivity check and WiFi/Ethernet setup
    ├── print.sh             # CUPS printing service enable toggle
    ├── root.sh              # Root password
    ├── timezone.sh          # Timezone selection via timedatectl
    └── user.sh              # Username, user password, sudo access
```

### SETUP_SCRIPTS Array (exact order)

From `retroinstall` lines 28-43:

```bash
SETUP_SCRIPTS=(
    "user.sh"        # index 0
    "root.sh"        # index 1
    "hostname.sh"    # index 2
    "keyboard.sh"    # index 3
    "locale.sh"      # index 4
    "mirrors.sh"     # index 5
    "timezone.sh"    # index 6
    "disk.sh"        # index 7
    "luks.sh"        # index 8
    "kernel.sh"      # index 9
    "bluetooth.sh"   # index 10
    "print.sh"       # index 11
    "network.sh"     # index 12
    "config.sh"      # index 13
)
```

### Setup Flow

**rx_run_step function** (retroinstall lines 89-109):

```bash
rx_run_step() {
    local script="$1"
    local step_index=$2

    # Skip if step_index <= RX_SKIP_STEP
    if [[ -n "$RX_SKIP_STEP" && $step_index -le $RX_SKIP_STEP ]]; then
        return 0
    fi

    rx_clear_logo
    rx_load_state                    # Reload state before running step
    /opt/retrolinux/bin/setup/"$script"  # Execute setup script
    local exit_code=$?
    rx_load_state                    # Reload state after step

    # Exit code 42 = go back (skip to step 6 = timezone, then restart)
    if [[ $exit_code -eq 42 ]]; then
        RX_SKIP_STEP=6
        rx_save_state
        exec /opt/retrolinux/bin/retroinstall  # Restart installer
    elif [[ $exit_code -ne 0 ]]; then
        rx_show_error_and_qr "$exit_code"
    fi
}
```

**Main loop** (retroinstall lines 111-113):
```bash
for i in "${!SETUP_SCRIPTS[@]}"; do
    rx_run_step "${SETUP_SCRIPTS[$i]}" "$i"
done
```

**Return codes:**
- `0` = success, proceed to next step
- `42` = go back to disk selection (disk.sh returns 42 when user declines wipe confirmation)
- `non-zero, not 42` = error, show error QR and offer retry

**Go-back mechanism:**
- `disk.sh` returns exit code `42` when user declines disk wipe confirmation
- On `42`: Sets `RX_SKIP_STEP=6`, saves state, restarts installer via `exec`
- The installer loops, skipping steps 0-6 (user through timezone), resumes from disk.sh (index 7)

### State Management (CRITICAL)

Setup scripts run as subprocesses of `retroinstall`. Because subprocesses cannot share variables with their parent, all state is persisted to `/tmp/retroinstall_state` (exported as `$RETRO_STATE`).

**State Functions** (defined in `bin/lib/handlers.sh`):

| Function | Purpose |
|----------|---------|
| `rx_save_state` | Writes all state variables to `$RETRO_STATE` |
| `rx_load_state` | Sources `$RETRO_STATE` if it exists |

**All state variables saved to `$RETRO_STATE`:**
```bash
KEYBOARD              # Keyboard layout code (e.g., "us")
SYS_LANG              # System language (e.g., "en_US.UTF-8")
SYS_ENC               # System encoding (e.g., "UTF-8")
USER_NAME             # Username
USER_PASSWORD         # Plain text user password
USER_PASSWORD_HASH    # OpenSSL passwd hash of user password (openssl passwd -6)
USER_HOSTNAME         # hostname
USER_TIMEZONE         # timezone (e.g., "America/New_York")
DISK_SELECTED         # Selected disk device (e.g., "/dev/sda")
NETWORK_TYPE          # "WiFi" or "Ethernet"
WIFI_SSID             # WiFi SSID if connected via WiFi
ROOT_PASSWORD         # Plain text root password
ROOT_PASSWORD_HASH    # OpenSSL passwd hash of root password
USER_SUDO             # "true" or "false"
LUKS_ENABLED          # "true" or "false"
LUKS_PASSWORD         # Plain text LUKS encryption password
LUKS_ITER_TIME        # LUKS iteration time in ms (e.g., 2000)
KERNEL_SELECTION      # Kernel package (e.g., "linux", "linux-lts", "linux-zen", "linux-hardened")
BLUETOOTH_ENABLED     # "true" or "false"
PRINT_SERVICE_ENABLED # "true" or "false"
CUSTOM_MIRRORS        # Custom mirror URL
MIRROR_REGIONS        # Mirror regions (space-separated)
RX_CURRENT_STEP       # Current step number (saved but not actively used)
RX_START_STEP         # Starting step (default 1, saved but not actively used)
RX_SKIP_STEP          # Step to skip to (used for "go back" skip)
RX_GO_BACK_TO         # Name of step to go back to (set by disk.sh)
```

**Rules for State Management**:

1. **Every script that sets a state variable MUST call `rx_save_state`** before returning
2. **Never assume variables persist between scripts** - always load state at start
3. **`rx_load_state` is called automatically** by `rx_run_step` before/after each step
4. **State file location**: `/tmp/retroinstall_state` (exported as `$RETRO_STATE`)

**Setup Scripts and Their Variables**:

| Step | Script | Variables Set |
|------|--------|---------------|
| 0 | `user.sh` | `USER_NAME`, `USER_PASSWORD`, `USER_PASSWORD_HASH`, `USER_SUDO` |
| 1 | `root.sh` | `ROOT_PASSWORD`, `ROOT_PASSWORD_HASH` |
| 2 | `hostname.sh` | `USER_HOSTNAME` |
| 3 | `keyboard.sh` | `KEYBOARD` (hardcoded list of 54 layouts) |
| 4 | `locale.sh` | `SYS_LANG` (from `LOCALE_LANG_NAMES` array) |
| 5 | `mirrors.sh` | `MIRROR_REGIONS`, `CUSTOM_MIRRORS` |
| 6 | `timezone.sh` | `USER_TIMEZONE` (via timedatectl) |
| 7 | `disk.sh` | `DISK_SELECTED`, `RX_GO_BACK_TO`; returns 42 on decline |
| 8 | `luks.sh` | `LUKS_ENABLED`, `LUKS_PASSWORD`, `LUKS_ITER_TIME` |
| 9 | `kernel.sh` | `KERNEL_SELECTION` (linux, linux-lts, linux-zen, linux-hardened) |
| 10 | `bluetooth.sh` | `BLUETOOTH_ENABLED` |
| 11 | `print.sh` | `PRINT_SERVICE_ENABLED` |
| 12 | `network.sh` | `NETWORK_TYPE`, `WIFI_SSID` |
| 13 | `config.sh` | Writes JSON files (no state variables) |

### rx_install_system Function

After all setup steps complete, `rx_install_system` (retroinstall lines 224+) does:

1. **Display summary table** with all configured values (username, passwords masked, hostname, keyboard, language, mirrors, timezone, disk, LUKS status, kernel, bluetooth, printing, network type)
2. **Ask for confirmation** to proceed with installation
3. **Run archinstall** with JSON config files and `--silent --skip-ntp --skip-wkd --skip-wifi-check`
4. **On failure**: Show error QR code, offer retry
5. **On success**: Display "Installation Complete!" message, wait for Enter, reboot

### User Input Patterns

#### Filter Input (Recommended for Lists)

Use `gum filter` for selectable lists with search/filter capability:

```bash
# Use GUM_FILTER_STYLE from display.sh
choice=$(echo "$items" | gum filter --height 15 --selected "$current" --header "Select" --style "${GUM_FILTER_STYLE[@]}" --padding "$GUM_FILTER_PADDING")
```

#### Confirm Input

```bash
# Simple yes/no confirmation with GUM_CONFIRM_STYLE
if gum confirm --affirmative "Continue" --negative "Go back" --padding "$GUM_CONFIRM_PADDING" "${GUM_CONFIRM_STYLE[@]}"; then
    # user selected affirmative
fi
```

#### Password Input

```bash
# Hidden password input
password=$(gum input --password --placeholder "Create a password" --prompt "Password> " --padding "$GUM_INPUT_PADDING")
```

### Centralized Style Variables

**From `lib/display.sh` - GUM_CONFIRM_STYLE:**

```bash
export GUM_CONFIRM_PROMPT_FOREGROUND="5"    # Magenta prompt
export GUM_CONFIRM_SELECTED_FOREGROUND="7"  # White text on selected
export GUM_CONFIRM_SELECTED_BACKGROUND="5"   # Magenta background
export GUM_CONFIRM_UNSELECTED_FOREGROUND="7"
export GUM_CONFIRM_UNSELECTED_BACKGROUND="240"
export GUM_CONFIRM_STYLE="--selected.foreground $GUM_CONFIRM_SELECTED_FOREGROUND --selected.background $GUM_CONFIRM_SELECTED_BACKGROUND --unselected.foreground $GUM_CONFIRM_UNSELECTED_FOREGROUND --unselected.background $GUM_CONFIRM_UNSELECTED_BACKGROUND"
```

**From `lib/display.sh` - GUM_FILTER_STYLE:**

```bash
export GUM_FILTER_STYLE=(--indicator="> " --prompt.foreground 5 --placeholder.foreground 8)
```

**Padding system:**

```bash
export TERM_WIDTH=$(stty size | awk '{print $2}')
export LOGO_WIDTH=74
export PADDING_LEFT=$(((TERM_WIDTH - LOGO_WIDTH) / 2))
export PADDING="0 0 0 $PADDING_LEFT"

export GUM_CHOOSE_PADDING="$PADDING"
export GUM_FILTER_PADDING="$PADDING"
export GUM_INPUT_PADDING="$PADDING"
export GUM_SPIN_PADDING="$PADDING"
export GUM_TABLE_PADDING="$PADDING"
export GUM_CONFIRM_PADDING="$PADDING"

export GUM_HEIGHT=15
export GUM_CHOOSE_HEIGHT=15
export GUM_FILTER_HEIGHT=15
export GUM_INPUT_HEIGHT=15
```

### Language and Keyboard Arrays

**LOCALE_LANG_NAMES** (in `lib/locale.sh`, ~80 entries):
Maps language codes to display names, e.g.:
```bash
LOCALE_LANG_NAMES["en"]="English"
LOCALE_LANG_NAMES["fr"]="French"
LOCALE_LANG_NAMES["de"]="German"
```

**KEYBOARD_LAYOUT_NAMES** (in `lib/locale.sh`, many entries):
Maps keymap codes to display names, e.g.:
```bash
KEYBOARD_LAYOUT_NAMES["us"]="English (US)"
KEYBOARD_LAYOUT_NAMES["uk"]="English (UK)"
KEYBOARD_LAYOUT_NAMES["fr"]="French"
KEYBOARD_LAYOUT_NAMES["de"]="German"
```

### Error Handling Pattern

All installer scripts set up traps for error handling:

```bash
# In bin/lib/handlers.sh
trap rx_catch_errors ERR
trap 'rx_show_signal_info "SIGINT"' INT
trap 'rx_show_signal_info "SIGTERM"' TERM
trap rx_exit_handler EXIT
```

### QR Code Error Reporting

Errors generate a QR code with system info for GitHub issues:

```bash
rx_generate_error_qr() {
    local exit_code=$1
    local repo_url="github.com/itsvlxd/RetroLinux/issues/new"
    local issue_title="Installation Halt - Exit Code $exit_code"
    # ... gathers system specs, generates QR code URL
}
```

### Installer Color Codes

The installer uses numeric color codes for gum style commands:

| Code | Color | Usage |
|------|-------|-------|
| 1 | Red | Errors, failure messages |
| 2 | Green | Success, connected |
| 3 | Yellow | Warnings, waiting |
| 5 | Magenta | Highlights, dividers, prompts |
| 6 | Cyan | Prompts, borders |
| 7 | White | Regular text |
| 8 | Gray | Placeholder text |
| 240 | Dark gray | Unselected items background |

---

## 18. Quick Reference

### File Locations

```
RetroLinux/
├── retro.sh                    # Entry point
├── lib/                        # All shared libraries
│   ├── colors.sh
│   ├── log.sh
│   ├── fs.sh
│   ├── driver.sh
│   ├── helpers.sh
│   ├── module.sh
│   └── ...
├── bin/                        # Installer system
│   ├── retroinstall            # Main entry point
│   ├── logo.txt                # ASCII art logo
│   ├── lib/                    # Low-level utilities (14 files)
│   │   ├── debug.sh
│   │   ├── disk.sh
│   │   ├── display.sh
│   │   ├── errors.sh
│   │   ├── gum.sh
│   │   ├── handlers.sh
│   │   ├── locale.sh
│   │   ├── output.sh
│   │   ├── progress.sh
│   │   ├── qr.sh
│   │   ├── setup_lib.sh
│   │   ├── setup.sh
│   │   ├── timezone.sh
│   │   └── wifi.sh
│   └── setup/                  # Modular setup scripts (14 scripts)
│       ├── bluetooth.sh
│       ├── config.sh
│       ├── disk.sh
│       ├── hostname.sh
│       ├── kernel.sh
│       ├── keyboard.sh
│       ├── locale.sh
│       ├── luks.sh
│       ├── mirrors.sh
│       ├── network.sh
│       ├── print.sh
│       ├── root.sh
│       ├── timezone.sh
│       └── user.sh
├── scripts/                    # Backend core scripts
│   ├── audio_core.sh
│   ├── network_core.sh
│   ├── driver_core.sh
│   └── ...
├── scripts/events/             # Event hook modules
│   ├── battery_events.sh
│   ├── power_events.sh
│   └── ...
├── scripts/watchers/           # Background system monitors
│   ├── battery.sh
│   ├── bluetooth.sh
│   ├── timers.sh
│   └── ...
├── cmds/tools/                 # Frontend commands
│   ├── audio.sh
│   ├── network.sh
│   └── ...
└── modules/                    # Desktop environment configs
    ├── hyprland/
    ├── ags/
    └── ...
```

### Key Patterns Summary

| Pattern | Code |
|--------|------|
| Status header | `echo -e "\n ${PINK}󰑊 Title${RESET}"` |
| Separator | `echo -e " ${PINK}󰇝${MUTE} ───────..."` |
| Table row | `printf " ${PINK}󰄾${RESET} %-36s ${PINK}%s${RESET}\n" "Label" "Value"` |
| Help entry | `printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "cmd" "desc"` |
| Log success | `rx_log "success" "Message"` |
| Log error | `rx_log "error" "Message" && return 1` |
| Register cmd | `register_command "TOOLS" "cmd|alias" "desc" "cmd_cmd"` |
| Event hook | `on_event_name() { ... }` in `scripts/events/*.sh` |
| Watcher | `start_watcher_name() { ... }` in `scripts/watchers/*.sh` |
| Installer clear | `rx_clear_logo` in `bin/lib/display.sh` |
| Installer error | `rx_retry_or_exit "message"` in `bin/lib/errors.sh` |
| Setup script guard | `if [[ "${RETRO_SETUP_SOURCED:-}" != "1" ]]; then` |
| Run setup step | `/opt/retrolinux/bin/setup/network.sh` |
| Gum filter with style | `gum filter ... --padding "$GUM_FILTER_PADDING" "${GUM_FILTER_STYLE[@]}"` |
| Gum confirm with style | `gum confirm ... --padding "$GUM_CONFIRM_PADDING" ${GUM_CONFIRM_STYLE}` |
| Save state | `rx_save_state` (in `bin/lib/handlers.sh`) |
| Load state | `rx_load_state` (in `bin/lib/handlers.sh`) |
