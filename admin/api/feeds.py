"""Reading a podcast feed, and deciding whether it is the show we think it is.

Two jobs that turn out to be one. Twenty-seven catalog rows point at a different podcast
that happens to share a name, and the only reliable way to tell is to fetch the candidate
feed and look at what is inside it -- the publisher it names and the episodes it carries.
Once it is fetched and read, storing those episodes costs nothing extra. So verification
and ingestion are the same pass, and doing them separately would mean pulling every feed
twice.

What actually settles these cases, in order:

  The publisher. `<itunes:author>` on the feed against the curator's `network`. When the
  catalog says Pushkin Industries and the feed says "Tim Ebl & Ryan Hanson", that is the
  answer, and no amount of title similarity argues with it.

  The episode titles. "S01 EP5: Description & Content Encoded Only" is a podcast host's
  test sandbox. "7 Hebrew Words for Praise" is a church. Neither is Serial or The
  Clearing, and both were sitting in the catalog under those names.

Nothing here writes. `verify()` returns evidence a person can read and disagree with,
because the last two times this scoring was tightened by feel it put the original bug
straight back.
"""

from __future__ import annotations

import re
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

from admin.api.rematch import _GENERIC_PUBLISHER, _norm, publisher_similarity


def _distinctive(s: str | None) -> set[str]:
    """The words in a name that identify anybody. Same rule the publisher scorer uses."""
    return {t for t in _norm(s).split() if len(t) >= 4 and t not in _GENERIC_PUBLISHER}

ITUNES = "{http://www.itunes.com/dtds/podcast-1.0.dtd}"
CONTENT = "{http://purl.org/rss/1.0/modules/content/}"

# Publishers serve a different feed to a bare urllib than to a browser, and some refuse it
# outright. This is the same string the app will send.
UA = "Mozilla/5.0 (compatible; i-want-ur-pod catalog comber)"


class FeedError(RuntimeError):
    """The feed could not be fetched or parsed. Never silently treated as empty --
    "no episodes" and "the server said 403" mean opposite things about a show."""


@dataclass
class Episode:
    guid: str
    title: str
    published_at: str | None = None
    description: str | None = None
    season: int | None = None
    episode_number: int | None = None
    episode_type: str | None = None
    duration_s: int | None = None


@dataclass
class Feed:
    url: str
    title: str
    author: str | None
    description: str | None
    # Phase 4's comber has to watch this anyway -- publishers replace cover art and Apple
    # serves it with a 190-day max-age, so only a feed read can notice. Repairs need it
    # for a simpler reason: the artwork on a mispointed row is the wrong show's face.
    image: str | None = None
    episodes: list[Episode] = field(default_factory=list)

    def sample(self, n: int = 8) -> list[str]:
        return [e.title for e in self.episodes[:n]]


# A feed is third-party XML fetched over the network, so it is hostile input, and this
# module runs inside the workbench service. Two limits stand between a bad feed and the
# process.
#
# The read is capped. The largest real feed in the catalog is a few megabytes; anything
# past this is either broken or not a feed, and `read()` on an unbounded socket is how a
# service dies quietly.
MAX_BYTES = 32 * 1024 * 1024

# And a DOCTYPE is refused outright. Python's ElementTree expands internal entities --
# verified, not assumed: a ten-line declaration expands to 1,000 characters and the same
# trick nests to gigabytes. defusedxml would handle it, but it is not installed and this
# project has no dependency manifest to add it to, so adding an undeclared import to a
# running service is worse than the two lines below. RSS has no legitimate use for a DTD.
_DOCTYPE = re.compile(rb"<!DOCTYPE", re.IGNORECASE)


def fetch(url: str, timeout: int = 40) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as e:
        raise FeedError(f"{url} -> HTTP {e.code}") from e
    except Exception as e:
        raise FeedError(f"{url} -> {e}") from e

    if len(raw) > MAX_BYTES:
        raise FeedError(f"{url} -> larger than {MAX_BYTES // 1024 // 1024} MB; not read")
    if _DOCTYPE.search(raw):
        raise FeedError(f"{url} -> declares a DOCTYPE, which a podcast feed has no reason "
                        f"to do and an entity-expansion attack does; refused unparsed")
    return raw.decode("utf-8", "replace")


def _text(node, *paths) -> str | None:
    for p in paths:
        found = node.find(p)
        if found is not None and (found.text or "").strip():
            return found.text.strip()
    return None


def _int(value: str | None) -> int | None:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def parse_duration(text: str | None) -> int | None:
    """Seconds, from either 3600 or 1:00:00. Feeds use both, sometimes in one feed."""
    if not text:
        return None
    text = text.strip()
    if text.isdigit():
        return int(text)
    try:
        parts = [int(p) for p in text.split(":")]
    except ValueError:
        return None
    seconds = 0
    for p in parts:
        seconds = seconds * 60 + p
    return seconds or None


def _published(node) -> str | None:
    raw = _text(node, "pubDate")
    if not raw:
        return None
    try:
        # Normalised to UTC ISO because the catalog sorts and groups on this, and feeds
        # carry every timezone there is.
        return parsedate_to_datetime(raw).astimezone(timezone.utc).isoformat(timespec="seconds")
    except (TypeError, ValueError):
        return None


def parse(xml: str, url: str = "") -> Feed:
    # Checked here as well as in fetch(), because parse() is callable on its own and a
    # guard that only covers one entry point is not a guard.
    if _DOCTYPE.search(xml.encode("utf-8", "replace")):
        raise FeedError(f"{url or 'feed'} declares a DOCTYPE; refused unparsed")
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as e:
        raise FeedError(f"{url or 'feed'} is not parseable XML: {e}") from e
    channel = root.find("channel")
    if channel is None:
        raise FeedError(f"{url or 'feed'} has no <channel>")

    episodes = []
    for item in channel.findall("item"):
        title = _text(item, "title")
        # A GUID is what makes an episode stable across refetches; without one there is
        # nothing to key on, so the item is skipped rather than given an invented id that
        # would duplicate on the next run. The audio URL is the usual stand-in when a
        # publisher omits the guid -- read off the element, since ElementTree's find()
        # has no attribute syntax and "enclosure/@url" is a path error, not a miss.
        guid = _text(item, "guid")
        if not guid:
            enclosure = item.find("enclosure")
            guid = (enclosure.get("url") or "").strip() if enclosure is not None else None
        if not title or not guid:
            continue
        episodes.append(Episode(
            guid=guid,
            title=re.sub(r"\s+", " ", title).strip(),
            published_at=_published(item),
            description=_text(item, f"{ITUNES}summary", "description", f"{CONTENT}encoded"),
            season=_int(_text(item, f"{ITUNES}season")),
            episode_number=_int(_text(item, f"{ITUNES}episode")),
            episode_type=_text(item, f"{ITUNES}episodeType"),
            duration_s=parse_duration(_text(item, f"{ITUNES}duration")),
        ))

    # <itunes:image href="..."> carries it as an attribute; plain RSS nests <image><url>.
    itunes_image = channel.find(f"{ITUNES}image")
    image = (itunes_image.get("href") or "").strip() if itunes_image is not None else ""

    return Feed(
        url=url,
        title=_text(channel, "title") or "",
        author=_text(channel, f"{ITUNES}author", "managingEditor"),
        description=_text(channel, "description", f"{ITUNES}summary"),
        image=image or _text(channel, "image/url"),
        episodes=episodes,
    )


def read(url: str, timeout: int = 40) -> Feed:
    return parse(fetch(url, timeout), url)


# --- is this the show we meant? ---------------------------------------------------

@dataclass
class Verdict:
    ok: bool
    reason: str
    publisher_score: float
    feed_title: str
    feed_author: str | None
    episode_count: int
    sample: list[str]

    def describe(self) -> str:
        mark = "✓" if self.ok else "✗"
        return (f"  {mark} {self.feed_title[:40]:<42} by {str(self.feed_author)[:24]:<26} "
                f"{self.episode_count:>4} eps  p={self.publisher_score:.2f}  {self.reason}")


# A feed with almost nothing in it cannot be checked and cannot be shipped. Three is
# enough for a limited series (The Clearing runs to 11) and rules out the trailer-only
# rows that several of these had become.
MIN_EPISODES = 3


def verify(feed: Feed, *, network: str | None, expect_title: str | None = None) -> Verdict:
    """Does this feed belong to the show the catalog describes?

    The publisher is the discriminator, for the reason Empire made obvious: the row
    carries the curator's `network` for the show they meant, and the import copied
    `author` from whatever it happened to find. Comparing the feed's own author against
    the curator's note is comparing our intent against the feed's identity.

    A title check is deliberately *not* a gate. These rows are broken precisely because
    titles collide -- "Cautionary Tales" matches "Cautionary Tales" perfectly and is a
    different show -- and two of the five fixed by hand had been renamed by their
    publisher, so the catalog's title no longer matched the correct feed either.
    """
    p = publisher_similarity(network, feed.author)

    # A self-titled-feed rule lived here briefly and was removed. The idea was that
    # "Reading Sirens" by "Reading Sirens" carries no independent evidence, which is true,
    # but every form of the test also rejected real shows named after their maker --
    # Benjamen Walker's Theory of Everything, and Lea Thau's. What the bad matches
    # actually had in common was agreeing on a word that identifies nobody, so the fix
    # belongs in _GENERIC_PUBLISHER, where "radio" and "sounds" now sit, and not here.

    if len(feed.episodes) < MIN_EPISODES:
        return Verdict(False, f"only {len(feed.episodes)} episodes; too thin to confirm",
                       p, feed.title, feed.author, len(feed.episodes), feed.sample())
    if not network:
        return Verdict(False, "no network recorded, so nothing to check the publisher against",
                       p, feed.title, feed.author, len(feed.episodes), feed.sample())
    if p < 0.60:
        return Verdict(False, f"publisher disagrees: catalog says {network!r}, "
                              f"feed says {feed.author!r}",
                       p, feed.title, feed.author, len(feed.episodes), feed.sample())
    return Verdict(True, f"publisher agrees ({feed.author})",
                   p, feed.title, feed.author, len(feed.episodes), feed.sample())


_TAG = re.compile(r"<[^>]+>")
_BOILERPLATE = re.compile(
    r"\s*(see (privacy policy|omnystudio\.com/listener)|learn more about your ad choices|"
    r"privacy policy|california privacy notice|hosted on acast|"
    r"to listen to all our|become a member at)\b.*$",
    re.IGNORECASE | re.DOTALL)


def plain_text(html: str | None, limit: int | None = None) -> str:
    """A description as prose, for reading rather than rendering.

    Feeds carry markup -- `<p>`, `&ndash;`, `&rsquo;` -- and a tail of legal boilerplate
    that every episode of a network repeats verbatim. Both are stored as sent, because
    that is what the publisher published, and both are stripped here because neither is
    what a model should be shown. On a 20-episode batch the boilerplate alone is a few
    hundred wasted tokens and a paragraph of text identical across every item, which is
    exactly the kind of thing that makes a batch read as repetitive.
    """
    import html as _html

    if not html:
        return ""
    text = _html.unescape(_TAG.sub(" ", html))
    text = _BOILERPLATE.sub("", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:limit].rstrip() if limit else text


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")
