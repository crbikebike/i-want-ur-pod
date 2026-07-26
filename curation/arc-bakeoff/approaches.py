#!/usr/bin/env python3
"""The 5 story-arc detection approaches for the bake-off, plus the current
baseline. Each is a pure function of a feed's episodes -> list of arcs.

An episode dict: {guid, title, season, episodeNumber, episodeType, iso}.
An arc dict:      {name, season|None, members:[guid,...]}  (>= 2 members).

All regexes are ICU-compatible so the winner ports to NSRegularExpression.
Grouping preserves newest-first order (callers sort episodes newest-first).
"""
import re
import unicodedata
from collections import OrderedDict, Counter

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
NOISE_PREFIX = re.compile(
    r'^(Encore|Fan Favorite|Listen Now|New Season|Introducing|Presenting)\s*:?\s*', re.I)
CANON_ROMAN = re.compile(r'^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$', re.I)
DASHES = "-‐‑‒–—"  # hyphen, non-breaking/figure/en/em dashes


def strip_noise(title):
    return NOISE_PREFIX.sub("", title or "").strip()


def roman_to_int(tok):
    tok = tok.strip()
    if not tok or not CANON_ROMAN.match(tok):
        return None
    vals = {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}
    total = 0
    prev = 0
    for ch in reversed(tok.upper()):
        v = vals[ch]
        total += -v if v < prev else v
        prev = max(prev, v)
    return total


def parse_part(tok):
    tok = tok.strip()
    if tok.isdigit():
        return int(tok)
    return roman_to_int(tok)


def norm_name(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"^(the|a|an)\s+", "", s.lower())
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def _finalize(order, buckets, episodes_by_guid, min_size=2):
    """order: list of arc-name keys in encounter order.
    buckets: name -> list of guids. Returns arcs with a shared season if uniform."""
    arcs = []
    for name in order:
        members = buckets[name]
        if len(members) < min_size:
            continue
        seasons = {episodes_by_guid[g].get("season") for g in members}
        seasons.discard(None)
        season = seasons.pop() if len(seasons) == 1 else None
        arcs.append({"name": name, "season": season, "members": members})
    return arcs


def sort_newest_first(episodes):
    return sorted(episodes, key=lambda e: e.get("iso") or "", reverse=True)


# ---------------------------------------------------------------------------
# Title-pattern derivations (return (arc_name|None, part|None))
# ---------------------------------------------------------------------------
PIPE = re.compile(r'^(.+?)\s*\|\s*(.+?)\s*\|\s*(\d+)\s*$')
PART = re.compile(r'^(.+?)\s*[' + DASHES + r']\s*Part\s*(\d+|[IVXLCDM]+)\s*(?:[' + DASHES + r']\s*(.*))?$', re.I)
CHAPTER_LEAD = re.compile(r'^Chapter\s*(\d+)\s*[|:]\s*(.+)$', re.I)
TRAIL_PAREN = re.compile(r'^(.+?)\s*[(\[]\s*Part\s*(\d+)\s*[)\]]\s*$', re.I)
TRAIL_COMMA = re.compile(r'^(.+?),\s*Part\s*(\d+)\s*$', re.I)
TRAIL_EP = re.compile(r'^(.+?)\s*[' + DASHES + r']\s*Ep(?:isode|\.)?\s*(\d+)\s*$', re.I)
TRAIL_CHAPTER = re.compile(r'^(.+?)\s*[' + DASHES + r']\s*Chapter\s*(\d+)\s*$', re.I)


def derive_baseline(title):
    """Port of EpisodeArcs.swift derive(fromTitle:)."""
    t = strip_noise(title)
    m = PIPE.match(t)
    if m:
        return (m.group(1).strip() or None), int(m.group(3))
    m = PART.match(t)
    if m:
        p = parse_part(m.group(2))
        if p is not None:
            return (m.group(1).strip() or None), p
    m = CHAPTER_LEAD.match(t)
    if m:  # groups by season, no arc name in title -> not a title arc
        return None, int(m.group(1))
    for rx in (TRAIL_PAREN, TRAIL_COMMA, TRAIL_EP, TRAIL_CHAPTER):
        m = rx.match(t)
        if m:
            return (m.group(1).strip() or None), int(m.group(2))
    return None, None


# extra anchored patterns for A1
A1_SEASON = re.compile(r'^(.+?)\s*[' + DASHES + r'|:]\s*Season\s*(\d+)\b.*$', re.I)
A1_SERIES = re.compile(r'^(.+?)\s*[' + DASHES + r'|:]\s*Series\s*(\d+)\b.*$', re.I)
A1_BOOK = re.compile(r'^(.+?)\s*[' + DASHES + r'|:]\s*Book\s*(\d+)\b.*$', re.I)
A1_VOL = re.compile(r'^(.+?)\s*[' + DASHES + r'|:]\s*Vol(?:ume|\.)?\s*(\d+)\b.*$', re.I)
A1_LEAD_NUM = re.compile(r'^(\d+)\s*[.:)]\s*(.+?)\s*[' + DASHES + r'(\[]\s*Part\s*(\d+)\s*[)\]]?\s*$', re.I)
A1_PIPE_DASH = re.compile(r'^(.+?)\s*[' + DASHES + r']\s*(.+?)\s*[' + DASHES + r']\s*(\d+)\s*$')


def derive_a1(title):
    name, part = derive_baseline(title)
    if name is not None:
        return name, part
    t = strip_noise(title)
    for rx in (A1_SEASON, A1_SERIES, A1_BOOK, A1_VOL):
        m = rx.match(t)
        if m and m.group(1).strip():
            return m.group(1).strip(), int(m.group(2))
    m = A1_LEAD_NUM.match(t)
    if m and m.group(2).strip():
        return m.group(2).strip(), int(m.group(3))
    m = A1_PIPE_DASH.match(t)  # "Arc - Title - N" mirror of pipe
    if m and m.group(1).strip():
        return m.group(1).strip(), int(m.group(3))
    return None, None


# ---------------------------------------------------------------------------
# Generic grouping driver used by pattern-based approaches
# ---------------------------------------------------------------------------
def group_by_derive(episodes, derive_fn):
    episodes = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in episodes}
    order, buckets, display = [], {}, {}
    for e in episodes:
        name, _ = derive_fn(e["title"])
        if not name:
            continue
        key = norm_name(name)
        if key not in buckets:
            buckets[key] = []
            order.append(key)
            display[key] = name  # first (newest) display form wins
        buckets[key].append(e["guid"])
    out = []
    for key in order:
        members = buckets[key]
        if len(members) < 2:
            continue
        seasons = {by_guid[g].get("season") for g in members}
        seasons.discard(None)
        out.append({"name": display[key], "season": seasons.pop() if len(seasons) == 1 else None,
                    "members": members})
    return out


# ---------------------------------------------------------------------------
# Season fallback (dominance) — shared by baseline / A1 / A5
# ---------------------------------------------------------------------------
def season_cards(episodes, taken_guids, derive_fn):
    episodes = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in episodes}
    seasons_present = {e.get("season") for e in episodes if e.get("season") is not None}
    if len(seasons_present) < 2:
        return []  # single/absent season is the whole show, not an arc
    by_season = OrderedDict()
    for e in episodes:
        s = e.get("season")
        if s is None:
            continue
        by_season.setdefault(s, []).append(e)
    cards = []
    for s, members in sorted(by_season.items(), key=lambda kv: kv[0], reverse=True):
        arc_members = [e for e in members if e["guid"] in taken_guids]
        if arc_members and arc_members and len(arc_members) * 2 >= len(members):
            continue  # season already represented by a title arc
        leftovers = [e for e in members if e["guid"] not in taken_guids]
        if len(leftovers) < 2:
            continue
        names = Counter()
        for e in leftovers:
            n, _ = derive_fn(e["title"])
            if n:
                names[norm_name(n)] += 1
        label = f"Season {s}"
        if names:
            top, cnt = names.most_common(1)[0]
            if cnt * 2 >= len(leftovers):
                # recover display form
                for e in leftovers:
                    n, _ = derive_fn(e["title"])
                    if n and norm_name(n) == top:
                        label = n
                        break
        cards.append({"name": label, "season": s, "members": [e["guid"] for e in leftovers]})
    return cards


def _with_season_fallback(episodes, derive_fn):
    title_arcs = group_by_derive(episodes, derive_fn)
    taken = {g for a in title_arcs for g in a["members"]}
    return title_arcs + season_cards(episodes, taken, derive_fn)


# ===========================================================================
# THE CONTENDERS
# ===========================================================================
def baseline(episodes):
    return _with_season_fallback(episodes, derive_baseline)


def a1_extended(episodes):
    return _with_season_fallback(episodes, derive_a1)


# --- A2: prefix / affix clustering -----------------------------------------
COUNTER_ANY = re.compile(
    r'^(?P<stem>.+?)\s*(?:[' + DASHES + r'|:,(\[]\s*)?'
    r'(?:Part|Ep(?:isode|\.)?|Chapter|Pt\.?)?\s*'
    r'(?P<num>\d+|[IVXLCDM]+)\s*[)\]]?\s*$', re.I)


def _stem_and_part(title):
    t = strip_noise(title)
    # prefer explicit "Part/Ep/Chapter N" or "| N" or trailing "(Part N)"
    for rx in (PIPE, PART, TRAIL_PAREN, TRAIL_COMMA, TRAIL_EP, TRAIL_CHAPTER):
        m = rx.match(t)
        if m:
            grp = m.group(1).strip()
            try:
                p = parse_part(m.group(m.lastindex if rx is not PIPE else 3))
            except Exception:  # noqa: BLE001
                p = None
            if grp:
                return grp, p
    m = COUNTER_ANY.match(t)
    if m:
        stem = m.group("stem").strip(" " + DASHES + "|:,([")
        p = parse_part(m.group("num"))
        # reject if stem too short (avoids "Ep 5" -> stem "")
        if stem and len(norm_name(stem)) >= 3 and p is not None:
            return stem, p
    return None, None


def a2_prefix_cluster(episodes):
    episodes = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in episodes}
    order, buckets, display = [], {}, {}
    for e in episodes:
        stem, part = _stem_and_part(e["title"])
        if not stem or part is None:
            continue
        key = norm_name(stem)
        if key not in buckets:
            buckets[key] = []
            order.append(key)
            display[key] = stem
        buckets[key].append(e["guid"])
    # merge clusters where one normalized stem is a word-prefix of another
    keys = sorted(order, key=lambda k: len(k))
    merged = {}
    for k in keys:
        target = k
        for other in keys:
            if other != k and (k.startswith(other + " ") or k == other):
                target = other
        merged.setdefault(target, [])
    canonical = {}
    for k in order:
        tgt = k
        for other in order:
            if other != k and k.startswith(other + " "):
                if len(other) < len(tgt):
                    tgt = other
        canonical[k] = tgt
    final_order, final_buckets, final_disp = [], {}, {}
    for k in order:
        tgt = canonical[k]
        if tgt not in final_buckets:
            final_buckets[tgt] = []
            final_order.append(tgt)
            final_disp[tgt] = display[tgt]
        final_buckets[tgt].extend(buckets[k])
    out = []
    for k in final_order:
        members = final_buckets[k]
        if len(members) < 2:
            continue
        seasons = {by_guid[g].get("season") for g in members}
        seasons.discard(None)
        out.append({"name": final_disp[k], "season": seasons.pop() if len(seasons) == 1 else None,
                    "members": members})
    return out


# --- A3: structured-first (season / episode tags) --------------------------
def a3_structured(episodes):
    episodes = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in episodes}
    seasons_present = {e.get("season") for e in episodes if e.get("season") is not None}
    out = []
    taken = set()
    if len(seasons_present) >= 2:
        by_season = OrderedDict()
        for e in episodes:
            s = e.get("season")
            if s is None or e.get("episodeType", "full") != "full":
                continue
            by_season.setdefault(s, []).append(e)
        for s, members in sorted(by_season.items(), key=lambda kv: kv[0], reverse=True):
            if len(members) < 2:
                continue
            names = Counter()
            for e in members:
                n, _ = derive_baseline(e["title"])
                if n:
                    names[norm_name(n)] += 1
            label = f"Season {s}"
            if names:
                top, cnt = names.most_common(1)[0]
                if cnt * 2 >= len(members):
                    for e in members:
                        n, _ = derive_baseline(e["title"])
                        if n and norm_name(n) == top:
                            label = n
                            break
            guids = [e["guid"] for e in members]
            out.append({"name": label, "season": s, "members": guids})
            taken.update(guids)
    # secondary: title arcs for anything not captured by seasons
    for a in group_by_derive(episodes, derive_baseline):
        rest = [g for g in a["members"] if g not in taken]
        if len(rest) >= 2:
            out.append({**a, "members": rest})
    return out


# --- A4: generalized delimiter parser --------------------------------------
A4 = re.compile(
    r'^(?P<name>.+?)\s*[' + DASHES + r'|:(\[,]\s*'
    r'(?:Part|Pt\.?|Ep(?:isode|\.)?|Chapter|Season|Series|Vol(?:ume|\.)?|No\.?|#)?\s*'
    r'(?P<num>\d+|[IVXLCDM]+)\s*[)\]]?\s*$', re.I)


def derive_a4(title):
    t = strip_noise(title)
    m = A4.match(t)
    if not m:
        return None, None
    name = m.group("name").strip(" " + DASHES + "|:,([")
    p = parse_part(m.group("num"))
    if not name or len(norm_name(name)) < 3 or p is None:
        return None, None
    return name, p


def a4_delimiter(episodes):
    return group_by_derive(episodes, derive_a4)


# --- A5: hybrid cascade -----------------------------------------------------
def a5_hybrid(episodes):
    episodes = sort_newest_first(episodes)
    # 1) high-precision anchored patterns (A1)
    title_arcs = group_by_derive(episodes, derive_a1)
    taken = {g for a in title_arcs for g in a["members"]}
    # 2) season signal for the rest
    cards = season_cards(episodes, taken, derive_a1)
    taken |= {g for a in cards for g in a["members"]}
    # 3) prefix clustering fallback for still-loose episodes with counters
    loose = [e for e in episodes if e["guid"] not in taken]
    prefix_arcs = []
    for a in a2_prefix_cluster(loose):
        prefix_arcs.append(a)
    return title_arcs + cards + prefix_arcs


# ===========================================================================
# A2r1 — prefix clustering, refined (round 1)
#   + word-numbers (Part One), #N counters, "Pt N", numbers with trailing
#     subtitle/brackets; strips trailing "| #123" episode ids and "[...]" tags;
#   - rejects generic "Season N / Ep" stems; splits a stem group across distinct
#     itunes:season values (un-merges same-named arcs from different seasons).
# ===========================================================================
WORD_NUM = {w: i for i, w in enumerate(
    ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
     "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
     "seventeen", "eighteen", "nineteen", "twenty"], 0)}
R1_NOISE = re.compile(
    r'^(Encore|Fan Favorite|Fan-Favorite|Listen Now|New Season|Introducing|Presenting|'
    r'Announcing|Update|Bonus|Replay|Revisited)\s*:?\s*', re.I)
TRAIL_ID = re.compile(r'\s*[|]\s*#\d+\s*$')             # "... | #457" (episode id); NOT "| 5" (AHT part)
TRAIL_BRACKET = re.compile(r'\s*[\[(][^\])]*[\])]\s*$')  # "... [Repetición]"
NUMWORD = r'(?:\d+|[IVXLCDM]+|' + "|".join(WORD_NUM) + r')'
GENERIC_STEM = re.compile(r'^(season|episode|ep|part|chapter|vol(ume)?|series|book|no)\b', re.I)

# counter markers: stem is group 1, number token is group 2. Trailing subtitle ok.
R1_MARKERS = [
    re.compile(r'^(.+?)\s*\|\s*.+?\s*\|\s*(\d+)\s*$'),                                  # pipe (AHT)
    re.compile(r'^(.+?)\s*[' + DASHES + r']\s*Part\s+(' + NUMWORD + r')\b', re.I),      # - Part N/One
    # arc name inside a trailing paren: "Turning the Lens (Seeing White, Part 1)"
    # (Scene on Radio). Before the ", Part N" marker, which would take the unique
    # main title as the stem. End-anchored + ≥1 char before Part → never eats a
    # bare "(Part 1)" or a plain "X, Part N". POST-BAKEOFF (needs a gold re-score).
    re.compile(r'^.+?\(\s*(.+?)\s*,?\s*Part\s+(' + NUMWORD + r')\s*\)\s*$', re.I),       # (Stem, Part N)
    re.compile(r'^(.+?),\s*Part\s+(' + NUMWORD + r')\b', re.I),                          # , Part N/One
    re.compile(r'^(.+?)\s*[(\[]\s*Part\s+(' + NUMWORD + r')\s*[)\]]', re.I),             # (Part N)
    re.compile(r'^(.+?)\s*,?\s*\(?\s*Pt\.?\s+(' + NUMWORD + r')\b', re.I),               # Pt N / (Pt N)
    re.compile(r'^(.+?)\s+#\s*(\d+)\b'),                                                 # #N (99pi)
    re.compile(r'^(.+?)\s*[' + DASHES + r']\s*Ep(?:isode|\.)?\s*(\d+)\b', re.I),         # - Ep N
    re.compile(r'^(.+?)\s*[' + DASHES + r':]\s*Chapter\s+(' + NUMWORD + r')\b', re.I),   # Chapter N
    re.compile(r'^Chapter\s+(?:' + NUMWORD + r')\s*[|:]\s*(.+)$', re.I),                 # Chapter N: Title (name in g? handled below)
]


def r1_part(tok):
    tok = tok.strip().lower()
    if tok.isdigit():
        return int(tok)
    if tok in WORD_NUM:
        return WORD_NUM[tok]
    return roman_to_int(tok)


def r1_stem_and_part(title):
    t = strip_noise(title)
    t = R1_NOISE.sub("", t).strip()
    t = TRAIL_ID.sub("", t).strip()
    t = TRAIL_BRACKET.sub("", t).strip()
    for i, rx in enumerate(R1_MARKERS):
        m = rx.match(t)
        if not m:
            continue
        if i == len(R1_MARKERS) - 1:  # "Chapter N: Title" — no arc name, skip (season-grouped)
            return None, None
        stem = m.group(1).strip(" " + DASHES + "|:,([#")
        p = r1_part(m.group(2))
        if stem and p is not None and len(norm_name(stem)) >= 3 and not GENERIC_STEM.match(stem):
            return stem, p
    return None, None


def a2r1_prefix_plus(episodes):
    episodes = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in episodes}
    order, buckets, display = [], {}, {}
    for e in episodes:
        stem, part = r1_stem_and_part(e["title"])
        if not stem or part is None:
            continue
        key = norm_name(stem)
        if key not in buckets:
            buckets[key] = []
            order.append(key)
            display[key] = stem
        buckets[key].append(e["guid"])
    # prefix-merge: fold a longer stem into a shorter one it starts with
    canonical = {}
    for k in order:
        tgt = k
        for other in order:
            if other != k and k.startswith(other + " ") and len(other) < len(tgt):
                tgt = other
        canonical[k] = tgt
    merged_order, merged = [], {}
    for k in order:
        tgt = canonical[k]
        if tgt not in merged:
            merged[tgt] = []
            merged_order.append(tgt)
        merged[tgt].extend(buckets[k])
    # emit, splitting a group across distinct non-null seasons
    out = []
    for k in merged_order:
        members = merged[k]
        by_season = OrderedDict()
        for g in members:
            s = by_guid[g].get("season")
            by_season.setdefault(s, []).append(g)
        nonnull = [s for s in by_season if s is not None]
        if len(nonnull) >= 2:
            groups = [(s, gs) for s, gs in by_season.items() if s is not None]
            # keep any None-season members with the largest group
            if None in by_season and groups:
                biggest = max(groups, key=lambda sg: len(sg[1]))
                biggest[1].extend(by_season[None])
        else:
            groups = [(nonnull[0] if nonnull else None, members)]
        for s, gs in groups:
            if len(gs) < 2:
                continue
            out.append({"name": display[k], "season": s, "members": gs})
    return out


# ===========================================================================
# A2r2 — round 2: recover parenthetical counters "(Part 1)/(Pt 1)/(Volume 1)"
#   (previously eaten by the bracket-stripper) and a general separator-agnostic
#   "Part/Parte N" marker ("Ted Bundy: Part 1", "JFK Part Two", "Parte 1").
# ===========================================================================
COUNTER_IN_BRACKET = re.compile(r'(part|pt|vol|volume|chapter|parte)\b|\d|[IVXLCDM]', re.I)
R2_GENERAL_PART = re.compile(
    r'^(.+?)[\s:,.' + DASHES + r']+Part[e]?\s+(' + NUMWORD + r')\b', re.I)


def r2_clean(title):
    t = strip_noise(title)
    t = R1_NOISE.sub("", t).strip()
    t = TRAIL_ID.sub("", t).strip()
    # strip a trailing bracket ONLY when it holds no counter (keep "(Part 1)")
    m = TRAIL_BRACKET.search(t)
    if m and not COUNTER_IN_BRACKET.search(m.group(0)):
        t = t[:m.start()].strip()
    return t


def r2_stem_and_part(title):
    t = r2_clean(title)
    for i, rx in enumerate(R1_MARKERS):
        m = rx.match(t)
        if not m:
            continue
        if i == len(R1_MARKERS) - 1:  # "Chapter N: Title" -> season-grouped, no name
            return None, None
        stem = m.group(1).strip(" " + DASHES + "|:,([#")
        p = r1_part(m.group(2))
        if stem and p is not None and len(norm_name(stem)) >= 3 and not GENERIC_STEM.match(stem):
            return stem, p
    m = R2_GENERAL_PART.match(t)  # general "…Part/Parte N" fallback
    if m:
        stem = m.group(1).strip(" " + DASHES + "|:,.([#")
        p = r1_part(m.group(2))
        if stem and p is not None and len(norm_name(stem)) >= 3 and not GENERIC_STEM.match(stem):
            return stem, p
    return None, None


def a2r2_prefix_plus(episodes):
    return _cluster_with(episodes, r2_stem_and_part)


def _cluster_with(episodes, stem_fn):
    """Shared clustering body (prefix-merge + season-split) parameterized by stem fn."""
    episodes = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in episodes}
    order, buckets, display = [], {}, {}
    for e in episodes:
        stem, part = stem_fn(e["title"])
        if not stem or part is None:
            continue
        key = norm_name(stem)
        if key not in buckets:
            buckets[key] = []
            order.append(key)
            display[key] = stem
        buckets[key].append(e["guid"])
    canonical = {}
    for k in order:
        tgt = k
        for other in order:
            if other != k and k.startswith(other + " ") and len(other) < len(tgt):
                tgt = other
        canonical[k] = tgt
    merged_order, merged = [], {}
    for k in order:
        tgt = canonical[k]
        if tgt not in merged:
            merged[tgt] = []
            merged_order.append(tgt)
        merged[tgt].extend(buckets[k])
    out = []
    for k in merged_order:
        members = merged[k]
        by_season = OrderedDict()
        for g in members:
            by_season.setdefault(by_guid[g].get("season"), []).append(g)
        nonnull = [s for s in by_season if s is not None]
        if len(nonnull) >= 2:
            groups = [(s, gs) for s, gs in by_season.items() if s is not None]
            if None in by_season and groups:
                max(groups, key=lambda sg: len(sg[1]))[1].extend(by_season[None])
        else:
            groups = [(nonnull[0] if nonnull else None, members)]
        for s, gs in groups:
            if len(gs) >= 2:
                out.append({"name": display[k], "season": s, "members": gs})
    return out


# ===========================================================================
# A2r3 — round 3: fix the char-class range bug in the general Part marker
#   (dash must be FIRST in the class to stay literal), add "|" separator and a
#   general "Volume/Vol N" marker. Recovers "X: Part N", "X | Part N",
#   "JFK Part Two", "X (Volume 1)".
# ===========================================================================
# NOTE: dash chars lead the class so the ASCII hyphen is literal, not a range.
R3_GENERAL_PART = re.compile(
    r'^(.+?)[' + DASHES + r'\s:,.|]+Part[e]?\s+(' + NUMWORD + r')\b', re.I)
R3_GENERAL_VOL = re.compile(
    r'^(.+?)[' + DASHES + r'\s:,.|]*[(\[]?\s*Vol(?:ume)?\.?\s+(' + NUMWORD + r')\b', re.I)


def r3_stem_and_part(title):
    t = r2_clean(title)
    for i, rx in enumerate(R1_MARKERS):
        m = rx.match(t)
        if not m:
            continue
        if i == len(R1_MARKERS) - 1:
            return None, None
        stem = m.group(1).strip(" " + DASHES + "|:,([#")
        p = r1_part(m.group(2))
        if stem and p is not None and len(norm_name(stem)) >= 3 and not GENERIC_STEM.match(stem):
            return stem, p
    for rx in (R3_GENERAL_PART, R3_GENERAL_VOL):
        m = rx.match(t)
        if m:
            stem = m.group(1).strip(" " + DASHES + "|:,.([#")
            p = r1_part(m.group(2))
            if stem and p is not None and len(norm_name(stem)) >= 3 and not GENERIC_STEM.match(stem):
                return stem, p
    return None, None


def a2r3_prefix_plus(episodes):
    return _cluster_with(episodes, r3_stem_and_part)


# ---------------------------------------------------------------------------
# Junk-reduction guards (structural, generalizable — no per-show hardcodes)
# ---------------------------------------------------------------------------
# The stem function returns the COUNTER KIND so guards can be recall-safe: instead of a
# blunt "big number" rule (which kills real mini-series whose early parts fell outside the
# fetch window), we target the specific anthology signatures.
#   VOLUME_ANTHOLOGY_MIN — a "Volume N" counter with N this high is an open-ended anthology
#                          ("Mini-Stories: Volume 19..22"), not a bounded arc. "(Volume 1)" stays.
# NOTE on what is NOT guardable: a bare pipe episode-number ("Diss & Tell | guest | 218") cannot be
# used to reject a cluster — shows like Even the Rich number EVERY arc by episode number
# ("Taylor Swift: Fearless | … | 212"), so a "big pipe number" rule kills real arcs. A 2-entry
# recurring segment is structurally identical to a 2-part story; regex cannot separate them.
VOLUME_ANTHOLOGY_MIN = 3


def r3_stem_part_kind(title):
    """Like r3_stem_and_part but also returns the counter KIND (pipe|part|paren|pt|hash|ep|
    chapter|volume) so guards can act on how the number was expressed."""
    t = r2_clean(title)
    kinds = ["pipe", "part", "paren", "part", "part", "pt", "hash", "ep", "chapter", "chapter-lead"]
    for i, rx in enumerate(R1_MARKERS):
        m = rx.match(t)
        if not m:
            continue
        if i == len(R1_MARKERS) - 1:
            return None, None, None
        stem = m.group(1).strip(" " + DASHES + "|:,([#")
        p = r1_part(m.group(2))
        if stem and p is not None and len(norm_name(stem)) >= 3 and not GENERIC_STEM.match(stem):
            return stem, p, kinds[i]
    for rx, kind in ((R3_GENERAL_PART, "part"), (R3_GENERAL_VOL, "volume")):
        m = rx.match(t)
        if m:
            stem = m.group(1).strip(" " + DASHES + "|:,.([#")
            p = r1_part(m.group(2))
            if stem and p is not None and len(norm_name(stem)) >= 3 and not GENERIC_STEM.match(stem):
                return stem, p, kind
    return None, None, None


def _is_anthology(kind, parts):
    """True when a cluster's numbering marks it as a recurring anthology / episode-numbered
    segment rather than a bounded 1..N mini-series. Recall-safe: only fires on Volume-keyword
    or very-large bare-pipe/hash counters, never on ordinary 'Part N'."""
    if not parts:
        return False
    lo = min(parts)
    if kind == "volume" and lo >= VOLUME_ANTHOLOGY_MIN:
        return True
    return False


# A re-release/rebroadcast marker in a title. When the same arc airs twice (original + encore/
# redux/archive), both collapse to the same (stem, part); dedup keeps ONE, preferring the original.
# NOTE: "rerun" is a correctness dependency of A6's LEAD_BRACKET strip, not optional polish.
# Once "[RERUN] " is stripped, a rerun collapses to the same (stem, part) as its original and
# the two merge into one oversized arc unless dedup can see the marker. Measured on gold:
# omitting it costs 0.0074 membership precision (0.9985 -> 0.9911) on history-on-fire alone.
RERELEASE = re.compile(
    r'\b(encore|archive|rebroadcast|rerun|redux|replay|revisited|throwback|fan[\s-]?favorite|'
    r'from the vault|classic episode)\b', re.I)


def _cluster_guarded(episodes, guard=True, dedup=False, stem_fn=None):
    """A2r3 clustering that tracks each member's part number + counter kind and drops
    anthology/episode-numbered clusters via _is_anthology. With dedup=True, collapses
    duplicate part numbers within an arc (re-release airings), preferring the original.
    stem_fn defaults to r3_stem_part_kind; pass a (title)->(stem, part, kind) fn to swap
    in a richer parser while keeping every guard identical (A6 tiers do this)."""
    stem_fn = stem_fn or r3_stem_part_kind
    episodes = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in episodes}
    part_of, kind_of, rerel_of = {}, {}, {}
    order, buckets, display = [], {}, {}
    for e in episodes:
        stem, part, kind = stem_fn(e["title"])
        if not stem or part is None:
            continue
        key = norm_name(stem)
        if key not in buckets:
            buckets[key] = []
            order.append(key)
            display[key] = stem
        buckets[key].append(e["guid"])
        part_of[e["guid"]] = part
        kind_of[e["guid"]] = kind
        rerel_of[e["guid"]] = bool(RERELEASE.search(e["title"] or ""))
    canonical = {}
    for k in order:
        tgt = k
        for other in order:
            if other != k and k.startswith(other + " ") and len(other) < len(tgt):
                tgt = other
        canonical[k] = tgt
    merged_order, merged = [], {}
    for k in order:
        tgt = canonical[k]
        if tgt not in merged:
            merged[tgt] = []
            merged_order.append(tgt)
        merged[tgt].extend(buckets[k])
    out = []
    for k in merged_order:
        members = merged[k]
        by_season = OrderedDict()
        for g in members:
            by_season.setdefault(by_guid[g].get("season"), []).append(g)
        nonnull = [s for s in by_season if s is not None]
        if len(nonnull) >= 2:
            groups = [(s, gs) for s, gs in by_season.items() if s is not None]
            if None in by_season and groups:
                max(groups, key=lambda sg: len(sg[1]))[1].extend(by_season[None])
        else:
            groups = [(nonnull[0] if nonnull else None, members)]
        for s, gs in groups:
            if dedup:
                # Collapse re-aired duplicates ONLY: drop a re-release-marked episode when a
                # non-re-release sibling already covers that part number. Never drops a distinct
                # (unmarked) episode, even if two share a part after a prefix-merge.
                covered = {part_of[g] for g in gs if not rerel_of[g]}
                drop = set()
                seen_rr = set()
                for g in gs:
                    if rerel_of[g]:
                        p = part_of[g]
                        if p in covered or p in seen_rr:
                            drop.add(g)
                        else:
                            seen_rr.add(p)
                if drop:
                    gs = [g for g in gs if g not in drop]
            if len(gs) < 2:
                continue
            if guard:
                parts = [part_of[g] for g in gs if g in part_of]
                kinds = {kind_of[g] for g in gs if g in kind_of}
                kind = next(iter(kinds)) if len(kinds) == 1 else "mixed"
                if _is_anthology(kind, parts):
                    continue
            out.append({"name": display[k], "season": s, "members": gs})
    return out


def a2r3_1_prefix_plus(episodes):
    """Round-1 junk guard: drop Volume-anthology + episode-numbered clusters (recall-safe)."""
    return _cluster_guarded(episodes, guard=True)


def a2r3_2_prefix_plus(episodes):
    """Round-2: + collapse re-release duplicates (encore/redux/archive re-airings)."""
    return _cluster_guarded(episodes, guard=True, dedup=True)


# POST-BAKEOFF season-serial extensions (mirror EpisodeArcs.swift; need a gold re-score).
# Leading "S7 E1: Title" (Scene on Radio): arc name absent from the title, season is the arc.
SEASON_EPISODE_LEAD = re.compile(r'^S\s*\d+\s*E\s*\d+\b', re.I)
# Season theme lives on the trailer/intro title; scan RAW titles (strip_noise eats "Introducing").
SEASON_THEME_PATTERNS = [
    re.compile(r'Season\s+\d+\s+Trailer\s*:\s*(.+)$', re.I),      # "Season 7 Trailer: Capitalism"
    re.compile(r'Season\s+\d+\s*:\s*(.+?)\s+Trailer\s*$', re.I),  # "…Season 3: MEN Trailer"
    re.compile(r'Introducing\b.*?:\s*(.+)$', re.I),               # "Introducing Scene on Radio: The News"
]


def _season_theme(titles):
    for title in titles:
        t = title.strip()
        for pat in SEASON_THEME_PATTERNS:
            m = pat.search(t)
            if m:
                theme = m.group(1).strip().strip('"“”‘’ ')
                if theme:
                    return theme
    return None


def _tier1(episodes, stem_fn=None):
    """A2r3.2 clustering + a SCOPED chaptered-season handler. Shows whose arcs live only in
    `itunes:season` with `Chapter N | Title` (Bone Valley) or `S7 E1: Title` (Scene on Radio)
    episodes carry no arc name in the title, so title-clustering misses them. Group those
    specific episodes (and only those) by season, named from the season trailer when present.
    Tightly scoped to those two leading shapes, so it adds none of the blanket season-fallback's
    junk on other feeds.

    stem_fn is threaded through to _cluster_guarded so the A6 tiers can swap in a richer
    parser while every guard, the dedup and this season pass stay byte-identical."""
    episodes = sort_newest_first(episodes)
    arcs = _cluster_guarded(episodes, guard=True, dedup=True, stem_fn=stem_fn)
    taken = {g for a in arcs for g in a["members"]}
    by_season = OrderedDict()
    titles_by_season = OrderedDict()
    for e in episodes:
        if e.get("season") is None:
            continue
        titles_by_season.setdefault(e["season"], []).append(e["title"])
        if e["guid"] in taken:
            continue
        t = strip_noise(e["title"])
        if CHAPTER_LEAD.match(t) or SEASON_EPISODE_LEAD.match(t):
            by_season.setdefault(e["season"], []).append(e)
    for s, members in by_season.items():
        if len(members) >= 2:
            name = _season_theme(titles_by_season.get(s, [])) or f"Season {s}"
            arcs.append({"name": name, "season": s,
                         "members": [e["guid"] for e in members]})
    return arcs


def a2r3_3_final(episodes):
    """The shipped detector: _tier1 with the stock r3 parser."""
    return _tier1(episodes)


# ===========================================================================
# A6 — cascading multi-pass detector
# ===========================================================================
# The incumbent A2r3.3-final holds memPrec 0.999 / junk 0.003 but only 0.627 arc
# recall: 218 of its 220 missed gold arcs are "zero members detected" — the parser
# never clusters those episodes at all. Escalating to the wide detectors (A5-hybrid
# et al) recovers only 20% of that while memPrec collapses to 0.42, because they miss
# the same grammars for the same reason. This is a PARSER gap, not a risk-appetite
# gap, so A6 keeps tier 1 untouched and adds parser tiers on top.
#
#   tier 1  a2r3_3_final, unchanged
#   tier 2a CLEANER — strip leading noise so the EXISTING markers can fire
#   tier 2b MARKERS — grammars the existing marker table cannot express
#   tier 3a affix clustering (gated + shape-guarded)
#   tier 3b counter-run / adjacency (experimental)
#
# Tier 2a is the cheapest lever in the whole design. "EPISODE 47: Give Me Back My
# Legions! (Part 1)" ALREADY parses its (Part N) marker correctly — GENERIC_STEM then
# rejects the stem because it starts with "episode". Likewise "691 // Kierra Coles -
# Part 2" yields the right part but a stem polluted by the episode number, so Part 1
# and Part 2 land in different buckets. Both are fixed by cleaning the title and
# re-running the UNMODIFIED r3 parser — no new marker regexes at all.
# ---------------------------------------------------------------------------
# "[RERUN] ", "[Repetición] " — a bracketed tag before the real title. Length-capped
# so it can never eat a genuine bracketed arc name.
LEAD_BRACKET = re.compile(r'^\s*[\[(][^\])]{0,20}[\])]\s*')
# "EPISODE 47: ", "Episode 391 - " — the word form, always followed by a separator.
LEAD_EPISODE_WORD = re.compile(r'^\s*Ep(?:isode|\.)?\s+\d{1,4}\s*[' + DASHES + r':|]\s*', re.I)
# "691 // ", "450 - ", "1. ", "36: " — a bare leading counter plus a separator. The
# separator and the trailing space are both REQUIRED: without them this would eat the
# leading number of a real title ("1917 - The Somme" is guarded by the residue check
# and, if that proves insufficient, by the feed-level shape check in _lead_epnum_ok).
LEAD_EPNUM = re.compile(r'^\s*(\d{1,4})\s*(?://|[' + DASHES + r'.:)\]#|])\s+')


def r4_clean(title):
    """r2_clean + leading-noise strips, each guarded by a residue check.

    The residue check is load-bearing: without it "EPISODE 47" collapses to "" and the
    episode is lost entirely rather than merely unparsed."""
    t = r2_clean(title)
    for rx in (LEAD_BRACKET, LEAD_EPISODE_WORD, LEAD_EPNUM):
        t2 = rx.sub("", t).strip()
        if len(norm_name(t2)) >= 3:
            t = t2
    return t


def r4_clean_stem_part_kind(title):
    """Tier 2a only: clean, then run the STOCK r3 parser. No new markers."""
    return r3_stem_part_kind(r4_clean(title))


def a6_1_clean(episodes):
    """A6.1 — tier 1 pipeline, cleaner swapped in. Isolates the cleaner's recall gain."""
    return _tier1(episodes, stem_fn=r4_clean_stem_part_kind)


# ---------------------------------------------------------------------------
# Tier 2b — counter grammars the existing marker table cannot express
# ---------------------------------------------------------------------------
# "Part One: Richard Marcinko: The Founder of SEAL Team 6" (Behind the Bastards) — the
# counter LEADS and the arc name follows it. Every R1/R3 marker requires stem-before-
# counter, so these parse to (None, None). Where the remainder is not shared between
# parts (7am: "Part 1: Victoria's treaty" / "Part 2: The politics and pushback") the
# resulting singletons are simply dropped by the >= 2 floor — no junk, no gain.
LEAD_PART = re.compile(
    r'^Part\s+(' + NUMWORD + r')\s*[' + DASHES + r':]\s*(.+)$', re.I)
# "Becoming Justice Gorsuch | 3. A Lunch Room for Life" (Slow Burn) — pipe, then a
# DOTTED counter, then the per-episode subtitle. The stock pipe marker wants two pipes
# and no dot. The trailing ". Subtitle" is required, which is what keeps this off the
# feed-wide "Rockwood | 18" counters that grammar 7 was cut for.
PIPE_DOT = re.compile(r'^(.+?)\s*\|\s*(\d{1,3})\s*[.)]\s+(.+)$')
# "Case 339: Waco (Part 3/3)" (Casefile) — an i/j fraction inside the paren. The stock
# (Part N) marker anchors the closing bracket straight after the number, so "3/3)" fails.
# The stem ("Case 339: Waco") is already shared across parts, so no lead strip is needed.
FRACTION_PAREN = re.compile(
    r'^(.+?)\s*[(\[]\s*(?:Part|Pt\.?)\s*(' + NUMWORD + r')\s*/\s*\d+\s*[)\]]', re.I)
# "Released To Die: Episode 3" (Suave) — trailing "Episode N" after a colon/pipe.
COLON_EP = re.compile(r'^(.+?)\s*[:|]\s*Ep(?:isode|\.)?\s*(\d+)\s*$', re.I)

R4_MARKERS = [  # (regex, stem_group, num_group, kind)
    (LEAD_PART,      2, 1, "lead-part"),
    (PIPE_DOT,       1, 2, "pipe-dot"),
    (FRACTION_PAREN, 1, 2, "part"),
    (COLON_EP,       1, 2, "ep"),
]


def _accept(stem, p):
    """The stem/part acceptance predicate shared by every marker layer (r3 inlines this
    same test at four sites; A6 factors it so the tiers cannot drift apart)."""
    return bool(stem) and p is not None and len(norm_name(stem)) >= 3 \
        and not GENERIC_STEM.match(stem)


def r4_stem_part_kind(title, markers=None):
    """Tier 2a + 2b: clean, try the new markers, then fall through to the STOCK r3 parser
    ON THE CLEANED TITLE. That fall-through is what makes the cleaner's levers work through
    the existing marker table without duplicating a single regex."""
    t = r4_clean(title)
    for rx, gs, gp, kind in (R4_MARKERS if markers is None else markers):
        m = rx.match(t)
        if not m:
            continue
        stem = m.group(gs).strip(" " + DASHES + "|:,([#")
        p = r1_part(m.group(gp))
        if _accept(stem, p):
            return stem, p, kind
    return r3_stem_part_kind(t)


def a6_2_markers(episodes):
    """A6.2 — tier 1 pipeline with the full tier-2 parser (cleaner + new markers).

    Note this REPLACES the parser rather than cascading: the new markers are tried ahead of
    the stock r3 table for every episode, so a title r3 used to claim can be re-read by a
    tier-2 marker. A6.3 is the cascade alternative that leaves tier 1 untouched."""
    return _tier1(episodes, stem_fn=r4_stem_part_kind)


def a6_3_tier2(episodes):
    """A6.3 — the actual cascade: stock tier 1 runs FIRST and unmodified, then the tier-2
    parser gets a second pass over only the episodes tier 1 did not claim. Follows the
    taken-guid-set discipline of a5_hybrid (:370) and a2r3_3_final (:806). Naive concat —
    A6.4 swaps in _reconcile."""
    episodes = sort_newest_first(episodes)
    t1 = _tier1(episodes)
    taken = {g for a in t1 for g in a["members"]}
    rest = [e for e in episodes if e["guid"] not in taken]
    t2 = _cluster_guarded(rest, guard=True, dedup=True, stem_fn=r4_stem_part_kind)
    return t1 + t2


def _reconcile(stages, episodes):
    """Resolve arcs emitted by different tiers into one consistent list.

    stages: [(tier_int, arcs), ...] in priority order. Nothing in the file did this before —
    the existing cascades just concatenate, which is safe only while later stages are fed a
    pre-filtered episode list. Tier 3 breaks that assumption, so reconciliation is explicit:

      * TRIM, don't drop — a later arc keeps whatever members are still free, mirroring
        a3_structured (:339-342), and is re-checked against the >= 2 floor.
      * CANNIBALIZATION guard — a later-tier arc that lost more than half of itself to an
        earlier tier IS that earlier arc's family; emitting the remainder under a different
        name is pure junk. No precedent in the file; it is the main thing stopping tier 3
        from re-emitting the tail of a tier-2 arc.
      * NO cross-tier merge on name. Merging arcs that share (norm_name, season) was tried and
        MEASURED HARMFUL: memPrec 0.9963 -> 0.9902 and matched 482 -> 479 on gold. Two arcs can
        legitimately normalize to the same name in one feed (a recurring title shape with
        separate part runs), and fusing them builds an oversized arc that then falls under the
        0.5 Jaccard match threshold — losing arcs that both tiers had already got right.
        The taken-set already guarantees the tiers are disjoint, so leaving them separate is
        both simpler and strictly better.
      * SEASON is recomputed from the surviving members, so a trimmed arc never keeps a season
        claim that no longer describes it.
    """
    by_guid = {e["guid"]: e for e in episodes}
    taken, out = set(), []
    for tier, arcs in stages:
        for a in arcs:
            orig = len(a["members"])
            members = [g for g in a["members"] if g not in taken]
            if len(members) < 2:
                continue
            if tier > 1 and len(members) * 2 < orig:
                continue
            out.append({**a, "members": list(members)})
            taken.update(members)
    final = []
    for a in out:
        if len(a["members"]) < 2:
            continue
        seasons = {by_guid[g].get("season") for g in a["members"] if g in by_guid}
        seasons.discard(None)
        a["season"] = seasons.pop() if len(seasons) == 1 else None
        final.append(a)
    return final


# ---------------------------------------------------------------------------
# Tier 3a — affix clustering (the risky tier)
# ---------------------------------------------------------------------------
# 76 of the missed gold arcs carry NO usable counter: a constant prefix or suffix segment
# plus a per-episode subtitle ("We Keep Us Safe: Who Killed Antonio Mays Jr." / "We Keep Us
# Safe: The Standoff"; "The Sentence - Ep. 1" / "The Hustle - Ep. 2" where the arc name is
# nowhere in the title). Clustering on a shared segment instead of a shared stem+counter is
# the only way to reach them — and it is genuinely dangerous, because a feed-wide episode
# counter ("Rockwood | 18", 545 such titles across 26 feeds) has the identical shape.
#
# Measured: ungated this scores memPrec 0.65 / junk 0.16. The FEED GATE alone only reaches
# 0.79 — it is a cheap pre-filter, NOT the load-bearing guard. The cluster-SHAPE guards
# (contiguity above all) are what make this survivable.
AFFIX_SPLIT = re.compile(r'\s*(?:\|\s|:\s|\s[' + DASHES + r']\s)\s*')


def _affix_segments(title):
    return [s for s in (x.strip() for x in AFFIX_SPLIT.split(r4_clean(title))) if s]


def _repeated_segment_ratio(episodes, mode):
    """RLS (mode='prefix') / RTS (mode='suffix'): fraction of episodes whose leading (or
    trailing) segment is shared with at least one other episode. Coverage ratio ALONE is
    degenerate as a trigger — 227 of 315 corpus feeds sit at exactly zero — so this is the
    feature that actually separates a missed serial from a genuinely arcless weekly show."""
    if not episodes:
        return 0.0
    i = 0 if mode == "prefix" else -1
    keys = []
    for e in episodes:
        segs = _affix_segments(e["title"])
        keys.append(norm_name(segs[i]) if len(segs) >= 2 else None)
    counts = Counter(k for k in keys if k)
    return sum(1 for k in keys if k and counts[k] >= 2) / len(episodes)


def _tier3_gate(episodes, arcs, mode, min_eps=8, max_cov=0.30, min_ratio=0.15):
    if len(episodes) < min_eps:
        return False
    covered = len({g for a in arcs for g in a["members"]})
    if covered / len(episodes) >= max_cov:
        return False
    return _repeated_segment_ratio(episodes, mode) >= min_ratio


def _affix_arcs(episodes, taken, mode, max_size=None, min_len=0,
                contiguity=None, counter_reject=False):
    """Cluster untaken episodes on a shared leading/trailing segment.

    contiguity: reject a cluster whose members are scattered across the feed. A real arc airs
      as a block; a recurring segment recurs across the whole run. Reject unless
      (max_pos - min_pos) <= len(members) * contiguity.
    counter_reject: drop a cluster whose episodeNumbers form a strictly-increasing run with no
      repeats and a wide span — the feed-wide-counter signature (business-wars, even-the-rich).
    """
    episodes = sort_newest_first(episodes)
    pos = {e["guid"]: i for i, e in enumerate(episodes)}
    by_guid = {e["guid"]: e for e in episodes}
    i = 0 if mode == "prefix" else -1
    order, buckets, display = [], {}, {}
    for e in episodes:
        if e["guid"] in taken:
            continue
        segs = _affix_segments(e["title"])
        if len(segs) < 2:
            continue  # a single-segment title has no affix to share
        seg = segs[i]
        key = norm_name(seg)
        if len(key) < min_len or GENERIC_STEM.match(seg):
            continue
        if key not in buckets:
            buckets[key] = []
            order.append(key)
            display[key] = seg
        buckets[key].append(e["guid"])
    out = []
    for k in order:
        members = buckets[k]
        if len(members) < 2:
            continue
        if max_size is not None and len(members) > max_size:
            continue
        if contiguity is not None:
            ps = [pos[g] for g in members]
            if max(ps) - min(ps) > len(members) * contiguity:
                continue
        if counter_reject:
            nums = [by_guid[g].get("episodeNumber") for g in members]
            nums = [n for n in nums if n is not None]
            if len(nums) == len(members) and len(set(nums)) == len(nums) \
                    and max(nums) - min(nums) > len(nums) * 2:
                continue
        seasons = {by_guid[g].get("season") for g in members}
        seasons.discard(None)
        out.append({"name": display[k], "season": seasons.pop() if len(seasons) == 1 else None,
                    "members": members})
    return out


# ---------------------------------------------------------------------------
# Tier 3b — counter-run / adjacency (experimental)
# ---------------------------------------------------------------------------
# 7am publishes "Part 1: Victoria's historic treaty" then "Part 2: The politics and
# pushback". The counter parses fine, but the two parts share ZERO title text, so no
# amount of stem or affix clustering can ever join them — the only evidence they belong
# together is that they are ADJACENT in publication order and numbered 1 then 2.
#
# Deliberately strict: a run must START at part 1 and step by exactly 1 with no gaps in
# publication order. That makes it near-unfireable on a weekly show that happens to use
# "Part N" occasionally, at the cost of missing arcs whose part 1 fell outside the fetch
# window. Experimental — ship only if it independently clears the floor.
LEAD_COUNTER_ONLY = re.compile(
    r'^(?:Part|Chapter|Ep(?:isode|\.)?)\s+(' + NUMWORD + r')\s*[' + DASHES + r':]\s*(.+)$', re.I)


def _counter_run_arcs(episodes, taken, min_run=2):
    eps = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in eps}
    oldest_first = list(reversed(eps))
    seq = []
    for e in oldest_first:
        m = LEAD_COUNTER_ONLY.match(r4_clean(e["title"]))
        if m:
            seq.append((e, r1_part(m.group(1)), m.group(2).strip()))
        else:
            seq.append((e, None, None))
    # Match a contiguous block whose parts form the COMPLETE set {1..k}, in any order.
    # Order-insensitivity is required, not a nicety: 7am publishes both halves the same day,
    # so the iso tie-break can invert them ("Part 2" lands before "Part 1" in publication
    # order). Requiring the full 1..k set keeps this strict — a stray "Part 2" with no
    # part 1 beside it never forms an arc.
    out, n = [], len(seq)
    i = 0
    while i < n:
        if seq[i][1] is None or seq[i][0]["guid"] in taken:
            i += 1
            continue
        j = i
        while j < n and seq[j][1] is not None and seq[j][0]["guid"] not in taken:
            j += 1
        block, b = seq[i:j], 0                      # maximal counter-bearing block
        while b < len(block):
            k = b
            while k < len(block):
                parts = [x[1] for x in block[b:k + 1]]
                if sorted(parts) == list(range(1, len(parts) + 1)) and len(parts) >= min_run:
                    run = block[b:k + 1]
                    members = [x[0]["guid"] for x in reversed(run)]  # back to newest-first
                    seasons = {by_guid[g].get("season") for g in members}
                    seasons.discard(None)
                    first = min(run, key=lambda x: x[1])            # the part-1 episode
                    out.append({"name": first[2] or f"Part 1-{len(run)}",
                                "season": seasons.pop() if len(seasons) == 1 else None,
                                "members": members})
                    break
                k += 1
            b = k + 1 if k < len(block) else b + 1
        i = j
    return out


def _a6_cascade(episodes, tier3=False, gate=True, max_size=None, min_len=0,
                contiguity=None, counter_reject=False, tier3b=False):
    """The full A6 cascade. tier3/gate/guard params exist so each increment is measurable."""
    episodes = sort_newest_first(episodes)
    t1 = _tier1(episodes)
    taken = {g for a in t1 for g in a["members"]}
    rest = [e for e in episodes if e["guid"] not in taken]
    t2 = _cluster_guarded(rest, guard=True, dedup=True, stem_fn=r4_stem_part_kind)
    stages = [(1, t1), (2, t2)]
    if tier3:
        so_far = t1 + t2
        taken2 = {g for a in so_far for g in a["members"]}
        for mode in ("prefix", "suffix"):
            if gate and not _tier3_gate(episodes, so_far, mode):
                continue
            stages.append((3, _affix_arcs(episodes, taken2, mode, max_size=max_size,
                                          min_len=min_len, contiguity=contiguity,
                                          counter_reject=counter_reject)))
    if tier3b:
        taken3 = {g for _, arcs in stages for a in arcs for g in a["members"]}
        stages.append((3, _counter_run_arcs(episodes, taken3)))
    return _reconcile(stages, episodes)


def a6_5_affix_raw(episodes):
    """A6.5 — tier 3 with no gate and no guards. Ceiling measurement only; never ship."""
    return _a6_cascade(episodes, tier3=True, gate=False)


def a6_6_affix_gated(episodes):
    """A6.6 — tier 3 with the feed gate only. Confirms the gate is not the load-bearing guard."""
    return _a6_cascade(episodes, tier3=True, gate=True)


def a6_7_affix_guarded(episodes):
    """A6.7 — tier 3 gated AND cluster-shape guarded, params tuned on gold.

    Swept max_size x min_len x contiguity x counter_reject, then the gate thresholds. Two
    configs topped the sweep; this is the SAFER one. The aggressive alternative
    (max_cov=0.5, contiguity=4) scores 0.8763 recall but leaves only 0.0021 of junk margin
    under the 0.05 ceiling — on a 45-feed gold sample that margin is noise, and tipping over
    it forfeits the entire win. This config gives up ~3 arcs for 5x the margin.

    counter_reject changes nothing on gold (business-wars / even-the-rich are not gold feeds)
    but is kept as corpus-side insurance against feed-wide episode counters.

    max_size=12 rather than 8: Suspect's arc is a 10-episode season and an 8 cap rejected it
    outright (the show is a named target in HFAB_PROMPT.md). 10/12/16/24 score identically on
    gold, so the exact value is not sensitive in that band — but removing the cap entirely
    collapses memPrec to 0.836, so the bound itself is load-bearing."""
    return _a6_cascade(episodes, tier3=True, gate=True, max_size=12, min_len=6,
                       contiguity=3, counter_reject=True)


def a6_cascade(episodes):
    """A6 — THE RECOMMENDED WINNER. Full cascade: tier 1 (untouched) -> tier 2 parser
    (cleaner + new markers) -> tier 3a affix clustering (gated + shape-guarded) -> tier 3b
    counter-run adjacency, reconciled.

    Gold (45 feeds / 590 arcs): memPrec 0.9736, junk 0.0391, arcRecall 0.8746, 537 arcs.
    Incumbent A2r3.3-final: memPrec 0.9985, junk 0.0027, arcRecall 0.6271, 371 arcs.
    Spends 0.025 of the 0.049 memPrec headroom and 0.039 of the 0.047 junk headroom to buy
    +0.247 arc recall."""
    return _a6_cascade(episodes, tier3=True, gate=True, max_size=12, min_len=6,
                       contiguity=3, counter_reject=True, tier3b=True)


def a6_4_reconciled(episodes):
    """A6.4 — A6.3 with _reconcile instead of naive concat. Must score IDENTICALLY to A6.3:
    tier 2 only ever sees episodes tier 1 declined, so there is nothing to reconcile yet.
    Any difference here is a reconcile bug, not an improvement."""
    episodes = sort_newest_first(episodes)
    t1 = _tier1(episodes)
    taken = {g for a in t1 for g in a["members"]}
    rest = [e for e in episodes if e["guid"] not in taken]
    t2 = _cluster_guarded(rest, guard=True, dedup=True, stem_fn=r4_stem_part_kind)
    return _reconcile([(1, t1), (2, t2)], episodes)


# ===========================================================================
# A7 — closing the measured coverage gap (regex only)
# ===========================================================================
# A6 leaves 181 of 315 corpus feeds with zero arcs. Partitioning those feeds showed
# roughly 40% are genuinely arcless (weekly interview / news / anthology) but ~60% are
# our miss. Two shapes account for most of the recoverable half, and both are reachable
# without any semantic layer:
#
#   A7.1  bare "Episode N: Title" chaptering  (bundyville, blindspot, death-of-an-artist)
#   A7.2  bare/trailing counter runs          (fairy-meadow "1. …", empire-city "… | 8")
#
# The remaining misses (floodlines, dolly-partons-america) carry NO title signal at all —
# the season is the arc and every title is a standalone noun phrase. Regex cannot reach
# those; they are the case for a later semantic pass.

# --- A7.1 -----------------------------------------------------------------
# Tier 1's scoped season pass recognised "Chapter N |" and "S7 E1:" but not a bare
# "Episode 1: The Explosion". Same situation exactly: the arc name is absent from the
# title and itunes:season is the only grouping evidence.
#
# Season metadata looked like a sufficient guard on the corpus: of the 36 zero-arc feeds
# using this lead, the 29 with season metadata are serials and the 7 without are exactly
# the feed-wide-counter traps (homecoming 116 episodes, anatomy-of-doubt 196, message 39).
# Gold said otherwise. bear-grease numbers 60 episodes INSIDE one itunes:season and
# history-on-fire 101 — a per-season episode counter, not an arc. Grouping on the lead
# alone cost 0.104 membership precision (0.9684 -> 0.8648).
#
# So this pass needs two things the tier-1 season pass does not:
#   1. a SIZE CAP. A 60-episode season is a publishing convention; an arc is not.
#   2. a LATE position. Run inside tier 1 it also cost RECALL (0.8763 -> 0.8610), because
#      it swallowed episodes tier 2's richer parser was already grouping correctly
#      ("Episode 47: Give Me Back My Legions! (Part 1)" is a Part-1, not a season member).
# Both are why this is tier 4 and not an extra lead regex on tier 1.
EPISODE_NUM_LEAD = re.compile(r'^Ep(?:isode|\.)?\s*\d{1,3}\b', re.I)
SEASON_LEAD_MAX = 12


def _season_lead_arcs(episodes, taken, leads=(EPISODE_NUM_LEAD,), max_size=SEASON_LEAD_MAX):
    """Group leftover episodes whose titles carry a bare counter lead by itunes:season."""
    by_season, titles_by_season = OrderedDict(), OrderedDict()
    for e in episodes:
        if e.get("season") is None:
            continue
        titles_by_season.setdefault(e["season"], []).append(e["title"])
        if e["guid"] in taken:
            continue
        t = strip_noise(e["title"])
        if any(rx.match(t) for rx in leads):
            by_season.setdefault(e["season"], []).append(e)
    out = []
    for s, members in by_season.items():
        if not 2 <= len(members) <= max_size:
            continue
        name = _season_theme(titles_by_season.get(s, [])) or f"Season {s}"
        out.append({"name": name, "season": s,
                    "members": [e["guid"] for e in members]})
    return out

# --- A7.2 -----------------------------------------------------------------
# Tier 3b's LEAD_COUNTER_ONLY needs a keyword ("Part 2", "Chapter 4"). These grammars
# carry the counter with no keyword at all, which is why 50 zero-arc feeds slip past it:
#
#     "1. When the Wind Changed"          fairy-meadow
#     "04_KEEP IT 200"                    trailing-underscore variant
#     "They Keep People Safe | 1"         empire-city
#
# A bare number is far weaker evidence than "Part 2", so this pass is stricter than 3b
# in three ways: min_run is 3 (not 2), the run must be a COMPLETE {1..k} set, and a run
# longer than max_run is read as a feed-wide episode counter and rejected outright
# rather than trimmed. On the corpus that cap separates cleanly with zero overlap —
# arc-shaped runs top out at 12, feed counters start at 31.
BARE_LEAD_COUNTER = re.compile(r'^(\d{1,2})\s*[' + DASHES + r'._:)\]]\s*(\S.*)$')
TRAIL_PIPE_COUNTER = re.compile(r'^(\S.*?)\s*\|\s*(\d{1,2})\s*$')
BARE_COUNTER_GRAMMARS = [(BARE_LEAD_COUNTER, 2, 1), (TRAIL_PIPE_COUNTER, 1, 2)]


def _bare_counter_seq(episodes, grammar):
    """Parse every title with ONE grammar, returning [(episode, part|None, text|None)]."""
    rx, gs, gp = grammar
    out = []
    for e in episodes:
        m = rx.match(strip_noise(e["title"]))
        if m:
            stem = m.group(gs).strip(" " + DASHES + "|:,([#")
            part = r1_part(m.group(gp))
            if stem and part is not None and len(norm_name(stem)) >= 3:
                out.append((e, part, stem))
                continue
        out.append((e, None, None))
    return out


def _bare_counter_run_arcs(episodes, taken, min_run=3, max_run=12):
    eps = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in eps}
    oldest_first = list(reversed(eps))
    # One grammar per feed — whichever the most titles use. A feed that mixes "1. Title"
    # and "Title | 1" is not expressing an arc, and letting both fire would let a run in
    # one grammar bridge a gap in the other.
    seqs = [_bare_counter_seq(oldest_first, g) for g in BARE_COUNTER_GRAMMARS]
    seq = max(seqs, key=lambda s: sum(1 for x in s if x[1] is not None))
    if sum(1 for x in seq if x[1] is not None) < min_run:
        return []

    out, n = [], len(seq)
    i = 0
    while i < n:
        if seq[i][1] is None or seq[i][0]["guid"] in taken:
            i += 1
            continue
        j = i
        while j < n and seq[j][1] is not None and seq[j][0]["guid"] not in taken:
            j += 1
        block, b = seq[i:j], 0                      # maximal counter-bearing block
        while b < len(block):
            # LONGEST complete {1..k} from b, not the shortest. Tier 3b can stop at the
            # first complete set because "Part 1"/"Part 2" really is a 2-parter; here,
            # stopping early would carve a 3-episode arc out of a 66-long feed counter
            # and never see that the run kept going.
            best = 0
            for k in range(b, len(block)):
                parts = [x[1] for x in block[b:k + 1]]
                if sorted(parts) == list(range(1, len(parts) + 1)):
                    best = k + 1 - b
            if best == 0:
                b += 1
                continue
            if min_run <= best <= max_run:
                run = block[b:b + best]
                members = [x[0]["guid"] for x in reversed(run)]   # back to newest-first
                seasons = {by_guid[g].get("season") for g in members}
                seasons.discard(None)
                first = min(run, key=lambda x: x[1])
                out.append({"name": first[2] or f"Part 1-{best}",
                            "season": seasons.pop() if len(seasons) == 1 else None,
                            "members": members})
            b += best                               # consume the run either way
        i = j
    return out


def _a7_cascade(episodes, season_lead=False, bare_counter=False):
    """A6-cascade plus the two A7 levers, each switchable so its gain is measurable alone."""
    episodes = sort_newest_first(episodes)
    t1 = _tier1(episodes)
    taken = {g for a in t1 for g in a["members"]}
    rest = [e for e in episodes if e["guid"] not in taken]
    t2 = _cluster_guarded(rest, guard=True, dedup=True, stem_fn=r4_stem_part_kind)
    stages = [(1, t1), (2, t2)]
    so_far = t1 + t2
    taken2 = {g for a in so_far for g in a["members"]}
    for mode in ("prefix", "suffix"):
        if not _tier3_gate(episodes, so_far, mode):
            continue
        stages.append((3, _affix_arcs(episodes, taken2, mode, max_size=12, min_len=6,
                                      contiguity=3, counter_reject=True)))
    taken3 = {g for _, arcs in stages for a in arcs for g in a["members"]}
    stages.append((3, _counter_run_arcs(episodes, taken3)))
    if bare_counter:
        taken4 = {g for _, arcs in stages for a in arcs for g in a["members"]}
        stages.append((4, _bare_counter_run_arcs(episodes, taken4)))
    if season_lead:
        taken5 = {g for _, arcs in stages for a in arcs for g in a["members"]}
        stages.append((4, _season_lead_arcs(episodes, taken5)))
    return _reconcile(stages, episodes)


def a7_1_season_lead(episodes):
    """A7.1 — A6-cascade + a late, size-capped season pass over bare "Episode N:" leads."""
    return _a7_cascade(episodes, season_lead=True)


def a7_2_bare_counter(episodes):
    """A7.2 — A6-cascade + bare/trailing counter runs as tier 4."""
    return _a7_cascade(episodes, bare_counter=True)


def a7_cascade(episodes):
    """A7 — both levers on top of A6-cascade."""
    return _a7_cascade(episodes, season_lead=True, bare_counter=True)


CONTENDERS = OrderedDict([
    ("baseline", baseline),
    ("A1-extended", a1_extended),
    ("A2-prefix", a2_prefix_cluster),
    ("A3-structured", a3_structured),
    ("A4-delimiter", a4_delimiter),
    ("A5-hybrid", a5_hybrid),
    ("A2r1-prefix+", a2r1_prefix_plus),
    ("A2r2-prefix+", a2r2_prefix_plus),
    ("A2r3-prefix+", a2r3_prefix_plus),
    ("A2r3.1-guard", a2r3_1_prefix_plus),
    ("A2r3.2-dedup", a2r3_2_prefix_plus),
    ("A2r3.3-final", a2r3_3_final),
    # A6 ladder — each entry isolates one increment so per-lever gain stays measurable.
    # The ceiling-only variants (tier 3 ungated / gate-only) are deliberately NOT registered:
    # both fail the floor by design and exist in RECOMMENDATION-recall.md as evidence that the
    # feed gate is not the load-bearing guard. Reproduce them via _a6_cascade(gate=False) and
    # _a6_cascade(tier3=True, gate=True) with no shape guards.
    ("A6.1-clean", a6_1_clean),
    ("A6.2-markers", a6_2_markers),
    ("A6.3-tier2", a6_3_tier2),
    ("A6.4-reconciled", a6_4_reconciled),
    ("A6.7-affix-guarded", a6_7_affix_guarded),
    ("A6-cascade", a6_cascade),
    # A7 ladder — same discipline: one lever per entry.
    ("A7.1-season-lead", a7_1_season_lead),
    ("A7.2-bare-counter", a7_2_bare_counter),
    ("A7-cascade", a7_cascade),
])


if __name__ == "__main__":
    import json
    import sys
    from pathlib import Path
    root = Path(__file__).resolve().parent.parent.parent
    for slug in ("american-history-tellers", "explorers-podcast"):
        p = root / "design" / "kit" / "data" / f"{slug}.json"
        if not p.exists():
            continue
        data = json.loads(p.read_text())
        eps = [{"guid": e["guid"], "title": e["rawTitle"], "season": e.get("season"),
                "episodeNumber": e.get("episodeNumber"), "episodeType": e.get("episodeType", "full"),
                "iso": e.get("iso", "")} for e in data["episodes"]]
        print(f"\n=== {slug} ({len(eps)} eps) ===")
        for name, fn in CONTENDERS.items():
            try:
                arcs = fn(eps)
                print(f"  {name:16s} {len(arcs):3d} arcs  "
                      f"e.g. {[a['name'] for a in arcs[:3]]}")
            except Exception as e:  # noqa: BLE001
                print(f"  {name:16s} ERROR {type(e).__name__}: {e}")
