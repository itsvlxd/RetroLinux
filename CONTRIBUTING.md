<p align="center" style="vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="120" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-main-transparent-bg.png" alt="Logo" width="500" style="margin-right: 2px; vertical-align: middle">
  <img src="https://raw.githubusercontent.com/itsvlxd/RetroLinux/develop/assets/logo-palm-transparent-bg.png" alt="Logo" width="120" style="vertical-align: middle">
</p>

# Contributing to RetroLinux 🌴

First off, thank you for wanting to contribute! RetroLinux is a community-driven project — whether you're fixing a typo, squashing a bug, or building a whole new tool, your help keeps the neon alive.

Please take a moment to read this guide. Most importantly:

> [!IMPORTANT]
> **Read [CODING_GUIDELINES.md](CODING_GUIDELINES.md) before writing any code.** It is the **single source of truth** for project structure, code style, the two-layer architecture, multi-language libraries, logging, command registration, the daemon system, and the installer. Contributions that don't follow it will be asked to change.

---

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Commit Message Conventions](#commit-message-conventions)
- [Testing](#testing)
- [Reporting Issues](#reporting-issues)
- [Pull Request Checklist](#pull-request-checklist)

---

## Ways to Contribute

| Contribution | How |
|--------------|-----|
| 🐛 **Report a bug** | Open an [issue](https://github.com/itsvlxd/RetroLinux/issues) with repro steps, expected vs. actual behavior, and logs |
| 💡 **Suggest a feature** | Open an [issue](https://github.com/itsvlxd/RetroLinux/issues) with a clear description and use case |
| 🔧 **Write code** | Pick an issue, branch off `develop`, and open a [pull request](https://github.com/itsvlxd/RetroLinux/pulls) |
| 🧪 **Improve tests** | The test suite lives in `tests/` — make it faster, broader, or more accurate |
| 📖 **Docs** | Fix typos, improve README/CONTRIBUTING, or extend [CODING_GUIDELINES.md](CODING_GUIDELINES.md) |
| 🎨 **Share your rice** | Screenshots, theme previews, wallpaper setups — show them off in issues/discussions |

---

## Getting Started

1. **Fork** the repository on GitHub.
2. **Clone your fork** and add the upstream:

   ```bash
   git clone https://github.com/<your-username>/RetroLinux.git
   cd RetroLinux
   git remote add upstream https://github.com/itsvlxd/RetroLinux.git
   ```

3. **Create a branch** from `develop` (the default development branch):

   ```bash
   git fetch upstream
   git checkout -b feat/my-new-tool upstream/develop
   ```

4. **Run the test suite** to make sure your environment works:

   ```bash
   RETRO_TEST_BYPASS=true ./retro.sh --tests all
   ```

---

## Development Workflow

- **Branch off `develop`**, never `main`. `develop` is the integration branch; `main` tracks releases.
- **Keep PRs small and focused.** One logical change per PR — it's much easier to review and much less likely to be blocked on merge conflicts.
- **Keep your branch up to date** by rebasing on `upstream/develop` before opening or updating a PR.
- **Don't force-push to shared branches** unless you have to; prefer rebasing locally and pushing normally.
- **Discussion first for big changes**: if a change touches the installer, the daemon architecture, or core libraries, open an issue or discuss before writing hundreds of lines.

---

## Code Standards

This project has strict, enforced standards. The full details live in [CODING_GUIDELINES.md](CODING_GUIDELINES.md) — this is a quick checklist, not a replacement:

- ✅ **Two-layer pattern** — frontend UI in `cmds/tools/<name>.sh`, backend logic in `scripts/<name>_core.sh`. Core scripts output machine-parseable data only.
- ✅ **No duplicated functions** — check `lib/` and `bin/lib/` before writing a new helper. Add shared utilities there, not in command files.
- ✅ **Shared libraries stay 1:1** — if you change a function in `lib/foo.sh`, its Lua/Python port(s) must behave identically.
- ✅ **Naming** — `cmd_` for commands, `rx_` for library functions, `_` for private helpers. Constants uppercase, variables lowercase.
- ✅ **No comments unless needed, no TODOs** — do it now or file an issue.
- ✅ **Logging** — `rx_log` in frontends only; `rx_log_file` + `rx_log_register` in core scripts and daemon engines.
- ✅ **Shellcheck clean** — all scripts must pass before merge:

  ```bash
  shellcheck scripts/*.sh cmds/**/*.sh lib/*.sh bin/**/*.sh
  ```

- ✅ **No hardcoded user paths** — use `$RETRO_DIR`, `$RETRO_CONFIG`, `$HOME`.

---

## Commit Message Conventions

RetroLinux uses **Conventional Commits**. A commit message looks like:

```
type(scope): short summary
```

**Types:** `feat`, `fix`, `refactor`, `docs`, `style`, `chore`, `test`

**Scopes** (examples from the history): `settings`, `wallpaper`, `grub`, `bin`, `retro`, `power`, `shell`, `daemon`, `CODING`, `iso`

**Real examples:**

```text
feat(settings): make the logs page be in real time
fix(settings): fix frame and bar race in config file
feat(bin): make the qr code smaller
chore(retro): remove unused audio eq presets
docs(CODING): update coding guidelines
```

**Rules:**
- Imperative mood, lowercase, under ~72 chars.
- Reference the issue in the body when applicable (`Closes #123`).
- Group related changes; avoid `fix stuff` and mega-commits.

---

## Testing

The test suite is 19 scripts in `tests/`, covering structure, naming, shellcheck, Lua syntax, output formats, and more. Run everything:

```bash
RETRO_TEST_BYPASS=true ./retro.sh --tests all
```

- **Always run the suite before pushing.**
- **Add or update tests** when you add a feature or fix a bug — see `tests/` for the existing patterns (e.g., `tests/event_naming_test.sh`, `tests/shellcheck_test.sh`).
- If a test is flaky or environment-specific, tell us in the PR description.

---

## Reporting Issues

A great bug report includes:

- **What happened** and **what you expected** instead
- **Steps to reproduce**
- **Environment**: kernel, GPU, whether it's on a fresh install or an existing system
- **Logs**: run the relevant `retro log <name>` output, or the installer error QR / `/tmp/retro_logs/` entries
- **Screenshots** if it's visual

The installer generates a QR code on failure that pre-fills a GitHub issue with system info — include it if you have it.

---

## Pull Request Checklist

Before opening or marking a PR ready for review:

- [ ] Branch is off the latest `develop`
- [ ] Code follows [CODING_GUIDELINES.md](CODING_GUIDELINES.md)
- [ ] Shellcheck passes on all touched scripts
- [ ] Full test suite passes (`RETRO_TEST_BYPASS=true ./retro.sh --tests all`)
- [ ] New functionality includes tests
- [ ] Conventional commit(s) describe the change
- [ ] Screenshots/terminal output included for UI changes

Then open the PR against the **`develop`** branch (not `main`), fill in the template, and a maintainer will take a look. Thanks for helping build RetroLinux! 🌴⚡

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
