<p align="center" style="vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="140" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="Logo" width="700" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="140" style="vertical-align: middle">
</p>

<p align="center">

The **RetroLinux Installer** (`retroinstall`) is a guided, interactive TUI installer that walks you through 23 setup steps to configure a complete Arch-based Linux system. It uses `gum` for the terminal interface and generates configuration files for `archinstall` under the hood.

**What you get:**
- BTRFS filesystem with zstd compression and snapshots via Timeshift
- Hyprland desktop environment with SDDM greeter
- Optional LUKS disk encryption
- Bluetooth and printing service support
- PipeWire audio, UFW firewall, and more

</p>

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

**Debug Mode:**
```bash
retroinstall --debug
```

---

## Installation Stages

The installation happens in 3 stages:

| Stage | When | What |
|-------|------|------|
| **Stage 1: Live ISO Setup** | During live ISO booting | Runs `retroinstall` - 23 steps to configure system and run `archinstall` |
| **Stage 2: Live ISO Post-Install** | After archinstall completes | Runs automatically in chroot - configures boot, kernel modules, Plymouth |
| **Stage 3: Post-Install Setup** | First login inside installed OS | Runs automatically - configures modules, wallpaper, drivers, etc. |

### Stage 1 Scripts (bin/setup/)

```
setup/
├── install.sh         # Installation type selection (minimal/complete)
├── user.sh          # User account creation
├── root.sh          # Root password setup
├── hostname.sh      # Computer hostname
├── display.sh      # Display server choice
├── keyboard.sh    # Keyboard layout
├── locale.sh     # System language
├── mirrors.sh    # Mirror configuration
├── timezone.sh   # Timezone selection
├── disk.sh       # Target disk selection
├── luks.sh       # LUKS encryption
├── kernel.sh    # Kernel selection
├── boot.sh      # Bootloader setup
├── bluetooth.sh # Bluetooth service
├── fingerprint.sh # Fingerprint authentication
├── print.sh     # CUPS printing service
├── ssh.sh       # OpenSSH service
├── aur.sh       # AUR support
├── editor.sh    # Terminal editor choice
├── filemanager.sh  # File manager choice
├── browser.sh   # Browser choice
├── network.sh  # Network configuration
└── config.sh   # Final validation and config generation
```

### Stage 2 Scripts (bin/post/)

```
post/
├── chroot.sh          # Main post-install script (runs in chroot)
├── boot.sh         # Configures bootloader (GRUB/systemd-boot)
├── kernel.sh       # Removes live kernel, installs selected kernel + headers
├── plymouth.sh    # Installs and configures Plymouth splash
└── packages.sh    # Installs additional packages via pacman
```

### Stage 3 Scripts (cmds/system/setup/)

```
setup/
├── run.sh         # Main post-install runner
├── modules.sh     # Installs RetroLinux modules
├── network.sh    # Configures WiFi/Ethernet
├── xdg.sh       # XDG base directories
├── keyring.sh   # SSH/GPG keyring setup
├── mimeapps.sh   # Default app associations
├── terminal.sh  # Terminal emulator config
├── variables.sh # Environment variables
├── wallpaper.sh# Wallpaper setup
├── fonts.sh    # Font configuration
├── fingerprint.sh # Fingerprint auth setup
├── power.sh   # Power management
├── browser.sh # Browser configuration
├── drivers.sh # GPU/firmware drivers
└── editor.sh # Editor config
```

---

## Installation Steps

The installer guides you through 23 steps. State is saved after each step - if interrupted, running again resumes where you left off.

| # | Step | What It Asks |
|---|------|--------------|
| 1 | **Install** | Installation type: minimal or complete |
| 2 | **User Account** | Username, password, sudo access |
| 3 | **Root Password** | Root password (tip: use a different one) |
| 4 | **Hostname** | Computer name (default: "retrolinux") |
| 5 | **Display** | Display server: wayland or x11 |
| 6 | **Keyboard** | Layout selection (48 options: US, UK, Dvorak, FR, DE, ES, RU, JP, etc.) |
| 7 | **Language** | System language (English, French, German, Chinese, etc.) |
| 8 | **Mirrors** | Mirror regions to prioritize + optional custom URL |
| 9 | **Timezone** | Timezone selection via timedatectl |
| 10 | **Disk** | Target disk selection (**erases all data**) |
| 11 | **Encryption** | LUKS encryption: enable/disable, password, iteration time |
| 12 | **Kernel** | Kernel choice: `linux`, `linux-lts`, `linux-zen`, `linux-hardened` |
| 13 | **Boot** | Bootloader: grub or systemd |
| 14 | **Bluetooth** | Enable/disable Bluetooth service |
| 15 | **Fingerprint** | Enable/disable fingerprint authentication |
| 16 | **Printing** | Enable/disable CUPS printing service |
| 17 | **SSH** | Enable/disable OpenSSH service |
| 18 | **AUR** | Enable/disable AUR support |
| 19 | **Editor** | Terminal editor: vim, nano, or helix |
| 20 | **Filemanager** | File manager: yazi or vifm |
| 21 | **Browser** | Browser: firefox, zen, or librewolf |
| 22 | **Network** | Auto-check internet; WiFi or Ethernet |
| 23 | **Config** | Validates settings and generates archinstall JSON |

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
├── setup/       # Individual step scripts (23 steps)
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
   - **Firewall:** UFW enabled
   - **Snapshots:** Timeshift configured

5. **Complete** - Reboot prompt on success

6. **On Error** - QR code shown linking to GitHub issues

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

## Important Notes

- **Data Erasure** - Step 10 (disk selection) **ERASES ALL DATA** on the selected disk. There is no undo.

- **State Persistence** - State is saved to `/tmp/retroinstall_state`. Rerun the installer to resume after interruption.

- **LUKS Password** - Separate from user/root passwords. Higher iteration time = more secure but slower boot.

- **Go Back** - You can navigate back to previous steps. When declining disk wipe confirmation, the installer restarts from step 7 (timezone).

- **Stage 3 Trigger** - Post-install runs automatically on first boot - interruptions will rollback and restart safely
