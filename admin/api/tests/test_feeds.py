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


# --- description as prose --------------------------------------------------------


def test_markup_and_entities_come_out_as_text():
    """Feeds carry markup. A model should be shown the words, not the tags."""
    # `&rsquo;` is a curly apostrophe, not an ASCII one, and it stays curly -- unescaping
    # is not the same as transliterating, and rewriting a publisher's punctuation would be
    # a different decision than stripping their markup.
    got = feeds.plain_text("<p>It&rsquo;s easy to dismiss these &ndash; but they spread.</p>")
    assert got == "It’s easy to dismiss these – but they spread."


def test_network_boilerplate_is_cut():
    """Every episode of a network repeats the same legal tail verbatim. On a 20-episode
    batch that is a few hundred wasted tokens and a paragraph identical across items."""
    got = feeds.plain_text(
        "In November 1992, a camera crew soars above Kilauea.\n\n"
        "See Privacy Policy at https://art19.com/privacy and California Privacy Notice "
        "at https://art19.com/privacy#do-not-sell-my-info.")
    assert got == "In November 1992, a camera crew soars above Kilauea."


def test_it_is_cut_to_length_on_a_word_boundary_or_shorter():
    assert len(feeds.plain_text("word " * 400, 100)) <= 100


def test_nothing_in_nothing_out():
    assert feeds.plain_text(None) == "" and feeds.plain_text("") == ""


def test_the_stored_description_is_left_alone():
    """plain_text is for prompts. What the publisher sent is what gets stored -- stripping
    at write time would mean the catalog could never render the markup it was given."""
    raw = "<p>Hello</p>"
    feeds.plain_text(raw)
    assert raw == "<p>Hello</p>"


def test_a_clump_of_boilerplate_goes_together():
    """One Revisionist History episode carries an ad line, a privacy line and a website
    line in a row. Cutting from the first marker to the end takes all three -- they always
    come last and always come in clumps."""
    got = feeds.plain_text(
        "A painting took England by storm, then the artist vanished. "
        "To learn more about the topics covered in this episode, visit www.example.com "
        "Learn more about your ad-choices at https://www.iheartpodcastnetwork.com "
        "See omnystudio.com/listener for privacy information.")
    assert got == "A painting took England by storm, then the artist vanished."


def test_a_hyphen_is_not_a_hiding_place():
    """The first version matched "ad choices" and missed "ad-choices", which is what
    iHeart actually writes on every episode it publishes."""
    assert feeds.plain_text("The story. Learn more about your ad-choices at x.com") == "The story."


# The description a publisher means is not always the first one they list. 99% Invisible
# puts a 178-character teaser in <itunes:summary> and 1,070 characters of notes in
# <description>, so reading the first non-empty element labelled 781 episodes on a teaser
# -- and `refresh_episodes`, which never overwrites with less, kept the truncated import
# text and hid the miss.
TEASER_AND_NOTES = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:content="http://purl.org/rss/1.0/modules/content/">
 <channel><title>Show</title>
  <item>
   <title>Teaser first</title><guid>a</guid>
   <itunes:summary>A one-line teaser.</itunes:summary>
   <description>The full notes, which run considerably longer than the teaser does and
   are what a labelling pass actually needs to read.</description>
  </item>
  <item>
   <title>Markup does not win on tag bytes</title><guid>b</guid>
   <itunes:summary>This summary is the longest prose of the three by a clear margin, and
   it should win even though the encoded block carries more raw characters.</itunes:summary>
   <content:encoded>&lt;p&gt;&lt;strong&gt;&lt;em&gt;Short.&lt;/em&gt;&lt;/strong&gt;&lt;/p&gt;</content:encoded>
  </item>
 </channel>
</rss>"""


def test_the_fullest_description_wins_not_the_first_one_listed():
    first, second = feeds.parse(TEASER_AND_NOTES).episodes
    assert first.description.startswith("The full notes")
    assert second.description.startswith("This summary is the longest")
