"""Scoring a candidate feed against the show we meant.

The bug being defended against: 20 shows -- 7% of the catalog -- point at a different
podcast that happens to share a name. Strangers served Islamic teaching, The Clearing
served church sermons, Serial (Season 1) served a podcast-hosting sandbox's test items.

Every regression here is a real wrong answer this scorer gave at some point. The two
gates pull against each other, and loosening either one has put a known bug straight
back, so both directions are pinned.
"""

import sqlite3

import pytest

from admin.api import rematch


def cand(name, artist, feed="http://f"):
    return rematch.Candidate(name=name, artist=artist, feed_url=feed, home_url="", artwork="")


def score(title, network, name, artist):
    c = cand(name, artist)
    c.title_score = rematch.similarity(title, name)
    c.publisher_score = rematch.publisher_similarity(network, artist)
    return c


# --- publisher agreement is about shared names, not shared text --------------------


def test_a_shared_publisher_name_survives_decoration_on_both_sides():
    """The failure that cost us Theory of Everything.

    Our `network` column is a curator's prose note, not a database field. "Radiotopia /
    PRX" against Apple's "Benjamen Walker & Radiotopia" scored 0.50 on character overlap
    and missed the 0.60 gate, even though the word carrying the evidence is in both."""
    assert rematch.similarity("Radiotopia / PRX", "Benjamen Walker & Radiotopia") < 0.60
    assert rematch.publisher_similarity(
        "Radiotopia / PRX", "Benjamen Walker & Radiotopia") >= rematch.MIN_PUBLISHER


def test_generic_trade_words_are_not_evidence():
    """Half the publisher names in podcasting contain these. Agreeing on 'Media' is not
    agreeing."""
    assert rematch.publisher_similarity("Neon Hum Media", "Crawlspace Media") < rematch.MIN_PUBLISHER
    assert rematch.publisher_similarity("Wondery Productions", "Tenderfoot Productions") \
        < rematch.MIN_PUBLISHER


def test_short_tokens_are_not_evidence():
    """Initialisms collide. ABC is a broadcaster, a network and a record label."""
    assert rematch.publisher_similarity("ABC RN (Radio National)", "ABC Kids") \
        < rematch.MIN_PUBLISHER


def test_an_unrelated_publisher_still_scores_nothing():
    assert rematch.publisher_similarity("Gimlet Media", "Dr. Thema") < rematch.MIN_PUBLISHER


def test_a_person_cannot_be_matched_to_a_prose_network_note():
    """Why Strangers had to be fixed by hand and always would have been.

    The curator wrote "Independent / originally Radiotopia"; the real feed's artist is
    "Lea Thau", a person. No string comparison reaches across that, and pretending
    otherwise would mean guessing."""
    assert rematch.publisher_similarity(
        "Independent / originally Radiotopia", "Lea Thau") < rematch.MIN_PUBLISHER


# --- the title gate still does the work it was added for --------------------------


@pytest.mark.parametrize("title,network,name,artist", [
    # Weighting publisher and letting it outvote the title produced both of these.
    ("Earshot", "ABC RN (Radio National)", "RN Drive", "ABC Radio National"),
    ("Homecoming", "Gimlet Media", "Surprisingly Awesome", "Gimlet"),
])
def test_a_shared_publisher_cannot_rescue_an_implausible_title(title, network, name, artist):
    c = score(title, network, name, artist)
    assert c.publisher_score >= rematch.MIN_PUBLISHER   # the publisher does agree
    assert not rematch.acceptable(c)                    # and it does not matter


@pytest.mark.parametrize("title,network,name,artist", [
    # "A strong title can stand alone" reinstated the exact bug being fixed.
    ("Homecoming", "Gimlet Media", "Homecoming", "The Homecoming Podcast with Dr. Thema"),
    ("The Clearing", "Gimlet Media / Pineapple Street Studios",
     "The Clearing", "The Clearing Podcast"),
    ("Strangers", "Independent / originally Radiotopia",
     "The Strangers Podcast", "Ibn Bashiir & Slaveofmostwise"),
])
def test_a_perfect_title_is_exactly_what_a_collision_looks_like(title, network, name, artist):
    c = score(title, network, name, artist)
    assert c.title_score >= 0.9
    assert not rematch.acceptable(c)


def test_both_agreeing_is_accepted():
    c = score("Empire", "Goalhanger", "Empire: World History", "Goalhanger")
    assert rematch.acceptable(c)


def test_a_candidate_with_no_feed_is_not_a_candidate():
    """Apple lists shows it has no RSS for -- The Clearing is one, and Gimlet's
    Spotify-era catalog is full of them. There is nothing to point a row at, so the
    scorer never sees it and the show has to be resolved by hand."""
    assert rematch.rank("The Clearing", "Gimlet", [
        {"collectionName": "The Clearing", "artistName": "Pineapple Street Media / Gimlet"},
    ]) == []


# --- the Apple page a repaired row links to ---------------------------------------


def test_the_apple_page_is_looked_up_by_feed_url(tmp_path):
    """Repairing a row has to *replace* its home_url, not drop it.

    The old one pointed at the wrong show's Apple page -- Homecoming's led to "The
    Homecoming Podcast with Dr. Thema" -- so keeping it was never an option. But a first
    version simply cleared it, and that quietly cost the card its slide-up player: with no
    Apple id there is nothing to embed, so "Listen and look" degraded to a bare search
    link in a new tab. Chris noticed within the hour.

    Keyed on the feed URL, so it is exact rather than another name match.
    """
    from admin.api import podcastindex as pi

    dump = tmp_path / "feeds.db"
    conn = sqlite3.connect(dump)
    conn.execute("CREATE TABLE podcasts (url TEXT, originalUrl TEXT, itunesId INTEGER)")
    conn.execute("INSERT INTO podcasts VALUES (?,?,?)",
                 ("https://feeds.megaphone.fm/homecoming", "", 1170934381))
    conn.execute("INSERT INTO podcasts VALUES (?,?,?)",
                 ("https://example.com/nolisting", "", None))
    conn.commit(); conn.close()

    assert pi.itunes_home("https://feeds.megaphone.fm/homecoming", dump=dump) == \
        "https://podcasts.apple.com/us/podcast/id1170934381"
    # A feed Apple has never listed, and a feed the dump has never seen. Both are "no
    # answer", and the card falls back to a search rather than linking somewhere wrong.
    assert pi.itunes_home("https://example.com/nolisting", dump=dump) is None
    assert pi.itunes_home("https://example.com/unknown", dump=dump) is None


def test_no_dump_is_not_an_error(tmp_path):
    """The workbench has to run without a 4 GB file present."""
    from admin.api import podcastindex as pi
    assert pi.itunes_home("https://feeds.megaphone.fm/homecoming",
                          dump=tmp_path / "absent.db") is None
