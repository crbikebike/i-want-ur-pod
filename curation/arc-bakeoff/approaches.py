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
RERELEASE = re.compile(
    r'\b(encore|archive|rebroadcast|redux|replay|revisited|throwback|fan[\s-]?favorite|'
    r'from the vault|classic episode)\b', re.I)


def _cluster_guarded(episodes, guard=True, dedup=False):
    """A2r3 clustering that tracks each member's part number + counter kind and drops
    anthology/episode-numbered clusters via _is_anthology. With dedup=True, collapses
    duplicate part numbers within an arc (re-release airings), preferring the original."""
    episodes = sort_newest_first(episodes)
    by_guid = {e["guid"]: e for e in episodes}
    part_of, kind_of, rerel_of = {}, {}, {}
    order, buckets, display = [], {}, {}
    for e in episodes:
        stem, part, kind = r3_stem_part_kind(e["title"])
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


def a2r3_3_final(episodes):
    """Final: A2r3.2 + a SCOPED chaptered-season handler. Shows whose arcs live only in
    `itunes:season` with `Chapter N | Title` (Bone Valley) or `S7 E1: Title` (Scene on Radio)
    episodes carry no arc name in the title, so title-clustering misses them. Group those
    specific episodes (and only those) by season, named from the season trailer when present.
    Tightly scoped to those two leading shapes, so it adds none of the blanket season-fallback's
    junk on other feeds."""
    episodes = sort_newest_first(episodes)
    arcs = _cluster_guarded(episodes, guard=True, dedup=True)
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
