"""Reading a feed, and deciding whether it is the show we think it is.

The cases here are the real ones. Every fixture below is shaped like a feed that was
actually sitting in the catalog under a name that belonged to something else.
"""

import pytest

from admin.api import feeds

RSS = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
 <channel>
  <title>{title}</title>
  <itunes:author>{author}</itunes:author>
  <description>{desc}</description>
  {items}
 </channel>
</rss>"""

ITEM = """<item>
  <title>{title}</title><guid>{guid}</guid>
  <pubDate>{date}</pubDate><description>{desc}</description>
  <itunes:season>{season}</itunes:season><itunes:episode>{num}</itunes:episode>
  <itunes:episodeType>{kind}</itunes:episodeType><itunes:duration>{dur}</itunes:duration>
 </item>"""


def build(title="A Show", author="A Publisher", desc="about it", n=5, **kw):
    items = "".join(
        ITEM.format(title=f"Episode {i}", guid=f"g{i}", date="Tue, 21 Oct 2025 09:00:00 +0000",
                    desc="notes", season=1, num=i, kind="full", dur="1:02:03")
        for i in range(1, n + 1))
    return RSS.format(title=title, author=author, desc=desc, items=items, **kw)


# --- parsing ---------------------------------------------------------------------


def test_a_feed_yields_its_episodes():
    f = feeds.parse(build(n=3))
    assert f.title == "A Show" and f.author == "A Publisher"
    assert [e.title for e in f.episodes] == ["Episode 1", "Episode 2", "Episode 3"]
    e = f.episodes[0]
    assert e.guid == "g1" and e.season == 1 and e.episode_number == 1
    assert e.episode_type == "full" and e.duration_s == 3723


def test_dates_are_normalised_to_utc():
    """The catalog sorts and groups on this, and feeds carry every timezone there is."""
    xml = RSS.format(title="S", author="P", desc="d", items=ITEM.format(
        title="One", guid="g", date="Tue, 21 Oct 2025 09:00:00 -0700", desc="",
        season=1, num=1, kind="full", dur="600"))
    assert feeds.parse(xml).episodes[0].published_at == "2025-10-21T16:00:00+00:00"


@pytest.mark.parametrize("text,seconds", [
    ("3600", 3600), ("1:00:00", 3600), ("42:10", 2530), ("", None), (None, None),
    ("not a duration", None),
])
def test_durations_come_in_both_shapes_and_sometimes_neither(text, seconds):
    assert feeds.parse_duration(text) == seconds


def test_an_item_with_no_guid_is_skipped():
    """A GUID is what makes an episode stable across refetches. Inventing one would
    duplicate the episode on the next run."""
    xml = RSS.format(title="S", author="P", desc="d",
                     items="<item><title>No id here</title></item>")
    assert feeds.parse(xml).episodes == []


def test_a_feed_that_is_not_xml_says_so_rather_than_looking_empty():
    """"No episodes" and "the server sent an error page" mean opposite things about a
    show, and one of them must not be recorded as the other."""
    with pytest.raises(feeds.FeedError):
        feeds.parse("<html><body>404 Not Found</body></html>")


def test_xml_with_no_channel_is_refused():
    with pytest.raises(feeds.FeedError):
        feeds.parse("<rss version='2.0'></rss>")


# --- hostile input ----------------------------------------------------------------


def test_an_entity_expansion_bomb_is_refused_unparsed():
    """This module runs inside the workbench service and reads third-party XML.

    Python's ElementTree expands internal entities -- ten lines of declarations become a
    thousand characters, and the same nesting reaches gigabytes. A podcast feed has no
    reason to declare a DTD, so none is accepted."""
    bomb = ('<?xml version="1.0"?><!DOCTYPE r [<!ENTITY a "aaaaaaaaaa">'
            '<!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">'
            '<!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">]>'
            '<rss><channel><title>&c;</title></channel></rss>')
    with pytest.raises(feeds.FeedError, match="DOCTYPE"):
        feeds.parse(bomb)


def test_an_external_entity_is_refused_too():
    xxe = ('<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
           '<rss><channel><title>&x;</title></channel></rss>')
    with pytest.raises(feeds.FeedError, match="DOCTYPE"):
        feeds.parse(xxe)


# --- is this the show we meant? ---------------------------------------------------


def test_a_matching_publisher_confirms_the_feed():
    v = feeds.verify(feeds.parse(build(title="Cautionary Tales with Tim Harford",
                                       author="Pushkin Industries", n=20)),
                     network="Pushkin Industries")
    assert v.ok and v.publisher_score >= 0.9


def test_a_disagreeing_publisher_rejects_it_and_says_what_it_saw():
    """The real Cautionary Tales case. The titles are identical; the publishers are not,
    and that is the whole answer."""
    # `&amp;` because a real feed escapes it; a raw ampersand is not XML.
    v = feeds.verify(feeds.parse(build(title="Cautionary Tales",
                                       author="Tim Ebl &amp; Ryan Hanson", n=9)),
                     network="Pushkin Industries")
    assert not v.ok
    assert "Pushkin Industries" in v.reason and "Tim Ebl" in v.reason


def test_a_renamed_feed_still_passes_on_its_publisher():
    """Two of the five fixed by hand had been retitled by their publisher, so the
    catalog's title no longer matched the correct feed. Title is not a gate here."""
    v = feeds.verify(feeds.parse(build(title="STORIES by Lea Thau", author="Lea Thau", n=11)),
                     network="Lea Thau", expect_title="Strangers")
    assert v.ok


def test_a_feed_too_thin_to_check_is_not_confirmed():
    """Several broken rows had decayed to a lone trailer. That is unshippable and
    unverifiable, and 'looks fine' is the wrong answer to give about it."""
    v = feeds.verify(feeds.parse(build(author="Pushkin Industries", n=1)),
                     network="Pushkin Industries")
    assert not v.ok and "too thin" in v.reason


def test_no_network_means_nothing_to_check_against():
    v = feeds.verify(feeds.parse(build(n=10)), network=None)
    assert not v.ok


def test_the_verdict_carries_evidence_a_person_can_argue_with():
    """The last two times this scoring was tightened by feel it put the original bug
    straight back. A verdict that cannot be read cannot be checked."""
    v = feeds.verify(feeds.parse(build(title="The Clearing", author="The Clearing Podcast",
                                       n=208)), network="Gimlet Media / Pineapple Street")
    assert v.feed_author == "The Clearing Podcast"
    assert v.episode_count == 208
    assert len(v.sample) == 8
    assert "✗" in v.describe()
