#!/usr/bin/env python3
"""Turn browser verdicts into a gold file score.py can read.

    python3 curation/arc-bakeoff/export-verdicts-to-gold.py

Reads  human-verdicts.json  (recorded in the catalog browser)
Writes gold-human.json      {slug: [{name, members:[guid]}]} -- score.py's exact shape

Verdicts store an arc INDEX, not guids, so this re-runs the detector to resolve members.
Each verdict carries the arc's name and member count as a checksum: if the detector has
changed since the verdict was recorded, indices shift, and a stale verdict is reported and
skipped rather than silently attached to a different arc.

A show marked "no arcs here" exports as an empty list. That is deliberate and valuable --
score.py --negatives counts arcs invented on those feeds as pure junk, which is the main
failure mode of any semantic tier.
"""
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FEEDS = HERE.parent.parent / "curation" / "feeds"
VERDICTS = HERE / "human-verdicts.json"
OUT = HERE / "gold-human.json"

sys.path.insert(0, str(HERE))
import approaches as AP  # noqa: E402

# Reuse the builder's attribution rather than restating the cascade in a second place.
_spec = importlib.util.spec_from_file_location("_bci", HERE / "build-catalog-index.py")
_bci = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_bci)


def main():
    if not VERDICTS.exists():
        sys.exit(f"no verdicts yet at {VERDICTS}")
    verdicts = json.loads(VERDICTS.read_text())

    gold, stale, missing = {}, [], []
    kept = negatives = rejected = 0

    for slug, rec in sorted(verdicts.items()):
        path = FEEDS / f"{slug}.json"
        if not path.exists():
            missing.append(slug)
            continue

        if rec.get("show") and rec["show"].get("v") == "none":
            gold[slug] = []          # a labeled negative
            negatives += 1
            continue

        arc_verdicts = rec.get("arcs") or {}
        if not arc_verdicts:
            continue

        episodes = _bci.load_episodes(path)
        final, _ = _bci.attribute(AP.sort_newest_first(episodes))

        entries = []
        for idx, v in sorted(arc_verdicts.items(), key=lambda kv: int(kv[0])):
            i = int(idx)
            if i >= len(final):
                stale.append(f"{slug}#{i} ({v.get('name')}) — arc no longer exists")
                continue
            arc = final[i]
            if v.get("count") and len(arc["members"]) != v["count"]:
                stale.append(f"{slug}#{i} ({v.get('name')}) — was {v['count']} episodes, now "
                             f"{len(arc['members'])}")
                continue
            if v.get("v") != "right":
                rejected += 1
                continue
            entries.append({"name": arc["name"], "members": list(arc["members"])})
            kept += 1
        if entries:
            gold[slug] = entries

    OUT.write_text(json.dumps(gold, ensure_ascii=False, indent=1) + "\n")

    print(f"feeds in gold-human.json  {len(gold)}")
    print(f"  arcs confirmed correct  {kept}")
    print(f"  feeds marked arcless    {negatives}")
    print(f"  arcs judged wrong/unsure (excluded)  {rejected}")
    if missing:
        print(f"!! {len(missing)} verdict slugs have no feed on disk: {missing[:5]}")
    if stale:
        print(f"!! {len(stale)} verdicts no longer line up with the detector and were skipped:")
        for s in stale[:10]:
            print(f"     {s}")
    print(f"\nwrote {OUT}")
    print("score against it with:")
    print("  python3 -c \"import sys;sys.path.insert(0,'curation/arc-bakeoff');import score,pathlib;"
          "r=score.evaluate(gold_path=pathlib.Path('curation/arc-bakeoff/gold-human.json'),"
          "score_negatives=True)['results'];print({k:(v['membership_precision'],v['junk_arc_rate'],"
          "v['arc_recall']) for k,v in r.items()})\"")


if __name__ == "__main__":
    main()
