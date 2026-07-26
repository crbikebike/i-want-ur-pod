#!/usr/bin/env python3
"""Fetch per-episode descriptions for every show in the corpus, ONCE, to disk.

Step 0 of the episode-theming run (curation/arc-bakeoff/THEMING_PROMPT.md).

fetch-atlas-feeds.py never asked feeds for a description, so curation/feeds/*.json
carries six fields per episode and no synopsis. Titles alone cannot carry theming --
"Cinnamon Bears and Chocolate Gravy" is unthemeable without its blurb, and there are
thousands like it. Every feed serves descriptions and they are good.

Writes a SIDECAR, never an edit to curation/feeds/. That corpus is gitignored and
rebuilt by a script that skips existing files, so editing it in place would make the
corpus non-reproducible.

Runs in the main loop, never inside an agent: one network pass, agents read the output.
Polite + resilient by design -- sequential, delay between feeds, timeouts, limited
retries, resumable (skips a slug already on disk). Every failure is logged and skipped,
never fatal.

Usage:  python3 scripts/fetch-feed-descriptions.py [--limit N] [--only slug,slug]
Output: curation/arc-bakeoff/descriptions/<slug>.json  (gitignored -- third-party
        copyrighted blurbs) and descriptions/_index.json (run report)
"""

import argparse
import html
import importlib.util
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEED_DIR = ROOT / "curation" / "feeds"
OUT_DIR = ROOT / "curation" / "arc-bakeoff" / "descriptions"

IT = "{http://www.itunes.com/dtds/podcast-1.0.dtd}"
CONTENT = "{http://purl.org/rss/1.0/modules/content/}"

FEED_DELAY = 0.6    # seconds between feeds (matches fetch-atlas-feeds.py)
MAX_CHARS = 300     # the topic lands well inside this

# Shows whose feed resolves to a different show than their metadata claims. Kept in
# sync with THEMING_PROMPT.md; fetching them would just waste requests.
EXCLUDE = {
    "broken-record",    # a teenager's music vlog, not Rick Rubin's
    "hit-parade",       # a Spanish radio chart show
    "homecoming",       # a SoundCloud self-help podcast
    "gun-machine", "animal", "earshot", "shift", "startup",
    "making-oprah",     # byte-identical feed to making-obama
}


def _load_fetcher():
    """Import fetch-atlas-feeds.py for http_get + safe_fromstring.

    Reuse rather than copy: the XXE guard and retry logic must not drift between the
    two scripts. The hyphenated filename is not a valid module name, so go via spec.
    """
    path = ROOT / "scripts" / "fetch-atlas-feeds.py"
    spec = importlib.util.spec_from_file_location("_atlas_feeds", path)
    if spec is None or spec.loader is None:
        sys.exit(f"cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


TAGS = re.compile(r"<[^>]+>")
WS = re.compile(r"\s+")


def clean(raw: str) -> str:
    """HTML/entity soup -> one plain line, capped at MAX_CHARS."""
    if not raw:
        return ""
    # Unescape first: many feeds ship tags escaped (&lt;p&gt;) rather than in CDATA,
    # so stripping before unescaping would leave the markup behind. Unescape again
    # afterwards to catch entities that were double-encoded.
    text = html.unescape(raw)
    text = TAGS.sub(" ", text)
    text = html.unescape(text)
    text = WS.sub(" ", text).strip()
    if len(text) <= MAX_CHARS:
        return text
    cut = text[: MAX_CHARS - 1]      # leave room for the ellipsis; 300 is a hard cap
    space = cut.rfind(" ")
    if space > MAX_CHARS * 0.6:      # avoid slicing mid-word, but not at any cost
        cut = cut[:space]
    return cut.rstrip(" .,;:-") + "…"


def pick(item) -> str:
    """description, else itunes:summary, else content:encoded."""
    for tag in ("description", f"{IT}summary", f"{CONTENT}encoded"):
        got = clean(item.findtext(tag) or "")
        if got:
            return got
    return ""


def fetch_show(fetcher, slug: str, feed_url: str, want_guids: set[str]) -> dict:
    raw = fetcher.http_get(feed_url, timeout=45)
    root = fetcher.safe_fromstring(raw)
    channel = root.find("channel")
    if channel is None:
        channel = root

    descriptions: dict[str, str] = {}
    live_items = 0
    for item in channel.findall("item"):
        live_items += 1
        title = (item.findtext("title") or "").strip()
        # Mirror fetch-atlas-feeds.py's guid rule exactly, or nothing will line up.
        guid = (item.findtext("guid") or title).strip()
        if not guid:
            continue
        text = pick(item)
        if text:
            descriptions[guid] = text

    matched = want_guids & descriptions.keys()
    # Keep only what the stored corpus actually references. Live feeds have moved past
    # the snapshot (Radiolab: 663 live vs 659 stored) and the extras have no episode
    # to attach to.
    kept = {g: descriptions[g] for g in matched}
    return {
        "slug": slug,
        "fetchedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "feedUrl": feed_url,
        "liveItems": live_items,
        "storedEpisodes": len(want_guids),
        "matched": len(kept),
        "episodes": kept,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="stop after N shows (smoke test)")
    ap.add_argument("--only", default="", help="comma-separated slugs to fetch")
    args = ap.parse_args()

    if not FEED_DIR.is_dir():
        sys.exit(f"no corpus at {FEED_DIR}; run scripts/fetch-atlas-feeds.py first")

    fetcher = _load_fetcher()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    only = {s.strip() for s in args.only.split(",") if s.strip()}
    slugs = sorted(p.stem for p in FEED_DIR.glob("*.json") if not p.stem.startswith("_"))
    slugs = [s for s in slugs if s not in EXCLUDE and (not only or s in only)]
    if args.limit:
        slugs = slugs[: args.limit]

    index, ok, failed, cached = [], 0, 0, 0
    total = len(slugs)
    for i, slug in enumerate(slugs, 1):
        out = OUT_DIR / f"{slug}.json"
        if out.exists():
            cached += 1
            print(f"[{i}/{total}] SKIP (cached) {slug}", flush=True)
            continue

        try:
            feed = json.loads((FEED_DIR / slug).with_suffix(".json").read_text())
        except Exception as e:  # noqa: BLE001 - a bad corpus file is not fatal
            failed += 1
            print(f"[{i}/{total}] BAD-FEED  {slug} :: {type(e).__name__}: {e}", flush=True)
            index.append({"slug": slug, "status": "bad-feed-json"})
            continue

        url = feed.get("feedUrl")
        if not url:
            failed += 1
            print(f"[{i}/{total}] NO-URL    {slug}", flush=True)
            index.append({"slug": slug, "status": "no-feed-url"})
            continue

        want = {e["guid"] for e in feed.get("episodes", []) if e.get("guid")}
        try:
            data = fetch_show(fetcher, slug, url, want)
        except Exception as e:  # noqa: BLE001 - network is best-effort
            failed += 1
            print(f"[{i}/{total}] FETCH-ERR {slug} :: {type(e).__name__}: {e}", flush=True)
            index.append({"slug": slug, "status": "fetch-error",
                          "error": f"{type(e).__name__}: {e}"})
            time.sleep(FEED_DELAY)
            continue

        out.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        ok += 1
        miss = data["storedEpisodes"] - data["matched"]
        rate = (miss / data["storedEpisodes"] * 100) if data["storedEpisodes"] else 0.0
        print(f"[{i}/{total}] OK        {slug}: {data['matched']}/{data['storedEpisodes']} "
              f"matched (miss {rate:.1f}%)", flush=True)
        index.append({"slug": slug, "status": "ok", "matched": data["matched"],
                      "storedEpisodes": data["storedEpisodes"],
                      "missRatePct": round(rate, 1)})
        time.sleep(FEED_DELAY)

    report = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "total": total, "ok": ok, "cached": cached, "failed": failed,
        "shows": index,
    }
    (OUT_DIR / "_index.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"\nDONE  total={total} ok={ok} cached={cached} failed={failed}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
