<p align="center" style="vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="140" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="Logo" width="700" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="140" style="vertical-align: middle">
</p>

<p align="center">

The **RetroLinux Installer** (`retroinstall`) is a guided, interactive TUI installer that walks you through 14 setup steps to configure a complete Arch-based Linux system. It uses `gum` for the terminal interface and generates configuration files for `archinstall` under the hood.

**What you get:**
- BTRFS filesystem with zstd compression and snapshots via Timeshift
- Hyprland desktop environment with SDDM greeter
- Optional LUKS disk encryption
- Bluetooth and printing service support
- PipeWire audio, UFW firewall, and more

</p>

---

## Getting Started 🚀

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

## Installation Steps 📋

The installer guides you through 14 steps. State is saved after each step - if interrupted, running again resumes where you left off.

| # | Step | What It Asks |
|---|------|--------------|
| 1 | **User Account** | Username, password, sudo access |
| 2 | **Root Password** | Root password (tip: use a different one) |
| 3 | **Hostname** | Computer name (default: "retrolinux") |
| 4 | **Keyboard** | Layout selection (48 options: US, UK, Dvorak, FR, DE, ES, RU, JP, etc.) |
| 5 | **Language** | System language (English, French, German, Chinese, etc.) |
| 6 | **Mirrors** | Mirror regions to prioritize + optional custom URL |
| 7 | **Timezone** | Timezone selection via timedatectl |
| 8 | **Disk** | Target disk selection (**erases all data**) |
| 9 | **Encryption** | LUKS encryption: enable/disable, password, iteration time |
| 10 | **Kernel** | Kernel choice: `linux`, `linux-lts`, `linux-zen`, `linux-hardened` |
| 11 | **Bluetooth** | Enable/disable Bluetooth service |
| 12 | **Printing** | Enable/disable CUPS printing service |
| 13 | **Network** | Auto-check internet; WiFi or Ethernet |
| 14 | **Config** | Validates settings and generates archinstall JSON |

---

## What Happens After Steps? 💾

After completing all 14 steps:

1. **Summary Display** - Shows all configured options (usernames masked, disk, encryption status, kernel, etc.)

2. **Confirmation** - Confirm to proceed or go back to modify

3. **archinstall Runs** - Silent installation with the generated config

4. **Installation Details:**
   - **Filesystem:** BTRFS with zstd compression
   - **Subvolumes:** `@`, `@home`, `@log`, `@pkg`
   - **Boot:** GRUB with UKI support (FAT32 boot partition)
   - **DE:** Hyprland + SDDM
   - **Audio:** PipeWire
   - **Firewall:** UFW enabled
   - **Snapshots:** Timeshift configured

5. **Complete** - Reboot prompt on success

6. **On Error** - QR code shown linking to GitHub issues

---

## Important Notes ⚠️

- **Data Erasure** - Step 8 (disk selection) **ERASES ALL DATA** on the selected disk. There is no undo.

- **State Persistence** - State is saved to `/tmp/retroinstall_state`. Rerun the installer to resume after interruption.

- **LUKS Password** - Separate from user/root passwords. Higher iteration time = more secure but slower boot.

- **Go Back** - You can navigate back to previous steps. When declining disk wipe confirmation, the installer restarts from step 7 (timezone).
