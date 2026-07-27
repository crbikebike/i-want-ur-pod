"""The feed queue: is this row even about the show it claims to be?

A question that has to be settled before "does it belong?" means anything. Nineteen cuts
and eight keeps were recorded against podcasts nobody was looking at.
"""

import json
import sqlite3
from pathlib import Path

import pytest

from admin.api import feedqueue
from catalog.build import migrations

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "catalog/schema.sql"


@pytest.fixture
def db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    migrations.apply_all(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("INSERT INTO networks (id, slug, name) VALUES (1,'crooked','Crooked Media')")
    conn.execute(
        "INSERT INTO shows (id, slug, title, feed_url, network_id, why, description) "
        "VALUES (1,'this-land','This Land','http://wrong',1,'award-winning',"
        "'Rebecca Nagle investigates tribal sovereignty')")
    conn.execute(
        "INSERT INTO shows (id, slug, title, feed_url, why) "
        "VALUES (2,'strangers','Strangers','http://wrong2','founding Radiotopia show')")
    conn.commit()
    yield conn
    conn.close()


def offer(conn, show_id=1, url="http://right", title="First America",
          author="Pushkin Industries", eps=33, sample=None):
    return feedqueue.add(conn, show_id=show_id, feed_url=url, feed_title=title,
                         feed_author=author, episode_count=eps, image_url=None,
                         sample=sample or ["Playing Indian | Episode 2"], source="podcastindex")


def test_a_card_puts_both_claims_on_one_screen(db):
    """The decision is a comparison, so the card has to be one. What the catalog believes,
    and what the feed actually contains."""
    offer(db)
    card = feedqueue.next_card(db)
    assert card["title"] == "This Land"
    assert "Rebecca Nagle" in card["claims"]["description"]
    assert card["candidate"]["title"] == "First America"
    assert card["candidate"]["author"] == "Pushkin Industries"
    assert card["candidate"]["sample"] == ["Playing Indian | Episode 2"]


def test_the_episode_titles_travel_with_the_proposal(db):
    """Stored rather than re-fetched. A queue that pulls five feeds per card is a queue
    nobody opens twice, and the titles are the whole reason the card works."""
    offer(db, sample=["Land, Not Liberty | Episode 5", "Military Might | Episode 4"])
    stored = db.execute("SELECT sample FROM feed_proposals").fetchone()[0]
    assert json.loads(stored) == ["Land, Not Liberty | Episode 5", "Military Might | Episode 4"]


def test_the_card_says_what_rejecting_costs(db):
    """"Reject" reads as free until you know it is the only candidate anyone found."""
    offer(db)
    assert "only candidate" in feedqueue.next_card(db)["meaning"]


def test_a_second_candidate_is_announced(db):
    offer(db, url="http://a")
    offer(db, url="http://b")
    card = feedqueue.next_card(db)
    assert card["alsoWaiting"] == 1
    assert "1 other candidate" in card["meaning"]


def test_confirming_one_candidate_closes_the_others(db):
    """One feed per show. The alternatives are moot the moment one is right, and leaving
    them waiting asks the same question again with a worse answer."""
    offer(db, url="http://a")
    offer(db, url="http://b")
    first = db.execute("SELECT id FROM feed_proposals ORDER BY id").fetchone()[0]
    feedqueue.record(db, first, "confirmed")
    assert feedqueue.counts(db) == {"waiting": 0, "confirmed": 1, "rejected": 1,
                                   "decided": 2, "total": 2}


def test_rejecting_leaves_the_other_candidates_waiting(db):
    offer(db, url="http://a")
    offer(db, url="http://b")
    first = db.execute("SELECT id FROM feed_proposals ORDER BY id").fetchone()[0]
    feedqueue.record(db, first, "rejected")
    assert feedqueue.counts(db)["waiting"] == 1


def test_a_rejected_candidate_is_never_offered_again(db):
    """Rows are kept rather than deleted so the next repair pass does not re-propose what
    was already turned down."""
    pid = offer(db)
    feedqueue.record(db, pid, "rejected")
    assert feedqueue.add(db, show_id=1, feed_url="http://right", feed_title="x",
                         feed_author="y", episode_count=1, image_url=None,
                         sample=[], source="apple") is None
    assert feedqueue.next_card(db) is None


def test_skipping_does_not_resolve_anything(db):
    """A skip means "not now", so the card comes back next session."""
    pid = offer(db)
    assert feedqueue.next_card(db, [pid]) is None
    assert feedqueue.counts(db)["waiting"] == 1


def test_an_empty_skip_list_does_not_empty_the_queue(db):
    """`id NOT IN (NULL)` is UNKNOWN for every row, which looks exactly like finished."""
    offer(db)
    assert feedqueue.next_card(db, []) is not None


def test_the_fullest_feed_comes_first(db):
    """A 393-episode feed is easier to recognise than a 3-episode one, and clearing the
    recognisable ones first is what makes a queue feel finishable."""
    offer(db, show_id=1, url="http://small", eps=3)
    offer(db, show_id=2, url="http://big", eps=393)
    assert feedqueue.next_card(db)["candidate"]["episodeCount"] == 393


def test_a_soft_deleted_show_has_no_card(db):
    """Eighteen rows were soft-deleted for having nowhere to point. They must not come
    back as questions."""
    offer(db)
    db.execute("UPDATE shows SET deleted_at = '2026-07-27T00:00:00+00:00' WHERE id = 1")
    db.commit()
    assert feedqueue.next_card(db) is None


def test_only_a_real_decision_is_accepted(db):
    pid = offer(db)
    with pytest.raises(ValueError):
        feedqueue.record(db, pid, "maybe")
