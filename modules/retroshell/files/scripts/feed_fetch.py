#!/usr/bin/env python3
"""Fetch top articles for the desktop feed widget.

Usage: feed_fetch.py <source> <query> [apiKey]
  source: devto | hackernews | dailydev

Outputs a JSON array:
  [{id, title, url, readTime, upvotes, source, author, image}]
Cached for 30 minutes per (source, query). Offline falls back to cache.
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request

CACHE_DIR = os.path.expanduser("~/.cache/retro")
MAX_AGE = 30 * 60

HEADERS = {"User-Agent": "RetroLinux-Shell/1.0", "Accept": "application/json"}


def cache_path(source, query):
    return os.path.join(CACHE_DIR, "feed_%s_%s.json" % (source, query or "all"))


def get_json(url, headers=None, data=None):
    req = urllib.request.Request(url, headers=headers or HEADERS, data=data)
    with urllib.request.urlopen(req, timeout=12) as r:
        return json.load(r)


def fetch_devto(query, count):
    url = "https://dev.to/api/articles?per_page=%d&top=1" % count
    if query:
        url += "&tag=%s" % urllib.parse.quote(query)
    data = get_json(url)
    out = []
    for a in data:
        out.append({
            "id": str(a.get("id", "")),
            "title": a.get("title", ""),
            "url": a.get("url", ""),
            "readTime": a.get("reading_time_minutes", 0),
            "upvotes": a.get("public_reactions_count", 0),
            "source": "dev.to",
            "author": (a.get("user") or {}).get("username", ""),
            "image": a.get("cover_image") or a.get("social_image") or "",
        })
    return out


def fetch_hackernews(query, count):
    url = ("https://hn.algolia.com/api/v1/search?query=%s&tags=story&hitsPerPage=%d"
           % (urllib.parse.quote(query or "programming"), count))
    data = get_json(url)
    out = []
    for h in data.get("hits", []):
        if not h.get("title"):
            continue
        oid = str(h.get("objectID", ""))
        out.append({
            "id": oid,
            "title": h.get("title", ""),
            "url": h.get("url") or ("https://news.ycombinator.com/item?id=%s" % oid),
            "readTime": 0,
            "upvotes": h.get("points", 0),
            "source": "Hacker News",
            "author": h.get("author", ""),
            "image": "",
        })
    return out


def fetch_dailydev(query, api_key, count):
    url = "https://api.daily.dev/graphql"
    gql = ('query { searchPosts(query: "%s", first: %d) { edges { node { '
           'id title permalink readTime numUpvotes image source { name } } } } }'
           % (query.replace('"', ""), count))
    body = json.dumps({"query": gql}).encode()
    headers = dict(HEADERS)
    headers["Content-Type"] = "application/json"
    if api_key:
        headers["Authorization"] = "Bearer %s" % api_key
    data = get_json(url, headers=headers, data=body)
    out = []
    for e in (data.get("data", {}).get("searchPosts", {}).get("edges") or []):
        n = e.get("node") or {}
        out.append({
            "id": str(n.get("id", "")),
            "title": n.get("title", ""),
            "url": n.get("permalink", ""),
            "readTime": n.get("readTime", 0) or 0,
            "upvotes": n.get("numUpvotes", 0) or 0,
            "source": (n.get("source") or {}).get("name", "daily.dev"),
            "author": "",
            "image": n.get("image", ""),
        })
    return out


def read_cache(source, query):
    try:
        with open(cache_path(source, query)) as f:
            return f.read().strip()
    except OSError:
        return None


def main():
    source = (sys.argv[1] if len(sys.argv) > 1 else "devto").strip()
    query = (sys.argv[2] if len(sys.argv) > 2 else "").strip()
    api_key = (sys.argv[3] if len(sys.argv) > 3 else "").strip()
    try:
        count = max(3, min(10, int(sys.argv[4] if len(sys.argv) > 4 else 5)))
    except ValueError:
        count = 5

    cached = read_cache(source, query)
    if cached:
        try:
            if time.time() - os.path.getmtime(cache_path(source, query)) < MAX_AGE:
                print(cached)
                return
        except OSError:
            pass

    try:
        if source == "hackernews":
            articles = fetch_hackernews(query, count)
        elif source == "dailydev":
            articles = fetch_dailydev(query, api_key, count)
        else:
            articles = fetch_devto(query, count)
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(cache_path(source, query), "w") as f:
                json.dump(articles, f)
        except OSError:
            pass
        print(json.dumps(articles))
    except Exception:
        if cached:
            print(cached)
        else:
            print("[]")


if __name__ == "__main__":
    main()