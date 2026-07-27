"""Finding the right feed in Podcast Index's public dump, instead of asking Apple.

Apple's search was the wrong tool for this in three ways, and every one of them cost us a
show. It only indexes what is currently listed, so The Clearing came back with
`feedUrl: null` and had to be found by guessing at a hostname. It weights the title, which
is useless when the title is the thing that collided. And it rate-limits, which turns 27
lookups into an afternoon.

The dump is one SQLite file of ~4.7M feeds carrying `itunesAuthor`, `itunesOwnerName`,
`dead` and `episodeCount`. That last pair matters as much as the lookup: it is the
difference between "I could not find it" and "it is gone", which is exactly the
repointed-versus-soft-deleted decision this repair has to make 27 times.

    curl -A '<a UA naming your app>' -o feeds.db.tgz \\
        https://public.podcastindex.org/podcastindex_feeds.db.tgz

A default or vague User-Agent gets a 403 with a plain-text scolding, not a redirect.

One thing the dump does not fix: our broken rows carry the *wrong* Apple id in home_url,
copied from whatever the original import matched. Joining on `itunesId` would faithfully
reconfirm the wrong show. Title and publisher still have to do the work -- the win is that
they now do it locally.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from pathlib import Path

from admin.api.rematch import _GENERIC_PUBLISHER, _norm, publisher_similarity, similarity

# Words too common in podcast titles to narrow anything down. A candidate sharing only
# these with our title is not a candidate.
_WEAK_TITLE_WORDS = {
    "podcast", "show", "radio", "story", "stories", "true", "crime", "news", "daily",
    "life", "world", "time", "times", "talk", "hour", "live", "audio", "media",
}


def tokens(title: str | None) -> set[str]:
    """The words in a title worth searching on.

    Four characters and up, because the prefilter is a dict lookup over 4.7M rows and
    short tokens match half of them. This is also what stops the scan going quadratic.
    """
    return {t for t in _norm(title).split()
            if len(t) >= 4 and t not in _WEAK_TITLE_WORDS and t not in _GENERIC_PUBLISHER}


@dataclass
class Row:
    feed_id: int
    title: str
    author: str
    owner: str
    url: str
    itunes_id: int | None
    dead: int
    last_status: int | None
    episode_count: int
    image: str
    newest: int | None
    language: str

    @property
    def publisher(self) -> str:
        # Two publisher fields, and which one is populated varies by host. Owner is
        # usually the label and author the creator; either may be the one that matches.
        return f"{self.author} {self.owner}".strip()

    @property
    def alive(self) -> bool:
        return not self.dead and (self.last_status is None or self.last_status < 400)


@dataclass
class Match:
    row: Row
    title_score: float
    publisher_score: float

    @property
    def total(self) -> float:
        return self.title_score + self.publisher_score

    def describe(self) -> str:
        flag = "" if self.row.alive else "  DEAD"
        return (f"{self.row.title[:40]:<42} | {self.row.publisher[:26]:<28} | "
                f"{self.row.episode_count:>5} eps | t={self.title_score:.2f} "
                f"p={self.publisher_score:.2f}{flag}")


SELECT = """
    SELECT id, title, itunesAuthor, itunesOwnerName, url, itunesId, dead,
           lastHttpStatus, episodeCount, imageUrl, newestItemPubdate, language
    FROM podcasts
"""


class Index:
    """A read-only view over the dump. Never written to; it is somebody else's data."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        if not self.path.exists():
            raise FileNotFoundError(
                f"{self.path} not found. Download the Podcast Index dump first -- see this "
                f"module's docstring for the URL and the User-Agent it requires.")

    def search(self, targets: dict[str, str | None], per_target: int = 40
               ) -> dict[str, list[Match]]:
        """Score every target against the whole dump in one pass.

        `targets` is {title: network}. One scan for all of them rather than one scan each,
        because the scan is 4.7M rows and 27 of them would be 40 minutes of re-reading the
        same file.

        The pass is two-stage on purpose. Stage one is a dict lookup on shared distinctive
        words -- cheap enough to run 4.7M times. Stage two runs the real similarity only
        on what survives, because SequenceMatcher across the full dump would not finish.
        """
        by_token: dict[str, list[str]] = {}
        for title in targets:
            for token in tokens(title):
                by_token.setdefault(token, []).append(title)
        if not by_token:
            return {t: [] for t in targets}

        found: dict[str, list[Match]] = {t: [] for t in targets}
        conn = sqlite3.connect(f"file:{self.path}?mode=ro", uri=True)
        try:
            for r in conn.execute(SELECT):
                cand_tokens = tokens(r[1])
                if not cand_tokens:
                    continue
                interested = {t for tok in cand_tokens for t in by_token.get(tok, ())}
                if not interested:
                    continue
                row = Row(*r)
                for title in interested:
                    ts = similarity(title, row.title)
                    if ts < 0.55:
                        continue
                    found[title].append(
                        Match(row, ts, publisher_similarity(targets[title], row.publisher)))
        finally:
            conn.close()

        for title, matches in found.items():
            # Alive first -- a dead feed with a perfect name is a worse answer than a live
            # one, since the point of repointing is to have episodes to show.
            #
            # Then the two scores *summed*, not publisher first. Ranking on publisher
            # alone buried the correct answer for Strangers: the dump has Lea Thau's feed
            # under its old title, an exact 1.00 match, but the curator wrote the network
            # as "Independent / originally Radiotopia" and no comparison reaches "Lea
            # Thau" from that. It sorted below "Venting To Strangers", whose publisher
            # agreed no better but scored a hair higher by accident.
            #
            # This is ordering, not deciding. Nothing is repointed on a score -- the feed
            # is fetched and read, and feeds.verify() is the gate.
            matches.sort(key=lambda m: (m.row.alive, m.total, m.row.episode_count),
                         reverse=True)
            found[title] = matches[:per_target]
        return found


# Both must agree, exactly as in rematch. The dump changes where candidates come from, not
# how much evidence it takes to repoint a row at one.
MIN_TITLE = 0.55
MIN_PUBLISHER = 0.60
MIN_EPISODES = 3


def acceptable(m: Match) -> bool:
    return (m.title_score >= MIN_TITLE
            and m.publisher_score >= MIN_PUBLISHER
            and m.row.alive
            and m.row.episode_count >= MIN_EPISODES)
