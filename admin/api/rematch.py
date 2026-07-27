"""Find the right feed for a show we matched to the wrong one.

Twenty shows -- 7% of the catalog -- point at a different podcast that happens to share a
name. Homecoming is the Oscar Isaac drama in the catalogue and "The Homecoming Podcast
with Dr. Thema" in the feed. Fallout is an Essendon doping documentary here and a video
game lorecast there. Earshot matched Ear Shot.

The original import matched on title alone, and its own confidence score cannot see the
problem: the median matchScore for the twenty wrong ones is 1.00, the same as for
everything else, because "Uncover" and "unCoVer" are an identical string once normalised.
Two genuinely different podcasts called "The Message" both score perfectly, forever.

**Publisher is the missing discriminator, and only one of our two publisher fields can be
trusted.** Empire shows why: the row carries `network = Goalhanger`, which is the
curator's own note about the show they meant, and `author = Blockworks`, which the import
copied from the wrong podcast it found. Searching iTunes for "Empire" returns both --
"Empire: World History" by Goalhanger and "Empire" by Blockworks -- and the network field
picks the right one instantly.

So: score a candidate on title similarity AND on how well its artist matches the
*network*. A candidate that matches the title perfectly but comes from the wrong publisher
loses to one that matches both.
"""

from __future__ import annotations

import difflib
import json
import re
import sqlite3
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

SEARCH = "https://itunes.apple.com/search"

# Words that say nothing about which podcast this is.
_NOISE = re.compile(
    r"\b(the|a|an|podcast|show|series|with|from|official|presents)\b", re.IGNORECASE)


def _norm(s: str | None) -> str:
    if not s:
        return ""
    s = _NOISE.sub(" ", s.lower())
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


def similarity(a: str | None, b: str | None) -> float:
    a, b = _norm(a), _norm(b)
    if not a or not b:
        return 0.0
    if a == b:
        return 1.0
    if a in b or b in a:
        return 0.9
    return difflib.SequenceMatcher(None, a, b).ratio()


@dataclass
class Candidate:
    name: str
    artist: str
    feed_url: str
    home_url: str
    artwork: str
    title_score: float = 0.0
    publisher_score: float = 0.0
    total: float = 0.0


@dataclass
class Proposal:
    show_id: int
    slug: str
    title: str
    network: str | None
    old_feed: str
    best: Candidate | None = None
    runners: list[Candidate] = field(default_factory=list)

    @property
    def changed(self) -> bool:
        return bool(self.best and self.best.feed_url and self.best.feed_url != self.old_feed)

    def describe(self) -> str:
        if not self.best:
            return f"  {self.title[:34]:<36} no candidate found"
        b = self.best
        arrow = "->" if self.changed else "== (unchanged)"
        return (f"  {self.title[:30]:<32} {arrow} {b.name[:34]:<36} "
                f"by {b.artist[:20]:<22} t={b.title_score:.2f} p={b.publisher_score:.2f}")


def search(term: str, limit: int = 15) -> list[dict]:
    url = f"{SEARCH}?" + urllib.parse.urlencode(
        {"term": term, "entity": "podcast", "limit": limit})
    try:
        with urllib.request.urlopen(url, timeout=25) as r:
            return json.load(r).get("results", [])
    except Exception:
        return []


def rank(title: str, network: str | None, results: list[dict]) -> list[Candidate]:
    out = []
    for r in results:
        if not r.get("feedUrl"):
            continue
        c = Candidate(
            name=r.get("collectionName", ""),
            artist=r.get("artistName", ""),
            feed_url=r["feedUrl"],
            home_url=r.get("collectionViewUrl", ""),
            artwork=r.get("artworkUrl600") or r.get("artworkUrl100", ""),
        )
        c.title_score = similarity(title, c.name)
        c.publisher_score = similarity(network, c.artist) if network else 0.0
        c.total = c.title_score + 1.5 * c.publisher_score
        out.append(c)
    out.sort(key=lambda c: -c.total)
    return out


# Title is a gate, not a score. Weighting publisher heavily and letting it outvote the
# title produced exactly the failure it was meant to fix: Earshot matched "RN Drive" at a
# title similarity of 0.14 purely because both are ABC, and Homecoming matched
# "Surprisingly Awesome" because both are Gimlet. Publisher breaks ties between plausible
# titles; it cannot rescue an implausible one.
MIN_TITLE = 0.55
MIN_PUBLISHER = 0.60


def acceptable(c: Candidate) -> bool:
    """Both must agree, and the evidence is unusually clean about where the line is.

    Across the twenty broken shows, every correct match scored the publisher at 0.85 or
    better and every wrong one at under 0.5. There is no middle.

    An earlier version let a near-exact title stand alone, on the theory that a loosely
    recorded publisher should not block an obvious match. That put the original bug
    straight back: "Homecoming" scores 1.00 against "Homecoming" by The Homecoming
    Podcast, and "The Clearing" scores 1.00 against a church's sermon feed. A perfect
    title is exactly what a same-name collision looks like.

    So no proposal unless the publisher agrees too. For the shows where it does not, we
    genuinely do not know which podcast was meant -- several have been delisted -- and
    saying so is the right answer. Guessing the nearest thing on the shelf is how the
    catalogue got into this state.
    """
    return c.title_score >= MIN_TITLE and c.publisher_score >= MIN_PUBLISHER


def propose(conn: sqlite3.Connection, show_id: int) -> Proposal:
    slug, title, network, feed = conn.execute(
        "SELECT s.slug, s.title, n.name, s.feed_url FROM shows s "
        "LEFT JOIN networks n ON n.id = s.network_id WHERE s.id = ?", (show_id,)
    ).fetchone()

    results = search(title)
    if network:
        # A second pass with the publisher in the query surfaces shows the bare title
        # never reaches -- "Empire: World History" does not come back for "Empire".
        seen = {r.get("feedUrl") for r in results}
        results += [r for r in search(f"{title} {network}") if r.get("feedUrl") not in seen]

    ranked = [c for c in rank(title, network, results) if acceptable(c)]
    # No acceptable candidate is a real answer, not a failure. Several of these shows have
    # been delisted, and proposing the nearest thing on the shelf is how we got here.
    return Proposal(show_id, slug, title, network, feed,
                    best=ranked[0] if ranked else None, runners=ranked[1:4])


def apply_proposal(conn: sqlite3.Connection, p: Proposal, *, decisions_path=None) -> list[str]:
    """Point a show at the right feed.

    The episodes it currently holds belong to a different podcast, so they are hidden --
    keeping them would leave a show described as one thing and populated by another. The
    fit assessment is cleared for the same reason: it judged the wrong show.
    """
    from datetime import datetime, timezone
    from admin.api import edits

    if not p.changed:
        return []
    done, now = [], datetime.now(timezone.utc).isoformat(timespec="seconds")
    b = p.best

    for field, value in (("feed_url", b.feed_url), ("home_url", b.home_url),
                         ("artwork_url", b.artwork)):
        if not value:
            continue
        try:
            edits.apply(conn, entity_type="show", entity_id=p.show_id, field=field,
                        after=value, actor="agent:rematch",
                        note=f"matched to {b.name!r} by {b.artist!r} "
                             f"(title {b.title_score:.2f}, publisher {b.publisher_score:.2f})",
                        decisions_path=decisions_path)
        except edits.EditError as e:
            if "already" not in str(e):
                raise
    done.append(f"feed -> {b.name}")

    n = edits.apply_to_many(
        conn, entity_type="episode",
        scope_sql="show_id = ? AND deleted_at IS NULL", scope_args=(p.show_id,),
        field="deleted_at", after=now, actor="agent:rematch",
        note="belonged to the podcast this show was wrongly matched to",
        entity_key=f"{p.slug}/*", decisions_path=decisions_path)
    if n:
        done.append(f"{n} episodes of the wrong show hidden")

    for field in ("fit_verdict", "fit_confidence", "fit_reason", "fit_checked_at"):
        try:
            edits.apply(conn, entity_type="show", entity_id=p.show_id, field=field,
                        after=None, actor="agent:rematch",
                        note="assessment was of the wrong show", decisions_path=decisions_path)
        except edits.EditError:
            pass
    done.append("assessment cleared")
    return done
