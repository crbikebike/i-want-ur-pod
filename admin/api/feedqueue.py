"""The feed queue: rows pointing at the wrong podcast, and the best guess at the right one.

The inclusion queue asks "does this show belong?". This one asks a question that has to be
settled first: **is this row even about the show it claims to be?** Twenty-seven were not,
and nineteen keeps and eight cuts were recorded against podcasts nobody was looking at.

Why it is a queue rather than a script. Finding candidates is automatable and finding them
well is not. The three available signals are a title -- which is the thing that collided --
a publisher the curator wrote as prose ("Independent / originally Radiotopia"), and a
network that may have changed since (This Land moved from Crooked to Pushkin, so its
correct feed *disagrees* with the catalog). Tightening the scoring traded a false positive
for a false negative three times running: killing a match to a Japanese TBS Radio show
also killed Benjamen Walker's Theory of Everything.

What settles it is reading the episodes. "7 Hebrew Words for Praise" against "a true-crime
docuseries about April Balascio" is not a close call once both are on one screen. So the
card puts them there, and the evidence is stored with the proposal rather than re-fetched,
because a queue that pulls five feeds per card is a queue nobody opens twice.
"""

from __future__ import annotations

import json
import sqlite3

from admin.api.queues import thumbnail


def counts(conn: sqlite3.Connection) -> dict:
    row = conn.execute(
        """
        SELECT
          (SELECT count(DISTINCT show_id) FROM feed_proposals WHERE resolved_at IS NULL),
          (SELECT count(*) FROM feed_proposals WHERE resolved_as = 'confirmed'),
          (SELECT count(*) FROM feed_proposals WHERE resolved_as = 'rejected')
        """
    ).fetchone()
    waiting, confirmed, rejected = (r or 0 for r in row)
    return {
        "waiting": waiting,
        "confirmed": confirmed,
        "rejected": rejected,
        "decided": confirmed + rejected,
        "total": waiting + confirmed + rejected,
    }


def next_card(conn: sqlite3.Connection, skipped: list[int] | None = None) -> dict | None:
    """One show, what the catalog claims, and the candidate that fits it best.

    Ordered by how much of the show a candidate carries. A 393-episode feed is easier to
    recognise than a 3-episode one, and clearing the recognisable ones first is what makes
    a queue feel finishable.
    """
    skipped = skipped or []
    # Omitted rather than emptied: `id NOT IN (NULL)` is UNKNOWN for every row, which
    # looks exactly like "you're finished".
    skip = f"AND p.id NOT IN ({','.join('?' * len(skipped))})" if skipped else ""

    row = conn.execute(
        f"""
        SELECT p.id, p.show_id, p.feed_url, p.feed_title, p.feed_author, p.episode_count,
               p.image_url, p.sample, p.source, p.title_score, p.publisher_score,
               s.slug, s.title, s.description, s.why, s.feed_url, s.artwork_url,
               s.artwork_updated_at, s.include_verdict, s.years, n.name
        FROM feed_proposals p
        JOIN shows s ON s.id = p.show_id AND s.deleted_at IS NULL
        LEFT JOIN networks n ON n.id = s.network_id
        WHERE p.resolved_at IS NULL {skip}
        ORDER BY p.episode_count DESC, p.id
        LIMIT 1
        """,
        skipped,
    ).fetchone()
    if not row:
        return None

    (pid, show_id, feed_url, feed_title, feed_author, eps, image, sample, source,
     ts, ps, slug, title, description, why, current_feed, artwork, artwork_at,
     verdict, years, network) = row

    others = conn.execute(
        "SELECT count(*) FROM feed_proposals WHERE show_id = ? AND resolved_at IS NULL "
        "AND id != ?", (show_id, pid)).fetchone()[0]

    return {
        "id": pid,
        "showId": show_id,
        "slug": slug,
        "title": title,
        "network": network,
        "years": years,
        "verdict": verdict,
        # What the catalog believes this show is. Half the evidence.
        "claims": {
            "description": description,
            "why": why,
            "feed": current_feed,
            "artwork": thumbnail(artwork, updated_at=artwork_at),
        },
        # What the candidate feed actually contains. The other half.
        "candidate": {
            "feed": feed_url,
            "title": feed_title,
            "author": feed_author,
            "episodeCount": eps,
            "artwork": thumbnail(image),
            "sample": json.loads(sample) if sample else [],
            "source": source,
            "titleScore": ts,
            "publisherScore": ps,
        },
        # Said plainly, because "p=0.62" is not a reason to press a button.
        "alsoWaiting": others,
        "meaning": _meaning(network, feed_author, others),
    }


def _meaning(network: str | None, author: str | None, others: int) -> str:
    tail = (f" {others} other candidate{'s' if others != 1 else ''} for this show "
            f"follow{'' if others != 1 else 's'} if you reject it." if others else
            " This is the only candidate found, so rejecting it leaves the row broken "
            "until someone finds the feed by hand.")
    return (f"The catalog says {network or 'no publisher'}; this feed says "
            f"{author or 'nobody'}. Read the episode titles — they settle it faster than "
            f"the names do.") + tail


def record(conn: sqlite3.Connection, proposal_id: int, decision: str) -> None:
    """Mark a proposal decided. Workbench bookkeeping, not a catalog change.

    Confirming does not itself repoint the show -- that goes through edits.apply() in
    repair.apply(), so it lands in `edits` and decisions.jsonl like every other change and
    can be undone the same way. This row only records that the question was answered, so
    the same rejected candidate is not offered again next pass.
    """
    if decision not in ("confirmed", "rejected"):
        raise ValueError(f"{decision!r} is not a decision")
    conn.execute(
        "UPDATE feed_proposals SET resolved_at = datetime('now'), resolved_as = ? "
        "WHERE id = ? AND resolved_at IS NULL", (decision, proposal_id))
    if decision == "confirmed":
        # One feed per show. The alternatives are moot the moment one is right, and
        # leaving them waiting would ask the same question again with a worse answer.
        conn.execute(
            "UPDATE feed_proposals SET resolved_at = datetime('now'), resolved_as = "
            "'rejected' WHERE resolved_at IS NULL AND id != ? AND show_id = "
            "(SELECT show_id FROM feed_proposals WHERE id = ?)", (proposal_id, proposal_id))
    conn.commit()


def add(conn: sqlite3.Connection, *, show_id: int, feed_url: str, feed_title: str | None,
        feed_author: str | None, episode_count: int, image_url: str | None,
        sample: list[str], source: str, title_score: float = 0.0,
        publisher_score: float = 0.0) -> int | None:
    """Offer a candidate. Returns None if this show/feed pair was already decided."""
    seen = conn.execute(
        "SELECT id, resolved_at FROM feed_proposals WHERE show_id = ? AND feed_url = ?",
        (show_id, feed_url)).fetchone()
    if seen:
        return None
    cur = conn.execute(
        "INSERT INTO feed_proposals (show_id, feed_url, feed_title, feed_author, "
        "episode_count, image_url, sample, source, title_score, publisher_score) "
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        (show_id, feed_url, feed_title, feed_author, episode_count, image_url,
         json.dumps(sample, ensure_ascii=False), source, title_score, publisher_score))
    conn.commit()
    return cur.lastrowid
