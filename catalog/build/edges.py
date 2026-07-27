"""Derive the traversal layer.

Everything here is computed from the typed tables, so the edges table is always safe to
delete and rebuild. Nothing else in the catalog reads it.

Every edge carries a `why` -- the sentence the app shows when it explains a connection.
That is the whole reason this is a graph rather than a pile of similarity scores: a
recommendation the user can't interrogate is indistinguishable from a guess.

Pruning is not optional. shares_* edges are O(shows^2); at 315 shows that is 99,225
candidate pairs, and traversal through an unpruned table returns noise ranked by
rounding error. Keep the top 20 per show and drop anything below 0.15.

What does NOT belong here
-------------------------
Episode-to-subject. There are 43,818 of those, they would be 76% of the graph and about
8 MB of the shipped file, and nothing traverses them: they are always read through
`episode_subjects`, which is already indexed for exactly that. The edges table earns its
generality on show, arc, theme and subject relationships, where a path can run through
node types a hand-written join would have to anticipate.
"""

from __future__ import annotations

import sqlite3
from collections import defaultdict
from dataclasses import dataclass, field

from catalog.build.normalize import cosine, jaccard

TOP_N_PER_SHOW = 20
MIN_SIMILARITY = 0.15

# A show's own publisher is the least interesting recommendation there is -- it is what
# every other podcast app already does. Same-network edges exist so `explain` can name
# the relationship, but next-thing multiplies their weight down rather than up.
SAME_NETWORK_WEIGHT = 0.3

# A trailer is a 60-second advert for the show. Telling someone to *start* with one is the
# opposite of getting them to something good in three minutes, so entry points skip them.
# Titles are checked as well as episode_type, because plenty of publishers ship a trailer
# tagged 'full' and only the title gives it away.
_NOT_LISTENABLE = (
    "(coalesce(episode_type, '') IN ('trailer', 'invalid')"
    " OR lower(title) LIKE 'trailer%'"
    " OR lower(title) LIKE '%(trailer)%'"
    " OR lower(title) LIKE 'introducing:%'"
    " OR lower(title) LIKE '%show trailer%'"
    " OR lower(title) LIKE 'teaser%'"
    " OR lower(title) LIKE '%preview of %')"
)


@dataclass
class EdgeReport:
    counts: dict[str, int] = field(default_factory=dict)
    pruned: int = 0
    entry_points: int = 0

    def lines(self) -> list[str]:
        total = sum(self.counts.values())
        out = [f"edges: {total} across {len(self.counts)} kinds"]
        for kind, n in sorted(self.counts.items(), key=lambda kv: -kv[1]):
            out.append(f"  {kind:<20} {n}")
        out.append(f"  similarity edges pruned away: {self.pruned}")
        out.append(f"  entry points computed       : {self.entry_points}")
        return out


def build(conn: sqlite3.Connection) -> EdgeReport:
    report = EdgeReport()
    conn.execute("DELETE FROM edges")

    _vocabulary_structure(conn, report)
    _show_themes(conn, report)
    _arcs(conn, report)
    _same_network(conn, report)
    _shares_theme(conn, report)
    _shares_subject(conn, report)
    _entry_points(conn, report)

    conn.commit()
    return report


def _add(conn, report: EdgeReport, rows: list[tuple], kind: str) -> None:
    if not rows:
        return
    conn.executemany(
        "INSERT OR REPLACE INTO edges (src_type, src_id, dst_type, dst_id, kind, weight, why) "
        "VALUES (?,?,?,?,?,?,?)",
        rows,
    )
    report.counts[kind] = report.counts.get(kind, 0) + len(rows)


def _vocabulary_structure(conn, report) -> None:
    """subject -> its theme. The hop that lets `explain` climb from a specific episode
    subject up to the broad category two shows actually share."""
    rows = [
        ("subject", sid, "theme", tid, "subject_theme", 1.0, f"a kind of {tname}")
        for sid, tid, tname in conn.execute(
            "SELECT s.id, t.id, t.name FROM subjects s JOIN themes t ON t.id = s.theme_id"
        )
    ]
    _add(conn, report, rows, "subject_theme")


def _show_themes(conn, report) -> None:
    rows = [
        ("show", sid, "theme", tid, "show_theme", 1.0, f"tagged {tname}")
        for sid, tid, tname in conn.execute(
            "SELECT st.show_id, t.id, t.name FROM show_themes st JOIN themes t ON t.id = st.theme_id"
        )
    ]
    _add(conn, report, rows, "show_theme")


def _arcs(conn, report) -> None:
    rows = [
        ("arc", aid, "show", sid, "arc_of", 1.0, f"a story arc in {stitle}")
        for aid, sid, stitle in conn.execute(
            "SELECT a.id, s.id, s.title FROM arcs a JOIN shows s ON s.id = a.show_id"
        )
    ]
    _add(conn, report, rows, "arc_of")


def _same_network(conn, report) -> None:
    by_network = defaultdict(list)
    for sid, nid, nname in conn.execute(
        "SELECT s.id, n.id, n.name FROM shows s JOIN networks n ON n.id = s.network_id"
    ):
        by_network[(nid, nname)].append(sid)

    rows = []
    for (_nid, nname), shows in by_network.items():
        # A "network" of one is not a connection, and a handful of rows are really a
        # solo producer's name, which would otherwise link a show to itself.
        if len(shows) < 2:
            continue
        for a in shows:
            for b in shows:
                if a != b:
                    rows.append(
                        ("show", a, "show", b, "same_network", SAME_NETWORK_WEIGHT,
                         f"both from {nname}")
                    )
    _add(conn, report, rows, "same_network")


def _prune(pairs: dict[int, list[tuple[int, float, str]]], report: EdgeReport) -> list[tuple]:
    """Keep the strongest TOP_N_PER_SHOW per source, above MIN_SIMILARITY."""
    kept = []
    for src, candidates in pairs.items():
        above = [c for c in candidates if c[1] >= MIN_SIMILARITY]
        report.pruned += len(candidates) - len(above)
        above.sort(key=lambda c: -c[1])
        kept.extend((src, dst, w, why) for dst, w, why in above[:TOP_N_PER_SHOW])
        report.pruned += max(0, len(above) - TOP_N_PER_SHOW)
    return kept


def _shares_theme(conn, report) -> None:
    """Overlap of the browsable themes. Coarse, but it is what the swipe deck is built on."""
    themes_by_show = defaultdict(set)
    names = {}
    for sid, tid, tname in conn.execute(
        "SELECT st.show_id, t.id, t.name FROM show_themes st JOIN themes t ON t.id = st.theme_id"
    ):
        themes_by_show[sid].add(tid)
        names[tid] = tname

    candidates = defaultdict(list)
    shows = sorted(themes_by_show)
    for i, a in enumerate(shows):
        for b in shows[i + 1 :]:
            shared = themes_by_show[a] & themes_by_show[b]
            if not shared:
                continue
            weight = jaccard(themes_by_show[a], themes_by_show[b])
            if weight < MIN_SIMILARITY:
                report.pruned += 2
                continue
            why = "both cover " + names[sorted(shared, key=lambda t: names[t])[0]]
            candidates[a].append((b, weight, why))
            candidates[b].append((a, weight, why))

    rows = [
        ("show", src, "show", dst, "shares_theme", w, why)
        for src, dst, w, why in _prune(candidates, report)
    ]
    _add(conn, report, rows, "shares_theme")


def _shares_subject(conn, report) -> None:
    """Overlap of the 148 episode subjects, weighted by how much of a show each accounts
    for. This is the edge that actually finds a good recommendation: two shows can share a
    browse theme and have nothing in common, but sharing a subject profile means they
    genuinely dig at the same thing.
    """
    vectors = defaultdict(dict)
    names = {}
    for sid, tid, tname, n in conn.execute(
        "SELECT e.show_id, s.id, s.name, count(*) FROM episode_subjects es "
        "JOIN episodes e ON e.id = es.episode_id "
        "JOIN subjects s ON s.id = es.subject_id "
        "WHERE es.role = 'primary' GROUP BY e.show_id, s.id"
    ):
        vectors[sid][tid] = n
        names[tid] = tname

    candidates = defaultdict(list)
    shows = sorted(vectors)
    for i, a in enumerate(shows):
        va = vectors[a]
        for b in shows[i + 1 :]:
            vb = vectors[b]
            shared = va.keys() & vb.keys()
            if not shared:
                continue
            weight = cosine(va, vb)
            if weight < MIN_SIMILARITY:
                report.pruned += 2
                continue
            # Name the theme that contributes most to the similarity, not merely a
            # shared one -- that is the reason a person would accept.
            top = max(shared, key=lambda t: min(va[t], vb[t]))
            why = f"both dig into {names[top]}"
            candidates[a].append((b, weight, why))
            candidates[b].append((a, weight, why))

    rows = [
        ("show", src, "show", dst, "shares_subject", w, why)
        for src, dst, w, why in _prune(candidates, report)
    ]
    _add(conn, report, rows, "shares_subject")


def _entry_points(conn, report) -> None:
    """Where to start on a show.

    Preference order, and the reason for it: a verified arc is a story someone confirmed
    hangs together, so it beats any single episode. Failing that, the earliest episode
    carrying a high-confidence primary theme is at least about something. Failing that,
    the earliest episode at all.

    Computed here so the query is fast; Phase 2 lets a human override it, which is the
    real answer.
    """
    rows = []
    for show_id, title in conn.execute("SELECT id, title FROM shows"):
        arc = conn.execute(
            "SELECT a.id, a.name, count(e.id) n FROM arcs a "
            "JOIN episodes e ON e.arc_id = a.id "
            "WHERE a.show_id = ? "
            "GROUP BY a.id "
            "HAVING n >= 2 "
            "ORDER BY CASE a.confidence WHEN 'verified' THEN 0 WHEN 'high' THEN 1 "
            "         WHEN 'medium' THEN 2 ELSE 3 END, n DESC",
            (show_id,),
        ).fetchone()
        if arc:
            rows.append(
                ("show", show_id, "arc", arc[0], "entry_point", 1.0,
                 f"start with the {arc[2]}-part arc “{arc[1]}”")
            )
            continue

        episode = conn.execute(
            "SELECT e.id, e.title FROM episodes e "
            "JOIN episode_subjects es ON es.episode_id = e.id "
            "WHERE e.show_id = ? AND es.role = 'primary' AND es.confidence = 'high' "
            "  AND e.available = 1 AND NOT " + _NOT_LISTENABLE +
            " ORDER BY e.published_at ASC LIMIT 1",
            (show_id,),
        ).fetchone()
        if not episode:
            episode = conn.execute(
                "SELECT id, title FROM episodes WHERE show_id = ? AND available = 1 "
                "  AND NOT " + _NOT_LISTENABLE +
                " ORDER BY published_at ASC LIMIT 1",
                (show_id,),
            ).fetchone()
        if not episode:
            # A feed of nothing but trailers. Better to offer the trailer than nothing.
            episode = conn.execute(
                "SELECT id, title FROM episodes WHERE show_id = ? AND available = 1 "
                "ORDER BY published_at ASC LIMIT 1",
                (show_id,),
            ).fetchone()
        if episode:
            rows.append(
                ("show", show_id, "episode", episode[0], "entry_point", 0.5,
                 f"start at the beginning: “{episode[1]}”")
            )

    _add(conn, report, rows, "entry_point")
    report.entry_points = len(rows)
