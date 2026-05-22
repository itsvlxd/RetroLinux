---
name: Bug report
about: Create a report to help us improve
title: ''
labels: bug
assignees: itsvlxd

---

name: 🐛 Bug Report
about: Report a script failure, installer halt, or daemon crash
title: '[BUG] '
labels: bug
assignees: ''

**Describe the bug**
A clear and concise description of what the bug is. (e.g., "The installer halts at Step 12 when verifying the LUKS pass key" or "The event daemon stops running after high battery utilization triggers.")

**Environment & System Information**
Please tell us where you ran into this issue:
- **Execution State:** [e.g., Live ISO environment, Stage 2 Post-Install chroot, or fully installed OS]
- **Hardware Platform:** [e.g., ThinkPad X1 Carbon Gen 9, Custom PC, VM VirtualBox]
- **CPU / GPU / Architecture:** [e.g., AMD Ryzen 7, NVIDIA RTX 3060, x86_64]
- **Current Kernel Version (if known):** [e.g., linux, linux-lts, linux-zen]

**To Reproduce**
List the exact terminal steps or choices made to trigger the bug:
1. Boot/Start the machine with '...'
2. Run command `...`
3. Select option '....' in the TUI menu
4. See error output:

**Terminal Output / Tracebacks**
Paste the exact raw console output, error dump, or `shellcheck` trace here. Please wrap it inside the code block below:
```text
[PASTE RAW TERMINAL OR ERROR OUTPUT HERE]
