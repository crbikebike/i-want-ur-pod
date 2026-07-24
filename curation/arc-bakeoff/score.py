#!/usr/bin/env python3
"""Score the arc-detection approaches against the gold labels, precision-first.

Reads:
  curation/feeds/<slug>.json         (fetched corpus)
  curation/arc-bakeoff/gold.json     (LLM ground truth: {slug: [{name, members:[guid]}]})
Writes:
  curation/arc-bakeoff/scoreboard.json

Metrics per approach (aggregated over gold feeds):
  membership_precision  correctly-placed episodes / all episodes the detector grouped   (PRIMARY)
  junk_arc_rate         detected arcs with no true match / detected arcs                  (PRIMARY, lower better)
  arc_precision         matched detected arcs / detected arcs         (= 1 - junk_arc_rate)
  arc_recall            matched true arcs / true arcs                 (tiebreaker)
  membership_recall     correctly-placed / all true-arc episodes
A detected arc matches a true arc when member-set Jaccard >= 0.5 (greedy best alignment).
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
FEEDS = ROOT / "curation" / "feeds"
GOLD_FEEDS = HERE / "gold_feeds"
GOLD = HERE / "gold.json"

sys.path.insert(0, str(HERE))
import approaches as AP  # noqa: E402

JACCARD_MATCH = 0.5


def load_feed(slug):
    # Gold scoring uses the exact frozen slice the labelers saw.
    p = GOLD_FEEDS / f"{slug}.json"
    if not p.exists():
        p = FEEDS / f"{slug}.json"
    if not p.exists():
        return None
    data = json.loads(p.read_text())
    return [{"guid": e["guid"], "title": e["title"], "season": e.get("season"),
             "episodeNumber": e.get("episodeNumber"),
             "episodeType": e.get("episodeType", "full"), "iso": e.get("iso", "")}
            for e in data.get("episodes", [])]


def jaccard(a, b):
    a, b = set(a), set(b)
    if not a and not b:
        return 0.0
    return len(a & b) / len(a | b)


def align(detected, truth):
    """Greedy best-Jaccard matching. Returns list of (det_idx, true_idx, jac, overlap)."""
    pairs = []
    for di, d in enumerate(detected):
        for ti, t in enumerate(truth):
            j = jaccard(d["members"], t["members"])
            if j > 0:
                pairs.append((j, di, ti))
    pairs.sort(reverse=True)
    used_d, used_t, matches = set(), set(), []
    for j, di, ti in pairs:
        if di in used_d or ti in used_t or j < JACCARD_MATCH:
            continue
        used_d.add(di)
        used_t.add(ti)
        overlap = len(set(detected[di]["members"]) & set(truth[ti]["members"]))
        matches.append((di, ti, j, overlap))
    return matches


def score_feed(detected, truth):
    matches = align(detected, truth)
    det_assigned = sum(len(d["members"]) for d in detected)
    true_total = sum(len(t["members"]) for t in truth)
    correct = sum(ov for _, _, _, ov in matches)
    return {
        "detected_arcs": len(detected),
        "true_arcs": len(truth),
        "matched": len(matches),
        "det_assigned": det_assigned,
        "true_total": true_total,
        "correct": correct,
    }


def evaluate(names=None):
    if not GOLD.exists():
        return None
    gold = json.loads(GOLD.read_text())
    contenders = AP.CONTENDERS if names is None else {n: AP.CONTENDERS[n] for n in names}
    results = {}
    for name, fn in contenders.items():
        agg = {"detected_arcs": 0, "true_arcs": 0, "matched": 0,
               "det_assigned": 0, "correct": 0, "true_total": 0, "feeds": 0, "errors": 0}
        per_feed = {}
        for slug, truth in gold.items():
            eps = load_feed(slug)
            if eps is None or not truth:
                continue
            try:
                detected = fn(eps)
            except Exception as e:  # noqa: BLE001 - a broken approach scores zero here
                agg["errors"] += 1
                per_feed[slug] = {"error": f"{type(e).__name__}: {e}"}
                continue
            s = score_feed(detected, truth)
            per_feed[slug] = s
            agg["feeds"] += 1
            for k in ("detected_arcs", "true_arcs", "matched", "det_assigned", "correct", "true_total"):
                agg[k] += s[k]
        da, ta = agg["detected_arcs"], agg["true_arcs"]
        results[name] = {
            "membership_precision": round(agg["correct"] / agg["det_assigned"], 4) if agg["det_assigned"] else 0.0,
            "membership_recall": round(agg["correct"] / agg["true_total"], 4) if agg["true_total"] else 0.0,
            "junk_arc_rate": round((da - agg["matched"]) / da, 4) if da else 0.0,
            "arc_precision": round(agg["matched"] / da, 4) if da else 0.0,
            "arc_recall": round(agg["matched"] / ta, 4) if ta else 0.0,
            "detected_arcs": da, "true_arcs": ta, "matched": agg["matched"],
            "feeds_scored": agg["feeds"], "errors": agg["errors"],
            "per_feed": per_feed,
        }
    # precision-first ranking
    ranking = sorted(results.keys(), key=lambda n: (
        -results[n]["membership_precision"],
        results[n]["junk_arc_rate"],
        -results[n]["arc_recall"],
    ))
    return {"results": results, "ranking": ranking}


def corpus_stats(names=None):
    contenders = AP.CONTENDERS if names is None else {n: AP.CONTENDERS[n] for n in names}
    slugs = [p.stem for p in FEEDS.glob("*.json") if p.stem != "_index"]
    stats = {}
    for name, fn in contenders.items():
        feeds_with_arcs = total_arcs = big = errors = 0
        for slug in slugs:
            eps = load_feed(slug)
            if not eps:
                continue
            try:
                arcs = fn(eps)
            except Exception:  # noqa: BLE001
                errors += 1
                continue
            if arcs:
                feeds_with_arcs += 1
            total_arcs += len(arcs)
            big += sum(1 for a in arcs if len(a["members"]) >= 3)
        stats[name] = {"feeds": len(slugs), "feeds_with_arcs": feeds_with_arcs,
                       "total_arcs": total_arcs, "arcs_ge3": big, "errors": errors}
    return stats


def main():
    out = {"scored": evaluate(), "corpus": corpus_stats()}
    (HERE / "scoreboard.json").write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n")
    if out["scored"]:
        print("RANK (precision-first):")
        for i, n in enumerate(out["scored"]["ranking"], 1):
            r = out["scored"]["results"][n]
            print(f"  {i}. {n:16s} memPrec={r['membership_precision']:.3f} "
                  f"junk={r['junk_arc_rate']:.3f} arcRecall={r['arc_recall']:.3f} "
                  f"({r['feeds_scored']} feeds)")
    else:
        print("No gold.json yet — corpus stats only.")
    print("\nCorpus coverage:")
    for n, s in out["corpus"].items():
        print(f"  {n:16s} {s['feeds_with_arcs']}/{s['feeds']} feeds have arcs, "
              f"{s['total_arcs']} arcs total")


if __name__ == "__main__":
    main()
