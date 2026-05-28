<p align="center" style="vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="120" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="Logo" width="660" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="120" style="vertical-align: middle">
</p>

This directory contains everything needed to build the **RetroLinux Live ISO**. The build system uses `archiso` inside Docker to create a reproducible, bootable ISO image with the RetroLinux installer pre-configured.

**What you get:**
- Bootable ISO with GRUB + Syslinux (UEFI + BIOS)
- Custom "retropunk" purple/pink theme
- Pre-configured `retroinstall` TUI installer
- Pre-installed packages (base, tools, recovery utilities)

---

## Quick Build

```bash
cd iso/
./build.sh --yes
```

**Output:** `iso/out/retrolinux-YYYY.MM.DD-x86_64.iso`

> [!TIP]
> Always run `build.sh` from the `iso/` directory. It detects the project root (`RETRO_DIR`) as the parent directory automatically. If you run it from elsewhere, set `RETRO_DIR` manually or symlink the script to your `$PATH`.

---

## Build Options

| Flag | Description |
|------|-------------|
| `./build.sh` | Build ISO (default) |
| `./build.sh --yes` | Skip all prompts (CI/CD) |
| `./build.sh --force` | Force rebuild even if unchanged |
| `./build.sh --clean` | Clean build artifacts only |
| `./build.sh --repo` | Include full repo in ISO |
| `./build.sh --docker` | Build and push Docker image to GHCR |

> [!WARNING]
> **Resource requirements:** Building the ISO is resource-intensive. A beefy machine makes the process much faster.
>
> - `docker`, `bc` (Basic Calculator), `convert` (ImageMagick) — must be installed on the host
> - **4+ CPU cores** — recommended for parallel compilation inside the Docker container
> - **8GB+ RAM** — disk encryption and ISO generation need memory
> - **15GB+ free disk space** — build artifacts, package cache, and the output ISO

---

## Build Output

After a successful build:

```
iso/out/
├── retrolinux-2026.04.27-x86_64.iso      # Bootable ISO
├── kernel-version.txt                    # Kernel version (e.g., 6.19.14)
└── .build-checksum                       # SHA256 of packages for incremental builds
```

> [!NOTE]
> **Incremental builds:** The build script calculates a SHA256 checksum of `packages.x86_64` before building. If the checksum matches the previous build and an ISO already exists, `mkarchiso` is skipped entirely. Use `--force` to override and force a full rebuild.

---

## Profile Details

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
- `root/.zlogin` - Runs automated_script
- `opt/retrolinux/bin/retroinstall` - Main installer entry point

### Boot Themes

**GRUB (UEFI):** Custom `retropunk` theme with:
- Purple `#97238B`, Pink `#C258D4`, Cyan `#74d6cf` colors
- Rajdhani font for menu
- Background image and logo

**Syslinux (BIOS):** Retro styling with splash.png

---

## Docker Build Environment

**Dockerfile** builds `retrolinux-build:latest` image:

```dockerfile
FROM archlinux/archlinux:latest
RUN pacman --noconfirm -Sy archiso git sudo base-devel jq grub bc imagemagick
# Pre-downloads all packages from packages.x86_64 into cache volume
```

**Image:** `ghcr.io/itsvlxd/retrolinux-build:latest`

> [!TIP]
> Use `./build.sh --docker` to build and push the Docker image to GHCR without building the ISO. This is useful for CI/CD or when you only need to update the build environment.

> [!NOTE]
> **Package caching:** The build uses a named Docker volume (`retrolinux-pkg-cache`) to persist downloaded packages across builds. This means subsequent builds are much faster since packages don't need to be re-downloaded. The volume is created automatically on first run.

```bash
# Pull image
docker pull ghcr.io/itsvlxd/retrolinux-build:latest

# Build ISO using the image
./build.sh --yes
```

---

## Local Build Example

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

## How the ISO Works

**Boot sequence:**

```
1. BIOS/UEFI loads GRUB or Syslinux
2. GRUB shows "retropunk" themed menu
3. Kernel boots
4. User logs in (auto-login as root)
5. .automated_script.sh runs
6. retroinstall TUI wizard starts
7. User completes 24 setup steps
8. archinstall runs silently
9. Reboot into installed RetroLinux
```

---

## For Developers

### Incremental Builds
The build script checks SHA256 of `packages.x86_64` before rebuilding. If unchanged, skips rebuild. Use `--force` to override.

> [!NOTE]
> Use `--repo` (`-r`) to include the full RetroLinux repository inside the ISO at `/opt/retrolinux`. This enables live debugging and development from the live environment but increases ISO size by approximately 200MB. The `.git/` directory and `.env` file are excluded automatically.

### Adding Packages
Edit `profile/packages.x86_64` - one package per line. Rebuild to update.

### Modifying the Installer
The installer is at `profile/airootfs/opt/retrolinux/bin/`. This gets rsynced from the main `bin/` directory during build.

### Customizing the Theme
- GRUB theme: `profile/grub/themes/retropunk/`
- Syslinux splash: `profile/syslinux/splash.png`

---

## Troubleshooting

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
