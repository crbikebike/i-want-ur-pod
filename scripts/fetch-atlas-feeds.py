#!/usr/bin/env python3
"""Fetch real RSS episode data for every curated atlas show, ONCE, to disk.

This is the single network pass for the story-arc regex bake-off. It runs in the
main loop (never inside an agent). For each show in curation/atlas-source.json it:
  1. Resolves a feed URL via the free iTunes Search API (verifying the returned
     collection name fuzzy-matches the atlas title, to avoid wrong-show matches).
  2. Downloads the RSS feed and extracts per-episode title + itunes:season /
     itunes:episode / episodeType / pubDate / guid.
  3. Writes curation/feeds/<slug>.json.

Polite + resilient by design: sequential, short delay between iTunes calls,
timeouts, limited retries, and resumable caching (skip shows already on disk).
Every failure is logged and skipped, never fatal. Feed URLs are NOT stored in the
repo, so this script is how the corpus gets built; subagents read only its output.

Usage:  python3 scripts/fetch-atlas-feeds.py
Output: curation/feeds/<slug>.json  and  curation/feeds/_index.json (run report)
"""

import json
import re
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from difflib import SequenceMatcher
from email.utils import parsedate_to_datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "curation" / "atlas-source.json"
OUT_DIR = ROOT / "curation" / "feeds"
IT = "{http://www.itunes.com/dtds/podcast-1.0.dtd}"
UA = "Mozilla/5.0 (iWantUrPod arc-bakeoff; +https://example.invalid/contact)"

ITUNES_DELAY = 0.6      # seconds between iTunes calls (be polite)
MAX_EPISODES = 800      # cap per feed (newest kept)
NAME_MATCH_MIN = 0.62   # fuzzy ratio floor to accept an iTunes result
RETRIES = 2


def norm(t: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", re.sub(r"^(the|a|an)\s+", "", (t or "").lower())).strip()


def slugify(t: str) -> str:
    s = re.sub(r"^(the|a|an)\s+", "", (t or "").lower())
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "show"


def http_get(url: str, timeout: int = 30) -> bytes:
    last = None
    for attempt in range(RETRIES + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - network is best-effort
            last = e
            time.sleep(0.8 * (attempt + 1))
    raise last  # type: ignore[misc]


def safe_fromstring(raw: bytes):
    """Parse RSS but block DTD-based attacks (XXE, billion-laughs)."""
    head = raw[:4096].lower()
    if b"<!doctype" in head or b"<!entity" in raw.lower():
        raise ValueError("feed declares a DTD/entity - refusing to parse (XXE guard)")
    return ET.fromstring(raw)


def resolve_feed(title: str) -> dict | None:
    """iTunes Search -> {feedUrl, collectionName, artistName, score} or None."""
    q = urllib.parse.urlencode({"term": title, "entity": "podcast", "limit": 5, "country": "US"})
    try:
        raw = http_get(f"https://itunes.apple.com/search?{q}", timeout=20)
        data = json.loads(raw)
    except Exception:  # noqa: BLE001
        return None
    want = norm(title)
    best = None
    for res in data.get("results", []):
        feed = res.get("feedUrl")
        if not feed:
            continue
        cand = norm(res.get("collectionName", ""))
        score = SequenceMatcher(None, want, cand).ratio()
        if want and (want in cand or cand in want):
            score = max(score, 0.9)
        if best is None or score > best["score"]:
            best = {"feedUrl": feed, "collectionName": res.get("collectionName", ""),
                    "artistName": res.get("artistName", ""), "score": round(score, 3)}
    if best and best["score"] >= NAME_MATCH_MIN:
        return best
    return best and {**best, "belowThreshold": True}


def parse_feed(slug: str, title: str, network: str, match: dict) -> dict:
    raw = http_get(match["feedUrl"], timeout=45)
    root = safe_fromstring(raw)
    channel = root.find("channel") or root
    episodes = []
    for it in channel.findall("item"):
        etitle = (it.findtext("title") or "").strip()
        if not etitle:
            continue
        season = it.findtext(f"{IT}season")
        epnum = it.findtext(f"{IT}episode")
        pub = it.findtext("pubDate")
        try:
            dt = parsedate_to_datetime(pub) if pub else None
        except (TypeError, ValueError):
            dt = None
        episodes.append({
            "guid": (it.findtext("guid") or etitle).strip(),
            "title": etitle,
            "season": int(season) if season and season.strip().isdigit() else None,
            "episodeNumber": int(epnum) if epnum and epnum.strip().isdigit() else None,
            "episodeType": (it.findtext(f"{IT}episodeType") or "full").strip().lower(),
            "iso": dt.date().isoformat() if dt else "",
        })
        if len(episodes) >= MAX_EPISODES:
            break
    return {
        "slug": slug,
        "title": title,
        "network": network,
        "feedUrl": match["feedUrl"],
        "itunesCollection": match.get("collectionName", ""),
        "matchScore": match.get("score"),
        "episodeCount": len(episodes),
        "episodes": episodes,
    }


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    src = json.loads(SOURCE.read_text())
    shows = src.get("shows", [])

    # Dedup by normalized title (mirrors build-atlas.mjs dedup).
    seen_norm = set()
    unique = []
    for s in shows:
        n = norm(s.get("title", ""))
        if n and n not in seen_norm:
            seen_norm.add(n)
            unique.append(s)

    index = []
    total = len(unique)
    ok = fail = skip = 0
    for i, s in enumerate(unique, 1):
        title = s.get("title", "")
        network = s.get("network", "")
        slug = slugify(title)
        out = OUT_DIR / f"{slug}.json"
        if out.exists():
            skip += 1
            print(f"[{i}/{total}] SKIP (cached) {slug}", flush=True)
            try:
                cached = json.loads(out.read_text())
                index.append({"slug": slug, "title": title, "status": "cached",
                              "episodeCount": cached.get("episodeCount", 0)})
            except Exception:  # noqa: BLE001
                index.append({"slug": slug, "title": title, "status": "cached"})
            continue

        match = resolve_feed(title)
        time.sleep(ITUNES_DELAY)
        if not match or not match.get("feedUrl"):
            fail += 1
            print(f"[{i}/{total}] NO-FEED   {slug} :: {title}", flush=True)
            index.append({"slug": slug, "title": title, "status": "no-feed"})
            continue
        if match.get("belowThreshold"):
            fail += 1
            print(f"[{i}/{total}] LOW-MATCH {slug} ({match['score']}) -> {match['collectionName']!r}", flush=True)
            index.append({"slug": slug, "title": title, "status": "low-match",
                          "score": match["score"], "itunesCollection": match["collectionName"]})
            continue
        try:
            data = parse_feed(slug, title, network, match)
        except Exception as e:  # noqa: BLE001
            fail += 1
            print(f"[{i}/{total}] FETCH-ERR {slug} :: {type(e).__name__}: {e}", flush=True)
            index.append({"slug": slug, "title": title, "status": "fetch-error",
                          "error": f"{type(e).__name__}: {e}", "feedUrl": match["feedUrl"]})
            continue
        out.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        ok += 1
        print(f"[{i}/{total}] OK        {slug}: {data['episodeCount']} eps (match {match['score']})", flush=True)
        index.append({"slug": slug, "title": title, "status": "ok",
                      "episodeCount": data["episodeCount"], "score": match["score"],
                      "itunesCollection": match["collectionName"]})

    report = {
        "total": total, "ok": ok, "failed": fail, "cached": skip,
        "shows": index,
    }
    (OUT_DIR / "_index.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"\nDONE  total={total} ok={ok} cached={skip} failed={fail}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
