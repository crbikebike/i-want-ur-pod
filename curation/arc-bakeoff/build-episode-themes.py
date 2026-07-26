#!/usr/bin/env python3
"""Episode-level theme index over the whole catalog.

See THEMING_PROMPT.md. Themes are a second index beside arcs, not a mop-up for the
shows the arc detector could not reach: an episode inside an arc still has a subject,
so it still gets a theme.

    python3 build-episode-themes.py prepare
    # ... run episode-theme-workflow.mjs over episode-themes/_input-all.json ...
    python3 build-episode-themes.py finalize --result /path/to/workflow.json

prepare   parse every full episode in the corpus into model input (title, segment,
          subject, description) and write _input-all.json
finalize  validate + audit the model's output, then write _vocabulary.json, one file
          per show, and _run-report.json

Stdlib only.
"""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
FEEDS = ROOT / "curation" / "feeds"
DESCS = HERE / "descriptions"
THEMES = ROOT / "curation" / "catalog" / "themes.json"
OUT_DIR = HERE / "episode-themes"
IN_DIR = OUT_DIR / "_input"          # per-show model input
WORK = OUT_DIR / "_work"             # raw agent output, merged by finalize

# Episodes per model call. The brief specified 80; this box has 4 cores, so the workflow
# runs only min(16, cores-2) = 2 agents at a time and 80 would need ~17h of wall clock.
# Bigger batches trade some per-row attention for finishing in one night. Assign emits
# ~3 theme applications per row, so its batches stay smaller to avoid truncation.
BATCH = 130
ASSIGN_BATCH = 130
BRIEF_CHARS = 120        # description length for open coding; the gist is enough there
DESC_CHARS = 150         # description length for assigning from a fixed vocabulary

# Open coding exists to DERIVE the vocabulary, not to label the catalog -- assign does
# that, and assign still covers every episode. A 663-episode show does not contribute
# 663 episodes' worth of new theme ideas, so cap what open coding reads per show and
# sample evenly across the run. Every show stays represented, which is what
# consolidation needs; shows at or under the cap are still read in full.
OPEN_CAP = 50

sys.path.insert(0, str(HERE))
from approaches import a8_cascade  # noqa: E402  -- read-only; this job never edits it

# --- audit thresholds -------------------------------------------------------------
# Catalog level. A theme under MIN is a label, not a category; one over MAX_SHARE
# draws no distinction across 28k episodes.
VOCAB_MIN, VOCAB_MAX = 120, 200
MIN_THEME_EPISODES = 15
MAX_THEME_SHARE = 0.08
# Per show. A show that collapses to one theme has been described, not indexed.
MAX_SHOW_THEME_SHARE = 0.60
MIN_SHOW_THEMES = 2
MIN_EPS_FOR_MULTI_THEME = 4

# Shows whose feed resolves to a different show than their metadata claims.
EXCLUDE = {
    "broken-record", "hit-parade", "homecoming", "gun-machine", "animal",
    "earshot", "shift", "startup", "making-oprah",
}

# --- title parsing ----------------------------------------------------------------
# A trailing parenthetical usually holds the real subject -- but not when it holds a
# counter ("(Chapter 14 of MITGR)"). Reject those rather than feed the model garbage.
COUNTER_IN_PAREN = re.compile(r'\b(chapter|part|pt\.?|vol(?:ume)?|episode|ep\.?)\s*\d', re.I)
TRAILING_PAREN = re.compile(r'\(([^()]{2,80})\)\s*$')

# Leading counters and boilerplate, stripped before anything else looks at the title.
COUNTER_PREFIX = re.compile(
    r'^\s*(?:'
    r'(?:S(?:eason)?\s*\d+\s*[,:|-]?\s*)?(?:Ep(?:isode)?|E)\.?\s*\#?\d+\s*[:.–—-]\s*'
    r'|\#?\d{1,4}\s*[:.–—-]\s+'
    r'|(?:Rerun|Encore|Replay|Free Bonus|Bonus|Update|Presenting|Introducing)\s*:\s*'
    r')', re.I)
RERUN_PREFIX = re.compile(r'^\s*(?:Rerun|Encore|Replay)\s*:\s*', re.I)

# "This Country Life - Cinnamon Bears": a name, a dash, a subject. Only treated as a
# segment when the same name repeats across the show (see SEGMENT_MIN_EPISODES).
DASH_PREFIX = re.compile(r'^(.{2,40}?)\s+[-–—|]\s+(.{3,})$')
COLON_SPLIT = re.compile(r'^([^:]{1,40}):\s*(.{3,})$')
SEGMENT_MIN_EPISODES = 5


def strip_counter(title):
    """Peel leading counters. Repeat: 'S6 Ep. 480: Bonus: X' stacks them."""
    prev, out = None, title.strip()
    while out != prev:
        prev = out
        out = COUNTER_PREFIX.sub("", out).strip()
    return out or title.strip()


def find_segments(titles):
    """Names that repeat across a show's episodes are segments, not subjects.

    Detected by frequency rather than a hand-written list -- 307 shows cannot each get
    bespoke config. Bear Grease yields This Country Life (161), Render (58),
    Backwoods University (34).
    """
    counts = collections.Counter()
    for t in titles:
        m = DASH_PREFIX.match(strip_counter(t))
        if m:
            counts[m.group(1).strip().lower()] += 1
    return {name for name, n in counts.items() if n >= SEGMENT_MIN_EPISODES}


def split_segment(title, segments):
    """-> (segment_or_empty, remaining_title)"""
    body = strip_counter(title)
    m = DASH_PREFIX.match(body)
    if m and m.group(1).strip().lower() in segments:
        return m.group(1).strip(), m.group(2).strip()
    return "", body


def extract_subject(body):
    """Generic best-effort subject guess. Order per THEMING_PROMPT.md."""
    m = TRAILING_PAREN.search(body)
    if m and not COUNTER_IN_PAREN.search(m.group(1)):
        return m.group(1).strip()
    m = COLON_SPLIT.match(body)
    if m:
        return m.group(2).strip()
    m = DASH_PREFIX.match(body)
    if m:
        return m.group(2).strip()
    return body.strip()


# --- prepare ----------------------------------------------------------------------
def load_descriptions(slug):
    path = DESCS / f"{slug}.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text()).get("episodes", {})
    except Exception:  # noqa: BLE001 - a bad sidecar costs descriptions, not the run
        return {}


def prepare_show(slug):
    feed = json.loads((FEEDS / f"{slug}.json").read_text())
    full = [e for e in feed.get("episodes", []) if e.get("episodeType") == "full"]
    if not full:
        return None

    # Arcs and themes are orthogonal: arc'd episodes stay in and carry inArc.
    in_arc = {g for a in a8_cascade(full) for g in a["members"]}
    descs = load_descriptions(slug)
    segments = find_segments([e["title"] for e in full])

    rows, seen, dropped = [], {}, 0
    for e in full:
        raw = e["title"]
        is_rerun = bool(RERUN_PREFIX.match(raw))
        segment, body = split_segment(raw, segments)
        subject = extract_subject(body)

        key = (segment.lower(), body.lower())
        if key in seen:
            # Feeds are newest-first, so the RE-AIRING is seen first and the original
            # second. Keep the original's guid, evict the rerun.
            prev = rows[seen[key]]
            if prev["rerun"] and not is_rerun:
                prev.update(guid=e["guid"], iso=e.get("iso", ""), rerun=False,
                            inArc=e["guid"] in in_arc)
            dropped += 1
            continue
        seen[key] = len(rows)

        rows.append({
            "i": len(rows), "guid": e["guid"], "display": raw,
            "segment": segment, "subject": subject,
            "desc": descs.get(e["guid"], ""),
            "iso": e.get("iso", ""), "inArc": e["guid"] in in_arc,
            "rerun": is_rerun,
        })

    return {
        "slug": slug, "title": feed.get("title", slug),
        "episodes": rows, "segments": sorted(segments),
        "reairingsDropped": dropped,
        "withDescription": sum(1 for r in rows if r["desc"]),
    }


def prepare():
    if not FEEDS.is_dir():
        sys.exit(f"no corpus at {FEEDS}")
    slugs = sorted(p.stem for p in FEEDS.glob("*.json") if not p.stem.startswith("_"))
    slugs = [s for s in slugs if s not in EXCLUDE]

    shows, total, with_desc = [], 0, 0
    for slug in slugs:
        try:
            show = prepare_show(slug)
        except Exception as e:  # noqa: BLE001 - one bad feed must not stop 306 others
            print(f"  SKIP {slug}: {type(e).__name__}: {e}", flush=True)
            continue
        if not show:
            continue
        shows.append(show)
        total += len(show["episodes"])
        with_desc += show["withDescription"]

    OUT_DIR.mkdir(exist_ok=True)
    IN_DIR.mkdir(parents=True, exist_ok=True)
    # One file per show: an agent reads only its own slice, so no agent ever pulls the
    # whole 28k-episode corpus into context.
    for show in shows:
        (IN_DIR / f"{show['slug']}.json").write_text(
            json.dumps(show, ensure_ascii=False, indent=1) + "\n")

    # Batch plan for open coding. The rule is that an agent sees a show's COMPLETE set --
    # consolidation cannot spot that two labels are one theme otherwise. Splitting one
    # show across calls breaks that; packing several whole small shows into one call does
    # not, and one batch per show would cost 558 calls against a 1000-agent cap.
    def _size(p):
        return p.get("count", len(p.get("indices", ())))

    def build_plan(size, cap=0):
        plan, pack = [], []
        for show in sorted(shows, key=lambda s: len(s["episodes"])):
            n = len(show["episodes"])
            if cap and n > cap:
                # Sample evenly across the whole run rather than taking a prefix -- feeds
                # are newest-first, so a prefix would only ever see recent episodes.
                # The sample is small, so it packs alongside other shows like any small one.
                idxs = sorted(set(round(k * (n - 1) / (cap - 1)) for k in range(cap)))
                if sum(_size(p) for p in pack) + len(idxs) > size and pack:
                    plan.append({"parts": pack, "split": False})
                    pack = []
                pack.append({"slug": show["slug"], "indices": idxs})
                continue
            if n > size:                   # too big to pack: split it
                for start in range(0, n, size):
                    plan.append({"parts": [{"slug": show["slug"], "start": start,
                                            "count": min(size, n - start)}],
                                 "split": True})
                continue
            if sum(_size(p) for p in pack) + n > size and pack:
                plan.append({"parts": pack, "split": False})
                pack = []
            pack.append({"slug": show["slug"], "start": 0, "count": n})
        if pack:
            plan.append({"parts": pack, "split": False})
        for i, b in enumerate(plan):
            b["id"] = i
        return plan

    plan = build_plan(BATCH, OPEN_CAP)
    (OUT_DIR / "_batch-plan.json").write_text(
        json.dumps({"batchSize": BATCH, "batches": plan}, ensure_ascii=False, indent=1) + "\n")
    aplan = build_plan(ASSIGN_BATCH)
    (OUT_DIR / "_assign-plan.json").write_text(
        json.dumps({"batchSize": ASSIGN_BATCH, "batches": aplan}, ensure_ascii=False, indent=1) + "\n")

    out = OUT_DIR / "_input-all.json"
    out.write_text(json.dumps({"shows": shows}, ensure_ascii=False, indent=1) + "\n")

    print(f"shows              {len(shows)}")
    print(f"batches            {len(plan)} @ {BATCH}/batch")
    print(f"episodes           {total}")
    print(f"  with description {with_desc} ({with_desc / total:.1%})" if total else "")
    print(f"  segments found   {sum(len(s['segments']) for s in shows)}")
    print(f"  in an arc        {sum(1 for s in shows for r in s['episodes'] if r['inArc'])}")
    print(f"\nwrote {out}")
    if total and with_desc / total < 0.5:
        print("\nWARNING: under half the episodes have a description. "
              "Run scripts/fetch-feed-descriptions.py before theming.")


# --- agent-facing helpers ---------------------------------------------------------
def batch(batch_id, with_desc=True, plan_name="_batch-plan.json", brief=False):
    """Print one batch as compact TSV. Agents call this instead of reading the corpus.

    TSV, not JSON: a 500-row batch as JSON is ~190KB, which blows past the agent's tool
    output cap and forces it to spill to a scratch file and page through it -- which was
    costing more wall clock than the labelling itself. One line per episode is ~5x smaller
    and needs no parsing on the agent's side.

    A batch holds either one slice of a big show or several whole small shows, so every
    row carries its own slug.
    """
    plan = json.loads((OUT_DIR / plan_name).read_text())["batches"]
    if not 0 <= batch_id < len(plan):
        sys.exit(f"batch id {batch_id} out of range 0..{len(plan) - 1}")
    entry = plan[batch_id]
    cap = BRIEF_CHARS if brief else DESC_CHARS

    def clean(x):
        return (x or "").replace("\t", " ").replace("\n", " ").strip()

    lines, n = [], 0
    for part in entry["parts"]:
        show = json.loads((IN_DIR / f"{part['slug']}.json").read_text())
        if "indices" in part:
            by_i = {r["i"]: r for r in show["episodes"]}
            rows = [by_i[i] for i in part["indices"] if i in by_i]
        else:
            rows = show["episodes"][part["start"]:part["start"] + part["count"]]
        for r in rows:
            n += 1
            lines.append("\t".join([
                part["slug"], str(r["i"]),
                clean(r["segment"]) or "-",
                clean(r["subject"])[:90],
                clean(r["desc"])[:cap] if with_desc else "",
            ]))

    print(f"# batch {batch_id}: {n} episodes")
    print("# slug\ti\tsegment\tsubject\tdescription")
    print("\n".join(lines))


def labels(slice_index=0, slices=1):
    """Aggregate open-coding output into distinct labels for consolidation.

    Collapses raw labels to distinct phrases in plain Python before any model sees them,
    and carries the show set per label -- that is what decides showSpecific later,
    computed here rather than asked of the model.
    """
    counts = collections.Counter()
    shows = collections.defaultdict(set)
    for path in sorted((WORK / "open").glob("*.tsv")):
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                continue
            slug, _, lab = parts[0], parts[1], parts[2].strip().lower()
            if lab:
                counts[lab] += 1
                shows[lab].add(slug)
    items = [{"label": lab, "count": n, "shows": len(shows[lab])}
             for lab, n in counts.most_common()]
    chunk = items[slice_index::slices] if slices > 1 else items
    print(f"# {len(items)} distinct labels, slice {slice_index} of {slices}")
    print("# label\tepisodes\tshows")
    for it in chunk:
        print(f"{it['label']}\t{it['count']}\t{it['shows']}")


def print_vocab():
    """Compact vocabulary for assign agents: slug, name, definition, one line each."""
    path = OUT_DIR / "_vocabulary-draft.json"
    if not path.exists():
        sys.exit(f"no vocabulary at {path}")
    themes = json.loads(path.read_text())["themes"]
    print(f"# {len(themes)} themes. Use these slugs VERBATIM. Never invent one.")
    for t in themes:
        print(f"{t['slug']}\t{t['definition']}")


# --- finalize ---------------------------------------------------------------------
def audit_catalog(vocab, per_show, known_show_themes):
    problems = []
    slugs = {v["slug"] for v in vocab}
    total = sum(len(s["episodes"]) for s in per_show)

    if not VOCAB_MIN <= len(vocab) <= VOCAB_MAX:
        problems.append(f"vocabulary is {len(vocab)} themes, wanted {VOCAB_MIN}-{VOCAB_MAX}")

    counts = collections.Counter()
    for show in per_show:
        for ep in show["episodes"]:
            apps = ep.get("themes") or []
            prim = [a for a in apps if a.get("role") == "primary"]
            if len(prim) != 1:
                problems.append(f"{show['slug']} ep {ep.get('i')}: {len(prim)} primary themes")
            if len(apps) - len(prim) > 2:
                problems.append(f"{show['slug']} ep {ep.get('i')}: more than 2 secondary")
            for a in apps:
                if a.get("slug") not in slugs:
                    problems.append(f"{show['slug']} ep {ep.get('i')}: "
                                    f"{a.get('slug')!r} is not in the vocabulary")
                if a.get("confidence") not in ("high", "medium", "low"):
                    problems.append(f"{show['slug']} ep {ep.get('i')}: "
                                    f"{a.get('slug')!r} has no confidence value")
                counts[a.get("slug")] += 1

    for v in vocab:
        n = counts.get(v["slug"], 0)
        if n < MIN_THEME_EPISODES:
            problems.append(f"theme {v['slug']!r} has {n} applications (min {MIN_THEME_EPISODES})")
        if total and n / total > MAX_THEME_SHARE:
            problems.append(f"theme {v['slug']!r} holds {n}/{total} ({n / total:.1%}) "
                            f"— over the {MAX_THEME_SHARE:.0%} ceiling")
        for rel in v.get("relatedShowThemes") or []:
            if rel not in known_show_themes:
                problems.append(f"theme {v['slug']!r} links to unknown show theme {rel!r}")
    return problems, counts


def audit_show(show):
    flags = []
    eps = show["episodes"]
    if not eps:
        return ["no episodes"]
    prim = collections.Counter()
    for ep in eps:
        for a in ep.get("themes") or []:
            if a.get("role") == "primary":
                prim[a["slug"]] += 1
    if prim:
        top, n = prim.most_common(1)[0]
        if n / len(eps) > MAX_SHOW_THEME_SHARE:
            flags.append(f"collapsed: {top!r} is {n}/{len(eps)} ({n / len(eps):.0%})")
    if len(prim) < MIN_SHOW_THEMES and len(eps) >= MIN_EPS_FOR_MULTI_THEME:
        flags.append(f"only {len(prim)} theme(s) across {len(eps)} episodes")
    return flags


def parse_assign_dir(subdir):
    """{(slug, i): [ {slug, role, confidence}, ... ]} from compact agent output.

    Each line: slug \t i \t primary \t conf [ \t secondary,conf ]*
    Malformed lines are skipped and counted -- one bad row must not cost a whole batch.
    """
    out, bad = {}, 0
    for path in sorted((WORK / subdir).glob("*.tsv")):
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            f = line.split("\t")
            if len(f) < 4:
                bad += 1
                continue
            slug, i_raw, prim, conf = f[0], f[1], f[2].strip(), f[3].strip().lower()
            try:
                i = int(i_raw)
            except ValueError:
                bad += 1
                continue
            if not prim:
                bad += 1
                continue
            apps = [{"slug": prim, "role": "primary",
                     "confidence": conf if conf in ("high", "medium", "low") else "medium"}]
            for extra in f[4:]:
                if not extra.strip():
                    continue
                bits = extra.split(",")
                sl = bits[0].strip()
                c = (bits[1].strip().lower() if len(bits) > 1 else "medium")
                if sl and sl != prim:
                    apps.append({"slug": sl, "role": "secondary",
                                 "confidence": c if c in ("high", "medium", "low") else "medium"})
            out[(slug, i)] = apps[:3]
    if bad:
        print(f"  {subdir}: skipped {bad} malformed row(s)", flush=True)
    return out


def _primaries(subdir):
    """{(slug, i): primary theme slug} for the agreement comparison."""
    return {k: v[0]["slug"] for k, v in parse_assign_dir(subdir).items() if v}


def compute_agreement():
    """Two-run primary agreement over the sample shows, as Swindled's 0.7582 was.

    Reported per show and overall. This is the check on whether the vocabulary cuts
    anything -- radiolab and 99-invisible are in the sample precisely because a vague,
    non-discriminating vocabulary is least visible to the audit there.
    """
    run_a, run_b = _primaries("assign"), _primaries("agree")
    per_show = collections.defaultdict(lambda: [0, 0])   # [same, compared]
    for key, prim_b in run_b.items():
        prim_a = run_a.get(key)
        if prim_a is None:
            continue
        slug = key[0]
        per_show[slug][1] += 1
        if prim_a == prim_b:
            per_show[slug][0] += 1
    out = {}
    tot_same = tot_cmp = 0
    for slug, (same, cmp_) in per_show.items():
        tot_same += same
        tot_cmp += cmp_
        if cmp_:
            out[slug] = {"runs": 2, "compared": cmp_,
                         "primaryAgreement": round(same / cmp_, 4)}
    if tot_cmp:
        out["_overall"] = {"runs": 2, "compared": tot_cmp,
                           "primaryAgreement": round(tot_same / tot_cmp, 4)}
    return out


def finalize(vocab_path):
    """Merge _work/assign/*.json against the vocabulary into the committed output."""
    vsrc = json.loads(Path(vocab_path).read_text())
    vocab = vsrc.get("themes") or vsrc.get("vocabulary") or []
    models = vsrc.get("models") or {"openCoding": "sonnet", "consolidate": "sonnet",
                                    "assign": "haiku"}
    agreement = compute_agreement()
    known = {t["slug"] for t in json.loads(THEMES.read_text())}

    flat = parse_assign_dir("assign")
    assigns = collections.defaultdict(dict)
    for (slug, i), apps in flat.items():
        assigns[slug][i] = {"themes": apps}

    per_show, missing = [], []
    for path in sorted(IN_DIR.glob("*.json")):
        show = json.loads(path.read_text())
        got = assigns.get(show["slug"], {})
        eps = []
        for row in show["episodes"]:
            a = got.get(row["i"])
            if not a:
                missing.append((show["slug"], row["i"]))
                continue
            eps.append({
                "guid": row["guid"], "display": row["display"],
                "segment": row["segment"], "subject": row["subject"],
                "iso": row["iso"], "inArc": row["inArc"],
                "themes": a.get("themes") or [],
            })
        per_show.append({"slug": show["slug"], "title": show["title"], "episodes": eps})

    if missing:
        print(f"WARNING: {len(missing)} episodes were never assigned "
              f"(first: {missing[:5]})", flush=True)
    src = {"models": models, "agreement": agreement}

    problems, counts = audit_catalog(vocab, per_show, known)

    # showSpecific is computed here, in plain Python, from who actually used the theme --
    # never asked of the model. Reach is a flag, not a filter: a theme used by one show
    # is kept.
    show_sets = collections.defaultdict(set)
    for show in per_show:
        for ep in show["episodes"]:
            for a in ep.get("themes") or []:
                show_sets[a["slug"]].add(show["slug"])
    for v in vocab:
        v["episodeCount"] = counts.get(v["slug"], 0)
        v["showCount"] = len(show_sets.get(v["slug"], ()))
        v["showSpecific"] = v["showCount"] <= 1
        v.setdefault("relatedShowThemes", [])
        v.setdefault("junkDrawerSuspect", False)
    vocab.sort(key=lambda v: -v["episodeCount"])

    OUT_DIR.mkdir(exist_ok=True)
    (OUT_DIR / "_vocabulary.json").write_text(
        json.dumps({"themes": vocab, "models": src.get("models", {})},
                   ensure_ascii=False, indent=1) + "\n")

    report_shows = []
    for show in per_show:
        used = collections.Counter()
        conf = collections.Counter()
        for ep in show["episodes"]:
            for a in ep.get("themes") or []:
                used[a["slug"]] += 1
                conf[a.get("confidence", "")] += 1
        flags = audit_show(show)
        payload = {
            "slug": show["slug"], "title": show["title"],
            "models": src.get("models", {}),
            "themesUsed": [{"slug": s, "count": n} for s, n in used.most_common()],
            "episodes": show["episodes"],
            "agreement": (src.get("agreement") or {}).get(show["slug"], {}),
            "auditFlags": flags,
        }
        (OUT_DIR / f"{show['slug']}.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=1) + "\n")
        report_shows.append({
            "slug": show["slug"], "title": show["title"],
            "episodes": len(show["episodes"]), "themesUsed": len(used),
            "confidence": dict(conf), "auditFlags": flags,
        })

    total_eps = sum(len(s["episodes"]) for s in per_show)
    report = {
        "shows": len(per_show),
        "episodesLabelled": total_eps,
        "vocabularySize": len(vocab),
        "showSpecificThemes": sum(1 for v in vocab if v["showSpecific"]),
        "junkDrawerSuspects": sum(1 for v in vocab if v.get("junkDrawerSuspect")),
        "unassigned": len(missing),
        "catalogAudit": problems,
        "agreement": src.get("agreement", {}),
        "showReports": report_shows,
    }
    (OUT_DIR / "_run-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=1) + "\n")

    print(f"shows              {len(per_show)}")
    print(f"episodes labelled  {total_eps}")
    print(f"vocabulary         {len(vocab)} themes "
          f"({report['showSpecificThemes']} show-specific)")
    print(f"shows flagged      {sum(1 for s in report_shows if s['auditFlags'])}")
    print()
    if problems:
        print(f"CATALOG AUDIT — {len(problems)} flag(s), non-blocking:")
        for p in problems[:20]:
            print(f"   ! {p}")
        if len(problems) > 20:
            print(f"   ... and {len(problems) - 20} more (see _run-report.json)")
    else:
        print("CATALOG AUDIT PASSED")
    print(f"\nwrote {OUT_DIR}/_vocabulary.json, {len(per_show)} show files, _run-report.json")
    return 0  # audits flag; they never fail the run


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("prepare")
    b = sub.add_parser("batch")
    b.add_argument("--id", type=int, required=True, dest="batch_id")
    b.add_argument("--no-desc", action="store_true")
    b.add_argument("--assign", action="store_true", help="use the assign batch plan")
    b.add_argument("--brief", action="store_true", help="short descriptions (open coding)")
    sub.add_parser("vocab")
    ll = sub.add_parser("labels")
    ll.add_argument("--slice", type=int, default=0)
    ll.add_argument("--slices", type=int, default=1)
    f = sub.add_parser("finalize")
    f.add_argument("--vocab", required=True)
    args = ap.parse_args()
    if args.cmd == "prepare":
        prepare()
    elif args.cmd == "batch":
        batch(args.batch_id, not args.no_desc,
              "_assign-plan.json" if args.assign else "_batch-plan.json",
              args.brief)
    elif args.cmd == "vocab":
        print_vocab()
    elif args.cmd == "labels":
        labels(args.slice, args.slices)
    else:
        sys.exit(finalize(args.vocab))


if __name__ == "__main__":
    main()
