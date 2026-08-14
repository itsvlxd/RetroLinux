<p align="center" style="vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="120" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="Logo" width="660" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="120" style="vertical-align: middle">
</p>

The **RetroLinux Installer** (`retroinstall`) is a guided, interactive TUI installer that walks you through 25 setup steps to configure a complete Arch-based Linux system. It uses `gum` for the terminal interface and generates configuration files for `archinstall` under the hood.

**What you get:**
- BTRFS filesystem with zstd compression and snapshots via Timeshift
- Hyprland desktop environment with SDDM greeter
- Optional LUKS disk encryption
- Bluetooth and printing service support
- PipeWire audio, nftables firewall, and more

---

## Getting Started

### How to Run

```bash
/opt/retrolinux/bin/retroinstall
```

**Requirements:**
- RetroLinux live environment (Arch Linux-based live USB)
- Internet connection (checked during network step)
- Minimum 2GB disk space
- UEFI boot recommended

> [!WARNING]
> The installer **erases the target disk** during step 10. Back up any important data before running. The installer also requires a working internet connection for package downloads and AUR support.

**Debug Mode:**
```bash
retroinstall --debug
```

> [!TIP]
> Use `--debug` to enable verbose output and press Enter between each step. Helpful for troubleshooting or understanding what the installer does under the hood.

> [!IMPORTANT]
> `retroinstall` runs **automatically** when you boot into the RetroLinux live ISO. It is strongly recommended **not to exit** the installer — all configuration and setup is handled from the live environment. If you do exit (e.g. with `Ctrl+C`), simply run `retroinstall` again to resume where you left off.

---

## Installation Stages

The installation happens in 3 stages:

| Stage | When | What |
|-------|------|------|
| **Stage 1: Live ISO Setup** | During live ISO booting | Runs `retroinstall` - 25 steps to configure system and run `archinstall` |
| **Stage 2: Live ISO Post-Install** | After archinstall completes | Runs automatically in chroot - configures boot, kernel modules, Plymouth |
| **Stage 3: Post-Install Setup** | First login inside installed OS | Runs automatically - configures modules, wallpaper, drivers, etc. |

### Stage 1 Scripts (bin/setup/)

```
setup/
├── install.sh         # Installation type selection (minimal/complete)
├── branch.sh          # Release branch (stable main / rolling develop)
├── ricing.sh          # Ricing mode (managed symlinks / manual copy)
├── user.sh          # User account creation
├── root.sh          # Root password setup
├── hostname.sh      # Computer hostname
├── keyboard.sh    # Keyboard layout
├── locale.sh     # System language
├── timezone.sh   # Timezone selection
├── display.sh      # Display server choice
├── disk.sh       # Target disk selection
├── luks.sh       # LUKS encryption
├── kernel.sh    # Kernel selection
├── boot.sh      # Bootloader setup
├── mirrors.sh    # Mirror configuration
├── network.sh  # Network configuration
├── bluetooth.sh # Bluetooth service
├── fingerprint.sh # Fingerprint authentication
├── print.sh     # CUPS printing service
├── ssh.sh       # OpenSSH service
├── aur.sh       # AUR support
├── editor.sh    # Terminal editor choice
├── filemanager.sh  # File manager choice
├── browser.sh   # Browser choice
└── config.sh   # Final validation and config generation
```

### Stage 2 Scripts (bin/post/)

```
post/
├── run.sh         # Main post-install runner (runs in chroot)
├── packages.sh    # Installs additional packages via pacman
├── network.sh     # Configures WiFi/Ethernet in chroot
├── aur.sh         # Installs AUR helper (yay/paru)
├── clone.sh       # Deploys RetroLinux repo + bootstraps first-boot autostart
└── state.sh       # Saves installation state to user home dir
```

> [!NOTE]
> **Stage 2 state persistence:** Installation choices are saved to `~/.retro_install` inside the installed system. This file is read by Stage 3 to apply the correct configuration on first boot.

### Stage 3 Scripts (cmds/system/setup/)

```
setup/
├── run.sh         # Main post-install runner
├── modules.sh     # Installs RetroLinux modules
├── network.sh    # Configures WiFi/Ethernet
├── xdg.sh       # XDG base directories
├── keyring.sh   # SSH/GPG keyring setup
├── terminal.sh  # Terminal emulator config
├── variables.sh # Environment variables
├── wallpaper.sh# Wallpaper setup
├── fonts.sh    # Font configuration
├── audio.sh    # Audio configuration
├── fingerprint.sh # Fingerprint auth setup
├── power.sh   # Power management
├── drivers.sh # GPU/firmware drivers
├── ricing.sh  # Rice mode (stable/advanced)
└── ssh.sh     # SSH configuration
```

---

## Installation Steps

The installer guides you through 25 steps. State is saved after each step - if interrupted, running again resumes where you left off.

| # | Step | What It Asks |
|---|------|--------------|
| 1 | **Install** | Installation type: minimal or complete |
| 2 | **Branch** | Release branch: stable (main) or rolling (develop) |
| 3 | **Ricing** | Config mode: stable (symlinked, auto-updates) or advanced (copied, manual) |
| 4 | **User Account** | Username, password, sudo access |
| 5 | **Root Password** | Root password (tip: use a different one) |
| 6 | **Hostname** | Computer name (default: "retrolinux") |
| 7 | **Keyboard** | Layout selection (48 options: US, UK, Dvorak, FR, DE, ES, RU, JP, etc.) |
| 8 | **Language** | System language (English, French, German, Chinese, etc.) |
| 9 | **Timezone** | Timezone selection via timedatectl |
| 10 | **Display** | Aspect ratio + resolution selection (auto-detect or custom) |
| 11 | **Disk** | Target disk selection (**erases all data**) |
| 12 | **Encryption** | LUKS encryption: enable/disable, password, iteration time |
| 13 | **Kernel** | Kernel choice: `linux`, `linux-lts`, `linux-zen`, `linux-hardened` |
| 14 | **Boot** | Bootloader (GRUB/systemd-boot), GRUB theme, resolution, OS prober, snapshots, timeout |
| 15 | **Mirrors** | Mirror regions to prioritize + optional custom URL |
| 16 | **Network** | Auto-check internet; WiFi or Ethernet |
| 17 | **Bluetooth** | Enable/disable Bluetooth service |
| 18 | **Fingerprint** | Enable/disable fingerprint authentication |
| 19 | **Printing** | Enable/disable CUPS printing service |
| 20 | **SSH** | Enable/disable, port, password login, key login, root login |
| 21 | **AUR** | AUR helper: `yay` or `paru` |
| 22 | **Editor** | Terminal editor: vim, nano, or helix |
| 23 | **Filemanager** | File manager: yazi or vifm |
| 24 | **Browser** | Browser: firefox, zen, or librewolf |
| 25 | **Config** | Validates settings and generates archinstall JSON |

---

## Minimal vs Complete

The installer offers two installation types at the start of the process:

**Minimal** installs only the core modules that are absolutely essential for the system to function. This is ideal for users who want a lightweight, fast system with just the basics and prefer to manually add extra applications and features later.

**Complete** installs all available modules, providing a fully-featured desktop out of the box with extra polish and functionality. This is ideal for users who want everything ready to go immediately.

Both options install the same base system - the difference is simply which optional modules are included. The complete install does not change any core system behavior, only adds extra applications on top of the minimal foundation.

---

## Directory Structure

```
bin/
├── retroinstall   # Main installer executable
├── lib/         # Helper libraries
│   ├── display.sh
│   ├── errors.sh
│   ├── gum.sh
│   ├── wifi.sh
│   ├── qr.sh
│   ├── locale.sh
│   ├── timezone.sh
│   ├── handlers.sh
│   ├── output.sh
│   └── debug.sh
├── setup/       # Individual step scripts (25 steps)
├── post/       # Post-installation scripts (Stage 2)
└── logo.txt   # ASCII logo
```

---

## What Happens After Steps

After completing all steps:

1. **Summary Display** - Shows all configured options (usernames masked, disk, encryption status, kernel, etc.)

2. **Confirmation** - Confirm to proceed or go back to modify

3. **archinstall Runs** - Silent installation with the generated config

4. **Installation Details:**
   - **Filesystem:** BTRFS with zstd compression
   - **Subvolumes:** `@`, `@home`, `@log`, `@pkg`
   - **Boot:** GRUB with UKI support (FAT32 boot partition) or systemd-boot
   - **DE:** Hyprland + SDDM
   - **Audio:** PipeWire
    - **Firewall:** nftables enabled
    - **Snapshots:** Timeshift configured

5. **Complete** - Reboot prompt on success

6. **On Error** - QR code shown linking to GitHub issues

> [!NOTE]
> **Dry run mode:** Run `retroinstall dry` to print the generated JSON configs (`user_configuration.json`, `user_credentials.json`) without actually installing. Useful for validating settings or debugging configuration issues.

---

## Post-Install (Stage 3)

After the system boots for the first time, `retro --setup` runs automatically to complete the post-install setup, which configures:

- WiFi/Ethernet network
- RetroLinux modules (Hyprland, Kitty, Rofi, etc.)
- Wallpaper and theme colors
- GPU drivers and firmware
- XDG directories

If the system gets powered off or interrupted during this stage, it will fully rollback and restart the post-install process on the next boot without any issues. There is no data loss or corruption - the process is designed to be resilient to interruptions.

---

> [!WARNING]
> **Data Erasure:** Step 10 (disk selection) **ERASES ALL DATA** on the selected disk. There is no undo. Back up everything before running.

> [!NOTE]
> **State Persistence:** Installation state is saved to `/tmp/retroinstall_state` after each step. If interrupted, simply rerun `retroinstall` to resume where you left off. To reset, delete the state file: `rm /tmp/retroinstall_state`.

> [!NOTE]
> **LUKS Password:** Separate from user/root passwords. Higher iteration time = more secure but slower boot.

> [!TIP]
> **Navigation:** You can go back to previous steps during configuration. When declining the disk wipe confirmation, the installer automatically returns you to the timezone step.

> [!NOTE]
> **Stage 3 Resilience:** Post-install runs automatically on first boot. If interrupted, it fully rolls back and restarts on the next boot — no data loss or corruption.

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
