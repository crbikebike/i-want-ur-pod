"""Point the broken rows back at the podcasts they were always meant to be.

Twenty-seven catalog rows serve a different podcast than they claim, and the damage runs
past the rows themselves: nineteen were *cut* on evidence that described some other show,
and eight were *kept* the same way. The queue emptied while roughly a third of its
decisions were made against something nobody was looking at.

The pass, per show:

  1. Candidates from the Podcast Index dump, then Apple as a fallback. Neither is
     complete -- The Clearing is in Apple with no feed URL and absent from the dump
     entirely -- so a show that neither knows about is a real outcome, not a bug.
  2. Fetch each candidate and read it. **This is the gate.** Scores only decide what
     order to try things in; nothing is repointed because a number cleared a threshold.
     Two earlier attempts to tighten scoring by feel put the original bug straight back,
     and the fix both times was to look at the feed.
  3. On a pass: repoint, hide the wrong show's episodes, ingest the real ones, clear the
     fit assessment (it judged the wrong show), and return the verdict to unreviewed
     where the decision was made against the wrong podcast.

Nothing here decides whether a show belongs in the catalog. That stays Chris's call, and
it can only be made once the row is pointing at the right thing.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

from admin.api import edits, feeds, rematch
from admin.api import podcastindex as pi

# How many candidates to actually fetch per show before giving up. Fetching is the
# expensive step and the correct answer has never been past the third when it exists at
# all; a long tail of tries is a long tail of wrong shows.
MAX_TRIES = 6


@dataclass
class Outcome:
    slug: str
    title: str
    network: str | None
    status: str                      # repointed | unresolved | already-right
    detail: str = ""
    feed_url: str | None = None
    # Resolved when the proposal was made and carried here, so confirming a card does not
    # depend on the 4 GB dump still being present. Without this, a confirm on a machine
    # with no dump clears home_url and the card loses its player -- the exact regression
    # this field was added to stop.
    home_url: str | None = None
    feed_title: str | None = None
    feed_author: str | None = None
    episodes: int = 0
    rejected: list[str] = field(default_factory=list)

    def describe(self) -> str:
        mark = {"repointed": "✓", "already-right": "=", "unresolved": "✗"}[self.status]
        head = f" {mark} {self.title[:30]:<32} {self.detail}"
        if self.status == "repointed":
            head += f"\n      -> {self.feed_title} by {self.feed_author} ({self.episodes} eps)"
            head += f"\n         {self.feed_url}"
        for r in self.rejected[:3]:
            head += f"\n      rejected: {r}"
        return head


def candidates(conn, index: pi.Index | None, title: str, network: str | None) -> list[str]:
    """Feed URLs worth fetching, best first, from both sources with duplicates removed."""
    urls: list[str] = []
    if index is not None:
        for m in index.search({title: network}).get(title, []):
            if pi.acceptable(m):
                urls.append(m.row.url)
    # Apple knows about shows the dump does not, and vice versa. Neither alone was enough
    # for the five resolved by hand.
    results = rematch.search(title)
    if network:
        results += rematch.search(f"{title} {network}")
    for c in rematch.rank(title, network, results):
        if rematch.acceptable(c):
            urls.append(c.feed_url)

    seen, out = set(), []
    for u in urls:
        if u and u not in seen:
            seen.add(u)
            out.append(u)
    return out


def resolve(conn: sqlite3.Connection, show_id: int, index: pi.Index | None,
            *, urls: list[str] | None = None) -> tuple[Outcome, feeds.Feed | None]:
    """Find and confirm the right feed. Reads only -- nothing is written here."""
    slug, title, network, current = conn.execute(
        "SELECT s.slug, s.title, n.name, s.feed_url FROM shows s "
        "LEFT JOIN networks n ON n.id = s.network_id WHERE s.id = ?", (show_id,)).fetchone()

    tries = urls if urls is not None else candidates(conn, index, title, network)
    rejected = []
    for url in tries[:MAX_TRIES]:
        try:
            feed = feeds.read(url)
        except feeds.FeedError as e:
            rejected.append(str(e)[:110])
            continue
        verdict = feeds.verify(feed, network=network, expect_title=title)
        if not verdict.ok:
            rejected.append(f"{url[:48]} — {verdict.reason[:80]}")
            continue
        # Keyword arguments, not positional. Adding `home_url` to Outcome shifted every
        # field after it, so feed.title landed in home_url and the episode count landed in
        # feed_author -- silently, because the dataclass takes anything.
        common = dict(feed_url=url, feed_title=feed.title, feed_author=feed.author,
                      episodes=len(feed.episodes), rejected=rejected)
        if url == current:
            return Outcome(slug, title, network, "already-right",
                           "the feed it is already on checks out", **common), feed
        return Outcome(slug, title, network, "repointed", verdict.reason, **common), feed

    return Outcome(slug, title, network, "unresolved",
                   f"no candidate feed confirmed out of {len(tries)}",
                   rejected=rejected), None


def apply(conn: sqlite3.Connection, show_id: int, outcome: Outcome, feed: feeds.Feed,
          *, decisions_path: Path | None = None) -> list[str]:
    """Write a confirmed repair. One show, one feed, one set of episodes."""
    done = []
    verdict = conn.execute("SELECT include_verdict FROM shows WHERE id = ?",
                           (show_id,)).fetchone()[0]

    if outcome.status == "repointed":
        note = (f"confirmed against the feed: {outcome.feed_title!r} "
                f"by {outcome.feed_author!r}")
        # home_url and artwork_url described the *wrong* show as surely as feed_url did --
        # Homecoming's Apple link led to "The Homecoming Podcast with Dr. Thema" -- so
        # they are replaced, not kept. The feed carries its own cover. The Apple page is
        # looked up by feed URL in the dump, which is exact rather than another name
        # match.
        #
        # A first version simply cleared home_url, and that quietly cost the card its
        # slide-up player: with no Apple id there is nothing to embed, so "Listen and
        # look" degraded to a bare search link opening in a new tab. Leaving the queue to
        # answer a question about the queue is a good way not to come back.
        home = outcome.home_url or pi.itunes_home(outcome.feed_url)
        for field_name, value in (("feed_url", outcome.feed_url),
                                  ("home_url", home),
                                  ("artwork_url", feed.image or None)):
            try:
                edits.apply(conn, entity_type="show", entity_id=show_id, field=field_name,
                            after=value, actor="agent:repair", note=note,
                            decisions_path=decisions_path)
            except edits.EditError as e:
                if "already" not in str(e):
                    raise
        done.append(f"feed -> {outcome.feed_title}")

        # Hide what this row is still carrying from the wrong podcast, but never anything
        # the correct feed also claims -- those GUIDs are about to be ingested, and hiding
        # then un-hiding the same row would churn the log for no change.
        keep = [e.guid for e in feed.episodes]
        if keep:
            scope = ("show_id = ? AND deleted_at IS NULL AND guid NOT IN (%s)"
                     % ",".join("?" * len(keep)))
            args = (show_id, *keep)
        else:
            scope, args = "show_id = ? AND deleted_at IS NULL", (show_id,)
        n = edits.apply_to_many(
            conn, entity_type="episode", scope_sql=scope, scope_args=args,
            field="deleted_at", after=feeds.now(), actor="agent:repair",
            note="belonged to the podcast this row was wrongly pointed at",
            entity_key=f"{outcome.slug}/*", decisions_path=decisions_path)
        if n:
            done.append(f"{n} wrong episodes hidden")

    got = edits.ingest_episodes(conn, show_id=show_id, episodes=feed.episodes,
                                actor="agent:repair",
                                note=f"read from {outcome.feed_url}",
                                decisions_path=decisions_path)
    if got["added"] or got["existing"]:
        done.append(f"{got['added']} episodes added, {got['existing']} already there")

    if outcome.status == "repointed":
        for f in ("fit_verdict", "fit_confidence", "fit_reason", "fit_checked_at"):
            try:
                edits.apply(conn, entity_type="show", entity_id=show_id, field=f, after=None,
                            actor="agent:repair", note="the assessment judged the wrong show",
                            decisions_path=decisions_path)
            except edits.EditError:
                pass
        done.append("assessment cleared")

        # A keep or a cut made against a different podcast is not a decision about this
        # show. It goes back in the queue rather than standing on evidence that was never
        # about it.
        if verdict in ("keep", "cut"):
            try:
                edits.apply(conn, entity_type="show", entity_id=show_id,
                            field="include_verdict", after="unreviewed", actor="agent:repair",
                            note=f"the {verdict} judged a different podcast",
                            decisions_path=decisions_path)
                done.append(f"{verdict} -> unreviewed")
            except edits.EditError as e:
                if "already" not in str(e):
                    raise
    return done
