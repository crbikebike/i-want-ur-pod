#!/usr/bin/env python3
"""Episode-level theme taxonomy for anthology shows.

Anthology feeds have no multi-part arcs -- every episode is a different story -- but they
are not unstructured. Swindled's Ford Pinto, OceanGate and ValuJet episodes are all the
same story: a company cut corners and people died. Nothing in the arc pipeline can see it.

    python3 build-episode-themes.py extract --slug swindled
    # ... run episode-theme-workflow.mjs over the emitted file ...
    python3 build-episode-themes.py merge --slug swindled --result /path/to/workflow.json

extract  pulls each episode's real subject out of its title and writes the model's input
merge    validates + audits the model's output and writes episode-themes/<slug>.json

Stdlib only, per HFAB_PROMPT.md.
"""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
FEEDS = HERE.parent.parent / "curation" / "feeds"
THEMES = HERE.parent.parent / "curation" / "catalog" / "themes.json"
OUT_DIR = HERE / "episode-themes"

# Audit thresholds. A category smaller than MIN is a label, not a category; one larger
# than MAX_SHARE is a bucket that draws no distinction.
MIN_THEME_EPISODES = 3
MAX_THEME_SHARE = 0.35
VOCAB_MIN, VOCAB_MAX = 10, 16

# A trailing parenthetical usually holds the real subject -- but not when it holds a
# counter. dirt-cheap scores a false 100% on this shape because its parens carry
# "(Chapter 14 of MITGR)". Reject those rather than feed the model garbage.
COUNTER_IN_PAREN = re.compile(r'\b(chapter|part|pt\.?|vol(?:ume)?|episode|ep\.?)\s*\d', re.I)
TRAILING_PAREN = re.compile(r'\(([^()]{2,80})\)\s*$')

# Per-show extraction. Adding an anthology means adding an entry here, nothing else.
SHOWS = {
    "swindled": {
        # "S10 Ep141: The Mirage (Nikola Motor Company)" -> "The Mirage" + "Nikola Motor Company"
        "strip": re.compile(r'^\s*(?:S\d+\s*Ep?\.?\s*\d*\s*:|Rerun:|Free Bonus:|Bonus:)\s*', re.I),
        "rerun": re.compile(r'^\s*Rerun:\s*', re.I),
        "subject": "trailing-paren",
        "include_types": ("full", "bonus"),
    },
}


def load_feed(slug):
    path = FEEDS / f"{slug}.json"
    if not path.exists():
        sys.exit(f"no feed at {path}")
    return json.loads(path.read_text())


def extract(slug):
    cfg = SHOWS.get(slug)
    if not cfg:
        sys.exit(f"no extractor configured for {slug!r}; known: {sorted(SHOWS)}")
    data = load_feed(slug)

    rows, dropped_rerun, no_subject = [], [], []
    seen = {}
    for e in data["episodes"]:
        etype = e.get("episodeType", "full")
        if etype not in cfg["include_types"]:
            continue
        raw = e["title"]
        is_rerun = bool(cfg["rerun"].match(raw))
        display = cfg["strip"].sub("", raw).strip()

        subject = None
        if cfg["subject"] == "trailing-paren":
            m = TRAILING_PAREN.search(display)
            if m and not COUNTER_IN_PAREN.search(m.group(1)):
                subject = m.group(1).strip()
                display = display[:m.start()].strip()

        key = (display.lower(), (subject or "").lower())
        if key in seen:
            # Same story twice. Feeds are newest-first, so the RE-AIRING is seen first and
            # the original second -- keep the original and evict the rerun, otherwise the
            # surviving row is titled "Rerun: ..." and points at the wrong episode.
            prev = seen[key]
            if rows[prev]["rerun"] and not is_rerun:
                rows[prev].update(guid=e["guid"], iso=e.get("iso", ""), type=etype, rerun=False)
            dropped_rerun.append(raw)
            continue
        seen[key] = len(rows)

        if not subject:
            no_subject.append(raw)
        rows.append({"i": len(rows), "guid": e["guid"], "display": display,
                     "subject": subject or display, "iso": e.get("iso", ""),
                     "type": etype, "rerun": is_rerun})

    OUT_DIR.mkdir(exist_ok=True)
    out = OUT_DIR / f"_input-{slug}.json"
    out.write_text(json.dumps({"slug": slug, "title": data.get("title", slug),
                               "episodes": rows}, ensure_ascii=False, indent=1) + "\n")

    print(f"show                 {data.get('title', slug)}")
    print(f"episodes kept        {len(rows)}")
    print(f"  re-airings dropped {len(dropped_rerun)}")
    print(f"  subject extracted  {len(rows) - len(no_subject)}/{len(rows)}")
    if no_subject:
        print(f"  NO SUBJECT ({len(no_subject)}) — model sees the title only:")
        for t in no_subject[:6]:
            print(f"     {t[:74]}")
    print(f"\nwrote {out}")
    print("next: run episode-theme-workflow.mjs with args {\"slug\":\"%s\"}" % slug)


def audit(vocab, episodes, known_themes):
    """Every check that must hold before this is worth looking at."""
    problems = []
    slugs = {v["slug"] for v in vocab}

    if not VOCAB_MIN <= len(vocab) <= VOCAB_MAX:
        problems.append(f"vocabulary is {len(vocab)} themes, wanted {VOCAB_MIN}-{VOCAB_MAX}")

    counts = collections.Counter()
    for ep in episodes:
        p = ep.get("primary")
        if not p:
            problems.append(f"episode {ep.get('i')} has no primary theme")
            continue
        if p not in slugs:
            problems.append(f"episode {ep.get('i')} primary {p!r} is not in the vocabulary")
        counts[p] += 1
        for sec in ep.get("secondary") or []:
            if sec not in slugs:
                problems.append(f"episode {ep.get('i')} secondary {sec!r} is not in the vocabulary")
            if sec == p:
                problems.append(f"episode {ep.get('i')} repeats its primary as a secondary")
        if len(ep.get("secondary") or []) > 2:
            problems.append(f"episode {ep.get('i')} has more than 2 secondary themes")

    total = len(episodes)
    for v in vocab:
        n = counts.get(v["slug"], 0)
        if n < MIN_THEME_EPISODES:
            problems.append(f"theme {v['slug']!r} has only {n} episodes (min {MIN_THEME_EPISODES})")
        if total and n / total > MAX_THEME_SHARE:
            problems.append(f"theme {v['slug']!r} holds {n}/{total} "
                            f"({n / total:.0%}) — over the {MAX_THEME_SHARE:.0%} ceiling")
        m = v.get("mapsTo")
        if m and m not in known_themes:
            problems.append(f"theme {v['slug']!r} maps to unknown show-level theme {m!r}")
    return problems, counts


def merge(slug, result_path):
    src = json.loads(Path(result_path).read_text())
    inp = json.loads((OUT_DIR / f"_input-{slug}.json").read_text())
    by_i = {e["i"]: e for e in inp["episodes"]}
    known = {t["slug"] for t in json.loads(THEMES.read_text())}

    vocab = src["vocabulary"]
    assigns = {a["i"]: a for a in src["assignments"]}
    missing = [i for i in by_i if i not in assigns]
    if missing:
        sys.exit(f"FATAL: {len(missing)} episodes were never assigned: {missing[:10]}")

    episodes = []
    for i, ep in sorted(by_i.items()):
        a = assigns[i]
        episodes.append({**ep, "primary": a.get("primary"),
                         "secondary": [s for s in (a.get("secondary") or []) if s != a.get("primary")],
                         "confidence": a.get("confidence", "")})

    problems, counts = audit(vocab, episodes, known)
    for v in vocab:
        v["count"] = counts.get(v["slug"], 0)
    vocab.sort(key=lambda v: -v["count"])

    out = {"slug": slug, "title": inp["title"], "models": src.get("models", {}),
           "vocabulary": vocab, "episodes": episodes,
           "agreement": src.get("agreement", {})}
    OUT_DIR.mkdir(exist_ok=True)
    dest = OUT_DIR / f"{slug}.json"
    dest.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n")

    print(f"episodes    {len(episodes)}")
    print(f"vocabulary  {len(vocab)} themes")
    for v in vocab:
        share = v["count"] / len(episodes) if episodes else 0
        maps = f"  -> {v['mapsTo']}" if v.get("mapsTo") else ""
        print(f"   {v['count']:4d}  {share:5.1%}  {v['slug']:32s} {v['name']}{maps}")
    ag = out["agreement"].get("primaryAgreement")
    if ag is not None:
        print(f"\ntwo-run primary agreement  {ag:.1%}")
    print()
    if problems:
        print(f"AUDIT FAILED — {len(problems)} problem(s):")
        for p in problems:
            print(f"   ! {p}")
        print("\nre-run the consolidation pass with this report as input.")
    else:
        print("AUDIT PASSED")
    print(f"\nwrote {dest}")
    return 1 if problems else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("extract"); e.add_argument("--slug", required=True)
    m = sub.add_parser("merge"); m.add_argument("--slug", required=True); m.add_argument("--result", required=True)
    args = ap.parse_args()
    if args.cmd == "extract":
        extract(args.slug)
    else:
        sys.exit(merge(args.slug, args.result))


if __name__ == "__main__":
    main()
