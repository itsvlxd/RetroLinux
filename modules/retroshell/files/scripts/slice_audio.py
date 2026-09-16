#!/usr/bin/env python3
import os
import sys
import json
import argparse
import subprocess
import shutil


CACHE_FORMAT_PATH = os.path.join(os.path.dirname(__file__), "cache_format.json")
with open(CACHE_FORMAT_PATH, "r", encoding="utf-8") as f:
    CACHE_FORMAT_VERSION = str(json.load(f)["version"])

DEFAULT_PACK_GAIN = 2.0


def transcode_to_qsoundeffect_wav(source_path, destination_path, gain):
    """Write a conservative WAV format supported by Qt's QSoundEffect."""
    cmd = [
        "ffmpeg", "-y", "-i", source_path,
        "-map", "0:a:0", "-ar", "44100", "-ac", "1",
        "-c:a", "pcm_s16le",
    ]
    if gain != 1.0:
        cmd.extend(["-af", f"volume={gain},alimiter=limit=1.0"])
    cmd.append(destination_path)
    result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if result.returncode != 0:
        error = result.stderr.decode("utf-8", errors="ignore").strip()
        raise RuntimeError(f"ffmpeg failed for {source_path}: {error}")

def main():
    parser = argparse.ArgumentParser(description="Slice Mechvibes sound pack into individual key audio files.")
    parser.add_argument("--pack-dir", required=True, help="Absolute path to the sound pack directory")
    parser.add_argument("--cache-dir", required=True, help="Absolute path to the cache output directory")
    parser.add_argument("--pack-gain", type=float, default=DEFAULT_PACK_GAIN,
                        help="Linear gain before limiting (default: 2.0)")
    args = parser.parse_args()

    pack_dir = os.path.abspath(args.pack_dir)
    cache_dir = os.path.abspath(args.cache_dir)
    config_path = os.path.join(pack_dir, "config.json")

    if not os.path.exists(config_path):
        print(f"Error: config.json not found in {pack_dir}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)
    except Exception as e:
        print(f"Error parsing config.json: {e}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(cache_dir, exist_ok=True)

    key_define_type = config.get("key_define_type", "single")
    defines = config.get("defines", {})

    if not defines:
        print("Error: No 'defines' found in config.json", file=sys.stderr)
        sys.exit(1)

    if key_define_type == "single":
        sound_file_name = config.get("sound")
        if not sound_file_name:
            print("Error: 'sound' key missing for single define type", file=sys.stderr)
            sys.exit(1)

        sound_path = os.path.join(pack_dir, sound_file_name)
        if not os.path.exists(sound_path):
            print(f"Error: Sound file {sound_path} not found", file=sys.stderr)
            sys.exit(1)

        # Slice each key individually — a single multi-output ffmpeg command
        # breaks because per-output -ss/-af on a shared decoder produces
        # silent or corrupted WAVs.
        keys_to_slice = [(k, d) for k, d in defines.items()
                         if d and len(d) >= 2]
        total = len(keys_to_slice)
        print(f"Slicing {total} keys from {sound_path} to {cache_dir}...")
        failed = 0
        for idx, (keycode, define) in enumerate(keys_to_slice, 1):
            offset_ms, duration_ms = define[0], define[1]
            out_file = os.path.join(cache_dir, f"{keycode}.wav")

            cmd = [
                "ffmpeg", "-y",
                "-ss", f"{offset_ms / 1000.0}",
                "-i", sound_path,
                "-t", f"{duration_ms / 1000.0}",
                "-map", "0:a:0", "-ar", "44100", "-ac", "1",
                "-c:a", "pcm_s16le",
            ]
            if args.pack_gain != 1.0:
                cmd.extend(["-af", f"volume={args.pack_gain},alimiter=limit=1.0"])
            cmd.append(out_file)

            res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if res.returncode != 0:
                err = res.stderr.decode('utf-8', errors='ignore').strip()
                print(f"  [{idx}/{total}] keycode {keycode}: {err}", file=sys.stderr)
                failed += 1

        if failed == total:
            print("Error: All slices failed", file=sys.stderr)
            sys.exit(1)
        if failed:
            print(f"Warning: {failed}/{total} slices failed", file=sys.stderr)

    elif key_define_type == "multi":
        print(f"Copying/converting multi-file sound pack from {pack_dir}...")
        normalized_sources = {}
        for keycode, file_name in defines.items():
            if not file_name:
                continue
            src_path = os.path.join(pack_dir, file_name)
            if not os.path.exists(src_path):
                continue
            
            dest_path = os.path.join(cache_dir, f"{keycode}.wav")
            # Do not symlink/copy source WAVs: QSoundEffect accepts only a
            # conservative subset of WAV variants. Normalize every file.
            try:
                # Old caches used symlinks to the source pack. Remove the
                # link itself before ffmpeg writes, never follow it.
                if os.path.lexists(dest_path):
                    os.remove(dest_path)
                if src_path in normalized_sources:
                    shutil.copyfile(normalized_sources[src_path], dest_path)
                else:
                    transcode_to_qsoundeffect_wav(src_path, dest_path, args.pack_gain)
                    normalized_sources[src_path] = dest_path
            except RuntimeError as e:
                print(f"Error: {e}", file=sys.stderr)
                sys.exit(1)

    # Create marker file
    try:
        with open(os.path.join(cache_dir, ".complete"), "w", encoding="utf-8") as f:
            f.write(CACHE_FORMAT_VERSION)
    except Exception as e:
        print(f"Warning: Could not write marker file: {e}", file=sys.stderr)

    print("Success: Sound pack prepared successfully.")

if __name__ == "__main__":
    main()
