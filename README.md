<div align="center">

<p align="center" style="vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="120" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="Logo" width="500" style="margin-right: 2px; vertical-align: middle">
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

RetroLinux is a **full Arch Linux distribution** with a curated retro-neon identity — but under the hood it's a modular framework you drive entirely from one command: retro

One CLI to rule the desktop: **30+ tools** for audio, network, power, themes, wallpapers, GRUB, drivers, fonts, firewall, fingerprint, SSH, timeshift and more. A **GTK4 desktop GUI** (`retro settings`) for point-and-click config. A **QML shell** (RetroShell) that *is* your desktop. A **Lua event daemon** that reacts to battery, power, bluetooth, USB, audio, SSH and updates — live.

Built on a strict two-layer architecture (`cmds/` UI → `scripts/*_core.sh` logic) so every feature is predictable, scriptable, and testable.

**Rock solid by design.** Every install runs on BTRFS with **Timeshift snapshots wired straight into the GRUB bootloader** — break something, and roll back to a working snapshot right from the boot menu. That's the RetroLinux safety net.

> Built on **Arch Linux**, tuned for the **retro-neon aesthetic** — but fast, modern, and yours to break.

---

## ⚡ Showcase

A look at the RetroLinux experience — the **RetroShell** desktop, the **Retro Settings** GUI, the **retro CLI**, the **installer**, and the **GRUB** boot themes.

<!-- SCREENSHOT: assets/screenshots/retro-desktop.png — full desktop (Hyprland + RetroShell), width="980" -->
<p align="center">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/retro-desktop.png" width="980" alt="RetroLinux desktop">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/retro-sddm-login.png" width="410" alt="SDDM login">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/retro-settings.png" width="410" alt="Retro Settings">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/retro-cli.png" width="410" alt="retro CLI">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/retro-installer-iso.png" width="410" alt="Installer">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/grub-retrolink-theme.png" width="410" alt="Retrolink GRUB theme">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/grub-retropunk-theme.png" width="410" alt="Retropunk GRUB theme">
</p>

<!-- SCREENSHOT PLAN:
1. retro-desktop.png — full Hyprland desktop with RetroShell bar + a theme/wallpaper applied (hero shot)
2. retro-sddm-login.png — the SDDM login screen with the RetroLinux theme
3. retro-settings.png — the Retro Settings GUI (sidebar + a page open)
4. retro-cli.png   — a terminal running `retro` commands with the neon palette
5. retro-installer-iso.png — the retroinstall TUI (live ISO) mid-install
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

## 🎨 Theming

Switch your entire look in one shot. Pick a palette, apply it, done — or drop in your own JSON themes, nothing is locked down.

<p align="center">
  <img alt="Retro" src="https://img.shields.io/badge/Retro-0a0a0a?style=flat&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHZpZXdCb3g9JzAgMCAxNiAxNic+PGNpcmNsZSBjeD0nOCcgY3k9JzgnIHI9JzYuNScgZmlsbD0nI2IyNGJmMycvPjxjaXJjbGUgY3g9JzgnIGN5PSc4JyByPScyLjUnIGZpbGw9JyMwYTBhMGEnIGZpbGwtb3BhY2l0eT0nMC4zNScvPjwvc3ZnPg==&color=1a0d24">
  <img alt="Tokyo Night" src="https://img.shields.io/badge/Tokyo%20Night-0a0a0a?style=flat&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHZpZXdCb3g9JzAgMCAxNiAxNic+PGNpcmNsZSBjeD0nOCcgY3k9JzgnIHI9JzYuNScgZmlsbD0nIzdhYTJmNycvPjxjaXJjbGUgY3g9JzgnIGN5PSc4JyByPScyLjUnIGZpbGw9JyMwYTBhMGEnIGZpbGwtb3BhY2l0eT0nMC4zNScvPjwvc3ZnPg==&color=1a0d24">
  <img alt="Gruvbox" src="https://img.shields.io/badge/Gruvbox-0a0a0a?style=flat&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHZpZXdCb3g9JzAgMCAxNiAxNic+PGNpcmNsZSBjeD0nOCcgY3k9JzgnIHI9JzYuNScgZmlsbD0nI2Q3OTkyMScvPjxjaXJjbGUgY3g9JzgnIGN5PSc4JyByPScyLjUnIGZpbGw9JyMwYTBhMGEnIGZpbGwtb3BhY2l0eT0nMC4zNScvPjwvc3ZnPg==&color=1a0d24">
  <img alt="Dracula" src="https://img.shields.io/badge/Dracula-0a0a0a?style=flat&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHZpZXdCb3g9JzAgMCAxNiAxNic+PGNpcmNsZSBjeD0nOCcgY3k9JzgnIHI9JzYuNScgZmlsbD0nI2JkOTNmOScvPjxjaXJjbGUgY3g9JzgnIGN5PSc4JyByPScyLjUnIGZpbGw9JyMwYTBhMGEnIGZpbGwtb3BhY2l0eT0nMC4zNScvPjwvc3ZnPg==&color=1a0d24">
  <img alt="Nordic" src="https://img.shields.io/badge/Nordic-0a0a0a?style=flat&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHZpZXdCb3g9JzAgMCAxNiAxNic+PGNpcmNsZSBjeD0nOCcgY3k9JzgnIHI9JzYuNScgZmlsbD0nIzgxYTFjMScvPjxjaXJjbGUgY3g9JzgnIGN5PSc4JyByPScyLjUnIGZpbGw9JyMwYTBhMGEnIGZpbGwtb3BhY2l0eT0nMC4zNScvPjwvc3ZnPg==&color=1a0d24">
  <img alt="Catppuccin Mocha" src="https://img.shields.io/badge/Catppuccin%20Mocha-0a0a0a?style=flat&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHZpZXdCb3g9JzAgMCAxNiAxNic+PGNpcmNsZSBjeD0nOCcgY3k9JzgnIHI9JzYuNScgZmlsbD0nI2NiYTZmNycvPjxjaXJjbGUgY3g9JzgnIGN5PSc4JyByPScyLjUnIGZpbGw9JyMwYTBhMGEnIGZpbGwtb3BhY2l0eT0nMC4zNScvPjwvc3ZnPg==&color=1a0d24">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/retro-theme-desktop.png" width="410" alt="Retro theme">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/tokyonight-theme-desktop.png" width="410" alt="Tokyo Night">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/gruvbox-theme-desktop.png" width="410" alt="Gruvbox">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/dracula-theme-desktop.png" width="410" alt="Dracula">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/nordic-theme-desktop.png" width="410" alt="Nordic">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/screenshots/catppuccinmocha-theme-desktop.png" width="410" alt="Catppuccin Mocha">
</p>

<sub>Palettes live in `themes/` as JSON — 43 and counting. Themes cascade across your terminal, shell, SDDM, GRUB and wallpapers.</sub>

---

## 🖼️ Wallpapers

Wallpaper collections live in their own repo — check out **[github.com/itsvlxd/retrowallpapers](https://github.com/itsvlxd/retrowallpapers)**.

---

## 💾 Hardware Support

RetroLinux detects your hardware during install and picks the right drivers automatically — no hunting for packages.

<p align="center">
  <img alt="NVIDIA" src="https://img.shields.io/badge/NVIDIA-0a0a0a?style=for-the-badge&labelColor=0a0a0a&color=76B900">
  <img alt="AMD" src="https://img.shields.io/badge/AMD-0a0a0a?style=for-the-badge&labelColor=0a0a0a&color=ED1C24">
  <img alt="Intel" src="https://img.shields.io/badge/Intel-0a0a0a?style=for-the-badge&labelColor=0a0a0a&color=0071C5">
</p>

- **NVIDIA** — `nvidia-open-dkms` + `nvidia-utils` with full **lib32 + OpenCL** support, **Wayland-ready** (DRM modeset/fbdev enabled, GBM + NVD backends configured), the initramfs rebuilt with the NVIDIA modules, **Optimus** support for hybrid laptops, and **CUDA/cuDNN + NVIDIA container toolkit** for AI/ML.
- **AMD** — open-source `amdgpu` + `mesa`, zero-fuss
- **Intel** — `intel-media-driver`, i915/xe out of the box

<sub>GPUs, CPUs, audio and network chips are all auto-detected — check the result anytime with `retro driver status`.</sub>

---

## 🛠️ Getting Started

RetroLinux is installed from the **live ISO** — no manual Arch setup required.

Grab the latest ISO from the **[Releases page](https://github.com/itsvlxd/RetroLinux/releases)** — boot it, and the installer runs automatically.

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

<details open>
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
`retro --update` syncs pacman and your AUR helper in one go. And because every install runs on BTRFS with Timeshift snapshots wired into GRUB, you can boot straight into a previous snapshot from the boot menu if anything ever breaks.
</details>

<details>
<summary><b>Can I make it look how I want?</b></summary>
<br>
**Yes.** RetroLinux ships with 40+ curated themes and ready-made shell presets — but those are just a starting point. If none of them fit your vibe, it's easy to make it your own: build your **own themes**, save your **own shell presets**, and assemble **custom wallpaper collections** — all from the Settings app or `retro`, no config files required.
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
