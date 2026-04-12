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
| `cmds/` | **User-facing** commands (tools, system, modules subdirectories) |
| `scripts/` | Backend automation scripts (core logic for each feature) |
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
| Backend core scripts | `scripts/` | `audio_core.sh`, `network_core.sh`, `driver_core.sh` |
| Standalone scripts | `scripts/` | `system_update.sh` (UI, invoked from events) |
| Frontend commands | `cmds/tools/` | `audio.sh`, `network.sh`, `driver.sh` |
| System commands | `cmds/system/` | `load.sh`, `update.sh`, `setup.sh` |
| Module definitions | `modules/<name>/` | `modules/hyprland/`, `modules/ags/` |
| Helper modules | `cmds/tools/clipboard/` | Subdirectories for complex tools |

---

## 4. The Two-Layer Tool Pattern (MOST IMPORTANT)

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

## 5. Code Style Rules

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

All scripts must pass shellcheck before being merged. Run `shellcheck scripts/*.sh cmds/**/*.sh lib/*.sh` locally to check.

Exceptions can be added inline for intentional cases:
```bash
# shellcheck disable=SC2086
local result=$myvar1$myvar2  # intentional concatenation
```

### Critical Rule: Never Duplicate Functions

> Before creating a new function, check `./lib/` first. If a function already exists that does what you need, use it.

If you need a utility that doesn't exist, add it to the appropriate lib file in `./lib/`, not in your command file.

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

**Real example** (from `cmds/tools/driver.sh`):

```bash
rx_help_usage "retro driver <command>"
rx_help_commands "Available commands"
rx_help_cmd "status" "Scan hardware and report driver status"
rx_help_cmd "install" "Install missing drivers"
rx_help_examples
rx_help_example "retro driver status" "Scan hardware..."
rx_help_spacer
```

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

**Real example for lists** (from `cmds/tools/service.sh`):

```bash
rx_table_header "󰒑" "System Services"
while IFS='|' read -r _ name load active sub; do
    rx_table_list_row "$name" "$active" "$sub" "$PINK" "$active_color" "$sub_color"
done <<<"$result"
rx_table_separator
rx_table_spacer
```

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

## 14. Walkthrough: Adding a New Tool

Let's add a hypothetical `temperature` tool:

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

            echo -e "\n ${PINK}󰈐 Temperature Status${RESET}"
            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────"

            while IFS='|' read -r zone type temp critical; do
                local zone_label="${zone:0:35}"
                printf " ${PINK}󰈐${RESET} %-36s ${PINK}%s${RESET}\n" "$zone_label" "$temp"
            done <<<"$data"

            echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────\n"
            ;;
        current)
            bash "$core" --current
            ;;
        help|"")
            rx_log "info" "Usage: retro temperature <command>"
            echo -e ""
            echo -e " ${PINK}  ${RESET}Commands${GRAY}:${RESET}"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "status" "Show all thermal zones"
            printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "current" "Show current CPU temp"
            echo ""
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

## 15. Best Practices and Gotchas

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

4. **Exit codes**: Core scripts should return 0 on success, 1 on failure. Frontend handles the messaging.

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

## 17. Event System (Background Daemon)

### Overview

The **Event System** is a background daemon that continuously monitors system state and fires events when conditions change. Unlike the two-layer tool pattern, this is a **long-running loop** that runs continuously in the background.

### File Structure

| File | Purpose |
|------|---------|
| `scripts/event_core.sh` | Main event loop daemon (runs with `--loop`) |
| `scripts/events/*.sh` | Event hook modules (define event handlers) |
| `cmds/tools/event.sh` | Frontend command to manage the daemon |

### How It Works

1. **Event Loop** (`event_core.sh --loop`):
   - Runs as a background daemon (started via `retro event start`)
   - Polls system state every 1-15 seconds depending on check type
   - Fires events by calling `broadcast_event "event_name" args`

2. **Event Hooks** (`scripts/events/*.sh`):
   - Each `.sh` file in `scripts/events/` is sourced automatically
   - Functions named `on_event_name()` become event handlers
   - Multiple hooks can respond to the same event

3. **Event Commands**:
   - `retro event start` - Start the daemon in background
   - `retro event stop` - Stop the running daemon
   - `retro event status` - Show if daemon is running
   - `retro event trigger <name>` - Manually fire an event
   - `retro event list` - Show all available hooks

### Available Events

| Event | Trigger |
|-------|---------|
| `on_event_loop_start` | Daemon starts |
| `on_power_disconnect` | Battery power connected |
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

- Event hooks run in a **subshell** - they don't share variables with the main loop
- Use `get_var`/`set_var` from `lib/helpers.sh` for persistent state
- Long-running operations in hooks can delay the main loop
- The daemon auto-starts on login (via `retro load`)

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
├── scripts/                    # Backend core scripts
│   ├── audio_core.sh
│   ├── network_core.sh
│   ├── driver_core.sh
│   └── ...
├── scripts/events/             # Event hook modules
│   ├── battery_events.sh
│   ├── power_events.sh
│   └── ...
├── cmds/tools/                 # Frontend commands
│   ├── audio.sh
│   ├── network.sh
│   └── ...
└── modules/                   # Desktop environment configs
    ├── hyprland/
    ├── ags/
    └── ...
```

### Key Patterns Summary

| Pattern | Code |
|---------|------|
| Status header | `echo -e "\n ${PINK}󰑊 Title${RESET}"` |
| Separator | `echo -e " ${PINK}󰇝${MUTE} ───────..."` |
| Table row | `printf " ${PINK}󰄾${RESET} %-36s ${PINK}%s${RESET}\n" "Label" "Value"` |
| Help entry | `printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "cmd" "desc"` |
| Log success | `rx_log "success" "Message"` |
| Log error | `rx_log "error" "Message" && return 1` |
| Register cmd | `register_command "TOOLS" "cmd|alias" "desc" "cmd_cmd"` |
| Event hook | `on_event_name() { ... }` in `scripts/events/*.sh` |
