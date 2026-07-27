"""One feed, one show.

Feeds get retitled -- a season ships and the publisher renames the feed after it -- so a
catalogue built from two snapshots holds the same programme twice. All eight duplicate
pairs here were that, and none was a judgement call.
"""

import sqlite3
from pathlib import Path

import pytest

from admin.api import merge, queues
from catalog.build import migrations

SCHEMA = Path(__file__).resolve().parents[3] / "catalog/schema.sql"


@pytest.fixture
def db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    migrations.apply_all(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    yield conn
    conn.close()


@pytest.fixture
def log(tmp_path):
    return tmp_path / "decisions.jsonl"


def add(conn, slug, title, feed, verdict="suspect", episodes=0):
    """Duplicates default to 'suspect' because that is the only way they can exist.

    shows_one_reviewed_per_feed permits at most one *reviewed* live show per feed, so a
    second row on a shared feed has to be flagged. The importer does exactly that. A
    fixture inserting two 'unreviewed' rows on one feed is building a state the catalogue
    cannot reach.
    """
    sid = conn.execute(
        "INSERT INTO shows (slug, title, feed_url, include_verdict) VALUES (?,?,?,?)",
        (slug, title, feed, verdict)).lastrowid
    for i in range(episodes):
        conn.execute("INSERT INTO episodes (show_id, guid, title) VALUES (?,?,?)",
                     (sid, f"{feed}-{i}", f"ep {i}"))
    conn.commit()
    return sid


# --- choosing the surviving name -------------------------------------------------


def test_the_feed_decides_the_name():
    assert merge.choose_title("Slow Burn", ["Slow Burn", "Slow Burn: Biggie & Tupac"]) == "Slow Burn"


def test_a_season_decorated_feed_title_loses_to_the_base_name():
    """Pushkin titles the feed after the current season, so taking it literally would
    mean chasing season names forever."""
    got = merge.choose_title(
        "Revisionist History: The Staten Island Problem",
        ["Revisionist History", "The Staten Island Problem"])
    assert got == "Revisionist History"


def test_the_feed_title_wins_when_we_hold_nothing_like_it():
    """WBEZ calls the feed "Making"; the catalogue only had the two season names."""
    assert merge.choose_title("Making", ["Making Obama", "Making Oprah"]) == "Making"


def test_case_differences_do_not_defeat_the_match():
    got = merge.choose_title("Man In The Window: The Golden State Killer",
                             ["Man in the Window", "Man in the Window: The Golden State Killer"])
    assert got == "Man in the Window"


def test_an_unreachable_feed_falls_back_to_the_shortest_name(db):
    assert merge.choose_title(None, ["Deep Cover: Never Seen Again", "Deep Cover"]) == "Deep Cover"


# --- planning --------------------------------------------------------------------


def test_a_feed_with_one_show_is_left_alone(db):
    add(db, "a", "A", "http://a", verdict="unreviewed")
    assert merge.plan(db, fetch=False) == []


def test_a_shared_feed_produces_one_plan(db):
    add(db, "sb", "Slow Burn", "http://sb", verdict="unreviewed", episodes=5)
    add(db, "sbbt", "Slow Burn: Biggie & Tupac", "http://sb", episodes=5)
    plans = merge.plan(db, fetch=False)
    assert len(plans) == 1
    assert plans[0].keep_title == "Slow Burn"
    assert [t for _, t in plans[0].absorb] == ["Slow Burn: Biggie & Tupac"]


def test_a_soft_deleted_row_is_not_a_duplicate(db):
    add(db, "sb", "Slow Burn", "http://sb")
    other = add(db, "sbbt", "Slow Burn: Biggie & Tupac", "http://sb")
    db.execute("UPDATE shows SET deleted_at='2026-07-27' WHERE id=?", (other,))
    db.commit()
    assert merge.plan(db, fetch=False) == []


# --- merging ---------------------------------------------------------------------


def test_the_absorbed_row_is_hidden_not_destroyed(db, log):
    keep = add(db, "sb", "Slow Burn", "http://sb", verdict="unreviewed", episodes=3)
    gone = add(db, "sbbt", "Slow Burn: Biggie & Tupac", "http://sb", episodes=3)
    merge.apply_plan(db, merge.plan(db, fetch=False)[0], decisions_path=log)

    assert db.execute("SELECT deleted_at FROM shows WHERE id=?", (gone,)).fetchone()[0]
    assert db.execute("SELECT count(*) FROM shows").fetchone()[0] == 2   # still there
    assert db.execute("SELECT deleted_at FROM shows WHERE id=?", (keep,)).fetchone()[0] is None


def test_the_duplicate_episodes_are_hidden_too(db, log):
    add(db, "sb", "Slow Burn", "http://sb", verdict="unreviewed", episodes=3)
    gone = add(db, "sbbt", "Slow Burn: Biggie & Tupac", "http://sb", episodes=3)
    merge.apply_plan(db, merge.plan(db, fetch=False)[0], decisions_path=log)

    live = db.execute("SELECT count(*) FROM episodes WHERE deleted_at IS NULL").fetchone()[0]
    assert live == 3
    assert db.execute("SELECT count(*) FROM episodes").fetchone()[0] == 6


def test_a_merge_leaves_a_trail(db, log):
    """It goes through the one door like everything else, so it can be undone."""
    add(db, "sb", "Slow Burn", "http://sb", verdict="unreviewed")
    add(db, "sbbt", "Slow Burn: Biggie & Tupac", "http://sb")
    merge.apply_plan(db, merge.plan(db, fetch=False)[0], decisions_path=log)

    actors = [r[0] for r in db.execute("SELECT DISTINCT actor FROM edits")]
    assert actors == ["agent:merge"]
    assert log.exists() and log.read_text().count("\n") >= 2


def test_merging_clears_a_flag_it_caused(db, log):
    """The show was only suspect because of the duplicate. That question is answered."""
    add(db, "sb", "Slow Burn", "http://sb", verdict="suspect")
    add(db, "sbbt", "Slow Burn: Biggie & Tupac", "http://sb", verdict="suspect")
    merge.apply_plan(db, merge.plan(db, fetch=False)[0], decisions_path=log)
    assert db.execute(
        "SELECT include_verdict FROM shows WHERE slug='sb'").fetchone()[0] == "unreviewed"


def test_the_queue_shrinks_by_the_absorbed_rows(db, log):
    add(db, "sb", "Slow Burn", "http://sb", verdict="unreviewed")
    add(db, "sbbt", "Slow Burn: Biggie & Tupac", "http://sb")
    add(db, "other", "Something Else", "http://other", verdict="unreviewed")
    before = queues.inclusion_counts(db)["waiting"]
    merge.apply_plan(db, merge.plan(db, fetch=False)[0], decisions_path=log)
    assert queues.inclusion_counts(db)["waiting"] == before - 1


def test_renaming_happens_when_the_feed_disagrees_with_every_row(db, log):
    add(db, "mo", "Making Obama", "http://making", verdict="unreviewed", episodes=2)
    add(db, "mp", "Making Oprah", "http://making", episodes=2)
    p = merge.plan(db, fetch=False)[0]
    p.live_title, p.retitle_to = "Making", "Making"
    merge.apply_plan(db, p, decisions_path=log)
    titles = {r[0] for r in db.execute("SELECT title FROM shows WHERE deleted_at IS NULL")}
    assert titles == {"Making"}
