<p align="center" style="vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="140" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="Logo" width="700" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="140" style="vertical-align: middle">
</p>

This document serves as the **single source of truth** for all RetroLinux development. Whether you're writing core scripts, frontend commands, installer utilities, or daemon handlers - these guidelines apply to everything.

**Who this is for:**
- **Contributors** building new features or fixing bugs
- **Maintainers** reviewing pull requests and enforcing standards
- **Anyone** extending RetroLinux's functionality

**What it covers:**
- Project structure and file naming conventions
- Code style rules and shellcheck compliance
- The two-layer architecture (frontend + backend)
- Multi-language libraries (Bash + Lua + Python 1:1 mapping)
- Color, logging, and UI patterns (rx_log for console, rx_log_file for files)
- Command registration and execution flow
- The daemon system and background watchers
- The installer system (bin/) in detail
- Module system (properties.json)
- Quick reference for common patterns

## 1. Directory Structure 📁

| Directory | Purpose |
|-----------|---------|
| `retro.sh` | Main entry point, command routing, global state |
| `lib/` | **Internal** core libraries (colors, logging, fs, driver detection, setup wizard, etc.) |
| `lib/setup.sh` | **Setup wizard library** — two-mode (interactive/`-o key=val`) config flow with validation, summary, confirm, and success stages |
| `lib/lua/` | Lua libraries for the event daemon (help.lua, colors.lua, log.lua) |
| `lib/python/` | Python libraries (log.py, env.py, obex.py) |
| `scripts/python/` | Python backend scripts (bluetooth_receive.py, log_core.py) |
| `bin/` | **Installer** system (retroinstall, lib, setup, post) |
| `cmds/` | **User-facing** commands (tools, system, modules subdirectories) |
| `scripts/` | Backend automation scripts (core logic for each feature, `*_core.sh` pattern, `log_core.sh` for file logging) |
| `daemon/` | **Lua event daemon** (engine.lua, event_daemon.lua, watcher.lua, watchers/, events/) |
| `modules/` | Desktop environment configurations (hyprland, ags, rofi, etc.) |
| `iso/` | Live ISO build system (archiso profile + Docker) |
| `assets/` | Project branding assets |
| `icons/` | Project icons |
| `wallpapers/` | Wallpaper assets |
| `tests/` | Test suite |
| `logs/` | Log directory |

> [!WARNING]
> **Critical Rule:** ALL lib files for anything should stay in `./lib/` — this is the single source of truth for shared utilities.
>
> **Why this matters:** When libraries are scattered across subdirectories like `scripts/lib/` or `cmds/lib/`, developers waste time searching for existing utilities and end up duplicating code. A flat `lib/` structure means one place to check before writing anything new.
---
## 2. File Naming Conventions 📝

| Pattern | Location | Example |
|---------|----------|---------|
| Internal libraries | `lib/` | `colors.sh`, `log.sh`, `fs.sh`, `helpers.sh`, `help.sh`, `battery.sh` |
| Lua libraries | `lib/lua/` | `help.lua`, `colors.lua`, `log.lua` |
| Python libraries | `lib/python/` | `log.py`, `env.py`, `obex.py` |
| Python scripts | `scripts/python/` | `bluetooth_receive.py`, `log_core.py` |
| Installer libraries | `bin/lib/` | `display.sh`, `wifi.sh`, `errors.sh`, `gum.sh`, `disk.sh`, `handlers.sh`, `output.sh`, `debug.sh`, `crypto.sh` |
| Backend core scripts | `scripts/` | `audio_core.sh`, `network_core.sh`, `driver_core.sh`, `fans_core.sh`, `theme_core.sh`, `grub_core.sh`, `test_core.sh`, `log_core.sh` |
| Event daemon core | `daemon/` | `engine.lua`, `event_daemon.lua`, `watcher.lua` |
| Event handlers | `daemon/events/` | `battery.lua`, `power.lua`, `notifications.lua`, `wallpaper.lua` |
| Watchers | `daemon/watchers/` | `battery.lua`, `bluetooth.lua`, `power.lua`, `usb.lua`, `audio.lua`, `wallpaper.lua`, `portal.lua`, `slideshow.lua`, `timers.lua` |
| Standalone scripts | `scripts/` | `system_update.sh` (UI, invoked from events) |
| Frontend commands | `cmds/tools/` | `audio.sh`, `network.sh`, `driver.sh`, `grub.sh`, `xdg.sh`, `power.sh`, `fingerprint.sh`, `bitwarden.sh`, `app.sh` |
| System commands | `cmds/system/` | `load.sh`, `update.sh`, `setup.sh`, `help.sh`, `version.sh`, `about.sh`, `test.sh` |
| Module commands | `cmds/modules/` | `install.sh`, `uninstall.sh`, `mirror.sh`, `pull.sh`, `list.sh` |
| Setup sub-commands | `cmds/system/setup/` | `audio.sh`, `network.sh`, `wallpaper.sh`, `ricing.sh`, `fonts.sh`, `drivers.sh`, etc. |
| Module definitions | `modules/<name>/` | `modules/hyprland/`, `modules/ags/` |
| Installer entry | `bin/` | `retroinstall` |
| ISO build | `iso/` | `build.sh`, `Dockerfile`, `profile/` |

---
## 3. Code Style Rules ✨

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

> [!IMPORTANT]
> **Key Rule:** Before creating a new function, check `./lib/` or `./bin/lib/` first. If a function already exists that does what you need, use it.
>
> **Why this matters:** Duplicated functions drift over time — one copy gets a bug fix while the other doesn't, leading to inconsistent behavior across the codebase. When every utility lives in `lib/`, fixes propagate everywhere automatically. This also reduces the codebase size and makes onboarding easier: new contributors learn one function, not five variants.
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
## 4. The Two-Layer Tool Pattern 🎯 (MOST IMPORTANT)

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
## 5. Multi-Language Libraries 🌐

### Overview

RetroLinux is a **multi-language codebase**. The primary language is **Bash** (shell scripts), but the daemon system and some tooling use **Lua**. To keep the codebase coherent and avoid developer confusion, every library in `lib/` has a **1:1 port** in `lib/lua/`.

### The 1:1 Mapping Rule

> [!WARNING]
> **Critical:** Every function in a shell library must have an equivalent in its Lua port with identical behavior.
>
> **Why this matters:** Developers constantly switch between shell and Lua code. If `rx_format_time(3600)` returns `"1 hours"` in Bash but `"60 min"` in Lua, the watcher that parses core script output will break silently. This rule eliminates an entire class of subtle bugs where the same function behaves differently depending on which language calls it.
- Same function name (adapted to language conventions: `rx_format_time` → `Helpers.format_time`)
- Same input parameters
- Same output format and return values
- Same edge-case handling
- **NO custom logic that diverges from the shell equivalent**

If `rx_format_time(3600)` in `lib/helpers.sh` returns `"1 hours"`, then `Helpers.format_time(3600)` in `lib/lua/helpers.lua` **must** return `"1 hours"` — not `"60 minutes"` or anything else.

This rule exists because:
1. Developers switch between shell and Lua code constantly
2. Watchers (Lua) call core scripts (Bash) and vice versa
3. Output parsed by one language may be produced by the other
4. Divergent behavior is a major source of subtle bugs

### Library Mapping Table

<details>
  <summary>📋 Click to view the full library mapping table</summary>
  <br>

| Shell (`lib/`) | Lua (`lib/lua/`) | Python (`lib/python/`) | Purpose |
|----------------|------------------|------------------------|---------|
| `colors.sh` | `colors.lua` | `log.py` (embedded) | Color definitions (PINK, GRAY, SUCCESS, etc.) |
| `log.sh` | `log.lua` | `log.py` | Logging (info, success, warn, error) |
| `help.sh` | `help.lua` | — | Table rendering, help formatting, confirmations |
| `helpers.sh` | `helpers.lua` | — | Utilities (format_time, format_size, battery icon, etc.) |
| `variable.sh` | `variable.lua` | `env.py` | Persistent key-value store (get_var, set_var) |
| `fs.sh` | `fs.lua` | — | File operations (get_json, read_file, write_file) |
| `battery.sh` | `battery.lua` | — | Battery management (saver, stats, limits) |
| `bluetooth.sh` | `bluetooth.lua` | `obex.py` | Bluetooth device detection, OBEX transfers |
| `wallpaper.sh` | `wallpaper.lua` | — | Wallpaper paths, slideshow, pause/resume |
| `audio.sh` | `audio.lua` | — | Audio device management |
| `xdg.sh` | `xdg.lua` | — | XDG directory handling |
| `power.sh` | `power.lua` | — | Power profile management |
| `icons.sh` | `icons.lua` | — | Nerd Font icon definitions |
| `—` | `notify.lua` | — | Desktop notifications (Lua only) |

</details>

### Naming Convention

| Shell pattern | Lua pattern | Example |
|---------------|-------------|---------|
| `rx_function_name` | `ModuleName.function_name` | `rx_format_time` → `Helpers.format_time` |
| Global variables | Module fields | `$PINK` → `Colors.PINK` |
| `source "$RETRO_DIR/lib/x.sh"` | `local X = require("x")` | Import pattern |

### Adding a New Library

1. Create the shell version in `lib/name.sh`
2. Create the Lua port in `lib/lua/name.lua`
3. Ensure all functions have matching behavior
4. Update this mapping table

### What NOT to Do

```lua
-- BAD: Lua version returns different format than shell
-- Shell: rx_format_time(3600) → "1 hours"
-- Lua:   Helpers.format_time(3600) → "60 min"  ← WRONG

-- GOOD: Lua version matches shell exactly
-- Shell: rx_format_time(3600) → "1 hours"
-- Lua:   Helpers.format_time(3600) → "1 hours"  ← CORRECT
```

---
## 6. Python Libraries 🐍

### Overview

> [!NOTE]
> **Why Python:** Shell scripting becomes impractical for DBus-heavy operations.
>
> **Why this matters:** Python's `dbus-python` and `pygobject` libraries provide clean APIs for BlueZ OBEX file transfers, GLib main loops, and structured logging. Python is used *only* where shell would be fragile — the rest of the codebase stays in Bash/Lua.
Python is used for **DBus-heavy operations** (Bluetooth OBEX file transfers) and **structured logging** where shell scripting would be impractical. Python scripts are called from shell commands via `python3` and follow the same 1:1 mapping rule as Lua.

### Library Files

| File | Purpose |
|------|---------|
| `lib/python/log.py` | Console logging with colors/icons (mirrors `lib/log.sh`) |
| `lib/python/env.py` | Environment setup, variable persistence (mirrors `lib/variable.sh`) |
| `lib/python/obex.py` | Bluetooth OBEX constants and helpers (no shell equivalent) |
| `lib/python/__init__.py` | Package exports for `obex` and `env` modules |
| `scripts/python/log_core.py` | File-based logging with rotation (used by Python scripts) |
| `scripts/python/bluetooth_receive.py` | OBEX agent for Bluetooth file transfers (DBus + GLib) |

### log.py — Console Logging

Mirrors `lib/log.sh` exactly. Same colors, same icons, same output format:

```python
from lib.python.log import rx_log, info, success, warn, error

rx_log("info", "Starting process...")
info("Starting process...")        # shorthand
success("Operation completed")
warn("Something might be wrong")
error("Operation failed")
```

**Output format** (identical to shell `rx_log` — colors applied internally, shown clean here):
```
[ INFO] Starting process...
[ SUCCESS] Operation completed
[ WARN] Something might be wrong
[󰅙 ERROR] Operation failed
```

### env.py — Environment and Variables

Mirrors `lib/variable.sh` and `lib/lua/variable.lua`. Same `get_var`/`set_var` API:

```python
from lib.python.env import get_var, set_var, reload_vars, ensure_dbus, get_shell_env

# Variable persistence (same file: $RETRO_CONFIG/variables.sh)
val = get_var("KEY", "default")
set_var("KEY", "value")
reload_vars()

# DBus setup (for scripts that need DBus)
ensure_dbus()

# Get shell environment for subprocess calls
env = get_shell_env({"EXTRA_VAR": "value"})
```

### obex.py — Bluetooth OBEX Helpers

```python
from lib.python.obex import (
    BUS_NAME, AGENT_IFACE, PROPS_IFACE, TRANSFER_IFACE, SESSION_IFACE,
    calc_notif_id, get_cancel_flag_path, clean_cancel_flag, set_cancel_flag,
    run_shell_cmd,
)

# Calculate notification ID from MAC address
notif_id = calc_notif_id("AA:BB:CC:DD:EE:FF")

# Cancel flag management for transfer cancellation
flag_path = get_cancel_flag_path("AA:BB:CC:DD:EE:FF")
set_cancel_flag("AA:BB:CC:DD:EE:FF")
clean_cancel_flag("AA:BB:CC:DD:EE:FF")

# Run shell scripts from Python
run_shell_cmd("/path/to/script.sh", "--arg1", "value", env=env)
result = run_shell_cmd("/path/to/script.sh", "--capture", capture=True)
```

### log_core.py — File-Based Logging

```python
from scripts.python.log_core import register, rx_log_file, log, info, success, warn, error

# Register a log identifier (creates /tmp/retro_logs/<id>.log)
register("bluetooth")

# Write to log file only (no console output)
rx_log_file("info", "Transfer started")

# Write to both console and log file
info("Transfer started")     # console + file
log("info", "Transfer started")  # same as info()
```

### bluetooth_receive.py — OBEX Agent

Full DBus OBEX agent for Bluetooth file transfers. Run as a background process:

```bash
python3 scripts/python/bluetooth_receive.py /path/to/callback.sh
```

The agent:
1. Registers with BlueZ OBex service via DBus
2. Listens for incoming file push requests
3. Calls back to shell script for user confirmation (`--obex-ask`)
4. Monitors transfer progress and notifies shell (`--obex-notify-progress`)
5. Handles transfer completion/cancellation (`--obex-notify-done`)
6. Supports cancellation via flag files

### Naming Convention

| Shell pattern | Python pattern | Example |
|---------------|----------------|---------|
| `rx_function_name` | `function_name` or `module.function_name` | `rx_log` → `rx_log` or `log.info` |
| `$VAR` | `os.environ.get("VAR")` | `$RETRO_DIR` → `os.environ.get("RETRO_DIR")` |
| `source "$RETRO_DIR/lib/x.sh"` | `from lib.python.x import ...` | Import pattern |

### Adding a New Python Library

1. Check if `lib/python/` already has what you need
2. Create new file in `lib/python/name.py` for shared utilities
3. Create new file in `scripts/python/name.py` for standalone scripts
4. Ensure any overlapping functions match shell/Lua behavior 1:1
5. Update the library mapping table

### What NOT to Do

```python
# BAD: Python logging uses different format than shell
# Shell: rx_log "info" "message" → "[ INFO] message"
# Python: print("INFO: message")  ← WRONG

# GOOD: Python uses same format
from lib.python.log import info
info("message")  # → "[ INFO] message"  ← CORRECT
```

```python
# BAD: Python variable storage uses different file
# Shell: stores in $RETRO_CONFIG/variables.sh
# Python: stores in /tmp/my_vars.json  ← WRONG

# GOOD: Python uses same variables.sh file
from lib.python.env import get_var, set_var
set_var("KEY", "value")  # writes to $RETRO_CONFIG/variables.sh  ← CORRECT
```

---
## 7. Color and Logging System 🔥

### Available Color Variables

All colors are defined in `lib/colors.sh`:

| Variable | Purpose |
|----------|---------|
| `$PINK` | Primary accent (headings, icons, important values) |
| `$GRAY` | Secondary text (descriptions, labels) |
| `$MUTE` | Subtle text (separators, hints) |
| `$SUCCESS` | Success messages (green-ish) |
| `$WARN` | Warning messages (yellow-ish) |
| `$ERROR` | Error messages (red-ish) |
| `$LABEL` | Label/dim text (244 gray) |
| `$BOLD` | Bold text modifier |
| `$RESET` | Reset sequence `\033[0m` |

### Two Logging Functions: rx_log vs rx_log_file

> [!WARNING]
> **Critical:** There are TWO distinct logging functions with completely different purposes.
>
> **Why this matters:** Mixing console output with file logging creates two problems. First, core scripts that produce colored console output break the frontend's ability to parse their results. Second, frontend commands that write to log files flood `/tmp/retro_logs/` with user-facing messages that aren't useful for debugging. The separation ensures core scripts produce clean, parseable output while frontend commands handle all user interaction.
| Function | Location | Purpose | Output |
|----------|----------|---------|--------|
| `rx_log` | `lib/log.sh` | **Frontend console output** | Terminal (colored, with icons) |
| `rx_log_file` | `scripts/log_core.sh` | **Backend file logging** | Log files in `/tmp/retro_logs/` |

#### rx_log — Frontend Console Output

Used in **frontend commands** (`cmds/**/*.sh`) to display messages to the user:

```bash
source "$RETRO_DIR/lib/log.sh"

rx_log "info" "Starting process..."
rx_log "success" "Operation completed"
rx_log "warn" "Something might be wrong"
rx_log "error" "Operation failed"
```

**Output format** (colored, with Nerd Font icons):
```
[ INFO] Starting process...
[ SUCCESS] Operation completed
[ WARN] Something might be wrong
[󰅙 ERROR] Operation failed
```

**Rules**:
- Only use in frontend commands (`cmds/`)
- Never use in core scripts (`scripts/*_core.sh`)
- Always `return 1` after `rx_log "error"`

#### rx_log_file — Backend File Logging

```bash
source "$RETRO_DIR/scripts/log_core.sh"

# Step 1: Register your log source (creates the log file)
rx_log_register "audio_core"

# Step 2: Write to log file (no console output)
rx_log_file "info" "Audio device changed"
rx_log_file "success" "Volume set to 75%"
rx_log_file "warn" "No default sink found"
rx_log_file "error" "Failed to connect to PipeWire"
```

**Output format** (timestamped, plain text in `/tmp/retro_logs/<id>.log`):
```
[2024-01-15 14:30:22] [INFO] Audio device changed
[2024-01-15 14:30:23] [SUCCESS] Volume set to 75%
[2024-01-15 14:30:24] [WARN] No default sink found
[2024-01-15 14:30:25] [ERROR] Failed to connect to PipeWire
```

**Rules**:
- Every core script and daemon engine **MUST** register a log entry at startup
- Use `rx_log_register "<unique_id>"` before any `rx_log_file` calls
- Log files are auto-rotated at `RX_LOG_MAX_LINES` (default: 500)
- Logs can be enabled/disabled per-source via `.disabled` flag files

### Log Management Functions

| Function | Purpose |
|----------|---------|
| `rx_log_register "id"` | Register a log source, creates `/tmp/retro_logs/<id>.log` |
| `rx_log_file "level" "msg"` | Write to all registered log files (skips disabled) |
| `rx_log_list` | Print all registered logs (id + line count) |
| `rx_log_status` | Print detailed status of all logs |
| `rx_log_tail "id" [limit]` | Print last N lines of a log (default: 30) |
| `rx_log_clear "id"` | Truncate a log file |
| `rx_log_disable "id"` | Create `.disabled` flag to stop logging |
| `rx_log_enable "id"` | Remove `.disabled` flag to resume logging |
| `rx_log_is_disabled "id"` | Check if logging is disabled for a source |
| `_rx_log_scan_files result_array` | Scan `/tmp/retro_logs/` and populate array with `id|lines|size|modified|last` |

### Log Frontend Command (`cmds/tools/log.sh`)

| Subcommand | Purpose |
|------------|---------|
| `retro log status` | Show summary (total sources, active, disabled, entries) |
| `retro log list` | List all log sources with status, line count, last modified |
| `retro log <name> [lines]` | View last N lines of a log (default: 30) |
| `retro log open <name>` | Stream log in real-time (`tail -f`) |
| `retro log enable <name|all>` | Enable logging for a source or all sources |
| `retro log disable <name|all>` | Disable logging for a source or all sources |
| `retro log clear <name|all>` | Clear a log file or all log files |
| `retro log help` | Show usage help |

### Using rx_log

```bash
rx_log "success" "Operation completed"
rx_log "info" "Starting process..."
rx_log "warn" "Something might be wrong"
rx_log "error" "Operation failed"
```

> [!NOTE]
> **Important:** When using `rx_log "error"`, always `return 1` after it.
>
> **Why this matters:** Without `return 1`, the script continues executing after logging an error, which can cause cascading failures or corrupt state. The `return 1` ensures the calling function knows the operation failed and can handle it appropriately.
```bash
[[ -z $value ]] && rx_log "error" "Value is required" && return 1
```

### Direct Echo Patterns

```bash
echo -e "${PINK}Header${RESET}"
printf " ${PINK}%-20s${GRAY}- ${RESET}%s\n" "command" "description"
```

---
## 8. Design Rules and Examples 🎨

### Status Table Pattern (Use Centralized Functions)

> [!TIP]
> **Why centralized functions:** When every command formats tables differently, the UI looks inconsistent and maintenance becomes a nightmare.
>
> **Why this matters:** Centralized functions in `lib/help.sh` ensure every tool uses the same spacing, colors, and icon alignment. Change the format once, update everywhere. This eliminates visual inconsistencies across the codebase and makes UI improvements a single-point change.
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

```bash
rx_help_usage "retro tool <command>"
rx_help_commands "Subcommands"
rx_help_cmd "status" "Show current status" 20
rx_help_cmd "set <value>" "Set a value" 20
rx_help_cmd "action" "Perform action" 20
rx_help_examples
rx_help_example "retro tool status" "Show current status" 30
```

**Available Help Functions** (in `lib/help.sh`):

| Function | Purpose |
|----------|---------|
| `rx_help_usage "usage text"` | Shows usage line |
| `rx_help_commands "title"` | Shows "Commands:" header |
| `rx_help_cmd "cmd" "desc" [width]` | Prints a command line (width default: 26) |
| `rx_help_examples` | Shows "Examples:" header |
| `rx_help_example "cmd" "desc" [width]` | Prints an example line (width default: 26) |
| `rx_help_header "icon" "title"` | Shows section header with icon |
| `rx_help_separator` | Prints separator line |
| `rx_help_footer` | Prints footer with separator |

### Table and Status Display Functions

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

```bash
rx_table_separator
rx_table_spacer
```

For help sections, use:

```bash
rx_help_separator
rx_help_spacer
```

**Legacy pattern (AVOID - use centralized functions instead):**

```bash
echo -e " ${PINK}󰇝${MUTE} ───────────────────────────────────────${RESET}"
```

The line width should be:
- 34 chars for simpler tables (36 - 2 for padding)
- 50+ chars for complex tables

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
## 9. Command System 🚀

### register_command

> [!NOTE]
> **Why register_command:** The command routing system in `retro.sh` discovers commands by scanning their registrations.
>
> **Why this matters:** Without `register_command`, your script exists but `retro` doesn't know about it — it won't appear in help output or be callable. The GROUP parameter determines which category the command appears under in the help menu. This registration system is the backbone of command discovery.
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
## 10. Backend Core Scripts ⚙️

### CLI Flags Pattern

```bash
# scripts/example_core.sh
source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "example_core"

case "$1" in
    --status)
        rx_log_file "info" "Status check requested"
        # Output: key1=value1|key2=value2
        rx_log_file "success" "Status check complete"
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

> [!WARNING]
> **Critical:**
>
> 1. **NO rx_log** — Core scripts don't produce console output. Use `rx_log_file` for file logging.
> 2. **NO user-facing echo** — No messages to stdout meant for users (no `echo "Success"`, `echo "Error"`, etc.)
> 3. **Only raw data output** — What the frontend parses
> 4. **Exit codes** — 0 for success, 1 for failure (frontend handles messaging)
>
>
> **Why this matters:** The frontend parses core script output using `IFS='|' read`. Any extra text (like `echo "Success"`) becomes a malformed line that breaks the parser. Human-readable messages belong in the frontend, which uses `rx_log` for colored, formatted output. Mixing console output with data output creates an entire class of subtle parsing bugs.
---
## 11. Frontend Command Scripts 💻

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

> [!TIP]
> **Why validate early:** Catching invalid input before any side effects occur prevents partial state changes.
>
> **Why this matters:** If a user runs `retro tool set` without a value, the error should appear instantly — not after the script has already modified files or started services. Early validation ensures atomic operations and gives users immediate feedback.
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
## 12. Setup Wizard Pattern (`lib/setup.sh`) 🗡️

The setup wizard pattern is a reusable interactive/non-interactive configuration flow used by tools that need guided setup. It lives in `lib/setup.sh` (sourced by frontend command scripts).

### When to Use This Pattern

> [!NOTE]
> **Use the setup wizard when:** Your tool needs to collect multiple configuration values from the user, validate them, show a summary, and apply changes atomically.
>
> **Don't use it for:** Simple single-action commands (use `rx_confirm` directly) or tools that don't persist configuration.

**Examples of tools that SHOULD use setup:**
- `retro timeshift setup` — collects backup device, snapshot counts, boot snapshots
- `retro xdg setup` — collects default apps (editor, browser, file manager, etc.)
- `retro grub setup` — collects theme, resolution, timeout, kernel options

**Examples of tools that SHOULD NOT use setup:**
- `retro audio status` — read-only, no config collection
- `retro network wifi on` — single action, no multi-step form

### The Pattern (Why)

Instead of each tool implementing its own prompts, validation, and confirmation logic, `lib/setup.sh` provides a standardized pipeline:

1. **Parse** CLI flags (`-o key=val,...` and `--needed`)
2. **Validate** options against declared keys and rules
3. **Check needed** — skip if `--needed` and already configured
4. **Branch** — collect values from `-o` flags (non-interactive) or prompt user (interactive)
5. **Summary** — show all values in a table  
6. **Confirm** — ask "Apply these settings?"
7. **Apply** — tool-specific changes
8. **Success** — show final table

This gives you two-mode behavior by default:
- **Non-interactive**: `retro tool setup -o key1=val1,key2=val2` — for automation/scripts
- **Interactive**: `retro tool setup` — guided prompts with defaults  
- **Combined**: `retro tool setup --needed` — only run setup if not yet configured (`-o` optional)

### Step-by-Step Implementation Guide

#### Step 1: Source the Library

At the top of your command file, source `lib/setup.sh` alongside other libs:

```bash
source "$RETRO_DIR/lib/setup.sh"
source "$RETRO_DIR/lib/help.sh"
source "$RETRO_DIR/lib/colors.sh"
```

> [!WARNING]
> **Source order matters:** Source `setup.sh` BEFORE your command function is called. The library declares global variables (`RX_SETUP_MODE`, `RX_SETUP_OPTS`) that your function will read.

#### Step 2: Add the Setup Subcommand

Inside your command's `case` statement, add a `"setup")` branch:

```bash
cmd_mytool() {
    local action="${1,,}"
    
    case "$action" in
        setup)
            # Setup logic goes here
            ;;
        status)
            # Status logic
            ;;
        help|"")
            rx_log "info" "Usage: retro mytool <command>"
            ;;
        *)
            rx_log "error" "Unknown command: $action"
            return 1
            ;;
    esac
}
```

#### Step 3: Parse CLI Flags

Always call `rx_setup_parse` as the FIRST setup function:

```bash
"setup")
    rx_setup_parse "$@"
    # ... rest of setup logic
```

> [!TIP]
> **What this does:** `rx_setup_parse "$@"` scans `$@` for `-o key=val,...` and `--needed` flags, then:
> - Sets `RX_SETUP_MODE="non-interactive"` if `-o` was provided
> - Sets `RX_SETUP_NEEDED=true` if `--needed` was provided
> - Populates `RX_SETUP_OPTS` associative array with parsed key-value pairs
> - Strips these flags from consideration in your remaining logic

#### Step 4: Declare Valid Keys and Validation Rules

Tell the setup system what options you accept and how to validate them:

```bash
rx_setup_validate "editor,browser,filemanager" "editor:required,browser:required,filemanager:in=thunar,nautilus,dolphin"
```

**Validation rule syntax:**
```
key1:rule1|rule2,key2:rule1|rule2
```

| Rule | Example | Effect |
|------|---------|--------|
| `required` | `editor:required` | Value must be non-empty |
| `numeric` | `count:numeric` | Must be an integer |
| `min=N` | `timeout:min=0` | Must be >= N |
| `max=N` | `timeout:max=300` | Must be <= N |
| `pattern=REGEX` | `name:pattern=^[a-z]+$` | Must match regex |
| `in=val1,val2` | `theme:in=dark,light` | Must be one of the listed values |
| `eq=VAL` | `mode:eq=advanced` | Must equal VAL |
| `ne=VAL` | `mode:ne=basic` | Must not equal VAL |

> [!NOTE]
> **Validation happens immediately:** If any rule fails, `rx_setup_validate` logs an error and returns 1. Your script should `|| return 1` to exit early.

#### Step 5: Check if Already Configured (for --needed)

Detect existing configuration and skip if `--needed` was passed:

```bash
local config=$(bash "$mytool_core" --config 2>/dev/null || echo "ERROR")
local config_exists=false
[[ $config != "ERROR"* ]] && config_exists=true

rx_setup_check_needed "$config_exists" && return 0
```

> [!TIP]
> **How --needed works:** When a user runs `retro mytool setup --needed`:
> - If config exists (`config_exists=true`): `rx_setup_check_needed` returns 0, script exits early
> - If config doesn't exist: `rx_setup_check_needed` returns 1, script continues
>
> **Use case:** Installers call `retro mytool setup --needed` to auto-configure tools that weren't set up yet, without re-running setup on already-configured tools.

#### Step 6: Collect Values (Branch on Mode)

Collect configuration values differently based on interactive vs non-interactive mode:

```bash
local editor="" browser="" filemanager=""

if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
    # Read from -o flags
    editor=$(rx_setup_get_opt "editor")
    browser=$(rx_setup_get_opt "browser")
    filemanager=$(rx_setup_get_opt "filemanager" "thunar")  # with default
else
    # Interactive: prompt user
    editor=$(rx_input "Default editor" "nvim")
    browser=$(rx_input_choice "󰇩" "Select browser:" "firefox" firefox chrome chromium)
    filemanager=$(rx_input "File manager" "thunar")
fi
```

**Input function quick reference:**

| Function | Use Case | Example |
|----------|----------|---------|
| `rx_input "label" "default"` | Free text input | `editor=$(rx_input "Editor" "nvim")` |
| `rx_input_numeric "label" "default" min max` | Numbers with range | `count=$(rx_input_numeric "Count" "5" 1 10)` |
| `rx_input_choice "icon" "label" "default" opt1 opt2` | Numbered menu | `choice=$(rx_input_choice "󰇩" "Pick:" "opt1" opt1 opt2 opt3)` |
| `rx_menu "icon" "label" options...` | Gum-style menu | `device=$(rx_menu "󰏗" "Select:" "${devices[@]}")` |
| `rx_setup_get_opt "key" "default"` | Non-interactive read | `val=$(rx_setup_get_opt "key" "default")` |

> [!WARNING]
> **Always use the same variable names in both branches:** The rest of your setup code should reference `$editor`, `$browser`, etc. regardless of how they were collected. This keeps the apply logic identical for both modes.

#### Step 7: Show Summary and Confirm

Display what will be applied and ask for confirmation:

```bash
rx_setup_summary "󰒓" "MyTool Setup Summary" \
    "Editor" "$editor" \
    "Browser" "$browser" \
    "File Manager" "$filemanager"

rx_setup_confirm || return 0
```

> [!TIP]
> **User experience:** The summary table shows values in pink highlight. The confirm prompt asks "Apply these settings? [y/N]". If user declines, `rx_setup_confirm` returns 1 and your script should exit cleanly with `return 0`.

#### Step 8: Apply Changes

Execute your tool-specific configuration logic:

```bash
local result=$(bash "$mytool_core" --apply-setup \
    "editor=${editor}" \
    "browser=${browser}" \
    "filemanager=${filemanager}" 2>&1)

if echo "$result" | grep -q "^OK|"; then
    # Success
else
    rx_log "error" "Failed to apply configuration: $result"
    return 1
fi
```

> [!WARNING]
> **Apply logic must be identical for both modes:** Whether values came from `-o` flags or interactive prompts, the apply step should be the same. Don't branch on `RX_SETUP_MODE` here.

#### Step 9: Show Success

Display the final configuration and log success:

```bash
rx_setup_success "󰒓" "MyTool Configured" \
    "Editor" "$editor" \
    "Browser" "$browser" \
    "File Manager" "$filemanager"
```

> [!NOTE]
> **What this does:** `rx_setup_success` shows a summary table (same format as `rx_setup_summary`) and logs "Setup complete" with a success icon. This is the user's confirmation that their configuration was applied.

### Complete Example: Minimal Setup Subcommand

```bash
"setup")
    # Step 1: Parse CLI flags
    rx_setup_parse "$@"
    
    # Step 2: Validate keys and rules
    rx_setup_validate "editor,browser" "editor:required,browser:required" || return 1
    
    # Step 3: Check existing config
    local config_exists=false
    [[ -f "$HOME/.config/mytool/config.sh" ]] && config_exists=true
    rx_setup_check_needed "$config_exists" && return 0
    
    # Step 4: Collect values
    local editor="" browser=""
    
    if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
        editor=$(rx_setup_get_opt "editor")
        browser=$(rx_setup_get_opt "browser")
    else
        # Show current config if exists
        if [[ $config_exists == true ]]; then
            source "$HOME/.config/mytool/config.sh"
            rx_setup_prompt_reconfigure "󰒓" "Current MyTool Config" \
                "Editor" "$MYTOOL_EDITOR" \
                "Browser" "$MYTOOL_BROWSER" || return 0
        fi
        
        editor=$(rx_input "Default editor" "nvim")
        browser=$(rx_input_choice "󰇩" "Select browser:" "firefox" firefox chrome chromium)
    fi
    
    # Step 5: Summary + confirm
    rx_setup_summary "󰒓" "Setup Summary" \
        "Editor" "$editor" \
        "Browser" "$browser"
    rx_setup_confirm || return 0
    
    # Step 6: Apply
    cat > "$HOME/.config/mytool/config.sh" <<EOF
MYTOOL_EDITOR="$editor"
MYTOOL_BROWSER="$browser"
EOF
    
    # Step 7: Success
    rx_setup_success "󰒓" "MyTool Configured" \
        "Editor" "$editor" \
        "Browser" "$browser"
    ;;
```

### Function Reference

| Function | Signature | Purpose |
|----------|-----------|---------|
| `rx_setup_parse` | `"$@"` | Parse `-o key=val,...` and `--needed`; sets `RX_SETUP_MODE` global |
| `rx_setup_validate` | `"keys" "rules"` | Validate provided `-o` values; warn on unknown keys |
| `rx_setup_get_opt` | `"key" "default"` | Read a parsed option value (non-interactive mode) |
| `rx_setup_current` | `icon title key val...` | Show current config table (returns 0 if anything configured) |
| `rx_setup_check_needed` | `config_exists` | Return 0 if `--needed` + config exists (skip setup) |
| `rx_setup_prompt_reconfigure` | `icon title key val...` | Show current config + ask "Reconfigure?" |
| `rx_setup_summary` | `icon title key val...` | Show setup summary table |
| `rx_setup_confirm` | — | "Apply these settings?" prompt; returns 1 if cancelled |
| `rx_setup_success` | `icon title key val...` | Show success table + log "Setup complete" |
| `rx_input` | `"label" "default" "pattern" "err"` | Text input with optional regex validation |
| `rx_input_numeric` | `"label" "default" [min] [max]` | Numeric input with optional range (min/max are optional) |
| `rx_input_choice` | `icon "label" "default" opt1 opt2 ...` | Numbered choice menu |
| `rx_menu` | `icon "label" options...` | Gum-style menu selection (returns selected option) |

### Validation Rules

Passed as the second argument to `rx_setup_validate` in pipe-delimited format:

```
key1:required|numeric,key2:in=val1,val2|min=1,key3:pattern=^[a-z]+$
```

| Rule | Description |
|------|------|
| `required` | Value must be non-empty |
| `numeric` | Must be an integer |
| `min=N` | Must be >= N |
| `max=N` | Must be <= N |
| `pattern=REGEX` | Must match regex |
| `in=val1,val2` | Must be one of the listed values |
| `eq=VAL` | Must equal VAL |
| `ne=VAL` | Must not equal VAL |

### Common Pitfalls and Gotchas

#### Pitfall 1: Forgetting to Source the Library

```bash
# WRONG: rx_setup_parse not defined
"setup")
    rx_setup_parse "$@"  # Error: command not found
```

```bash
# CORRECT: Source before use
source "$RETRO_DIR/lib/setup.sh"

"setup")
    rx_setup_parse "$@"  # Works
```

#### Pitfall 2: Not Checking rx_setup_validate Return

```bash
# WRONG: Continues even if validation fails
rx_setup_validate "editor" "editor:required"
# Script continues with invalid input

# CORRECT: Exit early on validation failure
rx_setup_validate "editor" "editor:required" || return 1
```

#### Pitfall 3: Using Different Variable Names in Branches

```bash
# WRONG: Different names for each mode
if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
    editor_from_opt=$(rx_setup_get_opt "editor")
else
    editor_input=$(rx_input "Editor" "nvim")
fi
# Which variable do I use in apply?!

# CORRECT: Same variable name in both branches
if [[ $RX_SETUP_MODE == "non-interactive" ]]; then
    editor=$(rx_setup_get_opt "editor")
else
    editor=$(rx_input "Editor" "nvim")
fi
# Use $editor in apply logic
```

#### Pitfall 4: Skipping the Confirm Step

```bash
# WRONG: Applies without confirmation
rx_setup_summary "Icon" "Summary" "Key" "$val"
# Immediately applies - user had no chance to review

# CORRECT: Always confirm before apply
rx_setup_summary "Icon" "Summary" "Key" "$val"
rx_setup_confirm || return 0
# User sees "Apply these settings? [y/N]"
```

#### Pitfall 5: Not Handling --needed Correctly

```bash
# WRONG: Ignores --needed flag
local config_exists=true
# Missing: rx_setup_check_needed "$config_exists" && return 0

# CORRECT: Check needed before collecting values
local config_exists=false
[[ -f "$CONFIG_FILE" ]] && config_exists=true
rx_setup_check_needed "$config_exists" && return 0  # Exit early if --needed and configured
```

### Alternative Flow: Manual Reconfigure Prompt

`cmds/tools/xdg.sh` uses a manual pattern instead of `rx_setup_prompt_reconfigure` when the tool needs more control over the reconfigure prompt. It shows the current config with `rx_setup_current` and asks explicitly with `rx_confirm`:

```bash
if [[ $config_exists == true ]]; then
    rx_setup_current "Icon" "Current Default Applications" \
        "Editor" "$cur_editor" \
        "Browser" "$detected_browser" \
        "File Manager" "$cur_fm" \
        "Image Viewer" "$detected_image" \
        "Video Player" "$detected_video" || true

    if ! rx_confirm "Reconfigure?" "N"; then
        rx_log "info" "Setup cancelled."
        return 0
    fi
fi
```

This pattern gives you more control over the message and default answer compared to `rx_setup_prompt_reconfigure`.

### Best Practices for New Tools

When adding a `setup` subcommand to a new tool:

1. **Always source `lib/setup.sh`** at the top of your command file.
2. **Use `rx_setup_parse "$@"` as the first setup call** — it strips `-o` and `--needed` from `$@` and populates globals.
3. **Declare all valid keys** in `rx_setup_validate` — this documents your options and rejects typos automatically.
4. **Add validation rules** for non-optional fields and type constraints (use `required` for must-have options).
5. **Always call `rx_setup_check_needed`** before collecting values — this gives `--needed` behavior for free.
6. **Branch on `$RX_SETUP_MODE`** — use `rx_setup_get_opt` for non-interactive, `rx_input*` / `rx_confirm` / `rx_menu` for interactive.
7. **Always show `rx_setup_summary` + `rx_setup_confirm`** — users must see what will be applied before it happens.
8. **Always end with `rx_setup_success`** on success or `rx_log "error"` on failure — consistent UX.
9. **Keep apply logic identical for both modes** — don't branch on `RX_SETUP_MODE` in the apply step.
10. **Test both modes** — run `retro tool setup` (interactive) and `retro tool setup -o key=val` (non-interactive) before committing.

---
## 13. Module System 🧩

### Module Structure

```
modules/<name>/
├── properties.json   # Module metadata (required)
├── packages.sh       # List of packages to install (one per line)
├── install.sh        # Custom installation logic (optional)
├── uninstall.sh      # Custom uninstallation logic (optional)
├── pre.sh            # Pre-installation hook (optional)
├── post.sh           # Post-installation hook (optional)
└── files/            # Configuration files to link/copy
```

### properties.json Format

> [!NOTE]
> **Why properties.json:** The module system reads this file to determine how to install, where to place files, and whether to symlink or copy.
>
> **Why this matters:** Without it, the module is invisible to `retro -ls/--list` and other module commands. The `type: "core"` field prevents accidental uninstallation of essential desktop environment components. This metadata file is the contract between your module and the module system.
```json
{
    "title": "Module Name",
    "description": "Brief description",
    "type": "core",
    "access": "user",
    "defaults": true,
    "mode": "install",
    "config": "~/.config/name",
    "overwrite": false
}
```

- `title`: Display name for the module
- `description`: Brief description shown in module list
- `type`: `core` (cannot uninstall) or `extra`
- `access`: `user` or `root` (root modules auto-elevate via sudo)
- `defaults`: Whether to install by default
- `mode`: `install` (symlink), `mirror` (copy), or `all`
- `config`: Target config path
- `overwrite`: Whether to overwrite existing files

### Module Commands

- `-i, --install <name>` — Install module configs as symlinks, rice via retro CLI vars
- `-ls, --list` — Browse all repo modules with install status
- `-m, --mirror <name>` — Copy module configs as physical files, full custom freedom
- `-p, --pull <name>` — Capture live system config changes back into repo modules for version tracking
- `-r, --remove <name>` — Remove module configs from system and restore previous backup files

---
## 14. Variable System 🔧

### Storage

Variables are stored in `$RETRO_CONFIG/variables.sh` (typically `~/.config/retro/variables.sh`).

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
## 15. Dependency Management 📦

### check_dep Function

> [!TIP]
> **Why check_dep:** Rather than failing mid-operation when a missing command is called, `check_dep` validates all dependencies upfront.
>
> **Why this matters:** This prevents partial state changes and gives users a clear path to resolution. If a script starts modifying files before discovering a missing dependency, the system could be left in a broken state. Validating everything first ensures atomic operations.
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
## 16. Daemon System 🖥️ (Lua Background Daemon)

### Overview

> [!NOTE]
> **Why Lua for the daemon:** Lua is lightweight, embeddable, and has excellent coroutine support for cooperative multitasking.
>
> **Why this matters:** Unlike shell, Lua can run multiple watchers concurrently without spawning subprocesses. Unlike Python, it has a tiny memory footprint — critical for a background process that runs 24/7. The coroutine-based engine means watchers yield control voluntarily, preventing any single watcher from blocking the entire daemon.
The **Daemon System** is a background daemon written in **Lua** that continuously monitors system state and fires events when conditions change. It uses a **coroutine-based engine** (`daemon/engine.lua`) that dynamically loads watchers and event handlers from `daemon/watchers/` and `daemon/events/`.

### File Structure

| File | Purpose |
|------|---------|
| `daemon/engine.lua` | Core engine - loads watchers, dispatches events via coroutines |
| `daemon/event_daemon.lua` | CLI interface - start/stop/status/trigger/list/log |
| `daemon/watcher.lua` | Shared watcher utilities - variable persistence, logging, sysfs reading |
| `daemon/watchers/*.lua` | Watcher modules (battery, bluetooth, power, usb, audio, wallpaper, portal, slideshow, timers) |
| `daemon/events/*.lua` | Event handler modules (battery, power, notifications, wallpaper) |
| `cmds/tools/event.sh` | Frontend command to manage the daemon |

### Architecture

The daemon uses **Lua coroutines** for cooperative multitasking. The engine (`engine.lua`) is a class-based system:

```lua
local Engine = require("engine")
local engine = Engine.new(daemon_dir)

-- Core methods:
engine:load_watchers()          -- Dynamically loads *.lua from watchers/
engine:load_event_handlers()    -- Dynamically loads *.lua from events/
engine:emit(event_name, ...)    -- Fire event to all handlers (async)
engine:emit_sync(event_name, ...) -- Fire event to all handlers (sync)
engine:run_loop()               -- Main coroutine scheduler loop
engine:trigger(event_name, ...) -- Manually fire an event
```

### How It Works

1. **Engine** (`daemon/engine.lua`):
   - Dynamically discovers `*.lua` files in `watchers/` and `events/`
   - Creates a coroutine for each watcher via `coroutine.create()`
   - Schedules watchers based on their `interval` property
   - Dispatches events via `engine:emit()` to registered handlers
   - Crash isolation: per-watcher crash counter, auto-disable after 3 crashes

2. **Watchers** (`daemon/watchers/*.lua`):
   - Export a module with `start(engine)` function and optional `interval` and `enabled()`
   - Call `engine:emit("event_name", args...)` to fire events
   - Use `Watcher` utilities from `daemon/watcher.lua` for common operations

3. **Event Handlers** (`daemon/events/*.lua`):
   - Export a table mapping event names to handler functions
   - Run in the same coroutine context (pcall-wrapped for safety)

4. **Event Commands**:
   - `retro daemon start` - Start the daemon in background
   - `retro daemon loop` - Internal: run the event loop (called by start)
   - `retro daemon stop` - Stop the daemon via stop file signal
   - `retro daemon status` - Show daemon PID and uptime
   - `retro daemon trigger <name>` - Manually fire an event
   - `retro daemon list` - List available watchers
   - `retro daemon log [name]` - View watcher logs
   - `retro daemon log true/false` - Enable/disable log generation
   - `retro daemon log limit <name> <lines>` - Set log line cap

### Available Watchers

| Watcher | File | Purpose |
|---------|------|---------|
| Battery | `watchers/battery.lua` | Battery capacity, saver mode, low/critical thresholds |
| Power | `watchers/power.lua` | AC power connect/disconnect detection |
| Bluetooth | `watchers/bluetooth.lua` | Device pairing/connection/disconnection |
| USB | `watchers/usb.lua` | USB device connect/disconnect |
| Audio | `watchers/audio.lua` | Audio device changes |
| Wallpaper | `watchers/wallpaper.lua` | Wallpaper slideshow tick |
| Portal | `watchers/portal.lua` | XDG portal monitoring |
| Slideshow | `watchers/slideshow.lua` | Slideshow timing |
| Timers | `watchers/timers.lua` | Package/Retro update checks |

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

### Creating a New Watcher (Lua)

```lua
-- daemon/watchers/mytemp.lua
local Watcher = require("watcher")

local M = {}
M.name = "mytemp"
M.interval = 30  -- seconds between checks

function M.enabled()
    -- Optional: return false to skip loading this watcher
    return true
end

function M.start(engine)
    while true do
        local temp = Watcher.read_sys("/sys/class/thermal/thermal_zone0/temp")
        local temp_c = math.floor(temp / 1000)

        if temp_c >= 80 then
            engine:emit("on_temperature_critical", temp_c)
        elseif temp_c >= 70 then
            engine:emit("on_temperature_high", temp_c)
        end

        coroutine.yield()  -- REQUIRED: must yield to avoid blocking the scheduler
    end
end

return M
```

2. The engine automatically discovers and runs it:
   - Module must export `start(engine)` function
   - Set `M.name` for unique identifier
   - Set `M.interval` for check frequency (default: 15s)
   - `M.enabled()` to conditionally load (required)
   - Wrap logic in `while true do ... end` loop
   - `coroutine.yield()` must be called inside the loop

> [!WARNING]
> **Critical:** Watcher functions MUST use `while true do` loops. Without it, the coroutine runs once, yields, then enters a 'dead' state on the next resume (function body ends). The scheduler cannot revive dead coroutines — the watcher will run exactly once then break silently.

> [!TIP]
> **Tip:** Do NOT use `os.execute("sleep ...")` — use `Watcher.sleep(seconds)` or `coroutine.yield()` instead.
>
> **Why this matters:** The daemon uses cooperative multitasking via coroutines. `os.execute("sleep")` blocks the entire Lua process, freezing all watchers and event handlers. `Watcher.sleep()` and `coroutine.yield()` yield control back to the engine so other watchers can run.
### Watcher Utility Module

| Function | Purpose |
|----------|---------|
| `Watcher.get_var(key, default)` | Read persistent variable (auto-reloads on file change) |
| `Watcher.set_var(key, value)` | Write persistent variable to `$RETRO_CONFIG/variables.sh` |
| `Watcher.reload_vars()` | Force reload variables from file |
| `Watcher.run_cmd(cmd)` | Execute shell command, return trimmed stdout |
| `Watcher.read_sys(path)` | Read a sysfs file (returns empty string on failure) |
| `Watcher.has_battery()` | Check if system has a battery (caches BAT_PATH) |
| `Watcher.has_bluetooth()` | Check if Bluetooth is powered on |
| `Watcher.parse_pipe(line)` | Split pipe-delimited string into table |
| `Watcher.time()` | Current Unix timestamp (`os.time()`) |
| `Watcher.sleep(seconds)` | Sleep for N seconds |
| `Watcher.log(name, msg)` | Write to watcher log file (respects caps and enabled flag) |
| `Watcher.tail_log(name, limit)` | Read last N lines from watcher log |
| `Watcher.clear_log(name)` | Truncate watcher log file |
| `Watcher.list_logs()` | List all watcher log files |
| `Watcher.get_log_path(name)` | Get log file path for a watcher |
| `Watcher.get_log_cap(name)` | Get log line cap (default: 100) |
| `Watcher.set_log_cap(name, cap)` | Set log line cap |
| `Watcher.is_log_enabled()` | Check if log generation is globally enabled |
| `Watcher.set_log_enabled(enabled)` | Enable/disable log generation |
| `Watcher.is_log_disabled(name)` | Check if a specific watcher log is disabled |

### Variable Persistence in Watchers

Watchers use `Watcher.get_var()`/`Watcher.set_var()` for persistent state across restarts. The variables file is auto-reloaded on mtime change:

```lua
local Watcher = require("watcher")

function M.start(engine)
    local bat_saver = Watcher.get_var("BAT_SAVER_ACTIVE", "false")
    -- ... logic ...
    Watcher.set_var("BAT_LAST_NOTIFIED", "20")
end
```

### Crash Isolation

> [!TIP]
> **Why crash isolation:** A buggy watcher shouldn't take down the entire daemon.
>
> **Why this matters:** With per-watcher crash tracking, a watcher that errors 3 times in a row gets auto-disabled while others continue running. The disabled state persists across restarts so the daemon doesn't keep crashing on boot. Check `` `watcher_<name>.disabled` `` in `/tmp/retro_logs/` to see if a watcher was auto-disabled. This ensures one broken feature doesn't break the entire system.
Each watcher runs in its own coroutine with independent crash tracking:
- Crash count tracked per-watcher
- After 3 crashes, the watcher is auto-disabled
- Log written to `/tmp/retro_logs/watcher_<name>.log`
- Disabled state persisted via `/tmp/retro_logs/watcher_<name>.disabled`
- Other watchers continue unaffected

### Log Management

- Enable/disable: `retro daemon log true/false`
- View: `retro daemon log <name> [limit]`
- Set cap: `retro daemon log limit <name> <lines>` (minimum 10)
- List all: `retro daemon log`

### Adding a New Event Handler

```lua
-- daemon/events/my_hooks.lua
local Log = require("log")
local Colors = require("colors")

local M = {}

function M.on_power_disconnect(capacity)
    Log.info("Power disconnected at " .. Colors.PINK .. capacity .. "%" .. Colors.RESET)
end

function M.on_battery_low(cap)
    -- Trigger a desktop notification
    os.execute(string.format('notify-send "Battery Low" "Only %s%% remaining"', cap))
end

return M
```

2. The module exports a table where keys are event names and values are handler functions:
   - `on_power_disconnect` → fires when AC power removed
   - `on_battery_low` → fires when battery below threshold

3. **Rules**:
   - Must declare `local M = {}` (or `local Events = {}`)
   - Must `return M` (or `return Events`)
   - All handler functions **MUST** start with `on_` prefix

### Important Notes

> [!NOTE]
> **Why these details matter:**
>
> **Why this matters:** Understanding the daemon's architecture prevents common mistakes. Coroutines are cooperative — if one watcher doesn't yield, everything stops. The `pcall` wrapper means event handler errors won't crash the daemon, but they also won't be visible unless you check logs.
>
> - Watchers run in **coroutines** — cooperative multitasking, not OS threads
> - Event handlers run in the same context, wrapped in `pcall` for safety
> - Use `Watcher.get_var()`/`Watcher.set_var()` for persistent state
> - Watchers must yield via `coroutine.yield()` to avoid blocking
> - The daemon auto-starts on login (via `retro load`)
> - PID stored in `/tmp/retro_event_daemon.pid`
> - Stop signal via `/tmp/retro_event_daemon_stop` file
---
## 17. Walkthrough: Adding a New Tool 🛠️

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
            rx_help_cmd "status" "Show all thermal zones" 20
            rx_help_cmd "current" "Show current CPU temp" 20
            rx_help_examples
            rx_help_example "retro temperature status" "Show all thermal zones" 30
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
## 18. Best Practices and Gotchas ✅

### Do

- Use `rx_log` for all user-facing messages in frontend scripts
- Use `rx_log_file` for persistent log files in core scripts and daemon engines
- Register a log source with `rx_log_register` before using `rx_log_file`
- Keep core scripts purely functional (no side effects, no user output)
- Use pipe-delimited output for structured data
- Handle `-y/--yes` flag by checking `$SKIP_PROMPT`
- Use icons consistently from the Nerd Font set
- Check existing lib functions before writing new ones
- Keep Lua library functions 1:1 with their shell equivalents
- Use `require("module")` for Lua imports, not `dofile()`
- Keep Python library functions 1:1 with their shell equivalents
- Use `from lib.python.x import ...` for Python imports
- Use `ensure_dbus()` before any DBus operations in Python

### Don't

- Don't put `rx_log` in core scripts — use `rx_log_file` instead
- Don't use `echo` for user messages in core scripts
- Don't use `rx_log_file` in frontend commands — use `rx_log` instead
- Don't duplicate existing library functions
- Don't skip the two-layer pattern (even for simple tools)
- Don't use TODO comments - either do it or don't
- Don't hardcode paths - use `$RETRO_DIR` and `$HOME`
- Don't make Lua functions behave differently than their shell counterparts
- Don't add custom logic to Lua ports that changes output format
- Don't make Python functions behave differently than their shell counterparts
- Don't use Python's `print()` directly for user output — use `lib.python.log`
- Don't store Python variables in a different file than `$RETRO_CONFIG/variables.sh`

### Core Script Logging Rule

> [!WARNING]
> **Required:** Every core script (`scripts/*_core.sh`) and daemon engine **MUST** register a log entry.
>
> **Why this matters:** Without registration, `rx_log_file` has nowhere to write. The log file won't be created, and debugging becomes impossible. The registration step creates the file in `/tmp/retro_logs/` and marks it as an active log source visible to `retro log list`.
```bash
#!/bin/bash
# scripts/my_core.sh

source "$RETRO_DIR/scripts/log_core.sh"
rx_log_register "my_core"

case "$1" in
    --status)
        rx_log_file "info" "Status check requested"
        # ... logic ...
        rx_log_file "success" "Status check complete"
        ;;
esac
```

### Core Script Output Rule

> [!WARNING]
> **Required:** Core scripts must produce **only machine-parseable output** (pipe-delimited). No user-facing messages.
>
> **Why this matters:** The frontend parses core script output using `IFS='|' read`. Any extra text (like `echo "Success"`) becomes a malformed line that breaks the parser. Human-readable messages belong in the frontend, which uses `rx_log` for colored, formatted output.
>
> - No `rx_log` calls
> - No `echo "Success"`, `echo "Error"`, `echo "Warning"`
> - Only raw data: `echo "key=value"`, `echo "field1|field2|field3"`
### Lua Watcher Structure Rules

> [!WARNING]
> **Required:** Every watcher in `daemon/watchers/*.lua` **MUST** follow this structure.
>
> **Why this matters:** The engine discovers watchers by scanning for `*.lua` files and expects specific fields. Missing `M.name` means no log source. Missing `M.interval` means the engine doesn't know when to schedule it. Missing `M.enabled()` causes a nil error on load. Missing `coroutine.yield()` blocks the entire daemon loop.
```lua
local Watcher = require("watcher")

local M = {}
M.name = "my_watcher"
M.interval = 30  -- seconds between checks

function M.enabled()
    return true  -- or check a condition
end

function M.start(engine)
    -- ... watcher logic ...
    engine:emit("on_my_event", data)
    coroutine.yield()  -- REQUIRED: must yield to avoid blocking
end

return M
```

> [!NOTE]
> **Required fields:**
>
> - `M.name` — unique watcher identifier
> - `M.interval` — check frequency in seconds
> - `M.enabled()` — function that returns true/false
> - `M.start(engine)` — main watcher logic
>
>
> **Why this matters:** The engine discovers watchers by scanning for `*.lua` files and expects these specific fields. Missing `M.name` means no log source. Missing `M.interval` means the engine doesn't know when to schedule it. Missing `M.enabled()` causes a nil error on load. Missing `coroutine.yield()` blocks the entire daemon loop.
### Lua Event Handler Structure Rules

> [!WARNING]
> **Required:** Every event file in `daemon/events/*.lua` **MUST** follow this structure.
>
> **Why this matters:** The engine matches emitted event names to handler function names. If your function doesn't start with `on_`, it won't be recognized as an event handler. The `on_` prefix is enforced by the test suite (`tests/event_naming_test.sh`) and ensures consistency across all event files.
```lua
local M = {}

function M.on_event_name(arg1, arg2)
    -- handler logic
end

return M
```

> [!NOTE]
> **Why these details matter:**
>
> **Why this matters:** Understanding the daemon's architecture prevents common mistakes. Coroutines are cooperative — if one watcher doesn't yield, everything stops. The `pcall` wrapper means event handler errors won't crash the daemon, but they also won't be visible unless you check logs. The auto-start on login means any syntax error in a watcher will prevent the daemon from starting at all.
>
> - Watchers run in **coroutines** — cooperative multitasking, not OS threads
> - Event handlers run in the same context, wrapped in `pcall` for safety
> - Use `Watcher.get_var()`/`Watcher.set_var()` for persistent state
> - Watchers must yield via `coroutine.yield()` to avoid blocking
> - The daemon auto-starts on login (via `retro load`)
> - PID stored in `/tmp/retro_event_daemon.pid`
> - Stop signal via `/tmp/retro_event_daemon_stop` file
### Common Gotchas

2. **Lowercase actions**: Always use `${action,,}` to lowercase user input for consistent case handling.

3. **Array handling**: Use `local arr=()` for local arrays to avoid polluting global state.

4. **Exit codes**: Core scripts should return 0 on success, 1 for failure. Frontend handles the messaging.

5. **Icon padding**: Always use `${PINK}icon${RESET}` pattern, never plain icon alone.

6. **rx_log vs rx_log_file**: `rx_log` = console output (frontend only), `rx_log_file` = file output (core/daemon only). Never mix them.

7. **Log registration**: Every core script must call `rx_log_register` before any `rx_log_file` calls.

### <kbd>Ctrl</kbd> + <kbd>C</kbd> Trap (Graceful Exits)

> [!WARNING]
> **Why traps matter:** Without a trap, a user pressing Ctrl + C mid-installation leaves the system in an unpredictable state.
>
> **Why this matters:** Packages half-installed, files partially moved, symlinks broken — these are hard to debug and harder to recover from. The trap ensures cleanup runs regardless of how the script exits, leaving the system in a known state.
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
## 19. Installer System 💾 (bin/)

> [!NOTE]
> **Why a separate installer system:** The installer (`bin/`) is isolated from the main tool system (`cmds/`, `scripts/`) because it runs in a fundamentally different environment.
>
> **Why this matters:** During Arch Linux installation, before the target system is bootable, the installer has its own libraries (`bin/lib/`), its own state management (`/tmp/retroinstall_state`), and its own error handling (QR codes for offline debugging). This separation prevents installer code from leaking into the runtime system and keeps the two environments completely isolated.
The Installer is a self-contained system that runs during initial system setup. It follows a **modular setup flow architecture**:

```
┌─────────────────────────────────────────────────────────────┐
│  retroinstall (parent process)                              │
│  - Holds all state variables                                │
│  - Exports RETRO_STATE="/tmp/retroinstall_state"            │
│  - Calls rx_load_state before each step                     │
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
│  - Exits with success/failure code                          │
└─────────────────────────────────────────────────────────────┘
                               │
                               ▼ sources
┌─────────────────────────────────────────────────────────────┐
│  UTILITIES (bin/lib/*)                                      │
│  - Pure functions, no orchestration                         │
│  - crypto, display, errors, gum, wifi, locale, timezone,    │
│    disk, handlers, output, debug, progress, qr, setup_lib,  │
│    setup                                                    │
└─────────────────────────────────────────────────────────────┘
```

### Directory Structure 📂

<details>
  <summary>📂 Click to view the full installer directory structure</summary>
  <br>

```
bin/
├── retroinstall              # Main entry point (317 lines)
├── lib/                      # Low-level utilities (15 files)
│   ├── crypto.sh            # rx_hash_password (yescrypt via Python/archinstall)
│   ├── debug.sh             # rx_debug conditional output
│   ├── disk.sh              # rx_get_disk_info, rx_get_available_disks, rx_write_configuration
│   ├── display.sh           # Terminal sizing, logo rendering, GUM styles, padding system
│   ├── errors.sh            # rx_retry_or_exit, rx_step_error, rx_abort
│   ├── gum.sh               # rx_notice (gum spin wrapper)
│   ├── handlers.sh          # rx_setup_traps, rx_catch_errors, rx_save_state, rx_load_state
│   ├── locale.sh            # Keyboard/layout names, LOCALE_LANG_NAMES, KEYBOARD_LAYOUT_NAMES
│   ├── output.sh            # rx_start_log_output, rx_start_install_log, rx_run_logged
│   ├── progress.sh          # rx_step progress tracking [n/total]
│   ├── qr.sh                # rx_generate_error_qr, rx_gather_system_info
│   ├── setup_lib.sh         # Shared sourcing hub, rx_setup_fail
│   ├── setup.sh             # rx_chrootable_systemctl_enable wrapper
│   ├── timezone.sh          # rx_list_timezones, rx_get_current_timezone
│   └── wifi.sh              # WiFi setup functions (iwctl based), rx_check_internet
├── setup/                    # Modular setup step scripts (24 scripts)
│   ├── install.sh           # Installation type: complete vs minimal
│   ├── ricing.sh            # Ricing mode: stable (symlink) vs advanced (copy)
│   ├── user.sh              # Username, user password, sudo access
│   ├── root.sh              # Root password
│   ├── hostname.sh          # Machine hostname
│   ├── display.sh           # Display resolution detection
│   ├── keyboard.sh          # Keyboard layout selection
│   ├── locale.sh            # System language selection
│   ├── mirrors.sh           # Mirror region and custom mirror URL
│   ├── timezone.sh          # Timezone selection via timedatectl
│   ├── disk.sh              # Disk selection, wipe confirmation, returns 42 on go-back
│   ├── luks.sh              # LUKS encryption enable/password/iteration time
│   ├── kernel.sh            # Kernel selection (linux, linux-lts, linux-zen, linux-hardened)
│   ├── boot.sh              # Bootloader config (GRUB theme, resolution, OS prober)
│   ├── bluetooth.sh         # Bluetooth service enable toggle
│   ├── fingerprint.sh       # Fingerprint authentication setup
│   ├── print.sh             # CUPS printing service enable toggle
│   ├── ssh.sh               # SSH service configuration (port, auth methods)
│   ├── aur.sh               # AUR helper selection (yay/paru)
│   ├── editor.sh            # Default editor selection
│   ├── filemanager.sh       # Default file manager selection
│   ├── browser.sh           # Default browser selection
│   ├── network.sh           # Network connectivity check and WiFi/Ethernet setup
│   └── config.sh            # Write user_configuration.json and user_credentials.json
└── post/                     # Post-install scripts (run in chroot after archinstall)
    └── run.sh               # Post-install orchestrator
```

</details>

### SETUP_SCRIPTS Array (exact order)

<details>
  <summary>📦 Click to view the exact installer script execution order</summary>
  <br>

```bash
SETUP_SCRIPTS=(
    "install.sh"      # index 0  - Installation type (complete/minimal)
    "ricing.sh"       # index 1  - Ricing mode (stable/advanced)
    "user.sh"         # index 2  - Username, password, sudo
    "root.sh"         # index 3  - Root password
    "hostname.sh"     # index 4  - Machine hostname
    "display.sh"      # index 5  - Display resolution detection
    "keyboard.sh"     # index 6  - Keyboard layout
    "locale.sh"       # index 7  - System language
    "mirrors.sh"      # index 8  - Mirror selection
    "timezone.sh"     # index 9  - Timezone
    "disk.sh"         # index 10 - Disk selection (go-back point, exit 42)
    "luks.sh"         # index 11 - LUKS encryption
    "kernel.sh"       # index 12 - Kernel selection
    "boot.sh"         # index 13 - Bootloader configuration
    "bluetooth.sh"    # index 14 - Bluetooth toggle
    "fingerprint.sh"  # index 15 - Fingerprint auth
    "print.sh"        # index 16 - Printing service
    "ssh.sh"          # index 17 - SSH configuration
    "aur.sh"          # index 18 - AUR helper
    "editor.sh"       # index 19 - Editor choice
    "filemanager.sh"  # index 20 - File manager choice
    "browser.sh"      # index 21 - Browser choice
    "network.sh"      # index 22 - Network setup
    "config.sh"       # index 23 - Generate JSON configs
)
```

</details>

### Setup Flow 🔄

```bash
rx_run_step() {
    local script="$1"
    local step_index=$2

    # Skip if step_index <= RX_SKIP_STEP
    if [[ -n $RX_SKIP_STEP && $step_index -le $RX_SKIP_STEP ]]; then
        return 0
    fi

    rx_clear_logo
    rx_load_state                    # Reload state before running step
    /opt/retrolinux/bin/setup/"$script"  # Execute setup script
    local exit_code=$?
    rx_load_state                    # Reload state after step

    # Exit code 42 = go back (skip to disk.sh at index 10, then restart)
    if [[ $exit_code -eq 42 ]]; then
        RX_SKIP_STEP=9
        rx_save_state
        exec /opt/retrolinux/bin/retroinstall  # Restart installer
    elif [[ $exit_code -ne 0 ]]; then
        rx_show_error_and_qr "$exit_code"
    fi
}
```

**Main loop** (retroinstall lines 135-137):
```bash
for i in "${!SETUP_SCRIPTS[@]}"; do
    rx_run_step "${SETUP_SCRIPTS[$i]}" "$i"
done
```

**Return codes:**
- `0` = success, proceed to next step
- `42` = go back (disk.sh returns 42 when user declines wipe confirmation)
- `non-zero, not 42` = error, show error QR and offer retry

**Go-back mechanism:**
- `disk.sh` returns exit code `42` when user declines disk wipe confirmation
- On `42`: Sets `RX_SKIP_STEP=9`, saves state, restarts installer via `exec`
- The installer loops, skipping steps 0-9, resumes from `disk.sh` (index 10)

### State Management 🔐 (CRITICAL)

> [!WARNING]
> **Critical:** Setup scripts run as subprocesses of `retroinstall`. Because subprocesses cannot share variables with their parent, all state is persisted to `/tmp/retroinstall_state` (exported as `$RETRO_STATE`).
>
> **Why this matters:** The installer uses `exec` to restart itself on "go back" (exit code 42). This means the entire process is replaced — no parent process exists to hold state. The file-based state system survives process restarts and enables the go-back mechanism. Without it, going back to disk selection would lose all previously entered values.
**State Functions** (defined in `bin/lib/handlers.sh`):

| Function | Purpose |
|----------|---------|
| `rx_save_state` | Writes all state variables to `$RETRO_STATE` |
| `rx_load_state` | Sources `$RETRO_STATE` if it exists |

**All state variables saved to `$RETRO_STATE`:**
```bash
# Installation type
INSTALL_TYPE          # "complete" or "minimal"
RICE_MODE             # "stable" (symlink) or "advanced" (copy)

# User credentials
USER_NAME             # Username
USER_PASSWORD         # Plain text user password
USER_PASSWORD_HASH    # Yescrypt hash of user password (via bin/lib/crypto.sh)
USER_SUDO             # "true" or "false"

# System configuration
USER_HOSTNAME         # hostname
KEYBOARD              # Keyboard layout code (e.g., "us")
SYS_LANG              # System language (e.g., "en_US")
SYS_ENC               # System encoding (e.g., "UTF-8")
USER_TIMEZONE         # timezone (e.g., "America/New_York")
MIRROR_REGIONS        # Mirror regions (space-separated)
CUSTOM_MIRRORS        # Custom mirror URL

# Hardware
DISK_SELECTED         # Selected disk device (e.g., "/dev/sda")
DISPLAY_RES_X         # Display width (e.g., "1920")
DISPLAY_RES_Y         # Display height (e.g., "1080")
DISPLAY_ASPECT_RATIO  # Display aspect ratio (e.g., "16:9")

# Security
LUKS_ENABLED          # "true" or "false"
LUKS_PASSWORD         # Plain text LUKS encryption password
LUKS_ITER_TIME        # LUKS iteration time in ms (e.g., 2000)
FINGERPRINT_ENABLED   # "true" or "false"

# Services
BLUETOOTH_ENABLED     # "true" or "false"
PRINT_SERVICE_ENABLED # "true" or "false"
SSH_ENABLED           # "true" or "false"
SSH_PORT              # SSH port (default: 22)
SSH_PASSWORD_LOGIN    # "true" or "false"
SSH_KEY_LOGIN         # "true" or "false"
SSH_ROOT_LOGIN        # "true" or "false"

# Software choices
KERNEL_SELECTION      # Kernel package (e.g., "linux", "linux-lts")
AUR_HELPER            # AUR helper ("yay" or "paru")
EDITOR_CHOICE         # Default editor
FILEMANAGER_CHOICE    # Default file manager
BROWSER_CHOICE        # Default browser

# Bootloader
GRUB_THEME_CHOICE     # "retropunk" or "retrolinux"
BOOT_VIDEO_GRUB       # GRUB resolution (e.g., "1920x1080")
GRUB_OS_PROBER        # "true" or "false"

# Network
NETWORK_TYPE          # "WiFi" or "Ethernet"
WIFI_SSID             # WiFi SSID if connected via WiFi

# Root
ROOT_PASSWORD         # Plain text root password
ROOT_PASSWORD_HASH    # Yescrypt hash of root password (via bin/lib/crypto.sh)

# Flow control
RX_SKIP_STEP          # Step index to skip to (used for "go back")
RX_GO_BACK_TO         # Name of step to go back to
```

**Password hashing**: Uses **yescrypt** via `bin/lib/crypto.sh` (`rx_hash_password`), which calls Python's `archinstall.lib.crypt.crypt_yescrypt`. This replaced the old SHA-512 (`openssl passwd -6`) method.

> [!TIP]
> **Why yescrypt over SHA-512:** Yescrypt is a memory-hard password hashing function designed to resist GPU and ASIC-based attacks.
>
> **Why this matters:** SHA-512 is fast, which makes it vulnerable to brute-force attacks on modern hardware. Yescrypt's configurable iteration time (stored as `LUKS_ITER_TIME`) lets users balance security vs. boot time. This is critical for full-disk encryption where password strength directly determines data security.
**Setup Scripts and Their Variables**:

| Step | Script | Variables Set |
|------|--------|---------------|
| 0 | `install.sh` | `INSTALL_TYPE` |
| 1 | `ricing.sh` | `RICE_MODE` |
| 2 | `user.sh` | `USER_NAME`, `USER_PASSWORD`, `USER_PASSWORD_HASH`, `USER_SUDO` |
| 3 | `root.sh` | `ROOT_PASSWORD`, `ROOT_PASSWORD_HASH` |
| 4 | `hostname.sh` | `USER_HOSTNAME` |
| 5 | `display.sh` | `DISPLAY_RES_X`, `DISPLAY_RES_Y`, `DISPLAY_ASPECT_RATIO` |
| 6 | `keyboard.sh` | `KEYBOARD` |
| 7 | `locale.sh` | `SYS_LANG`, `SYS_ENC` |
| 8 | `mirrors.sh` | `MIRROR_REGIONS`, `CUSTOM_MIRRORS` |
| 9 | `timezone.sh` | `USER_TIMEZONE` |
| 10 | `disk.sh` | `DISK_SELECTED`, `RX_GO_BACK_TO`; returns 42 on decline |
| 11 | `luks.sh` | `LUKS_ENABLED`, `LUKS_PASSWORD`, `LUKS_ITER_TIME` |
| 12 | `kernel.sh` | `KERNEL_SELECTION` |
| 13 | `boot.sh` | `GRUB_THEME_CHOICE`, `BOOT_VIDEO_GRUB`, `GRUB_OS_PROBER` |
| 14 | `bluetooth.sh` | `BLUETOOTH_ENABLED` |
| 15 | `fingerprint.sh` | `FINGERPRINT_ENABLED` |
| 16 | `print.sh` | `PRINT_SERVICE_ENABLED` |
| 17 | `ssh.sh` | `SSH_ENABLED`, `SSH_PORT`, `SSH_PASSWORD_LOGIN`, `SSH_KEY_LOGIN`, `SSH_ROOT_LOGIN` |
| 18 | `aur.sh` | `AUR_HELPER` |
| 19 | `editor.sh` | `EDITOR_CHOICE` |
| 20 | `filemanager.sh` | `FILEMANAGER_CHOICE` |
| 21 | `browser.sh` | `BROWSER_CHOICE` |
| 22 | `network.sh` | `NETWORK_TYPE`, `WIFI_SSID` |
| 23 | `config.sh` | Writes JSON files (no state variables) |

### rx_install_system Function 🔧

1. **Display summary table** with all configured values via `gum table`: install type, username, passwords (masked as dots), hostname, display resolution, sudo access, keyboard, language, mirrors, timezone, disk, LUKS status, kernel, bootloader (theme + resolution + OS prober), bluetooth, printing, SSH (port + auth flags), AUR helper, editor, file manager, browser, network
2. **Ask for confirmation** via `gum confirm` to proceed with installation
3. **Run archinstall** with JSON config files and `--silent --skip-ntp --skip-wkd --skip-wifi-check`
4. **On failure**: Show error QR code, offer retry
5. **On success**: Run post-install (`bin/post/run.sh`), display message about first-boot configuration, prompt to reboot

### User Input Patterns ⌨️

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

```bash
# In bin/lib/handlers.sh
trap rx_catch_errors ERR
trap 'rx_show_signal_info "SIGINT"' INT
trap 'rx_show_signal_info "SIGTERM"' TERM
trap rx_exit_handler EXIT
```

### QR Code Error Reporting

> [!TIP]
> **Why QR codes:** During installation, the system has no browser or easy way to copy-paste error details.
>
> **Why this matters:** A QR code encodes system specs, disk info, and the exit code into a scannable URL that opens a pre-filled GitHub issue. The user scans it with their phone and immediately has the right context for reporting the bug. This eliminates the frustrating "something went wrong but I can't tell anyone what" scenario during installation.
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
## 20. Quick Reference 📚

### File Locations

```
RetroLinux/
├── retro.sh                    # Entry point
├── lib/                        # Shared libraries
│   ├── colors.sh
│   ├── log.sh
│   ├── help.sh
│   ├── fs.sh
│   └── ...
├── lib/lua/                    # Lua libraries for daemon
│   ├── colors.lua
│   ├── help.lua
│   └── log.lua
├── lib/python/                 # Python libraries
│   ├── log.py
│   ├── env.py
│   └── obex.py
├── bin/                        # Installer system
│   ├── retroinstall            # Main entry point
│   ├── lib/                    # Low-level utilities
│   │   ├── display.sh
│   │   ├── handlers.sh
│   │   ├── crypto.sh
│   │   ├── wifi.sh
│   │   └── ...
│   ├── setup/                  # Setup step scripts (24)
│   │   ├── install.sh
│   │   ├── ricing.sh
│   │   ├── user.sh
│   │   ├── disk.sh
│   │   ├── config.sh
│   │   └── ...
│   └── post/                   # Post-install scripts
│       └── run.sh
├── scripts/                    # Backend core scripts
│   ├── audio_core.sh
│   ├── network_core.sh
│   ├── theme_core.sh
│   ├── grub_core.sh
│   └── ...
├── scripts/python/             # Python backend scripts
│   ├── bluetooth_receive.py
│   └── log_core.py
├── daemon/                     # Lua event daemon
│   ├── engine.lua
│   ├── event_daemon.lua
│   ├── watcher.lua
│   ├── watchers/               # Watcher modules
│   │   ├── battery.lua
│   │   ├── bluetooth.lua
│   │   └── ...
│   └── events/                 # Event handlers
│       ├── battery.lua
│       ├── power.lua
│       └── ...
├── cmds/tools/                 # Frontend commands
│   ├── audio.sh
│   ├── network.sh
│   ├── grub.sh
│   ├── xdg.sh
│   ├── power.sh
│   └── ...
├── cmds/system/                # System commands
│   ├── load.sh
│   ├── update.sh
│   ├── setup.sh
│   ├── help.sh
│   ├── about.sh
│   └── ...
├── cmds/modules/               # Module commands
│   ├── install.sh
│   ├── uninstall.sh
│   ├── mirror.sh
│   ├── pull.sh
│   └── list.sh
├── modules/                    # Desktop environment configs
│   ├── hyprland/
│   ├── ags/
│   └── ...
└── iso/                        # Live ISO build system
    ├── build.sh
    ├── Dockerfile
    └── profile/
```

### Key Patterns Summary 📋

| Pattern | Code |
|--------|------|
| Status header | `rx_table_header "icon" "Title"` |
| Table row | `rx_table_row "icon" "Label:" "Value" "$PINK" "26"` |
| Table row (gray) | `rx_table_row_gray "icon" "Label:" "Value" "26"` |
| Table separator | `rx_table_separator` + `rx_table_spacer` |
| Help usage | `rx_help_usage "retro tool <command>"` |
| Help command | `rx_help_cmd "cmd" "Description" 26` |
| Log (frontend) | `rx_log "success" "Message"` |
| Log (frontend error) | `rx_log "error" "Message" && return 1` |
| Log register (core) | `rx_log_register "my_core"` |
| Log file (core) | `rx_log_file "info" "Message"` |
| Register cmd | `register_command "TOOLS" "cmd|alias" "desc" "cmd_cmd"` |
| Event handler (Lua) | `M.on_event_name = function(...) ... end` in `daemon/events/*.lua` |
| Watcher (Lua) | `M.start(engine)` in `daemon/watchers/*.lua` |
| Emit event (Lua) | `engine:emit("event_name", args...)` |
| Lua log | `Log.info("message")` in `lib/lua/log.lua` |
| Lua table row | `Help.table_row("icon", "Label:", "Value", Colors.PINK, 26)` |
| Lua get/set var | `Watcher.get_var("KEY")` / `Watcher.set_var("KEY", "value")` |
| Lua run cmd | `Watcher.run_cmd("command")` |
| Lua require | `local Module = require("module")` |
| Lua yield | `coroutine.yield()` (required in watcher loops) |
| Lua sleep | `Watcher.sleep(seconds)` (NOT `os.execute("sleep")`) |
| Python log | `from lib.python.log import info, error` |
| Python log (file) | `from scripts.python.log_core import register, rx_log_file` |
| Python get/set var | `from lib.python.env import get_var, set_var` |
| Python run cmd | `run_shell_cmd("command", "--args", capture=True)` |
| Python import lib | `from lib.python.obex import BUS_NAME, run_shell_cmd` |
| Installer clear | `rx_clear_logo` in `bin/lib/display.sh` |
| Installer error | `rx_retry_or_exit "message"` in `bin/lib/errors.sh` |
| Setup script guard | `if ! setup_foo; then rx_setup_fail "Foo"; fi` |
| Run setup step | `/opt/retrolinux/bin/setup/network.sh` |
| Gum filter with style | `gum filter ... --padding "$GUM_FILTER_PADDING" "${GUM_FILTER_STYLE[@]}"` |
| Gum confirm with style | `gum confirm ... --padding "$GUM_CONFIRM_PADDING" $GUM_CONFIRM_STYLE` |
| Save state | `rx_save_state` (in `bin/lib/handlers.sh`) |
| Load state | `rx_load_state` (in `bin/lib/handlers.sh`) |
| Hash password | `rx_hash_password "$password"` (in `bin/lib/crypto.sh`, yescrypt) |
| Variable get/set | `get_var "KEY"` / `set_var "KEY" "value"` (in `lib/variable.sh`) |
| Log manage | `retro log <status|list|<name>|open|enable|disable|clear>` |

<br><br>
---
<div align="center">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Palm" width="35" style="vertical-align: middle; margin-right: 4px;">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="RetroLinux" width="180" style="vertical-align: middle; margin-right: 4px;">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Palm" width="35" style="vertical-align: middle;">
  
  <sub>© 2026 itsvlxd & Contributors • <a href="https://github.com/itsvlxd/RetroLinux/blob/develop/LICENSE">GPL-3.0 License</a> &nbsp;&nbsp;|&nbsp;&nbsp; <a href="https://github.com/itsvlxd/RetroLinux/blob/develop/CONTRIBUTING.md">🤝 Contributing</a> • <a href="https://github.com/itsvlxd/RetroLinux/issues">🐛 Issues</a> • <a href="https://github.com/itsvlxd/RetroLinux/pulls">🔧 Pulls</a></sub>
  <br>
  <sub><i>Licensed under the GNU General Public License v3.0. You are free to share, modify, and redistribute this documentation under the same copyleft terms, provided completely without warranty of any kind.</i></sub>
</div>
