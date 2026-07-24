#!/usr/bin/env python3
"""Build the bundled offline catalog: curation/catalog/{catalog.json, themes.json}.

Joins three sources — all offline except a one-time build-time iTunes enrichment:
  1. curation/atlas-data.json      -> title, network, years, description, `why`,
                                      and theme membership (arcs[].showIds).
  2. curation/feeds/<slug>.json    -> feedUrl (resolved in Phase 0 by fetch-atlas-feeds.py).
  3. iTunes Search (build time)    -> author (artistName), artworkUrl, homeUrl
                                      (collectionViewUrl), category (primaryGenreName).

Output shape is a SUPERSET of the shipped curated pattern (docs/spec/curated-list.schema.md /
DirectoryKit CuratedEntry) so it plugs into the app's loader + subscribe path unchanged. Only
shows with a live feedUrl are emitted. iTunes results are cached so re-runs are offline+instant.

Usage: python3 scripts/build-catalog.py
"""
import json
import re
import time
import urllib.parse
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ATLAS = ROOT / "curation" / "atlas-data.json"
FEEDS = ROOT / "curation" / "feeds"
OUT = ROOT / "curation" / "catalog"
CACHE = OUT / "_itunes_cache.json"
UA = "Mozilla/5.0 (iWantUrPod catalog build; +https://example.invalid/contact)"
ITUNES_DELAY = 0.5


def slugify(t: str) -> str:
    s = re.sub(r"^(the|a|an)\s+", "", (t or "").lower())
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-") or "show"


def norm(t: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", re.sub(r"^(the|a|an)\s+", "", (t or "").lower()))


def http_get(url: str, timeout: int = 20) -> bytes:
    last = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(0.8 * (attempt + 1))
    raise last  # type: ignore[misc]


def upscale(art: str) -> str:
    """Bump an iTunes artwork URL (…/600x600bb.jpg) to 3000px, matching the curated bundle."""
    return re.sub(r"/\d+x\d+bb", "/3000x3000bb", art) if art else art


def itunes_enrich(title: str, feed_url: str, cache: dict) -> dict:
    """Return {author, artworkUrl, homeUrl, category} for a show, matched to its feedUrl."""
    key = feed_url or title
    if key in cache:
        return cache[key]
    q = urllib.parse.urlencode({"term": title, "entity": "podcast", "limit": 5, "country": "US"})
    result = {"author": "", "artworkUrl": "", "homeUrl": "", "category": ""}
    try:
        data = json.loads(http_get(f"https://itunes.apple.com/search?{q}"))
        results = data.get("results", [])
        # prefer the result whose feedUrl matches ours; else best title match
        pick = next((r for r in results if r.get("feedUrl") == feed_url), None)
        if pick is None and results:
            want = norm(title)
            pick = max(results, key=lambda r: SequenceMatcher(None, want, norm(r.get("collectionName", ""))).ratio())
        if pick:
            result = {
                "author": pick.get("artistName", ""),
                "artworkUrl": upscale(pick.get("artworkUrl600") or pick.get("artworkUrl100") or ""),
                "homeUrl": pick.get("collectionViewUrl", ""),
                "category": pick.get("primaryGenreName", ""),
            }
    except Exception:  # noqa: BLE001 - enrichment is best-effort; feed still ships
        pass
    cache[key] = result
    time.sleep(ITUNES_DELAY)
    return result


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    atlas = json.loads(ATLAS.read_text())
    shows = atlas["shows"]
    arcs = atlas["arcs"]

    # show id -> [arc slug], and arc slug -> {name, description}
    themes_of = {}
    theme_meta = {}
    for a in arcs:
        theme_meta[a["slug"]] = {"name": a["arc"], "description": a["description"]}
        for sid in a.get("showIds", []):
            themes_of.setdefault(sid, []).append(a["slug"])

    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    catalog = []
    theme_counts = {}
    total = len(shows)
    for i, s in enumerate(shows, 1):
        slug = slugify(s["title"])
        feed_file = FEEDS / f"{slug}.json"
        if not feed_file.exists():
            continue
        try:
            feed = json.loads(feed_file.read_text())
        except Exception:  # noqa: BLE001
            continue
        feed_url = feed.get("feedUrl")
        if not feed_url:
            continue
        enr = itunes_enrich(s["title"], feed_url, cache)
        show_themes = themes_of.get(s["id"], [])
        for t in show_themes:
            theme_counts[t] = theme_counts.get(t, 0) + 1
        catalog.append({
            "id": s["id"],
            "title": s["title"],
            "author": enr["author"] or s.get("network", ""),
            "network": s.get("network", ""),
            "feedUrl": feed_url,
            "homeUrl": enr["homeUrl"],
            "artworkUrl": enr["artworkUrl"],
            "category": enr["category"],
            "years": s.get("years", ""),
            "why": s.get("why", ""),
            "description": s.get("description", ""),
            "themes": show_themes,
        })
        if i % 25 == 0:
            print(f"[{i}/{total}] built {len(catalog)} entries…", flush=True)
        CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2))  # checkpoint cache

    themes = [{"slug": slug, "name": m["name"], "description": m["description"],
               "showCount": theme_counts.get(slug, 0)}
              for slug, m in theme_meta.items()]
    themes.sort(key=lambda t: -t["showCount"])

    (OUT / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    (OUT / "themes.json").write_text(json.dumps(themes, ensure_ascii=False, indent=2) + "\n")
    missing_art = sum(1 for e in catalog if not e["artworkUrl"])
    print(f"\nDONE  catalog.json={len(catalog)} shows  themes.json={len(themes)}  "
          f"(missing artwork: {missing_art})")


if __name__ == "__main__":
    main()
