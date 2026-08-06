"""Naming an arc whose current name says nothing.

The bug this file exists for: flagging an arc as ungroupable drops its confidence but
leaves its name alone -- the name is not the problem, the grouping is. So the name still
failed the screen and the arc came straight back in the next batch, forever. An agent
found it within three calls and stopped rather than looping.
"""

import sqlite3
from pathlib import Path

import pytest

from admin.api import arcname
from catalog.build import migrations

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "catalog/schema.sql"


@pytest.fixture
def db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    migrations.apply_all(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("INSERT INTO shows (id, slug, title, feed_url, why, description) "
                 "VALUES (1,'deep-cover','Deep Cover','http://f','x','undercover stories')")
    conn.commit()
    yield conn
    conn.close()


@pytest.fixture
def log(tmp_path):
    return tmp_path / "decisions.jsonl"


def add_arc(conn, slug, name, n=3, show_id=1):
    cur = conn.execute(
        "INSERT INTO arcs (show_id, slug, kind, name, confidence, source) "
        "VALUES (?,?,'arc',?,'medium','llm')", (show_id, slug, name))
    aid = cur.lastrowid
    for i in range(n):
        conn.execute(
            "INSERT INTO episodes (show_id, guid, title, description, arc_id, published_at) "
            "VALUES (?,?,?,?,?,?)",
            (show_id, f"{slug}-{i}", f"Ep {i}", "<p>About the thing.</p>", aid,
             f"2024-01-0{i+1}"))
    conn.commit()
    return aid


def test_a_positional_name_is_offered_with_its_episodes(db):
    add_arc(db, "season-1", "Season 1")
    got = arcname.pending(db)
    assert len(got) == 1
    assert got[0]["why"] == "a position, not a subject"
    assert len(got[0]["episodes"]) == 3


def test_a_real_name_is_left_alone(db):
    add_arc(db, "hunting-season", "Hunting Season")
    assert arcname.pending(db) == []


def test_episode_text_arrives_as_prose(db):
    """Markup is stored because the publisher sent it, and stripped here because a model
    should be shown the words."""
    add_arc(db, "season-1", "Season 1")
    assert arcname.pending(db)[0]["episodes"][0]["description"] == "About the thing."


def test_a_named_arc_leaves_the_queue(db, log):
    aid = add_arc(db, "season-1", "Season 1")
    arcname.record(db, [{"arcId": aid, "name": "Season 1 — The Kolmanskop Vanishing",
                         "reason": "all three follow one disappearance"}],
                   decisions_path=log)
    assert arcname.pending(db) == []
    assert db.execute("SELECT name FROM arcs WHERE id=?", (aid,)).fetchone()[0] \
        == "Season 1 — The Kolmanskop Vanishing"


def test_a_flagged_arc_leaves_the_queue_even_though_its_name_did_not_change(db, log):
    """The bug. Flagging says the grouping is wrong, so the name stays as it is -- and the
    name is what the screen tests. Without this, the arc loops forever."""
    aid = add_arc(db, "trailer", "Trailer")
    got = arcname.record(db, [{"arcId": aid, "noCommonSubject": True,
                               "reason": "six trailers for unrelated seasons"}],
                         decisions_path=log)
    assert got["flagged"] == 1
    assert db.execute("SELECT confidence FROM arcs WHERE id=?", (aid,)).fetchone()[0] == "low"
    assert db.execute("SELECT name FROM arcs WHERE id=?", (aid,)).fetchone()[0] == "Trailer"
    assert arcname.pending(db) == []


def test_a_replacement_that_fails_the_same_test_is_refused(db, log):
    """Otherwise a model answering "Season 2" is taken at its word and nothing improves."""
    aid = add_arc(db, "season-1", "Season 1")
    got = arcname.record(db, [{"arcId": aid, "name": "Season 2"}], decisions_path=log)
    assert got["named"] == 0
    assert "still" in got["skipped"][0]
    assert db.execute("SELECT name FROM arcs WHERE id=?", (aid,)).fetchone()[0] == "Season 1"


def test_the_shows_own_name_is_refused_too(db, log):
    aid = add_arc(db, "x", "Bonus")
    got = arcname.record(db, [{"arcId": aid, "name": "Deep Cover"}], decisions_path=log)
    assert got["named"] == 0 and got["skipped"]


def test_a_name_with_no_arc_is_reported_not_swallowed(db, log):
    got = arcname.record(db, [{"arcId": 9999, "name": "Whatever"}], decisions_path=log)
    assert got["skipped"] == ["9999: no such arc"]


def test_slicing_partitions_without_overlap(db):
    for i in range(6):
        add_arc(db, f"season-{i}", f"Season {i}")
    seen = []
    for i in range(3):
        seen += [a["arcId"] for a in arcname.pending(db, limit=99, slice_of=(i, 3))]
    assert sorted(seen) == sorted(a["arcId"] for a in arcname.pending(db, limit=99))
    assert len(seen) == len(set(seen))


def test_an_arc_of_one_episode_is_not_offered(db):
    """There is nothing to read a common subject out of."""
    add_arc(db, "season-1", "Season 1", n=1)
    assert arcname.pending(db) == []


def test_flagging_an_already_low_arc_still_records_the_decision(db, log):
    """The bug's second half. Flagging was only a confidence drop, so an arc already at
    low produced a refused no-op -- no row in `edits`, nothing for pending() to match on,
    and the arc came back anyway. The reason is written first, and always."""
    aid = add_arc(db, "vault", "FROM THE VAULT")
    db.execute("UPDATE arcs SET confidence='low' WHERE id=?", (aid,))
    db.commit()

    got = arcname.record(db, [{"arcId": aid, "noCommonSubject": True,
                               "reason": "rerun branding, not a story"}],
                         decisions_path=log)
    assert got["flagged"] == 1
    assert db.execute("SELECT description FROM arcs WHERE id=?",
                      (aid,)).fetchone()[0] == "rerun branding, not a story"
    assert arcname.pending(db) == []


def test_flagging_the_same_arc_twice_with_the_same_reason_is_reported(db, log):
    """Not silently counted as a fresh decision -- that is how a loop looks like progress."""
    aid = add_arc(db, "vault", "FROM THE VAULT")
    arcname.record(db, [{"arcId": aid, "noCommonSubject": True, "reason": "same"}],
                   decisions_path=log)
    got = arcname.record(db, [{"arcId": aid, "noCommonSubject": True, "reason": "same"}],
                         decisions_path=log)
    assert got["flagged"] == 0 and got["skipped"]


def test_the_reason_reaches_a_reviewer(db, log):
    """A flag routes the arc to a human. Arriving without the reason wastes the trip."""
    aid = add_arc(db, "trailer", "Trailer")
    arcname.record(db, [{"arcId": aid, "noCommonSubject": True,
                         "reason": "six trailers for unrelated seasons"}], decisions_path=log)
    assert "unrelated seasons" in db.execute(
        "SELECT description FROM arcs WHERE id=?", (aid,)).fetchone()[0]
