"""System information for the About page.

Pure data collection — no GTK. Each getter is defensive: a missing
file, tool, or permission degrades to a ``"—"`` fallback rather than
raising, so the page always renders.

Collected pieces:

- OS name + version (``/etc/os-release`` + the RetroLinux git tag).
- CPU model + clock (``/proc/cpuinfo`` / ``lscpu``).
- GPU (``nvidia-smi`` first, ``lspci`` fallback).
- Memory usage (``/proc/meminfo``).
- Aggregate storage across real filesystems (``df -B1``).
- Kernel, compositor, and uptime.
"""

from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import threading
from dataclasses import dataclass, field


def _run(args: list[str], timeout: int = 10) -> str:
    try:
        r = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
        return r.stdout.strip()
    except Exception:
        return ""


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except OSError:
        return ""


def _retro_dir() -> str:
    return os.environ.get("RETRO_DIR", "/opt/retrolinux")


# ── OS / version ──

def _os_name() -> str:
    for line in _read("/etc/os-release").splitlines():
        if line.startswith("NAME="):
            val = line.split("=", 1)[1].strip().strip('"')
            if val:
                return val
    return "Retro Linux"


def _os_version() -> str:
    tag = _run(["git", "-C", _retro_dir(), "describe", "--tags", "--abbrev=0"], timeout=3)
    if not tag:
        short = _run(["git", "-C", _retro_dir(), "rev-parse", "--short", "HEAD"], timeout=3)
        tag = short or "rolling-release"
    return tag


def _os_branch() -> str:
    return _run(["git", "-C", _retro_dir(), "rev-parse", "--abbrev-ref", "HEAD"], timeout=3)


def display_version(version: str) -> str:
    """Version for display: numeric tags get a ``v`` prefix, others are kept as-is.

    ``"1.2"`` → ``"v1.2"``; ``"nightly"`` / ``"rolling-release"`` → unchanged.
    """
    version = version.strip()
    if version and version[0].isdigit():
        return f"v{version}"
    return version


def _release_line() -> str:
    os_release = _read("/etc/os-release")
    like = ""
    for line in os_release.splitlines():
        if line.startswith("ID_LIKE="):
            like = line.split("=", 1)[1].strip().strip('"')
    release = "Rolling Release" if "arch" in like.lower() else "Linux"
    session = os.environ.get("XDG_SESSION_TYPE", "")
    if "wayland" in session.lower() or os.environ.get("WAYLAND_DISPLAY"):
        return f"{release} · Wayland"
    return release


# ── CPU ──

def _cpu_model() -> str:
    for line in _read("/proc/cpuinfo").splitlines():
        if line.startswith("model name"):
            model = line.split(":", 1)[1].strip()
            if model:
                model = model.replace("(R)", "").replace("(TM)", "")
                return re.sub(r"\s+", " ", model).strip()
    return ""


def _cpu_cores() -> tuple[int, int]:
    """``(physical_cores, logical_cpus)`` from /proc/cpuinfo."""
    physical: set[tuple[str, str]] = set()
    logical = 0
    pid = ""
    cid = ""
    for line in _read("/proc/cpuinfo").splitlines():
        if line.startswith("processor"):
            logical += 1
        elif line.startswith("physical id"):
            pid = line.split(":", 1)[1].strip()
        elif line.startswith("core id"):
            cid = line.split(":", 1)[1].strip()
        elif not line.strip():
            if pid and cid:
                physical.add((pid, cid))
            pid = cid = ""
    if pid and cid:
        physical.add((pid, cid))
    if not physical:
        physical = {("0", str(i)) for i in range(logical)}
    return len(physical), logical


def _cpu_freq() -> str:
    raw = _run(["lscpu"])
    freq = ""
    for line in raw.splitlines():
        low = line.lower()
        if "cpu max mhz" in low or "cpu mhz" in low:
            val = line.split(":", 1)[1].strip()
            if val and val != "N/A":
                freq = val
                break
    if not freq:
        for line in _read("/proc/cpuinfo").splitlines():
            if line.startswith("cpu MHz"):
                freq = line.split(":", 1)[1].strip()
                break
    try:
        return f"{float(freq) / 1000:.2f}GHz"
    except ValueError:
        return ""


# ── GPU ──

def _clean_gpu(raw: str) -> str:
    s = re.sub(r"^\S+\s+", "", raw)  # drop PCI slot
    s = re.sub(r"^.*?controller:\s*", "", s, flags=re.I)
    s = re.sub(r"\(rev\s+[^)]*\)", "", s)
    s = re.sub(r"[()\[\]]", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    for old, new in (
        ("Advanced Micro Devices, Inc.", "AMD"),
        ("NVIDIA Corporation", "NVIDIA"),
        ("Intel Corporation", "Intel"),
    ):
        s = s.replace(old, new)
    return s


def _gpu() -> str:
    smi = _run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"], timeout=5)
    if smi and smi.lower() != "n/a":
        return re.sub(r"\s+", " ", smi).strip()
    for line in _run(["lspci"]).splitlines():
        low = line.lower()
        if "vga" in low or "3d controller" in low or "display controller" in low:
            cleaned = _clean_gpu(line)
            if cleaned:
                return cleaned
    return ""


# ── GPU memory usage ──

def _vram_sysfs_dirs() -> list[str]:
    """Directories exposing ``mem_info_vram_used``/``_total`` (AMD / Intel discrete)."""
    dirs = []
    for p in glob.glob("/sys/class/drm/card*/device/mem_info_vram_total"):
        d = os.path.dirname(p)
        if os.path.exists(os.path.join(d, "mem_info_vram_used")):
            dirs.append(d)
    return dirs


def _parse_intel_gpu_mem(raw: str) -> float:
    """Sum ``clients[*].memory.system.shared`` (bytes) from ``intel_gpu_top -J``."""
    try:
        sample = json.loads(raw)[-1]
    except Exception:
        return 0.0
    used = 0
    for client in (sample.get("clients") or {}).values():
        try:
            used += int(((client.get("memory") or {}).get("system") or {}).get("shared", 0))
        except (TypeError, ValueError):
            continue
    return used / 1024 ** 3


# ── Combined root-only query (single passwordless sudo call) ──
#
# ``system_core.sh --sysinfo`` returns every root-only chunk (SMBIOS memory,
# intel_gpu_top sample) in one invocation, separated by ``|MARKER|`` lines.
# The chunks are cached per-process so the whole app touches sudo once; the
# existing per-chunk parsers stay untouched.

_SYSINFO_LOCK = threading.Lock()
_sysinfo_cache: dict[str, str] | None = None


def _split_sysinfo(raw: str) -> dict[str, str]:
    """Split ``--sysinfo`` output into raw chunks keyed by marker name."""
    chunks: dict[str, str] = {}
    current = ""
    for line in raw.splitlines():
        stripped = line.strip()
        if stripped in ("|MEMINFO|", "|GPU_TOP|"):
            current = stripped[1:-1].lower()
            chunks[current] = ""
        elif current:
            chunks[current] += line + "\n"
    return chunks


def _sysinfo_chunks() -> dict[str, str]:
    """Raw root-only chunks, fetched once per process."""
    global _sysinfo_cache
    with _SYSINFO_LOCK:
        if _sysinfo_cache is None:
            raw = _run(
                ["sudo", "-n", os.path.join(_retro_dir(), "scripts", "system_core.sh"), "--sysinfo"],
                timeout=25,
            )
            _sysinfo_cache = _split_sysinfo(raw)
        return _sysinfo_cache


def _gpu_mem() -> tuple[float, float]:
    """``(used_gb, total_gb)`` of GPU memory, or ``(0, 0)`` if undetectable."""
    # NVIDIA
    r = _run(
        ["nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,noheader,nounits"],
        timeout=5,
    )
    if r:
        parts = r.split(",")
        if len(parts) == 2:
            try:
                used, total = float(parts[0].strip()), float(parts[1].strip())
                if total > 0:
                    return used / 1024, total / 1024
            except ValueError:
                pass

    # Dedicated VRAM via sysfs (AMD / Intel discrete)
    for d in _vram_sysfs_dirs():
        try:
            used = float(_read(os.path.join(d, "mem_info_vram_used")))
            total = float(_read(os.path.join(d, "mem_info_vram_total")))
        except (TypeError, ValueError):
            continue
        if total > 0:
            return used / 1024 ** 3, total / 1024 ** 3

    # Intel integrated — GPU shares system RAM (intel_gpu_top needs root)
    return _parse_intel_gpu_mem(_sysinfo_chunks().get("gpu_top", "")), 0.0


def gpu_memory_label() -> str:
    """Short label for GPU memory in use, or ``""`` when unavailable."""
    used, total = _gpu_mem()
    if not used:
        return ""
    used_s = f"{used:.1f} GB"
    if total:
        return f"{used_s} / {total:.0f} GB GPU memory"
    return f"{used_s} GPU memory used"


# ── Memory ──

def _mem_kib() -> tuple[int, int]:
    total = 0
    avail = 0
    for line in _read("/proc/meminfo").splitlines():
        if line.startswith("MemTotal:"):
            total = int(line.split()[1]) if len(line.split()) > 1 else 0
        elif line.startswith("MemAvailable:"):
            avail = int(line.split()[1]) if len(line.split()) > 1 else 0
    if total <= 0:
        return 0, 0
    if avail <= 0:
        avail = total
    return total, avail


# ── Storage ──

# Filesystem types that don't represent user-visible storage; excluded so
# tmpfs/squashfs/overlay/… don't inflate the aggregate numbers.
_VIRTUAL_FSTYPES = {
    "tmpfs", "devtmpfs", "squashfs", "overlay", "proc", "sysfs",
    "cgroup", "cgroup2", "efivarfs", "devpts", "shm", "mqueue",
    "binfmt_misc", "securityfs", "debugfs", "tracefs", "configfs",
    "fusectl", "hugetlbfs", "autofs", "pstore", "bpf", "rpc_pipefs",
    "nsfs", "tracefs", "ramfs",
}


def _df_rows() -> list[tuple[str, int, int]]:
    """``df`` rows as ``(source, used, avail)`` with virtual fstypes and
    bind-mounted duplicates filtered out."""
    rows: list[tuple[str, int, int]] = []
    seen_sources: set[str] = set()
    raw = _run(["df", "-B1", "--output=source,used,avail,fstype,target"])
    for line in raw.splitlines():
        parts = line.split(None, 4)
        if len(parts) < 5 or parts[1] == "Used":
            continue
        source, fstype = parts[0], parts[3]
        if fstype in _VIRTUAL_FSTYPES:
            continue
        # Count each device once — bind-mounted paths (e.g. /home on /)
        # otherwise inflate the aggregate.
        if source in seen_sources:
            continue
        seen_sources.add(source)
        try:
            used = int(parts[1])
            avail = int(parts[2])
        except ValueError:
            continue
        rows.append((source, used, avail))
    return rows


def _block_root(device: str) -> str:
    """Map a df source device basename to its sysfs block device, or ``""``."""
    for pattern in (
        r"(nvme\d+n\d+)(?:p\d+)?$",
        r"(sd[a-z]+)\d*$",
        r"(mmcblk\d+)(?:p\d+)?$",
        r"(vd[a-z]+)\d*$",
    ):
        m = re.match(pattern, device)
        if m:
            return m.group(1)
    return ""


def _describe_block(block: str) -> str:
    """Human label for a block device: ``model · interface kind``."""
    model = _read(f"/sys/block/{block}/device/model").strip()
    link = os.path.realpath(f"/sys/block/{block}")

    if block.startswith("nvme"):
        interface = "NVMe"
    elif block.startswith("mmcblk"):
        interface = "eMMC"
    elif "/usb" in link:
        interface = "USB"
    elif "/virtio" in link:
        interface = "VirtIO"
    else:
        interface = "SATA"

    if interface == "USB":
        kind = "drive"
    elif _read(f"/sys/block/{block}/queue/rotational").strip() == "0":
        kind = "SSD"
    else:
        kind = "HDD"

    if model:
        return f"{model} · {interface} {kind}"
    return f"{interface} {kind}"


def _storage_devices(sources: list[str]) -> list[str]:
    """Distinct physical devices behind the df mount sources."""
    seen: set[str] = set()
    labels: list[str] = []
    for src in sources:
        block = _block_root(os.path.basename(src))
        if not block or block in seen:
            continue
        seen.add(block)
        labels.append(_describe_block(block))
    return labels


# ── Memory type (SMBIOS, via system_core.sh so sudo is passwordless) ──

def _parse_dmidecode_memory(raw: str) -> str:
    """Parse ``dmidecode -t 17`` output into a short memory-type label."""
    _BRAND_JUNK = {
        "unknown", "[empty]", "not specified", "not available", "none", "no module installed", "",
    }
    sizes_gib: list[int] = []
    form = ""
    mtype = ""
    speed = ""
    brand = ""
    soldered = False

    for block in raw.split("\n\n"):
        if "DMI type 17" not in block and "Memory Device" not in block:
            continue
        size = 0
        b_form = ""
        b_type = ""
        b_speed = ""
        b_loc = ""
        b_brand = ""
        for line in block.splitlines():
            line = line.strip()
            if line.startswith("Size:"):
                m = re.match(r"(\d+)\s*(GiB|MB)", line.split(":", 1)[1].strip())
                if m:
                    size = int(m.group(1)) if m.group(2) == "GiB" else round(int(m.group(1)) / 1024)
            elif line.startswith("Form Factor:"):
                b_form = line.split(":", 1)[1].strip()
            elif line.startswith("Type:"):
                b_type = line.split(":", 1)[1].strip()
            elif line.startswith("Speed:"):
                b_speed = line.split(":", 1)[1].strip()
            elif line.startswith("Manufacturer:"):
                b_brand = line.split(":", 1)[1].strip()
            elif line.startswith("Locator:"):
                b_loc = line.split(":", 1)[1].strip().lower()
        if size <= 0:
            continue
        sizes_gib.append(size)
        if not form and b_form and b_form.lower() != "unknown":
            form = b_form
        if not mtype and b_type and b_type.lower() not in ("unknown", "other"):
            mtype = b_type
        if not speed and b_speed:
            speed = b_speed
        if not brand and b_brand and b_brand.strip().lower() not in _BRAND_JUNK:
            brand = b_brand.strip()
        if "on board" in b_loc or b_form.lower() in ("row of chips", "chip"):
            soldered = True

    if not sizes_gib:
        return ""

    total = sum(sizes_gib)
    count = len(sizes_gib)
    per = total // count if count > 1 and total % count == 0 else total

    speed_part = ""
    m = re.match(r"(\d+)\s*(?:MT/s|MHz)", speed, re.I)
    if m:
        speed_part = f"-{m.group(1)}"
    type_part = f"{mtype}{speed_part}" if mtype else speed_part.lstrip("-")

    parts = []
    if count > 1:
        parts.append(f"{count}\u00d7")
    if brand:
        parts.append(brand)
    parts.append(f"{per} GB")
    if form and not soldered:
        parts.append(form)
    if type_part:
        parts.append(type_part)
    if soldered:
        parts.append("(soldered)")
    return " ".join(parts)


def _memory_type() -> str:
    return _parse_dmidecode_memory(_sysinfo_chunks().get("meminfo", ""))


def memory_summary() -> str:
    """Short human label for installed memory (brand/type/speed), or ``""``."""
    return _memory_type()


def _human_gib(value: int) -> str:
    return f"{value / 1024 ** 3:.0f} GB"


def _uptime() -> str:
    raw = _read("/proc/uptime")
    try:
        seconds = float(raw.split()[0])
    except (ValueError, IndexError):
        return ""
    minutes = int(seconds // 60)
    hours, minutes = divmod(minutes, 60)
    days, hours = divmod(hours, 24)
    parts = []
    if days:
        parts.append(f"{days} day{'s' if days != 1 else ''}")
    if hours:
        parts.append(f"{hours} hour{'s' if hours != 1 else ''}")
    if minutes:
        parts.append(f"{minutes} min{'s' if minutes != 1 else ''}")
    if parts:
        return ", ".join(parts)
    return "Just started"


# ── Kernel / compositor ──

def _kernel_arch() -> str:
    return _run(["uname", "-m"])


def _human_build_date(raw: str) -> str:
    """Normalize a build-date string to ``Mon D YYYY``.

    Accepts day-month ("28 Jul 2026"), month-day ("Jul 27 2026"), and
    month-day with a timestamp in between ("Jul 27 16:33:49 2026");
    returns ``""`` when nothing parseable is found.
    """
    m = re.search(r"(\d{1,2}) ([A-Z][a-z]{2}) (\d{4})", raw)
    if m:
        return f"{m.group(2)} {m.group(1)} {m.group(3)}"
    m = re.search(r"([A-Z][a-z]{2}) (\d{1,2})", raw)
    if not m:
        return ""
    month, day = m.group(1), m.group(2)
    y = re.search(r"\b(\d{4})\b", raw)
    return f"{month} {day} {y.group(1)}" if y else f"{month} {day}"


def _kernel_build_date() -> str:
    """Build date from ``uname -v`` (e.g. ``Jul 28 2026``)."""
    return _human_build_date(_run(["uname", "-v"]))


def _compositor_details() -> dict[str, str]:
    """Best-effort Hyprland version details, or ``{}`` when offline."""
    try:
        from hyprland_socket import get_version
        v = get_version()
        return {
            "version": v.version or "",
            "tag": v.tag or "",
            "branch": v.branch or "",
            "commit": v.commit or "",
            "commit_date": v.commit_date or "",
            "commits": v.commits or "",
        }
    except Exception:
        return {}


# ── Aggregate ──

@dataclass(slots=True)
class SystemInfo:
    os_name: str = "Retro Linux"
    os_version: str = "rolling-release"
    os_branch: str = ""
    release_line: str = "Linux"
    cpu: str = ""
    cpu_freq: str = ""
    cpu_cores: int = 0
    cpu_threads: int = 0
    gpu: str = ""
    gpu_mem_used_gb: float = 0.0
    gpu_mem_total_gb: float = 0.0
    mem_used_gb: float = 0.0
    mem_total_gb: float = 0.0
    mem_fraction: float = 0.0
    storage_used_gb: float = 0.0
    storage_total_gb: float = 0.0
    storage_free_gb: float = 0.0
    storage_fraction: float = 0.0
    memory_type: str = ""
    storage_device_label: str = ""
    kernel: str = ""
    kernel_arch: str = ""
    kernel_build: str = ""
    compositor: str = "Hyprland"
    compositor_version: str = ""
    compositor_commit: str = ""
    compositor_build: str = ""
    uptime: str = ""

    # For copy-specs — humanized lines keyed by row label.
    lines: dict[str, str] = field(default_factory=dict)

    @property
    def cpu_label(self) -> str:
        if not self.cpu and not self.cpu_freq:
            return "—"
        parts = [self.cpu or "Unknown CPU"]
        if self.cpu_cores and self.cpu_threads:
            parts.append(f"{self.cpu_cores}C/{self.cpu_threads}T")
        base = " · ".join(parts)
        return f"{base} @ {self.cpu_freq}" if self.cpu_freq else base

    @property
    def mem_label(self) -> str:
        if not self.mem_total_gb:
            return "—"
        return f"{self.mem_used_gb:.1f} / {self.mem_total_gb:.0f} GB"

    @property
    def storage_label(self) -> str:
        if not self.storage_total_gb:
            return "—"
        free = f"{self.storage_free_gb:.0f} GB free"
        return f"{self.storage_used_gb:.0f} / {self.storage_total_gb:.0f} GB · {free}"

    @property
    def gpu_mem_label(self) -> str:
        if not self.gpu_mem_used_gb:
            return ""
        used = f"{self.gpu_mem_used_gb:.1f} GB"
        if self.gpu_mem_total_gb:
            return f"{used} / {self.gpu_mem_total_gb:.0f} GB GPU memory"
        return f"{used} GPU memory used"

    @property
    def kernel_label(self) -> str:
        parts = [self.kernel or "—"]
        if self.kernel_arch:
            parts.append(self.kernel_arch)
        if self.kernel_build:
            parts.append(f"built {self.kernel_build}")
        return " · ".join(parts)

    @property
    def compositor_label(self) -> str:
        parts = [self.compositor]
        if self.compositor_version:
            parts.append(self.compositor_version)
        if self.compositor_commit:
            parts.append(f"commit {self.compositor_commit}")
        if self.compositor_build:
            parts.append(f"built {self.compositor_build}")
        return " · ".join(parts)


def collect_system_info(compositor: str | None = None) -> SystemInfo:
    """Gather all About-page data. *compositor* overrides the default."""
    mem_total_kib, mem_avail_kib = _mem_kib()
    mem_total = mem_total_kib / 1024 / 1024
    mem_used = max(0.0, mem_total - (mem_avail_kib / 1024 / 1024))

    df_rows = _df_rows()
    stor_used = sum(r[1] for r in df_rows)
    stor_avail = sum(r[2] for r in df_rows)
    stor_total = stor_used + stor_avail
    storage_devices = _storage_devices([r[0] for r in df_rows])

    kernel = _run(["uname", "-r"])
    compositor = compositor or "Hyprland"
    gpu_mem_used, gpu_mem_total = _gpu_mem()
    cpu_cores, cpu_threads = _cpu_cores()
    comp = _compositor_details()
    compositor_version = comp.get("version", "") or (
        compositor if compositor and compositor != "Hyprland" else ""
    )

    info = SystemInfo(
        os_name=_os_name(),
        os_version=_os_version(),
        os_branch=_os_branch(),
        release_line=_release_line(),
        cpu=_cpu_model(),
        cpu_freq=_cpu_freq(),
        cpu_cores=cpu_cores,
        cpu_threads=cpu_threads,
        gpu=_gpu(),
        gpu_mem_used_gb=gpu_mem_used,
        gpu_mem_total_gb=gpu_mem_total,
        mem_used_gb=mem_used,
        mem_total_gb=mem_total,
        mem_fraction=mem_used / mem_total if mem_total else 0.0,
        storage_used_gb=stor_used / 1024 ** 3,
        storage_total_gb=stor_total / 1024 ** 3,
        storage_free_gb=stor_avail / 1024 ** 3,
        storage_fraction=stor_used / stor_total if stor_total else 0.0,
        memory_type=_memory_type(),
        storage_device_label=", ".join(storage_devices),
        kernel=kernel,
        kernel_arch=_kernel_arch(),
        kernel_build=_kernel_build_date(),
        compositor="Hyprland",
        compositor_version=compositor_version,
        compositor_commit=comp.get("commit", "")[:8],
        compositor_build=_human_build_date(comp.get("commit_date", "")),
        uptime=_uptime(),
    )
    info.lines = {
        "Processor": info.cpu_label,
        "Graphics": info.gpu + (f" · {info.gpu_mem_label}" if info.gpu_mem_label else "") or "—",
        "Memory": info.mem_label + (f" · {info.memory_type}" if info.memory_type else ""),
        "Storage": info.storage_label + (f" · {info.storage_device_label}" if info.storage_device_label else ""),
        "Kernel": info.kernel_label,
        "Compositor": info.compositor_label,
        "Uptime": info.uptime or "—",
    }
    return info


def copy_specs_text(info: SystemInfo) -> str:
    """Plain-text spec block for the Copy Specs button."""
    version = display_version(info.os_version)
    if info.os_branch:
        version = f"{version} ({info.os_branch})"
    head = f"{info.os_name} {version} — {info.release_line}"
    body = "\n".join(f"{k}: {v}" for k, v in info.lines.items())
    return f"{head}\n{body}"


# ── Preload cache ──
#
# The About page collects everything (incl. a passwordless sudo dmidecode
# and a ~1 s intel_gpu_top sample). We kick that off once at app startup so
# the page is already populated by the time it is opened; the page worker
# falls back to collecting itself if the cache isn't ready yet.

_preload_started = False
_preloaded_info: SystemInfo | None = None
_info_ready = threading.Event()
_info_lock = threading.Lock()


def preload_system_info(compositor: str | None = None) -> None:
    """Start background collection exactly once; no-op if already running."""
    global _preload_started
    with _info_lock:
        if _preload_started or _info_ready.is_set():
            return
        _preload_started = True

    def run():
        try:
            info = collect_system_info(compositor=compositor)
        except Exception:
            info = None
        with _info_lock:
            global _preloaded_info
            _preloaded_info = info
        _info_ready.set()

    threading.Thread(target=run, daemon=True).start()


def get_preloaded_info(timeout: float = 0.0) -> SystemInfo | None:
    """Return the cached result once ready, or ``None`` (blocking up to *timeout*)."""
    if _info_ready.wait(timeout):
        with _info_lock:
            return _preloaded_info
    return None
