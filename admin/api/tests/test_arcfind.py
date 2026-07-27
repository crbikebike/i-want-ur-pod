"""Finding stories in shows whose titles carry no pattern.

The bakeoff was blunt about why these need a reader: 218 of 220 misses are "zero members
detected" -- the parser never clusters those episodes at all. What is left is a judgement
about what episodes are about, not about how they are punctuated.
"""

import sqlite3
from pathlib import Path

import pytest

from admin.api import arcfind
from catalog.build import migrations

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "catalog/schema.sql"


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


def add_show(conn, slug="floodlines", title="Floodlines", eps=4, verdict="keep"):
    cur = conn.execute(
        "INSERT INTO shows (slug, title, feed_url, include_verdict, why, description) "
        "VALUES (?,?,?,?,'x','a show about a thing')", (slug, title, f"http://{slug}", verdict))
    sid = cur.lastrowid
    for i in range(eps):
        conn.execute(
            "INSERT INTO episodes (show_id, guid, title, description, published_at) "
            "VALUES (?,?,?,?,?)",
            (sid, f"{slug}-{i}", ["Antediluvian", "The Bridge", "Exodus", "Through the Roof"][i % 4],
             "<p>New Orleans, 2005.</p>", f"2024-01-0{i+1}"))
    conn.commit()
    return sid


def find(sid, arcs, eps=4):
    return {"showId": sid, "episodesRead": eps, "arcs": arcs}


def arc(name, members, **kw):
    return {"name": name, "members": members, "kind": kw.pop("kind", "arc"),
            "confidence": kw.pop("confidence", "medium"), **kw}


# --- what gets offered -----------------------------------------------------------


def test_only_shows_with_no_arcs_are_offered(db):
    a = add_show(db, "has-arcs", "Has Arcs")
    db.execute("INSERT INTO arcs (show_id, slug, kind, name, source) "
               "VALUES (?,'x','arc','A Real Story','llm')", (a,))
    add_show(db, "bare", "Bare")
    db.commit()
    assert [s["slug"] for s in arcfind.pending(db, limit=9)] == ["bare"]


def test_cut_shows_are_not_offered(db):
    add_show(db, "gone", "Gone", verdict="cut")
    assert arcfind.pending(db) == []


def test_episodes_arrive_oldest_first(db):
    """A story reads in the order it was told, and 'does this continue that' is the whole
    question."""
    add_show(db)
    eps = arcfind.pending(db)[0]["episodes"]
    assert [e["published"] for e in eps] == sorted(e["published"] for e in eps)


def test_a_long_feed_says_how_much_was_withheld(db):
    """No silent caps. 'Found nothing in all of it' and 'found nothing in the half we
    read' are different answers."""
    add_show(db, "big", "Big", eps=arcfind.EPISODE_CAP + 40)
    got = arcfind.pending(db)[0]
    assert got["episodeCount"] == arcfind.EPISODE_CAP + 40
    assert got["episodesShown"] == arcfind.EPISODE_CAP


def test_the_smallest_show_comes_first(db):
    """A 3-episode limited series is one glance. Clearing those makes the queue visibly
    shorten instead of opening on a 500-episode wall."""
    add_show(db, "big", "Big", eps=30)
    add_show(db, "small", "Small", eps=3)
    assert [s["slug"] for s in arcfind.pending(db, limit=2)] == ["small", "big"]


# --- recording -------------------------------------------------------------------


def test_a_found_arc_is_written_and_the_show_marked_read(db, log):
    sid = add_show(db)
    got = arcfind.record(db, [find(sid, [arc("The Flooding of New Orleans",
                                             ["floodlines-0", "floodlines-1", "floodlines-2"])])],
                         decisions_path=log)
    assert got["arcs"] == 1 and got["showsRead"] == 1
    assert db.execute("SELECT count(*) FROM arcs").fetchone()[0] == 1
    assert db.execute("SELECT arcs_checked_at FROM shows WHERE id=?", (sid,)).fetchone()[0]
    assert arcfind.pending(db) == []


def test_no_arcs_is_a_real_answer_and_is_remembered(db, log):
    """Most of these shows are anthologies. Without recording it, the next pass reads them
    all again -- the loop the naming queue hit."""
    sid = add_show(db)
    got = arcfind.record(db, [find(sid, [])], decisions_path=log)
    assert got["showsWithNoArcs"] == 1 and got["arcs"] == 0
    assert arcfind.pending(db) == []
    assert arcfind.remaining(db) == 0


def test_how_much_was_read_is_recorded(db, log):
    sid = add_show(db, eps=300)
    arcfind.record(db, [find(sid, [], eps=250)], decisions_path=log)
    assert db.execute("SELECT arcs_checked_eps FROM shows WHERE id=?", (sid,)).fetchone()[0] == 250


# --- what gets refused -----------------------------------------------------------


@pytest.mark.parametrize("name", ["Season 1", "Part 3", "Bonus", "Floodlines", "42"])
def test_a_name_that_says_nothing_is_refused(db, log, name):
    """The bar Job 2 set. Accepting "Season 1" here would recreate by hand the exact
    problem that pass just finished fixing."""
    sid = add_show(db)
    got = arcfind.record(db, [find(sid, [arc(name, ["floodlines-0", "floodlines-1"])])],
                         decisions_path=log)
    assert got["arcs"] == 0 and got["skipped"]


def test_a_refused_show_is_not_marked_read(db, log):
    """Otherwise a rejected batch looks like a show with no stories in it, and is never
    offered again."""
    sid = add_show(db)
    arcfind.record(db, [find(sid, [arc("Season 1", ["floodlines-0", "floodlines-1"])])],
                   decisions_path=log)
    assert db.execute("SELECT arcs_checked_at FROM shows WHERE id=?", (sid,)).fetchone()[0] is None
    assert len(arcfind.pending(db)) == 1


def test_an_arc_claiming_the_whole_feed_is_refused(db, log):
    """Past 24 episodes it is a recurring segment or the show itself, not a story."""
    sid = add_show(db, eps=40)
    got = arcfind.record(db, [find(sid, [arc("Everything", [f"floodlines-{i}" for i in range(40)])])],
                         decisions_path=log)
    assert got["arcs"] == 0 and "past" in got["skipped"][0]


def test_a_two_episode_minimum(db, log):
    sid = add_show(db)
    got = arcfind.record(db, [find(sid, [arc("A Lone Thing", ["floodlines-0"])])],
                         decisions_path=log)
    assert got["arcs"] == 0 and "fewer than two" in got["skipped"][0]


@pytest.mark.parametrize("bad", [{"kind": "season"}, {"confidence": "certain"}])
def test_vocabulary_is_policed(db, log, bad):
    sid = add_show(db)
    got = arcfind.record(db, [find(sid, [arc("A Real Story", ["floodlines-0", "floodlines-1"], **bad)])],
                         decisions_path=log)
    assert got["arcs"] == 0 and got["skipped"]


def test_a_series_is_allowed_where_the_whole_show_is_one_story(db, log):
    """Phase 1 only ever produced 'arc'. A three-episode limited series is a 'series'."""
    sid = add_show(db, eps=3)
    got = arcfind.record(db, [find(sid, [arc("The Laramie Murder", ["floodlines-0", "floodlines-1"],
                                             kind="series")])], decisions_path=log)
    assert got["arcs"] == 1
    assert db.execute("SELECT kind FROM arcs").fetchone()[0] == "series"


def test_an_unknown_show_is_reported(db, log):
    got = arcfind.record(db, [find(9999, [])], decisions_path=log)
    assert got["skipped"] == ["9999: no such show"]
