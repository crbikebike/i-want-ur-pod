#!/usr/bin/env python3
"""Build the catalog browser's data file: catalog x feed episodes x detected arcs.

Writes curation/arc-bakeoff/catalog-index.json (gitignored -- it embeds the corpus).

Every arc is attributed to the ONE rule that produced it. approaches.py is imported and
its internals are replayed stage by stage; nothing in it is modified. Attribution is by
member-set identity against the reconciled output, so an arc that _reconcile dropped is
never shown.

Join key: slugify(catalog title), the same function as scripts/build-catalog.py:34.
NOT feedUrl (8 URLs are shared by two shows each) and NOT catalog id (stale positional
index -- 231 of 315 now point at a different show).
"""
import collections
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
FEEDS = ROOT / "curation" / "feeds"
CATALOG = ROOT / "curation" / "catalog" / "catalog.json"
THEMES = ROOT / "curation" / "catalog" / "themes.json"
ATLAS = ROOT / "curation" / "atlas-data.json"
EP_THEMES = HERE / "episode-themes"
OUT = HERE / "catalog-index.json"

sys.path.insert(0, str(HERE))
import approaches as AP  # noqa: E402

TITLE_CAP = 110          # episode titles are display-only here
CONTEXT_EPISODES = 10    # non-arc episodes kept per show, so you can see what was skipped

# Human-readable names for every rule. Keys are what the attribution emits.
PATTERNS = {
    # --- title patterns (the kind returned by the stem parsers) ---
    "part":        ("Part N", "title", "A counter after the arc name: “THE STERLING AFFAIRS Part 5: Not Fit”"),
    "pipe":        ("Name | Title | N", "title", "Pipe-delimited with a trailing number: “Nightmare in Tornado Alley | What Remains | 3”"),
    "lead-part":   ("Part N leads", "title", "Counter first, name after: “Part 1: On board the flotilla”"),
    "pt":          ("Pt. N", "title", "Abbreviated counter: “Alice Isn’t Dead Novel Excerpt 4”"),
    "pipe-dot":    ("Name | N. Title", "title", "Pipe then a dotted counter: “Amazonas adentro | 5. Vivir sobre el río”"),
    "ep":          ("Ep. N", "title", "Trailing episode counter: “Back to Bardstown: All Eyes On Them | Ep. 5”"),
    "hash":        ("Name #N", "title", "Hash counter: “100 Objects #9: Missing Children Milk Carton”"),
    "paren":       ("(Name, Part N)", "title", "Arc name inside the parenthesis: “High Voltage (Emotions Part 2)”"),
    "chapter":     ("Chapter N", "title", "Named chapters: “Gear: Chapter 7”"),
    "volume":      ("Volume N", "title", "Numbered volumes: “Mini-Stories: Volume 22”"),
    # --- structural rules (no usable counter in the title) ---
    "affix-prefix":   ("Shared opening phrase", "structural", "Every episode starts with the same phrase, e.g. “We Keep Us Safe: …”"),
    "bare-counter":   ("Bare 1…k run", "structural", "Keyword-less numbers forming a complete run: “1. When the Wind Changed”, “04_KEEP IT 200”"),
    "season-lead":    ("Episode N + season tag", "structural", "Title only says which number; the season tag says which story"),
    "limited-series": ("Whole feed is one story", "structural", "No title signal at all — but the entire feed shipped inside 6 months"),
    "season-chapter": ("Chapter/S0E0 + season tag", "structural", "A bare “Chapter N |” or “S7 E1:” lead, grouped by season"),
    "counter-run":    ("Adjacent Part 1 / Part 2", "structural", "Consecutive numbered parts that share no title text"),
    "affix-suffix":   ("Shared closing phrase", "structural", "Every episode ends with the same phrase"),
}

# ---------------------------------------------------------------------------
# Why a feed is small
# ---------------------------------------------------------------------------
# A show with two episodes is usually not a short show. Most of the time the
# publisher puts a trailer and episode one in the public feed and keeps the rest
# behind a subscription -- the NYT and Serial Productions catalogues are almost
# entirely this. Some feeds say it outright: Wondery ships an item literally
# titled "Where to find Episodes 2-6 of The Shrink Next Door".
#
# This is NOT our truncation. fetch-atlas-feeds.py caps at 800 episodes, so a
# feed holding 2 items genuinely served 2. The only feeds we cut are the ones
# sitting exactly at 800.
SMALL_FEED_MAX = 6
WORD_ORD = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10}
SAMPLER_MARKER = re.compile(
    r'where to (find|hear|listen)|rest of (the )?(this )?(series|season|episodes)|'
    r'listen to the rest|full series (on|at)|subscribe to hear', re.I)
ORD_PATTERNS = [
    re.compile(r'^\s*(\d{1,3})\s*[:.\-]'),
    re.compile(r'^\s*(?:part|chapter|episode|ep\.?)\s+(\d{1,3}|' + "|".join(WORD_ORD) + r')\b', re.I),
    re.compile(r'^\s*(?:s\d+\s*)?e(?:pisode)?\s*(\d{1,3})\b', re.I),
    re.compile(r'^\s*(' + "|".join(WORD_ORD) + r')\s*:', re.I),
]

SMALL_FEED_LABELS = {
    "sampler": "Only the opening is public",
    "short-series": "A genuinely short series",
    "empty-feed": "Feed serves no episodes",
    "unknown-short": "Short, reason unclear",
    "windowed": "Recent episodes only",
}


def _ordinal(e):
    if e.get("episodeNumber"):
        return e["episodeNumber"]
    for rx in ORD_PATTERNS:
        m = rx.match(e["title"])
        if m:
            v = m.group(1).lower()
            return WORD_ORD.get(v, int(v) if v.isdigit() else None)
    return None


def _windowed(full):
    """A rolling window: This American Life numbers 884-892 while ~892 exist.

    The signature is a CONTIGUOUS run of episode numbers starting far above 1.
    Depth alone is not enough -- Criminal and RedHanded both carry a stray
    episodeNumber of 10001 as a sort key while genuinely numbering from 1, and a
    naive max/count ratio flags them as windowed when their archives are intact.
    """
    ords = sorted({o for o in (_ordinal(e) for e in full) if o})
    if len(ords) < 5:
        return None
    best = run = [ords[0]]
    for prev, cur in zip(ords, ords[1:]):
        run = run + [cur] if cur == prev + 1 else [cur]
        if len(run) > len(best):
            best = run
    if best[0] <= 10:                       # numbering reaches back to the start
        return None
    if len(best) < 0.6 * len(ords):         # not one clean recent block
        return None
    if best[-1] < 3 * len(full):            # archive is not meaningfully deeper
        return None
    return "windowed", (f"numbered {best[0]}-{best[-1]}, so roughly {best[-1]} exist "
                        f"but only {len(full)} are public")


def small_feed_reason(episodes):
    """Explain a feed with almost nothing in it, or None when it is a normal feed."""
    full = [e for e in episodes if e.get("episodeType", "full") == "full"]
    if len(full) >= SMALL_FEED_MAX:
        return _windowed(full)
    if not full:
        return "empty-feed", "the feed carries no full episodes at all"
    if any(SAMPLER_MARKER.search(e["title"]) for e in episodes):
        return "sampler", "the feed says outright where the rest of the episodes are"
    ords = sorted(o for o in (_ordinal(e) for e in full) if o)
    if ords:
        if ords == list(range(1, len(ords) + 1)) and len(ords) == len(full) >= 3:
            return "short-series", f"a complete run of {len(full)}"
        if min(ords) == 1:
            return "sampler", (f"starts at episode 1 and stops at {max(ords)}"
                               if max(ords) <= 2 else
                               f"starts at episode 1, only {len(full)} published")
    return "unknown-short", f"{len(full)} episodes, no numbering to go on"


NO_ARC_GROUPS = {
    "too-few":     ("Too few episodes", "The feed itself holds almost nothing — see the reason on each show. Usually the publisher keeps the rest behind a subscription."),
    "season-tag":  ("Season tag, unproven", "The season tag would group these, but Bear Grease puts 60 episodes in one season — the tag alone can’t be trusted."),
    "no-signal":   ("Small, no signal", "Small and unnumbered, but spread over too long a window to be a limited series."),
    "anthology":   ("Big anthology", "Hundreds of standalone episodes. Finding nothing here is usually the right answer."),
}


def slugify(t):
    """Verbatim from scripts/build-catalog.py:34 -- the catalog's only real join key."""
    s = re.sub(r"^(the|a|an)\s+", "", (t or "").lower())
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-") or "show"


def load_episode_themes(slug):
    """Anthologies have no arcs but their episodes still cluster by subject. When a theme
    taxonomy exists for a show, the browser shows themes where arcs would go."""
    path = EP_THEMES / f"{slug}.json"
    if not path.exists():
        return None, {}
    data = json.loads(path.read_text())
    idx = {v["slug"]: i for i, v in enumerate(data.get("vocabulary", []))}
    by_guid = {}
    for ep in data.get("episodes", []):
        by_guid[ep["guid"]] = (idx.get(ep.get("primary"), -1),
                               [idx[s] for s in (ep.get("secondary") or []) if s in idx])
    return data, by_guid


def load_episodes(path):
    data = json.loads(path.read_text())
    return [{"guid": e["guid"], "title": e["title"], "season": e.get("season"),
             "episodeNumber": e.get("episodeNumber"),
             "episodeType": e.get("episodeType", "full"), "iso": e.get("iso", "")}
            for e in data.get("episodes", [])]


def attribute(episodes):
    """Replay the shipped cascade, tagging each surviving arc with the rule that made it.

    Mirrors _a7_cascade + a8_cascade's limited-series tier. Kept in lockstep with
    approaches.py by construction: it calls the same functions with the same arguments.
    """
    eps = AP.sort_newest_first(episodes)
    tagged, stages = [], []

    t1 = AP._tier1(eps)
    tagged += [("tier1", a) for a in t1]
    stages.append((1, t1))

    taken = {g for a in t1 for g in a["members"]}
    rest = [e for e in eps if e["guid"] not in taken]
    t2 = AP._cluster_guarded(rest, guard=True, dedup=True, stem_fn=AP.r4_stem_part_kind)
    tagged += [("tier2", a) for a in t2]
    stages.append((2, t2))

    so_far = t1 + t2
    taken2 = {g for a in so_far for g in a["members"]}
    for mode in ("prefix", "suffix"):
        if not AP._tier3_gate(eps, so_far, mode):
            continue
        arcs = AP._affix_arcs(eps, taken2, mode, max_size=12, min_len=6,
                              contiguity=3, counter_reject=True)
        tagged += [("affix-" + mode, a) for a in arcs]
        stages.append((3, arcs))

    def claimed():
        return {g for _, arcs in stages for a in arcs for g in a["members"]}

    for label, fn in (("counter-run", AP._counter_run_arcs),
                      ("bare-counter", AP._bare_counter_run_arcs),
                      ("season-lead", AP._season_lead_arcs),
                      ("limited-series", AP._limited_series_arcs)):
        arcs = fn(eps, claimed())
        tagged += [(label, a) for a in arcs]
        stages.append((4, arcs))

    final = AP._reconcile(stages, eps)
    surviving = {frozenset(a["members"]) for a in final}
    by_members = {}
    for label, a in tagged:
        key = frozenset(a["members"])
        if key in surviving and key not in by_members:
            by_members[key] = label
    return final, by_members


def pattern_for(label, arc, by_guid):
    """tier1/tier2 arcs report which title grammar matched; structural rules report themselves.

    The arc dict carries only {name, season, members}, so the kind is re-derived from the
    members and the dominant value wins.
    """
    if label not in ("tier1", "tier2"):
        return label
    parse = AP.r3_stem_part_kind if label == "tier1" else AP.r4_stem_part_kind
    counts = collections.Counter()
    for g in arc["members"]:
        e = by_guid.get(g)
        if not e:
            continue
        kind = parse(e["title"])[2]
        if kind:
            counts[kind] += 1
    # No title grammar matched any member -> this came from tier 1's scoped season pass.
    return counts.most_common(1)[0][0] if counts else "season-chapter"


def span_months(episodes):
    ds = sorted(e.get("iso") or "" for e in episodes if e.get("iso"))
    if len(ds) < 2:
        return 0
    return (int(ds[-1][:4]) - int(ds[0][:4])) * 12 + (int(ds[-1][5:7]) - int(ds[0][5:7]))


def no_arc_group(full):
    if len(full) < 6:
        return "too-few"
    seasons = collections.Counter(e["season"] for e in full if e["season"] is not None)
    clean = [s for s, c in seasons.items() if 2 <= c <= 12]
    if clean and sum(seasons[s] for s in clean) >= 0.5 * len(full):
        return "season-tag"
    return "no-signal" if len(full) <= 15 else "anthology"


def main():
    catalog = json.loads(CATALOG.read_text())
    themes = {t["slug"]: t for t in json.loads(THEMES.read_text())}
    # feedAccess is hand-curated in atlas-source and dropped by build-catalog.py.
    # It says whether a show is paywalled, which is context for a small feed --
    # though not decisive: 1619 and Caliphate are "free-public" and still sampled.
    access = {}
    if ATLAS.exists():
        for s in json.loads(ATLAS.read_text()).get("shows", []):
            access[(s.get("title") or "").strip().lower()] = s.get("access")

    by_slug, dupes = {}, []
    for rec in catalog:
        slug = slugify(rec["title"])
        if slug in by_slug:
            dupes.append(slug)
        by_slug[slug] = rec
    if dupes:
        sys.exit(f"FATAL: duplicate slugs from slugify(title): {dupes}")

    shows, unmatched = [], []
    pattern_arcs, pattern_shows = collections.Counter(), collections.defaultdict(set)
    group_shows = collections.Counter()
    total_arcs = feeds_with_arcs = 0

    for path in sorted(FEEDS.glob("*.json")):
        slug = path.stem
        if slug == "_index":
            continue
        rec = by_slug.get(slug)
        if rec is None:
            unmatched.append(slug)
            continue
        episodes = load_episodes(path)
        if not episodes:
            continue

        eps = AP.sort_newest_first(episodes)
        by_guid = {e["guid"]: e for e in eps}
        final, labels = attribute(eps)
        total_arcs += len(final)
        if final:
            feeds_with_arcs += 1

        arcs_out, member_guids, pats = [], set(), []
        for a in final:
            pat = pattern_for(labels.get(frozenset(a["members"]), "tier1"), a, by_guid)
            pattern_arcs[pat] += 1
            pattern_shows[pat].add(slug)
            pats.append(pat)
            member_guids.update(a["members"])
            # Members are recorded as a count only. GUIDs never reach the browser: the
            # exporter re-runs the detector server-side, where the corpus already lives,
            # so shipping 40-char ids for 10k episodes would be pure weight. Episode rows
            # carry the arc's index instead, which is all the UI needs to draw the runs.
            arcs_out.append({"n": a["name"], "s": a["season"], "p": pat,
                             "c": len(a["members"])})

        full = [e for e in eps if e["episodeType"] == "full"]
        group = None
        if not final:
            group = no_arc_group(full)
            group_shows[group] += 1

        ep_themes, theme_of = load_episode_themes(slug)

        # Every arc member, plus a slice of context so you can see what was passed over.
        # A themed show keeps every themed episode instead — the taxonomy IS the content
        # there, so a 10-episode sample would hide most of it.
        arc_of = {}
        for i, a in enumerate(final):
            for g in a["members"]:
                arc_of[g] = i
        keep, extra = [], 0
        for e in eps:
            if e["guid"] in member_guids or e["guid"] in theme_of:
                keep.append(e)
            elif extra < CONTEXT_EPISODES:
                keep.append(e)
                extra += 1

        shows.append({
            "slug": slug,
            "title": rec["title"],
            "author": rec.get("author") or rec.get("network") or "",
            "network": rec.get("network") or "",
            "category": rec.get("category") or "",
            "years": rec.get("years") or "",
            "art": rec.get("artworkUrl") or "",
            "desc": rec.get("description") or "",
            "themes": rec.get("themes") or [],
            "nEps": len(full),
            "access": access.get(rec["title"].strip().lower()) or "",
            "small": ({"label": SMALL_FEED_LABELS[small[0]], "why": small[1], "key": small[0]}
                      if (small := small_feed_reason(eps)) else None),
            "span": span_months(full),
            "seasons": len({e["season"] for e in full if e["season"] is not None}),
            "patterns": sorted(set(pats)),
            "group": group,
            "arcs": arcs_out,
            "themes_vocab": [{"s": v["slug"], "n": v["name"], "d": v["definition"],
                              "c": v.get("count", 0), "m": v.get("mapsTo")}
                             for v in (ep_themes or {}).get("vocabulary", [])],
            "themes_meta": {"agreement": (ep_themes or {}).get("agreement", {}),
                            "models": (ep_themes or {}).get("models", {})} if ep_themes else None,
            # [title, date, season, non-full type, arc index or -1, theme index or -1]
            "eps": [[e["title"][:TITLE_CAP], e["iso"], e["season"],
                     "" if e["episodeType"] == "full" else e["episodeType"],
                     arc_of.get(e["guid"], -1),
                     theme_of.get(e["guid"], (-1, []))[0]] for e in keep],
        })

    if unmatched:
        sys.exit(f"FATAL: {len(unmatched)} feeds with no catalog record: {unmatched[:8]}")

    out = {
        "shows": shows,
        "themes": themes,
        "patterns": {k: {"label": v[0], "family": v[1], "hint": v[2],
                         "arcs": pattern_arcs.get(k, 0), "shows": len(pattern_shows.get(k, ()))}
                     for k, v in PATTERNS.items() if pattern_arcs.get(k)},
        "noArcGroups": {k: {"label": v[0], "hint": v[1], "shows": group_shows.get(k, 0)}
                        for k, v in NO_ARC_GROUPS.items()},
        "totals": {"shows": len(shows), "withArcs": feeds_with_arcs, "arcs": total_arcs},
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")

    kb = OUT.stat().st_size / 1024
    print(f"shows joined      {len(shows)} (0 unmatched, 0 duplicate slugs)")
    print(f"shows with arcs   {feeds_with_arcs}")
    print(f"arcs              {total_arcs}   (pattern sum {sum(pattern_arcs.values())})")
    print(f"no-arc groups     {dict(group_shows)}  total {sum(group_shows.values())}")
    print(f"payload           {kb:.0f} KB -> {OUT}")
    print()
    for k, v in sorted(pattern_arcs.items(), key=lambda kv: -kv[1]):
        print(f"   {PATTERNS[k][0]:28s} {v:5d} arcs / {len(pattern_shows[k]):3d} shows")


if __name__ == "__main__":
    main()
