#!/usr/bin/env python3
"""Fetch real episodes + derive story arcs from podcast RSS feeds.

Reusable companion to fetch-podcast-art.py. For each show it downloads the RSS
feed (the same feed the app parses), extracts per-episode fields, and derives
**story arcs** from the episode-title structure — so the design kit's Podcast
Detail screen can be built from real data, not invented fixtures.

Arc derivation (the "get it from somewhere" heuristic):
  - "Arc | Episode Title | N"     -> arc, episode title, part N   (art19 / AHT)
  - "Arc - Part N - Subtitle"     -> arc, subtitle,     part N     (Explorers)
  - anything else                 -> a "single" (no arc)
Season number is read from <itunes:season> when the feed sets it (AHT has it;
Explorers does not — the screen degrades to arc/date grouping).

Output: design/kit/data/<slug>.json  { show, episodes[], arcs[] }.

Usage:  python3 scripts/fetch-podcast-episodes.py
Add a show: put a `slug: feed_url` line in FEEDS and re-run.
"""

import html
import json
import re
import urllib.request
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "design" / "kit" / "data"
IT = "{http://www.itunes.com/dtds/podcast-1.0.dtd}"

# slug -> feed URL. Slug matches the art slug in design/kit/art/<slug>.jpg.
FEEDS = {
    "american-history-tellers": "https://rss.art19.com/american-history-tellers",
    "explorers-podcast": "https://feeds.megaphone.fm/ADL4434397541",
}

# Re-release / housekeeping prefixes that pollute an arc name.
NOISE_PREFIX = re.compile(r'^(Encore|Fan Favorite|Listen Now|New Season|Introducing|Presenting)\s*:?\s*', re.I)


def derive_arc(title: str):
    """Return (arc_name|None, episode_title, part|None)."""
    cleaned = NOISE_PREFIX.sub("", title).strip()
    m = re.match(r'^(.+?)\s*\|\s*(.+?)\s*\|\s*(\d+)\s*$', cleaned)      # AHT
    if m:
        return m.group(1).strip(), m.group(2).strip(), int(m.group(3))
    m = re.match(r'^(.+?)\s*-\s*Part\s*(\d+)\s*(?:-\s*(.*))?$', cleaned, re.I)  # Explorers
    if m:
        return m.group(1).strip(), (m.group(3) or "").strip(), int(m.group(2))
    return None, cleaned, None


def parse_duration(text: str | None) -> int:
    if not text:
        return 0
    text = text.strip()
    if text.isdigit():
        return int(text)
    parts = text.split(":")
    try:
        parts = [int(p) for p in parts]
    except ValueError:
        return 0
    secs = 0
    for p in parts:
        secs = secs * 60 + p
    return secs


def strip_html(text: str) -> str:
    text = re.sub(r'(?is)<(script|style).*?</\1>', '', text)
    text = re.sub(r'(?i)<br\s*/?>', ' ', text)
    text = re.sub(r'(?i)</p>', ' ', text)
    text = re.sub(r'<[^>]+>', '', text)
    return re.sub(r'\s+', ' ', html.unescape(text)).strip()


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (iWantUrPod design kit)"})
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.read()


def safe_fromstring(raw: bytes):
    """Parse RSS with stdlib ElementTree, but block the DTD-based attacks it's
    vulnerable to (XXE, billion-laughs). Podcast RSS never declares a DTD, so a
    DOCTYPE/ENTITY is either malformed or hostile — reject rather than expand."""
    head = raw[:4096].lower()
    if b"<!doctype" in head or b"<!entity" in raw.lower():
        raise ValueError("feed declares a DTD/entity — refusing to parse (XXE guard)")
    return ET.fromstring(raw)


def build(slug: str, url: str) -> dict:
    root = safe_fromstring(fetch(url))
    channel = root.find("channel")
    if channel is None:
        channel = root
    show = {
        "slug": slug,
        "title": (channel.findtext("title") or "").strip(),
        "author": (channel.findtext(f"{IT}author") or "").strip(),
        "category": "",
        "summary": strip_html(channel.findtext("description") or channel.findtext(f"{IT}summary") or ""),
        "feedUrl": url,
        "artworkSlug": slug,
    }
    cat = channel.find(f"{IT}category")
    if cat is not None:
        show["category"] = cat.get("text", "")

    episodes = []
    for it in channel.findall("item"):
        title = (it.findtext("title") or "").strip()
        arc, ep_title, part = derive_arc(title)
        season = it.findtext(f"{IT}season")
        epnum = it.findtext(f"{IT}episode")
        pub = it.findtext("pubDate")
        try:
            dt = parsedate_to_datetime(pub) if pub else None
        except (TypeError, ValueError):
            dt = None
        episodes.append({
            "guid": (it.findtext("guid") or title).strip(),
            "rawTitle": title,
            "arc": arc,
            "episodeTitle": ep_title,
            "part": part,
            "season": int(season) if season and season.isdigit() else None,
            "episodeNumber": int(epnum) if epnum and epnum.isdigit() else None,
            "date": dt.strftime("%b %-d, %Y") if dt else "",
            "iso": dt.date().isoformat() if dt else "",
            "durationSec": parse_duration(it.findtext(f"{IT}duration")),
            "episodeType": (it.findtext(f"{IT}episodeType") or "full").strip(),
            "summary": strip_html(it.findtext("description") or it.findtext(f"{IT}summary") or "")[:400],
        })

    # Arcs in feed order (newest first). Season taken from members when present.
    arcs = []
    seen = {}
    for i, e in enumerate(episodes):
        if not e["arc"]:
            continue
        if e["arc"] not in seen:
            seen[e["arc"]] = {"name": e["arc"], "season": e["season"], "parts": 0, "episodeIndices": []}
            arcs.append(seen[e["arc"]])
        seen[e["arc"]]["parts"] += 1
        seen[e["arc"]]["episodeIndices"].append(i)
        if seen[e["arc"]]["season"] is None and e["season"] is not None:
            seen[e["arc"]]["season"] = e["season"]

    return {"show": show, "episodes": episodes, "arcs": arcs,
            "counts": {"episodes": len(episodes), "arcs": len(arcs),
                       "singles": sum(1 for e in episodes if not e["arc"])}}


def main() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    for slug, url in FEEDS.items():
        data = build(slug, url)
        out = DATA_DIR / f"{slug}.json"
        out.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        c = data["counts"]
        print(f"{slug}: {c['episodes']} eps, {c['arcs']} arcs, {c['singles']} singles -> {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
