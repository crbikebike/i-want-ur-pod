#!/usr/bin/env python3
"""Fetch real podcast cover art + directory metadata for the design kit.

Reusable so prototypes don't re-pull the same data. It queries Apple's iTunes
Search API (the same source the shipping app uses), downloads each show's cover
to `design/kit/art/<slug>.jpg`, and writes a metadata manifest to
`design/kit/art/podcasts.json` (title, author, feed URL, artwork URL, genre,
iTunes collection id). Screens reference the art as `../art/<slug>.jpg`.

Usage:
    python3 scripts/fetch-podcast-art.py            # add any missing art + refresh manifest
    python3 scripts/fetch-podcast-art.py --force    # re-download every image

Add a show: put a `slug: "search term"` line in ROSTER and re-run. Keep slugs
stable — screens reference them by name.
"""

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART_DIR = ROOT / "design" / "kit" / "art"
MANIFEST = ART_DIR / "podcasts.json"

# slug -> iTunes search term. The first podcast result is used. Slugs are the
# stable handle screens reference (`../art/<slug>.jpg`); don't rename casually.
ROSTER = {
    "acquired": "Acquired podcast Ben Gilbert",
    "99pi": "99% Invisible",
    "the-daily": "The Daily New York Times",
    "serial": "Serial podcast",
    "radiolab": "Radiolab",
    "rest-is-history": "The Rest Is History Goalhanger",
    "behind-the-bastards": "Behind the Bastards",
    "search-engine": "Search Engine PJ Vogt",
    "bone-valley": "Bone Valley Lava for Good",
    "crime-junkie": "Crime Junkie audiochuck",
    "theory-of-everything": "Theory of Everything Benjamen Walker",
    "ezra-klein": "The Ezra Klein Show",
    "20k-hertz": "Twenty Thousand Hertz",
    "song-exploder": "Song Exploder",
    "hardcore-history": "Dan Carlin Hardcore History",
    "fall-of-civilizations": "Fall of Civilizations podcast",
    "the-ancients": "The Ancients History Hit",
    "empire": "Empire Goalhanger Dalrymple",
    "dead-to-me": "You're Dead to Me BBC",
    "revolutions": "Revolutions Mike Duncan",
    "american-history-tellers": "American History Tellers",
    "explorers-podcast": "The Explorers Podcast",
}

ITUNES = "https://itunes.apple.com/search"


def fetch_meta(term: str) -> dict | None:
    query = urllib.parse.urlencode(
        {"media": "podcast", "entity": "podcast", "term": term, "limit": 1}
    )
    with urllib.request.urlopen(f"{ITUNES}?{query}", timeout=20) as resp:
        data = json.load(resp)
    results = data.get("results") or []
    return results[0] if results else None


def art_url(meta: dict, size: int = 300) -> str | None:
    raw = meta.get("artworkUrl600") or meta.get("artworkUrl100")
    if not raw:
        return None
    return raw.replace("600x600bb", f"{size}x{size}bb").replace(
        "100x100bb", f"{size}x{size}bb"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="re-download every image")
    args = parser.parse_args()

    ART_DIR.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, dict] = {}
    failures: list[str] = []

    for slug, term in ROSTER.items():
        try:
            meta = fetch_meta(term)
        except Exception as exc:  # network/API hiccup
            failures.append(f"{slug}: search failed ({exc})")
            continue
        if not meta:
            failures.append(f"{slug}: no results for '{term}'")
            continue

        dest = ART_DIR / f"{slug}.jpg"
        if args.force or not dest.exists():
            url = art_url(meta)
            if not url:
                failures.append(f"{slug}: no artwork url")
            else:
                try:
                    with urllib.request.urlopen(url, timeout=25) as img:
                        dest.write_bytes(img.read())
                except Exception as exc:
                    failures.append(f"{slug}: image download failed ({exc})")

        manifest[slug] = {
            "title": meta.get("collectionName", ""),
            "author": meta.get("artistName", ""),
            "feedUrl": meta.get("feedUrl", ""),
            "homeUrl": meta.get("collectionViewUrl", ""),
            "artworkUrl": meta.get("artworkUrl600", ""),
            "genre": meta.get("primaryGenreName", ""),
            "itunesCollectionId": meta.get("collectionId"),
            "file": f"{slug}.jpg",
        }
        time.sleep(0.15)  # be polite to the API

    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"manifest: {MANIFEST.relative_to(ROOT)} ({len(manifest)} shows)")
    have = len(list(ART_DIR.glob("*.jpg")))
    print(f"images:   {have} in {ART_DIR.relative_to(ROOT)}")
    if failures:
        print("\nfailures:", file=sys.stderr)
        for line in failures:
            print(f"  - {line}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
