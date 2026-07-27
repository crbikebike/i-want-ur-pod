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
from urllib.parse import quote_plus

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


def thumbnail(url: str | None, px: int = 300, updated_at: str | None = None) -> str | None:
    """A small version of a show's cover, with a cachebust when the art has changed.

    Apple serves covers with `cache-control: max-age=16480651` -- 190 days. Once a phone
    has a copy, no amount of re-scanning feeds will dislodge it; only a different URL
    will. So when the comber records that a show's artwork changed, that timestamp rides
    along as ?v= and every cache in the path treats it as a new image.

    No timestamp means no parameter, which is right: we have no evidence the art ever
    changed, and inventing a version would defeat caching for nothing.
    """
    if not url or not url.strip():
        return None
    small = _APPLE_SIZE.sub(lambda m: f"/{px}x{px}bb.{m.group(1)}", url)
    if not updated_at:
        return small
    version = re.sub(r"\D", "", updated_at)[:14]
    joiner = "&" if "?" in small else "?"
    return f"{small}{joiner}v={version}"


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


# Apple categories that are rarely narrative. Not a verdict and not a sort key -- sorting
# by this put 30 for 30, Rough Translation and Bodies in the first ten, all excellent. But
# as a stated fact on a card it is honest: here is why this one is worth a look.
_ODD_CATEGORIES = {
    "Comedy", "Sports", "Self-Improvement", "Relationships", "Health & Fitness",
    "Video Games", "Daily News", "News Commentary", "Entertainment News",
    "Music Commentary", "Education", "Education for Kids", "Christianity", "Islam",
    "Business", "Management", "Technology", "Tech News", "Fashion & Beauty",
}


def _note(conn: sqlite3.Connection, show_id: int) -> dict | None:
    """Why a show was flagged, and -- the part that matters -- what it means for you.

    The first version stated facts and stopped: "7 episodes are also in The Loop". True,
    and useless. It does not say what The Loop is, whether either show is at fault, or
    which button that implies. Chris read it and could not act on it, which is the only
    test a warning has to pass.

    There are three different problems wearing one red badge, and only two of them are
    inclusion questions:

      duplicate-entry   Two catalogue rows point at one feed. One is a season or limited
                        series filed as though it were its own programme. A real
                        keep/cut: keep the parent, cut the child.

      cross-promotion   Different feeds, overlapping episodes. A show ran a sibling
                        series in its main feed to give it an audience -- Ear Hustle
                        carried all seven episodes of The Loop. Both shows are real and
                        both should be kept. Not an inclusion question at all; the
                        double-counted episodes belong to the duplicates queue.

      wrong-feed        The feed serves a different programme than the row claims.
                        Something is broken and it is not a matter of taste.
    """
    row = conn.execute(
        "SELECT title, feed_url, include_verdict FROM shows WHERE id = ?", (show_id,)
    ).fetchone()
    if not row or row[2] != "suspect":
        return None
    title, feed_url, _ = row

    # 1. Same feed as another row.
    peers = [
        r[0] for r in conn.execute(
            "SELECT title FROM shows WHERE feed_url = ? AND id != ? AND deleted_at IS NULL",
            (feed_url, show_id),
        )
    ]
    if peers:
        other = peers[0]
        child = ":" in title or "presents" in title.lower() or title.startswith(other)
        return {
            "kind": "duplicate-entry",
            "tone": "warn",
            "label": "Same feed",
            "detail": [f"{title} and {other} are the same feed."],
            "meaning": (
                "One of them is a duplicate — probably a season filed as its own show. "
                "Keep the parent, cut the other. Nothing is destroyed."
                if child else
                "They may genuinely be two programmes a publisher shipped together. "
                "If so, keep both."
            ),
        }

    # 2. Different feeds, shared episodes.
    overlap = conn.execute(
        """
        SELECT other.title, count(*) n
        FROM episodes mine
        JOIN episodes theirs ON theirs.guid = mine.guid AND theirs.show_id != mine.show_id
        JOIN shows other ON other.id = theirs.show_id AND other.deleted_at IS NULL
        WHERE mine.show_id = ? AND mine.deleted_at IS NULL
        GROUP BY other.id HAVING n > 2 ORDER BY n DESC LIMIT 1
        """,
        (show_id,),
    ).fetchone()
    if overlap:
        other, n = overlap
        return {
            "kind": "cross-promotion",
            "tone": "info",
            # A foregone conclusion, so this never becomes a card. See auto.py.
            "auto": "keep",
            "label": "Shares episodes",
            "detail": [f"{n} episodes appear in both this and {other}, on separate feeds."],
            "meaning": (
                "Normal cross-promotion. Both are real shows — keep both. The doubled "
                "episodes get sorted elsewhere."
            ),
        }

    # 3. Flagged at import for a reason the feed itself gives away.
    from admin.api.suspects import EXPLICIT_SUSPECTS

    reason = EXPLICIT_SUSPECTS.get(title)
    if reason:
        return {
            "kind": "wrong-feed",
            "tone": "warn",
            "label": "Wrong feed",
            "detail": [reason.capitalize() + "."],
            "meaning": "The row and the feed are different shows. Cut it; the feed gets fixed separately.",
        }

    return {
        "kind": "unclear",
        "tone": "info",
        "label": "Flagged at import",
        "detail": ["The importer was unsure but did not say why."],
        "meaning": "Judge it on its merits.",
    }


def inclusion_next(conn: sqlite3.Connection, skipped: list[int] | None = None) -> dict | None:
    """The next show to judge, with everything needed to judge it on one screen."""
    skipped = skipped or []
    # The clause is omitted rather than emptied when nothing is skipped. `id NOT IN (NULL)`
    # evaluates to UNKNOWN for every row, so the obvious placeholder would silently return
    # an empty queue -- which looks exactly like "you're finished".
    skip_clause = f"AND s.id NOT IN ({','.join('?' * len(skipped))})" if skipped else ""

    row = conn.execute(
        f"""
        SELECT s.id, s.slug, s.title, s.home_url, s.artwork_url,
               s.artwork_updated_at, s.apple_category, s.years, s.lang, s.include_verdict,
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

    (show_id, slug, title, home_url, artwork, artwork_updated_at, category,
     years, lang, verdict, network, eps, arcs) = row


    note = _note(conn, show_id)
    if note is None:
        note = {
            "kind": "unreviewed",
            "tone": "info",
            "label": "Never reviewed",
            "detail": ["Imported with the original 315 and never checked against the "
                       "story-driven standard."],
            "meaning": (f"Filed under {category}, which is rarely narrative."
                        if category in _ODD_CATEGORIES else
                        "No specific doubt — confirm it belongs and move on."),
        }

    return {
        "id": show_id,
        "slug": slug,
        "title": title,
        "network": network,
        "years": years,
        "artwork": thumbnail(artwork, updated_at=artwork_updated_at),
        "note": note,
        "links": _links(title, home_url),
    }


_APPLE_ID = re.compile(r"/id(\d+)")


def _links(title: str, home_url: str | None) -> list[dict]:
    """Somewhere to go and actually look.

    The card cannot tell you whether a show is narrated or two people chatting -- only
    listening can. So the card frames the question and hands you the door.

    Where possible that door opens in place rather than in a new tab. Apple's ordinary
    pages refuse to be framed (X-Frame-Options: DENY) but their embed player does not,
    and it carries the description, the episode list and playable previews -- everything
    the question actually turns on. Leaving the queue to answer a question about the
    queue is a good way to not come back.
    """
    out = []
    apple_id = _APPLE_ID.search(home_url or "")
    if home_url and apple_id:
        out.append({
            "label": "Listen and look",
            "href": home_url,
            "embed": f"https://embed.podcasts.apple.com/us/podcast/id{apple_id.group(1)}",
            "primary": True,
        })
    else:
        # 20 shows have no stored link, so there is no id to embed. A search opens in a
        # tab, which is worse than a preview and much better than a dead end.
        out.append({
            "label": "Find in Apple Podcasts",
            "href": f"https://podcasts.apple.com/us/search?term={quote_plus(title)}",
            "embed": None,
            "primary": True,
        })
    return out


# Verdicts a human may record here. 'suspect' is absent on purpose: it is what the
# importer says when it is unsure, not something a person should aim for. A human who
# cannot decide skips, which is not a verdict and writes nothing.
VERDICTS = {"keep", "cut"}
