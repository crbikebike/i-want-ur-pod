"""Labelling episodes with subjects and entities.

The pass this replaces showed its model 150 characters of each description and never asked
twice, so `agreement` is NULL on all 43,818 rows it wrote. Everything here is about not
repeating that: full text in, votes recorded, and nothing quietly repaired.
"""

import json
import sqlite3
from pathlib import Path

import pytest

from admin.api import label
from catalog.build import migrations

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "catalog/schema.sql"


@pytest.fixture
def db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    migrations.apply_all(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("INSERT INTO themes (id, slug, name) VALUES (1,'true-crime','True Crime')")
    for i, (slug, name) in enumerate(
            [("grief", "Living With Loss"), ("wrongful-conviction", "Convicted Anyway"),
             ("how-reported", "How the Reporting Was Done")], start=1):
        conn.execute("INSERT INTO subjects (id, slug, name, description, theme_id) "
                     "VALUES (?,?,?,?,1)", (i, slug, name, f"what {slug} covers"))
    conn.execute("INSERT INTO shows (id, slug, title, feed_url, include_verdict, why) "
                 "VALUES (1,'s-town','S-Town','http://f','keep','x')")
    for i in range(1, 4):
        conn.execute("INSERT INTO episodes (id, show_id, guid, title, description, published_at) "
                     "VALUES (?,1,?,?,?,?)", (i, f"g{i}", f"Chapter {i}",
                                              "<p>A death in Alabama.</p>", f"2017-03-0{i}"))
    conn.commit()
    yield conn
    conn.close()


@pytest.fixture
def log(tmp_path):
    return tmp_path / "decisions.jsonl"


def lab(eid, subjects, entities=None):
    return {"episodeId": eid, "subjects": subjects, "entities": entities or []}


def sub(slug, role="primary", confidence="high", **kw):
    return {"slug": slug, "role": role, "confidence": confidence, **kw}


# --- what gets offered -----------------------------------------------------------


def test_episodes_arrive_with_full_text_and_show_context(db):
    got = label.pending(db)
    assert len(got) == 3
    assert got[0]["description"] == "A death in Alabama."   # markup gone
    assert got[0]["show"] == "S-Town"


def test_an_episodes_arc_travels_with_it(db):
    """Part three of a named investigation is easy to place and ambiguous alone."""
    db.execute("INSERT INTO arcs (id, show_id, slug, kind, name, source) "
               "VALUES (1,1,'ch','arc','The Alabama Murders','llm')")
    db.execute("UPDATE episodes SET arc_id=1 WHERE id=1")
    db.commit()
    assert label.pending(db)[0]["arc"] == "The Alabama Murders"


def test_only_kept_shows_are_labelled(db):
    db.execute("UPDATE shows SET include_verdict='cut'")
    db.commit()
    assert label.pending(db) == [] and label.remaining(db) == 0


def test_an_episode_leaves_the_queue_once_labelled(db, log):
    label.record(db, [lab(1, [sub("grief")])], decisions_path=log)
    assert [e["episodeId"] for e in label.pending(db)] == [2, 3]


def test_the_vocabulary_carries_its_definitions(db):
    """They were written to be read by this pass, and they draw the lines."""
    v = label.vocabulary(db)
    assert len(v) == 3
    assert all(x["definition"] for x in v)


# --- what gets refused -----------------------------------------------------------


def test_exactly_one_primary(db, log):
    got = label.record(db, [lab(1, [sub("grief"), sub("wrongful-conviction")])],
                       decisions_path=log)
    assert got["labelled"] == 0 and "exactly one primary" in got["skipped"][0]

    got = label.record(db, [lab(1, [sub("grief", role="secondary")])], decisions_path=log)
    assert got["labelled"] == 0 and "exactly one primary" in got["skipped"][0]


def test_a_subject_outside_the_vocabulary_is_refused_and_proposed(db, log):
    """The old pipeline aliased near-misses, including one entry that silently dropped the
    row. A slug that is not in the list is a proposal, and proposals go to a queue."""
    got = label.record(db, [lab(1, [sub("grief"), sub("cybercrime", role="secondary")])],
                       decisions_path=log)
    assert got["labelled"] == 0
    assert got["proposed"] == ["cybercrime"]
    row = db.execute("SELECT name, seen, examples FROM subject_proposals").fetchone()
    assert row[0] == "cybercrime" and row[1] == 1
    assert "Chapter 1" in json.loads(row[2])


def test_a_proposal_seen_twice_is_counted_not_duplicated(db, log):
    for eid in (1, 2):
        label.record(db, [lab(eid, [sub("grief"), sub("cybercrime", role="secondary")])],
                     decisions_path=log)
    assert db.execute("SELECT seen FROM subject_proposals").fetchone()[0] == 2


@pytest.mark.parametrize("bad", [{"role": "tertiary"}, {"confidence": "certain"}])
def test_vocabulary_of_role_and_confidence_is_policed(db, log, bad):
    got = label.record(db, [lab(1, [sub("grief", **bad)])], decisions_path=log)
    assert got["labelled"] == 0 and got["skipped"]


def test_more_than_three_subjects_is_refused(db, log):
    got = label.record(db, [lab(1, [sub("grief"),
                                    sub("wrongful-conviction", role="secondary"),
                                    sub("how-reported", role="secondary"),
                                    sub("grief", role="secondary")])], decisions_path=log)
    assert got["labelled"] == 0 and any("subjects" in s for s in got["skipped"])


def test_an_unknown_entity_kind_is_refused(db, log):
    got = label.record(db, [lab(1, [sub("grief")],
                                entities=[{"name": "X", "kind": "vehicle"}])],
                       decisions_path=log)
    assert got["labelled"] == 0 and "vehicle" in got["skipped"][0]


def test_one_bad_episode_does_not_lose_the_good_ones(db, log):
    """A batch of 20 with one malformed answer must not throw away the other 19."""
    got = label.record(db, [lab(1, [sub("grief")]),
                            lab(2, [sub("nope")]),
                            lab(3, [sub("wrongful-conviction")])], decisions_path=log)
    assert got["labelled"] == 2 and len(got["skipped"]) == 1


# --- what gets written -----------------------------------------------------------


def test_votes_are_recorded(db, log):
    """The column the last run left NULL on every row."""
    label.record(db, [lab(1, [sub("grief", agreement=3, votes=3)])], decisions_path=log)
    assert db.execute("SELECT agreement, votes FROM episode_labels").fetchone() == (3, 3)


def test_entities_land_with_their_kind(db, log):
    label.record(db, [lab(1, [sub("grief")], entities=[
        {"name": "Theranos", "kind": "company", "confidence": "high"}])], decisions_path=log)
    assert db.execute("SELECT name, kind FROM entities").fetchone() == ("Theranos", "company")


def test_the_run_is_named_so_the_old_one_survives(db, log):
    label.record(db, [lab(1, [sub("grief")])], decisions_path=log)
    assert db.execute("SELECT DISTINCT run_id FROM episode_labels").fetchone()[0] == label.RUN_ID
