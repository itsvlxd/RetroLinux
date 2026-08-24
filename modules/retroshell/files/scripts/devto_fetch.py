#!/usr/bin/env python3
"""Fetch top DEV.to articles for a tag, cached for 30 minutes.

Usage: devto_fetch.py [tag]   (omit tag for all tags)
Outputs a JSON array of trimmed articles.
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

CACHE_DIR = os.path.expanduser("~/.cache/retro")
MAX_AGE = 30 * 60  # 30 minutes


def cache_path(tag):
    return os.path.join(CACHE_DIR, "devto_%s.json" % (tag or "all"))


def fetch(tag):
    per_page = 3
    url = "https://dev.to/api/articles?per_page=%d&top=1" % per_page
    if tag:
        url += "&tag=%s" % urllib.parse.quote(tag)
    req = urllib.request.Request(url, headers={
        "User-Agent": "RetroLinux-Shell/1.0",
        "Accept": "application/json",
    })
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.load(r)
    out = []
    for a in data:
        out.append({
            "id": a.get("id"),
            "title": a.get("title", ""),
            "url": a.get("url", ""),
            "reading_time_minutes": a.get("reading_time_minutes", 0),
            "public_reactions_count": a.get("public_reactions_count", 0),
            "username": (a.get("user") or {}).get("username", ""),
        })
    return out


def read_cache(tag):
    try:
        with open(cache_path(tag)) as f:
            return f.read().strip()
    except OSError:
        return None


def main():
    tag = (sys.argv[1] if len(sys.argv) > 1 else "").strip()

    cached = read_cache(tag)
    if cached:
        try:
            if time.time() - os.path.getmtime(cache_path(tag)) < MAX_AGE:
                print(cached)
                return
        except OSError:
            pass

    try:
        articles = fetch(tag)
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(cache_path(tag), "w") as f:
                json.dump(articles, f)
        except OSError:
            pass
        print(json.dumps(articles))
    except Exception:
        # Offline: fall back to any cached copy, else empty.
        if cached:
            print(cached)
        else:
            print("[]")


if __name__ == "__main__":
    main()