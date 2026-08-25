#!/usr/bin/env python3
import json, time, os, subprocess, threading, sys

def get_dev():
    r = subprocess.run(["ip", "route", "show", "default"], capture_output=True, text=True)
    return r.stdout.split()[4] if r.stdout.strip() else None

def get_bytes(dev, direction):
    try:
        with open(f"/sys/class/net/{dev}/statistics/{direction}_bytes") as f:
            return int(f.read().strip())
    except:
        return 0

def measure_speed(dev, direction, stop_event, callback):
    prev = get_bytes(dev, direction)
    prev_time = time.time()
    while not stop_event.is_set():
        time.sleep(0.5)
        now = time.time()
        elapsed = now - prev_time
        if elapsed <= 0:
            continue
        cur = get_bytes(dev, direction)
        speed = max(0, (cur - prev) / elapsed) * 8 / 1_000_000
        if speed >= 0.1:
            callback(round(speed, 1))
        prev = cur
        prev_time = now

def do_download(stop_event, speed_callback):
    urls = [
        "https://speed.cloudflare.com/__down?bytes=25000000",
        "https://proof.ovh.net/files/100mb.dat",
        "http://speedtest.tele2.net/10MB.zip",
    ]
    for url in urls:
        try:
            proc = subprocess.Popen(
                ["curl", "-s", "-o", "/dev/null", "--max-time", "15", url],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            proc.wait()
            if proc.returncode == 0:
                return True
        except:
            pass
    return False

def do_upload(stop_event, speed_callback):
    data = os.urandom(10_000_000)
    tmp = "/tmp/_speedtest_upload.bin"
    with open(tmp, "wb") as f:
        f.write(data)
    try:
        urls = [
            "https://speed.cloudflare.com/__up",
            "https://proof.ovh.net/files/100mb.dat",
        ]
        for url in urls:
            try:
                proc = subprocess.Popen(
                    ["curl", "-s", "-o", "/dev/null", "--max-time", "15",
                     "-X", "POST", "-d", f"@{tmp}", url],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                proc.wait()
                if proc.returncode == 0:
                    return True
            except:
                pass
        return False
    finally:
        try:
            os.unlink(tmp)
        except:
            pass

def main():
    dev = get_dev()
    if not dev:
        print(json.dumps({"type": "error", "message": "no network device"}), flush=True)
        return

    # Ping
    print(json.dumps({"type": "phase", "phase": "ping"}), flush=True)
    try:
        r = subprocess.run(["ping", "-c", "3", "-W", "3", "1.1.1.1"],
                          capture_output=True, text=True, timeout=10)
        for line in r.stdout.splitlines():
            if "avg" in line:
                avg = line.split("=")[1].split("/")[1]
                print(json.dumps({"type": "ping", "value": round(float(avg), 1)}), flush=True)
                break
        else:
            print(json.dumps({"type": "ping", "value": 0}), flush=True)
    except:
        print(json.dumps({"type": "ping", "value": 0}), flush=True)

    # Download test
    print(json.dumps({"type": "phase", "phase": "download"}), flush=True)
    stop_dl = threading.Event()
    dl_speeds = []

    def on_dl_speed(s):
        dl_speeds.append(s)
        print(json.dumps({"type": "download", "value": s}), flush=True)

    t_dl = threading.Thread(target=measure_speed, args=(dev, "rx", stop_dl, on_dl_speed), daemon=True)
    t_dl.start()
    do_download(stop_dl, on_dl_speed)
    stop_dl.set()
    t_dl.join(timeout=2)

    avg_dl = round(sum(dl_speeds) / len(dl_speeds), 2) if dl_speeds else 0
    print(json.dumps({"type": "download_done", "value": avg_dl}), flush=True)

    # Upload test
    print(json.dumps({"type": "phase", "phase": "upload"}), flush=True)
    stop_ul = threading.Event()
    ul_speeds = []

    def on_ul_speed(s):
        ul_speeds.append(s)
        print(json.dumps({"type": "upload", "value": s}), flush=True)

    t_ul = threading.Thread(target=measure_speed, args=(dev, "tx", stop_ul, on_ul_speed), daemon=True)
    t_ul.start()
    do_upload(stop_ul, on_ul_speed)
    stop_ul.set()
    t_ul.join(timeout=2)

    avg_ul = round(sum(ul_speeds) / len(ul_speeds), 2) if ul_speeds else 0
    print(json.dumps({"type": "upload_done", "value": avg_ul}), flush=True)

    print(json.dumps({"type": "done"}), flush=True)

if __name__ == "__main__":
    main()
