<p align="center" style="vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="140" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="Logo" width="700" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="140" style="vertical-align: middle">
</p>

<p align="center">

This directory contains everything needed to build the **RetroLinux Live ISO**. The build system uses `archiso` inside Docker to create a reproducible, bootable ISO image with the RetroLinux installer pre-configured.

**What you get:**
- Bootable ISO with GRUB + Syslinux (UEFI + BIOS)
- Custom "retropunk" purple/pink theme
- Plymouth splash screen
- Pre-configured `retroinstall` TUI installer
- 135 pre-installed packages (base, tools, recovery utilities)

</p>

---

## Quick Build 🚀

```bash
cd iso/
./build.sh --yes
```

**Output:** `iso/out/retrolinux-YYYY.MM.DD-x86_64.iso`

---

## Build Options ⚙️

| Flag | Description |
|------|-------------|
| `./build.sh` | Standard build with prompts |
| `./build.sh --yes` | Skip all prompts (CI/CD) |
| `./build.sh --force` | Force rebuild even if unchanged |
| `./build.sh --clean` | Clean build artifacts only |
| `./build.sh --plymouth` | Generate Plymouth splash only |
| `./build.sh --docker` | Build and push Docker image to GHCR |

**Requirements:**
- `docker`
- `bc` (Basic Calculator)
- `convert` (ImageMagick)
- **4+ CPU cores** (recommended for parallel compilation)
- **8GB+ RAM** (disk encryption and build need memory)
- **15GB+ free disk space** (ISO build artifacts)

> Building the ISO is resource-intensive. A beefy machine makes the process much faster.

---

## Build Output 📦

After a successful build:

```
iso/out/
├── retrolinux-2026.04.27-x86_64.iso    # Bootable ISO
├── kernel-version.txt                    # Kernel version (e.g., 6.19.14)
└── .build-checksum                       # SHA256 of packages for incremental builds
```

---

## Profile Details 📋

### profiledef.sh
Defines ISO metadata:
- **Name:** `retrolinux`
- **Label:** `RETRO_2026.04`
- **Version:** `2026.04.27`
- **Boot:** UEFI (GRUB) + BIOS (Syslinux)
- **Compression:** Zstd squashfs

### packages.x86_64
135 packages including:
- **Kernel:** `linux`
- **Boot:** `grub`, `syslinux`, `refind`, `memtest86+`, `amd-ucode`, `intel-ucode`
- **Encryption:** `cryptsetup`, `tpm2-tools`
- **Filesystems:** `btrfs-progs`, `ext4`, `xfsprogs`, `ntfs-3g`
- **Networking:** `networkmanager`, `iwd`, `openssh`
- **Recovery:** `partclone`, `ddrescue`, `testdisk`
- **Tools:** `archinstall`, `vim`, `nvim`, `tmux`, `zsh`, `git`, `rsync`, `jq`, `qrencode`

### airootfs/
Live ISO root filesystem. Key files:
- `root/.automated_script.sh` - Launches `retroinstall` on first boot
- `root/.zlogin` - Runs Plymouth quit and automated_script
- `opt/retrolinux/bin/retroinstall` - Main installer entry point

### Boot Themes

**GRUB (UEFI):** Custom `retropunk` theme with:
- Purple `#97238B`, Pink `#C258D4`, Cyan `#74d6cf` colors
- Rajdhani font for menu
- Background image and logo

**Syslinux (BIOS):** Retro styling with splash.png

---

## Docker Build Environment 🐳

**Dockerfile** builds `retrolinux-build:latest` image:

```dockerfile
FROM archlinux/archlinux:latest
RUN pacman --noconfirm -Sy archiso git sudo base-devel jq grub bc imagemagick
# Pre-downloads all packages from packages.x86_64 into cache volume
```

**Image:** `ghcr.io/itsvlxd/retrolinux-build:latest`

```bash
# Pull image
docker pull ghcr.io/itsvlxd/retrolinux-build:latest

# Build ISO using the image
./build.sh --yes
```

---

## Local Build Example 🖥️

```bash
# Clone the repo
git clone https://github.com/itsvlxd/RetroLinux.git
cd RetroLinux/iso

# Run the build
sudo ./build.sh --yes

# Wait for it to finish (can take 20-40 mins on slower machines)
# Output will be in iso/out/
```

---

## How the ISO Works 💿

**Boot sequence:**

```
1. BIOS/UEFI loads GRUB or Syslinux
2. GRUB shows "retropunk" themed menu
3. Kernel boots with: quiet splash
4. Plymouth splash screen shows
5. User logs in (auto-login as root)
6. .zlogin runs .automated_script.sh
7. retroinstall TUI wizard starts
8. User completes 14 setup steps
9. archinstall runs silently
10. Reboot into installed RetroLinux
```

---

## For Developers 👨‍💻

### Incremental Builds
The build script checks SHA256 of `packages.x86_64` before rebuilding. If unchanged, skips rebuild. Use `--force` to override.

### Adding Packages
Edit `profile/packages.x86_64` - one package per line. Rebuild to update.

### Modifying the Installer
The installer is at `profile/airootfs/opt/retrolinux/bin/`. This gets rsynced from the main `bin/` directory during build.

### Customizing the Theme
- GRUB theme: `profile/grub/themes/retropunk/`
- Syslinux splash: `profile/syslinux/splash.png`

---

## Troubleshooting 🔧

**Build fails with permission error:**
```bash
sudo chmod +x build.sh
```

**Docker not found:**
```bash
# Install Docker
sudo pacman -S docker
sudo systemctl enable --now docker
```

**Out of space:**
```bash
# Clean build artifacts
./build.sh --clean
# Or manually
rm -rf iso/work/ iso/out/*.iso
```
