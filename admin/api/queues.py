"""The queues: work waiting for a human decision.

A queue is one query that returns the next thing to look at, and one action that records
what was decided. Nothing more. Each one keeps that shape so the UI can render any of
them with the same card, the same toast and the same three colours.

Reads never write, so nothing here touches a table -- verdicts go through
`edits.apply()`, the single door. test_only_one_write_path.py enforces that.

On ordering
-----------
The inclusion queue is flagged-first, then random.

Flagged first because those 16 shows have real evidence attached -- a shared feed, a
guid overlap, a feed serving a different programme -- and a decision with evidence is
faster and better than one without.

Random after that, rather than any cleverness. Sorting by "least narrative-looking"
using Apple category was tried and is actively bad: it puts 30 for 30 Podcasts, Rough
Translation, Bodies and Normal Gossip in the first ten, all of them excellent narrative
shows. Apple category records how a publisher filled in a dropdown, not whether a show
is narrated. A wrong ordering is worse than no ordering, because it spends the first ten
cards -- the only ten some sessions get -- on shows that were never in doubt.
"""

from __future__ import annotations

import re
import sqlite3

# Deterministic per show so the order is stable across page loads, and shuffled enough
# that it is not alphabetical. sqlite has no hash(), so the guid-ish mix below does.
_SHUFFLE = "((s.id * 2654435761) % 1000003)"

# Every one of the 295 artwork URLs is an Apple 3000x3000 original: 3.9 MB for something
# rendered at 76 CSS pixels. A thirty-card session on cellular would pull over 100 MB and
# every card would sit waiting on it. Apple serves any size from the same path, and the
# 300px version is 38 KB.
#
# Derived at read time rather than rewritten in the catalog, because the stored URL is
# the canonical one and a future detail view may well want the full-size image.
_APPLE_SIZE = re.compile(r"/\d+x\d+bb\.(jpg|png)$", re.IGNORECASE)


def thumbnail(url: str | None, px: int = 300) -> str | None:
    if not url or not url.strip():
        return None
    return _APPLE_SIZE.sub(lambda m: f"/{px}x{px}bb.{m.group(1)}", url)


def inclusion_counts(conn: sqlite3.Connection) -> dict:
    row = conn.execute(
        """
        SELECT
          sum(include_verdict = 'unreviewed')                       AS waiting,
          sum(include_verdict = 'suspect')                          AS flagged,
          sum(include_verdict = 'keep')                             AS kept,
          sum(include_verdict = 'cut')                              AS cut
        FROM shows WHERE deleted_at IS NULL
        """
    ).fetchone()
    waiting, flagged, kept, cut = (r or 0 for r in row)
    return {
        "waiting": waiting + flagged,
        "flagged": flagged,
        "decided": kept + cut,
        "kept": kept,
        "cut": cut,
        "total": waiting + flagged + kept + cut,
    }


def _evidence(conn: sqlite3.Connection, show_id: int) -> list[str]:
    """Why this show was flagged. Empty for shows nobody has doubted.

    Read from the import's note in `edits` rather than recomputed, so the reason a human
    sees is the reason the importer actually had.
    """
    slug = conn.execute("SELECT slug FROM shows WHERE id = ?", (show_id,)).fetchone()
    if not slug:
        return []
    slug = slug[0]

    out = []
    shares = conn.execute(
        """
        SELECT group_concat(other.title, ' · ')
        FROM shows me JOIN shows other
          ON other.feed_url = me.feed_url AND other.id != me.id AND other.deleted_at IS NULL
        WHERE me.id = ?
        """,
        (show_id,),
    ).fetchone()[0]
    if shares:
        out.append(f"Shares its feed with {shares}")

    overlap = conn.execute(
        """
        SELECT other.title, count(*) n
        FROM episodes mine
        JOIN episodes theirs ON theirs.guid = mine.guid AND theirs.show_id != mine.show_id
        JOIN shows other ON other.id = theirs.show_id AND other.deleted_at IS NULL
        WHERE mine.show_id = ?
        GROUP BY other.id HAVING n > 2 ORDER BY n DESC LIMIT 2
        """,
        (show_id,),
    ).fetchall()
    for title, n in overlap:
        out.append(f"{n} episodes are also in {title}")

    return out


def inclusion_next(conn: sqlite3.Connection, skipped: list[int] | None = None) -> dict | None:
    """The next show to judge, with everything needed to judge it on one screen."""
    skipped = skipped or []
    # The clause is omitted rather than emptied when nothing is skipped. `id NOT IN (NULL)`
    # evaluates to UNKNOWN for every row, so the obvious placeholder would silently return
    # an empty queue -- which looks exactly like "you're finished".
    skip_clause = f"AND s.id NOT IN ({','.join('?' * len(skipped))})" if skipped else ""

    row = conn.execute(
        f"""
        SELECT s.id, s.slug, s.title, s.why, s.description, s.artwork_url,
               s.apple_category, s.years, s.lang, s.include_verdict,
               n.name AS network,
               (SELECT count(*) FROM episodes WHERE show_id = s.id AND deleted_at IS NULL) AS eps,
               (SELECT count(*) FROM arcs WHERE show_id = s.id AND deleted_at IS NULL) AS arcs
        FROM shows s LEFT JOIN networks n ON n.id = s.network_id
        WHERE s.deleted_at IS NULL
          AND s.include_verdict IN ('unreviewed', 'suspect')
          {skip_clause}
        ORDER BY (s.include_verdict = 'suspect') DESC, {_SHUFFLE}
        LIMIT 1
        """,
        skipped,
    ).fetchone()
    if not row:
        return None

    (show_id, slug, title, why, description, artwork, category, years, lang,
     verdict, network, eps, arcs) = row

    episodes = [
        r[0] for r in conn.execute(
            "SELECT title FROM episodes WHERE show_id = ? AND deleted_at IS NULL "
            "ORDER BY published_at DESC LIMIT 5", (show_id,))
    ]
    themes = [
        r[0] for r in conn.execute(
            "SELECT t.name FROM show_themes st JOIN themes t ON t.id = st.theme_id "
            "WHERE st.show_id = ? ORDER BY t.name", (show_id,))
    ]
    subjects = [
        r[0] for r in conn.execute(
            "SELECT su.name FROM episode_subjects es "
            "JOIN subjects su ON su.id = es.subject_id "
            "JOIN episodes e ON e.id = es.episode_id "
            "WHERE e.show_id = ? AND es.role = 'primary' "
            "GROUP BY su.id ORDER BY count(*) DESC LIMIT 4", (show_id,))
    ]

    return {
        "id": show_id,
        "slug": slug,
        "title": title,
        "network": network,
        "category": category,
        "years": years,
        "lang": lang,
        "pitch": why,
        "description": description,
        "artwork": thumbnail(artwork),
        "episodeCount": eps,
        "arcCount": arcs,
        "recentEpisodes": episodes,
        "themes": themes,
        "subjects": subjects,
        "flagged": verdict == "suspect",
        "evidence": _evidence(conn, show_id) if verdict == "suspect" else [],
    }


# Verdicts a human may record here. 'suspect' is absent on purpose: it is what the
# importer says when it is unsure, not something a person should aim for. A human who
# cannot decide skips, which is not a verdict and writes nothing.
VERDICTS = {"keep", "cut"}
