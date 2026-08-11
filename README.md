<div align="center">

<p align="center" style="vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="120" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="Logo" width="660" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="120" style="vertical-align: middle">
</p> 

**Arch. Retro. Neon.** A complete Arch-based distribution that turns your desktop into a retro-future masterpiece.

<p align="center">
  <img alt="Guided Installer" src="https://img.shields.io/badge/Guided%20Installer-F93BF3?style=for-the-badge">
  <img alt="Full Ricing CLI" src="https://img.shields.io/badge/Full%20Ricing%20CLI-FA8AF4?style=for-the-badge">
  <img alt="Desktop GUI" src="https://img.shields.io/badge/Desktop%20GUI-F93BF3?style=for-the-badge">
  <img alt="QML Shell" src="https://img.shields.io/badge/QML%20Shell-FA8AF4?style=for-the-badge">
  <img alt="Live Event Daemon" src="https://img.shields.io/badge/Live%20Event%20Daemon-F93BF3?style=for-the-badge">
</p>

</div>

<p align="center">
  <a href="https://github.com/itsvlxd/RetroLinux/releases"><img alt="Releases" src="https://img.shields.io/github/v/release/itsvlxd/RetroLinux?style=for-the-badge&labelColor=0a0a0a&color=F93BF3"></a>
  <a href="https://github.com/itsvlxd/RetroLinux/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/itsvlxd/RetroLinux?style=for-the-badge&labelColor=0a0a0a&color=FA8AF4"></a>
  <a href="https://github.com/itsvlxd/RetroLinux/blob/develop/LICENSE"><img alt="License" src="https://img.shields.io/badge/License-GPL--3.0-0a0a0a?style=for-the-badge&labelColor=0a0a0a&color=F93BF3"></a>
  <a href="https://github.com/itsvlxd/RetroLinux/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-0a0a0a?style=for-the-badge&labelColor=0a0a0a&color=FA8AF4"></a>
</p>

<p align="center">
  <img alt="Hyprland" src="https://img.shields.io/badge/Hyprland-0a0a0a?style=flat&logo=hyprland&logoColor=FA8AF4&color=1a0d24">
  <img alt="Wayland" src="https://img.shields.io/badge/Wayland-0a0a0a?style=flat&logo=wayland&logoColor=FA8AF4&color=1a0d24">
  <img alt="GTK4" src="https://img.shields.io/badge/GTK4-0a0a0a?style=flat&logo=gtk&logoColor=FA8AF4&color=1a0d24">
  <img alt="Lua" src="https://img.shields.io/badge/Lua-0a0a0a?style=flat&logo=lua&logoColor=FA8AF4&color=1a0d24">
  <img alt="Python" src="https://img.shields.io/badge/Python-0a0a0a?style=flat&logo=python&logoColor=F93BF3&color=1a0d24">
  <img alt="JavaScript" src="https://img.shields.io/badge/JavaScript-0a0a0a?style=flat&logo=javascript&logoColor=F93BF3&color=1a0d24">
  <img alt="Shell" src="https://img.shields.io/badge/Shell-0a0a0a?style=flat&logo=shell&logoColor=FA8AF4&color=1a0d24">
</p>

---

## 🌴 What is RetroLinux

RetroLinux is a **full Arch Linux distribution** with a curated retro-neon identity — but under the hood it's a modular framework you drive entirely from one command:

```bash
retro
```

One CLI to rule the desktop: **30+ tools** for audio, network, power, themes, wallpapers, GRUB, drivers, fonts, firewall, fingerprint, SSH, timeshift and more. A **GTK4 desktop GUI** (`retro settings`) for point-and-click config. A **QML shell** (RetroShell) that *is* your desktop. A **Lua event daemon** that reacts to battery, power, bluetooth, USB, audio, SSH and updates — live.

Built on a strict two-layer architecture (`cmds/` UI → `scripts/*_core.sh` logic) so every feature is predictable, scriptable, and testable.

**Rock solid by design.** Every install runs on BTRFS with **Timeshift snapshots wired straight into the GRUB bootloader** — break something, and roll back to a working snapshot right from the boot menu. That's the RetroLinux safety net.

> Built on **Arch Linux**, tuned for the **retro-neon aesthetic** — but fast, modern, and yours to break.

---

## ⚡ Showcase

<details>
<summary><b>📸 Adding your own screenshots</b></summary>
<br>
Drop captures into <code>assets/screenshots/</code> and link them via
<code>https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/&lt;name&gt;.png</code>.
Keep grid images at a consistent width and crop to the same aspect ratio so rows line up.
<br><br>
Round the corners to match the existing shots (32px radius, transparent corners):
<br>
<code>magick shot.png \( -size 1920x1080 xc:black -fill white -draw "roundrectangle 0,0,1920,1080,32,32" \) -alpha off -compose CopyOpacity -composite assets/screenshots/shot.png</code>
</details>

<br>

<!-- SCREENSHOT: assets/screenshots/desktop.png — full desktop (Hyprland + RetroShell), 16:9, width="1000" -->
<p align="center">
  <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/desktop.png" width="1000" alt="RetroLinux desktop"></kbd>
</p>

| | | | |
|:---:|:---:|:---:|:---:|
| <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/sddm.png" width="420" alt="SDDM login"></kbd><br><sub>SDDM login</sub> | <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/settings.png" width="420" alt="Retro Settings"></kbd><br><sub>Retro Settings</sub> | <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/cli.png" width="420" alt="retro CLI"></kbd><br><sub>retro CLI</sub> | <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/installer.png" width="420" alt="Installer"></kbd><br><sub>Installer TUI</sub> |

| | |
|:---:|:---:|
| <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/grub-retrolink-theme.png" width="420" alt="Retrolink GRUB theme"></kbd><br><sub>Retrolink</sub> | <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/grub-retropunk-theme.png" width="420" alt="Retropunk GRUB theme"></kbd><br><sub>Retropunk</sub> |

<!-- SCREENSHOT PLAN:
1. desktop.png  — full Hyprland desktop with RetroShell bar + a theme/wallpaper applied (hero shot)
2. sddm.png     — the SDDM login screen with the RetroLinux theme
3. settings.png — the Retro Settings GUI (sidebar + a page open)
4. cli.png      — a terminal running `retro` commands with the neon palette
5. installer.png— the retroinstall TUI mid-install
6. grub-retrolink-theme.png  — the GRUB boot menu with the "Retrolink" theme applied
7. grub-retropunk-theme.png — the GRUB boot menu with the "Retropunk" theme applied
-->

---

## 🚀 Features

| | |
|---|---|
| 🧭 **Guided Installer** | A 25-step interactive TUI that drives `archinstall` — BTRFS with zstd compression + Timeshift snapshots, optional LUKS encryption, Hyprland + SDDM. Boot the ISO, done. |
| 🧰 **Full Ricing CLI** | 30+ tools from one command — audio, network, power profiles, themes, wallpapers, GRUB, drivers, fonts, firewall, SSH, timeshift and more. |
| 🎛️ **Retro Settings GUI** | A GTK4 + libadwaita app with a page for every tool. Point-and-click config with live apply, search and undo — no config-file spelunking. |
| 🌴 **Alive, Not Static** | RetroShell, a QML desktop shell (bar, dock, launcher, notifications, lockscreen), plus a Lua event daemon — 14 watchers, 20+ events reacting to battery, power, bluetooth, USB, audio, SSH and updates. |
| 🔒 **Modular & Secure** | 15 config modules (symlink or copy) and hardened defaults — optional LUKS, granular sudo, SSH hardening and an nftables firewall. |

---

## 🕹️ Control It Your Way

| ⌨️ **retro CLI** | 🎛️ **Retro Settings GUI** | 🌴 **RetroShell** |
|---|---|---|
| 30+ commands from your terminal — themes, audio, network, power, GRUB, drivers and more. | A GTK4 + libadwaita desktop app with a page for every tool. Point, click, done. | The QML shell that *is* your desktop — bar, dock, launcher, notifications and a dashboard. |

All three share the same config, so you can mix and match however you like.

---

## 🎨 Theming

Switch your entire look in one shot. Pick a palette, apply it, done.

```bash
retro theme list                     # browse 40+ curated themes
retro theme set tokyo-night          # apply a palette everywhere
retro wallpaper list                 # noir / retro / sunset packs
retro wallpaper set "Retrowave Gtr Wallpaper"
```

| | | | |
|:---:|:---:|:---:|:---:|
| <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/theme-retro.png" width="330" alt="Retro theme"></kbd><br><sub>`retro`</sub> | <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/theme-tokyo-night.png" width="330" alt="Tokyo Night"></kbd><br><sub>`tokyo-night`</sub> | <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/theme-gruvbox.png" width="330" alt="Gruvbox"></kbd><br><sub>`gruvbox`</sub> | <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/theme-dracula.png" width="330" alt="Dracula"></kbd><br><sub>`dracula`</sub> |

<!-- SCREENSHOT: theme preview tiles — the palette applied to a terminal, width="330" -->

<sub>Palettes live in `themes/` as JSON — 43 and counting. Themes cascade across your terminal, shell, SDDM, GRUB and wallpapers.</sub>

---

## 🖼️ Wallpapers

Hand-tuned collections for every mood — swapped with one command, or left to auto-cycle through the daemon's slideshow.

```bash
retro wallpaper list              # noir · retro · sunset
retro wallpaper set retro
retro wallpaper slideshow on
```

| | | |
|:---:|:---:|:---:|
| <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/wallpaper-noir.png" width="330" alt="Noir collection"></kbd><br><sub>`noir`</sub> | <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/wallpaper-retro.png" width="330" alt="Retro collection"></kbd><br><sub>`retro`</sub> | <kbd><img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/wallpaper-sunset.png" width="330" alt="Sunset collection"></kbd><br><sub>`sunset`</sub> |

<!-- SCREENSHOT: wallpaper pack tiles — one hero shot per collection (noir/retro/sunset), width="330" -->

<sub>One hero shot per collection — drop them into `assets/screenshots/` and they'll show here.</sub>

---

## 💾 Hardware Support

RetroLinux detects your hardware during install and picks the right drivers automatically — no hunting for packages.

<p align="center">
  <img alt="NVIDIA" src="https://img.shields.io/badge/NVIDIA-0a0a0a?style=for-the-badge&labelColor=0a0a0a&color=76B900">
  <img alt="AMD" src="https://img.shields.io/badge/AMD-0a0a0a?style=for-the-badge&labelColor=0a0a0a&color=ED1C24">
  <img alt="Intel" src="https://img.shields.io/badge/Intel-0a0a0a?style=for-the-badge&labelColor=0a0a0a&color=0071C5">
</p>

- **NVIDIA** — `nvidia-open` / `nvidia-dkms` with full lib32 support
- **AMD** — open-source `amdgpu` + `mesa`, zero-fuss
- **Intel** — `intel-media-driver`, i915/xe out of the box

<sub>GPUs, CPUs, audio and network chips are all auto-detected — check the result anytime with `retro driver status`.</sub>

---

## 🛠️ Getting Started

RetroLinux is installed from the **live ISO** — no manual Arch setup required.

> **PLACEHOLDER:** Link to the latest ISO release + checksum. Boot it, and the installer runs automatically.

<details>
<summary><b>📦 The install in 3 stages</b></summary>
<br>

| Stage | When | What |
|-------|------|------|
| **1 · Live ISO** | At boot of the live environment | `retroinstall` walks through 25 setup steps, then runs `archinstall` with generated JSON configs |
| **2 · Chroot** | Right after `archinstall` | Post-install hooks configure the repo, packages, network and AUR helper in the target system |
| **3 · First boot** | Your first login | Post-install setup applies modules, wallpaper, drivers and keyring automatically |

</details>

---

## 🧰 The `retro` Command

```bash
retro help                    # every command, grouped
retro audio status            # sinks, sources, volume
retro network wifi on wlan0   # connect
retro power profile balanced  # switch power profiles
retro grub setup              # bootloader, theme, timeout, kernels
retro shell run launcher      # pop the RetroShell launcher
retro settings                # launch the Retro Settings GUI
retro daemon status           # is the event engine running?
retro log status              # what has been happening?
```

<sub>Frontends live in `cmds/`, backend logic in `scripts/*_core.sh` — see `CODING_GUIDELINES.md` for the full architecture.</sub>

---

## ❓ FAQ

<details>
<summary><b>Do I need to know Arch Linux to use RetroLinux?</b></summary>
<br>
No. The live ISO installer walks you through everything in 25 guided steps — you never touch a partition table or a pacman flag during setup.
</details>

<details>
<summary><b>Will it work on my hardware?</b></summary>
<br>
RetroLinux targets x86_64 systems with an NVIDIA, AMD or Intel GPU. The installer detects your hardware and installs the matching drivers automatically.
</details>

<details>
<summary><b>Is NVIDIA supported?</b></summary>
<br>
Yes — `nvidia-open` / `nvidia-dkms` with full lib32 support, configured for you during install.
</details>

<details>
<summary><b>How do updates and rollbacks work?</b></summary>
<br>
`retro update` syncs pacman and your AUR helper in one go. And because every install runs on BTRFS with Timeshift snapshots wired into GRUB, you can boot straight into a previous snapshot from the boot menu if anything ever breaks.
</details>

<details>
<summary><b>Can I make it look how I want?</b></summary>
<br>
That's the whole point. 43 themes, wallpaper collections and 15 modules — symlink them for stability, or copy them for full custom freedom.
</details>

---

## ❤️ Contributing

RetroLinux is open source (GPL-3.0) and community-driven. Contributions, bug reports and feature ideas are all welcome.

- 📖 **Architecture & rules** — read [CODING_GUIDELINES.md](CODING_GUIDELINES.md) before writing code
- 🐛 **Found a bug?** — open an [issue](https://github.com/itsvlxd/RetroLinux/issues)
- 🔧 **Want to contribute?** — check [CONTRIBUTING.md](CONTRIBUTING.md) and open a [pull request](https://github.com/itsvlxd/RetroLinux/pulls)
- 💬 **Show it off** — share your `retro` rice, screenshots, and setups

<p align="center">
  <a href="https://github.com/itsvlxd/RetroLinux/graphs/contributors"><img alt="Contributors" src="https://img.shields.io/github/contributors/itsvlxd/RetroLinux?style=for-the-badge&labelColor=0a0a0a&color=F93BF3"></a>
  <a href="https://github.com/itsvlxd/RetroLinux/issues"><img alt="Issues" src="https://img.shields.io/github/issues/itsvlxd/RetroLinux?style=for-the-badge&labelColor=0a0a0a&color=FA8AF4"></a>
  <a href="https://github.com/itsvlxd/RetroLinux/pulls"><img alt="Pull requests" src="https://img.shields.io/github/issues-pr/itsvlxd/RetroLinux?style=for-the-badge&labelColor=0a0a0a&color=F93BF3"></a>
</p>

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
