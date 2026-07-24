#!/usr/bin/env python3
"""Pick a stratified gold set spanning naming styles, and freeze an episode slice
per selected feed so the labelers and the scorer see the EXACT same episodes.

Writes:
  curation/arc-bakeoff/gold_feeds/<slug>.json   frozen slice {slug,title,episodes[]}
  curation/arc-bakeoff/gold_manifest.json       selection + per-feed style signals
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
FEEDS = ROOT / "curation" / "feeds"
GOLD_FEEDS = HERE / "gold_feeds"

sys.path.insert(0, str(HERE))
import approaches as AP  # noqa: E402

SLICE = 150            # newest N episodes frozen per gold feed
PER_TYPE = 12          # target feeds per style bucket
TOTAL_TARGET = 72
MIN_EPS = 8
ALWAYS = {"american-history-tellers", "explorers-podcast"}


def signals(eps):
    n = len(eps)
    if not n:
        return {}, "empty"
    hit = Counter()
    for e in eps:
        t = AP.strip_noise(e["title"])
        if AP.PIPE.match(t):
            hit["pipe"] += 1
        elif AP.PART.match(t):
            hit["dash-part"] += 1
        elif AP.CHAPTER_LEAD.match(t):
            hit["chapter"] += 1
        elif AP.TRAIL_PAREN.match(t) or AP.TRAIL_COMMA.match(t):
            hit["trailing-part"] += 1
        elif AP.TRAIL_EP.match(t) or AP.TRAIL_CHAPTER.match(t):
            hit["trailing-ep"] += 1
        elif any(rx.match(t) for rx in (AP.A1_SEASON, AP.A1_SERIES, AP.A1_BOOK, AP.A1_VOL)):
            hit["labeled-season"] += 1
        elif AP.COUNTER_ANY.match(t):
            hit["loose-counter"] += 1
    seasons = {e.get("season") for e in eps if e.get("season") is not None}
    frac = {k: round(v / n, 3) for k, v in hit.items()}
    structured = sum(hit.values())
    if structured >= 0.25 * n and hit:
        style = hit.most_common(1)[0][0]
    elif len(seasons) >= 2:
        style = "season-tagged"
    else:
        style = "unstructured"
    return {"fractions": frac, "distinct_seasons": len(seasons), "episodes": n}, style


def main():
    slugs = sorted(p.stem for p in FEEDS.glob("*.json") if p.stem != "_index")
    feeds = {}
    for slug in slugs:
        data = json.loads((FEEDS / f"{slug}.json").read_text())
        eps = data.get("episodes", [])
        eps = sorted(eps, key=lambda e: e.get("iso") or "", reverse=True)[:SLICE]
        if len(eps) < MIN_EPS and slug not in ALWAYS:
            continue
        sig, style = signals(eps)
        feeds[slug] = {"title": data.get("title", slug), "style": style, "sig": sig, "eps": eps}

    buckets = {}
    for slug, f in feeds.items():
        buckets.setdefault(f["style"], []).append(slug)

    selected = set(s for s in ALWAYS if s in feeds)
    # round-robin across styles, richest feeds first, until target reached
    for style in sorted(buckets, key=lambda s: -len(buckets[s])):
        ranked = sorted(buckets[style], key=lambda s: -feeds[s]["sig"]["episodes"])
        for slug in ranked[:PER_TYPE]:
            selected.add(slug)
    # trim/pad toward target deterministically
    selected = list(selected)
    if len(selected) > TOTAL_TARGET:
        selected = sorted(selected, key=lambda s: (feeds[s]["style"], -feeds[s]["sig"]["episodes"]))[:TOTAL_TARGET]

    GOLD_FEEDS.mkdir(exist_ok=True)
    manifest = {"slice": SLICE, "selected": [], "style_counts": Counter()}
    for slug in selected:
        f = feeds[slug]
        out = {"slug": slug, "title": f["title"],
               "episodes": [{"guid": e["guid"], "title": e["title"], "season": e.get("season"),
                             "episodeNumber": e.get("episodeNumber"),
                             "episodeType": e.get("episodeType", "full"), "iso": e.get("iso", "")}
                            for e in f["eps"]]}
        (GOLD_FEEDS / f"{slug}.json").write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n")
        manifest["selected"].append({"slug": slug, "title": f["title"], "style": f["style"],
                                     "episodes": len(f["eps"])})
        manifest["style_counts"][f["style"]] += 1
    manifest["style_counts"] = dict(manifest["style_counts"])
    manifest["total_selected"] = len(selected)
    (HERE / "gold_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Selected {len(selected)} gold feeds across styles: {manifest['style_counts']}")


if __name__ == "__main__":
    main()
