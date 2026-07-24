#!/usr/bin/env python3
"""Episode-level membership-precision diagnostic for the winner.

For each detected arc that MATCHED a gold arc but includes episodes NOT in that gold arc
(over-inclusions), report the detected arc, the matched gold arc, and the leaked episodes —
plus the part-number sequence, so we can see whether a prefix-merge folded two arcs together.

Usage: python3 memprec-diagnose.py [approach]   (default A2r3.1-guard)
Writes curation/arc-bakeoff/memprec-<approach>.json and prints a summary.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import approaches as AP  # noqa: E402
import score as SC  # noqa: E402

NAME = sys.argv[1] if len(sys.argv) > 1 else "A2r3.1-guard"


def main():
    gold = json.loads((HERE / "gold.json").read_text())
    fn = AP.CONTENDERS[NAME]
    clusters = []
    for slug, truth in gold.items():
        if not truth:
            continue
        eps = SC.load_feed(slug)
        if not eps:
            continue
        by_guid = {e["guid"]: e for e in eps}
        det = fn(eps)
        matches = SC.align(det, truth)
        matched = {di: ti for di, ti, _, _ in matches}
        for di, d in enumerate(det):
            if di not in matched:
                continue
            t = truth[matched[di]]
            tset = set(t["members"])
            leaked = [g for g in d["members"] if g not in tset]
            if not leaked:
                continue
            clusters.append({
                "slug": slug,
                "detected_name": d["name"],
                "detected_titles": [by_guid.get(g, {}).get("title", "?") for g in d["members"]],
                "matched_gold_name": t["name"],
                "matched_gold_titles": [by_guid.get(g, {}).get("title", "?") for g in t["members"]],
                "leaked_guids": leaked,
                "leaked_titles": [by_guid.get(g, {}).get("title", "?") for g in leaked],
            })
    (HERE / f"memprec-{NAME}.json").write_text(json.dumps(clusters, ensure_ascii=False, indent=2) + "\n")
    print(f"{NAME}: {len(clusters)} arcs with over-inclusions, "
          f"{sum(len(c['leaked_guids']) for c in clusters)} leaked episodes\n")
    for c in clusters:
        print(f"[{c['slug']}] detected {c['detected_name']!r} ({len(c['detected_titles'])} eps)"
              f" matched gold {c['matched_gold_name']!r} ({len(c['matched_gold_titles'])} eps)")
        print(f"    detected: {c['detected_titles']}")
        print(f"    gold arc: {c['matched_gold_titles']}")
        print(f"    LEAKED:   {c['leaked_titles']}\n")


if __name__ == "__main__":
    main()
