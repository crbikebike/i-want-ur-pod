"""The write path is the workbench's only door. These tests hold it shut.

The promise is that a decision lands in three places or nowhere: the row, the `edits`
table, and decisions.jsonl. Two of three is worse than none, because it looks like it
worked.
"""

import json
import sqlite3
from pathlib import Path

import pytest

from admin.api import edits
from catalog.build import migrations

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "catalog/schema.sql"


@pytest.fixture
def db():
    # Schema *and* migrations, because that is what the running catalog is. A fixture
    # built from schema.sql alone would pass while the real database failed.
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    migrations.apply_all(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("INSERT INTO themes (id, slug, name) VALUES (1, 'true-crime', 'True Crime')")
    conn.execute("INSERT INTO themes (id, slug, name) VALUES (2, 'being-human', 'Being Human')")
    conn.execute(
        "INSERT INTO subjects (id, slug, name, theme_id) VALUES (1, 'grief', 'Living With Loss', 1)")
    conn.execute(
        "INSERT INTO shows (id, slug, title, feed_url, why) "
        "VALUES (1, 's-town', 'S-Town', 'http://f', 'Peabody winner')")
    conn.execute(
        "INSERT INTO arcs (id, show_id, slug, kind, name, source) "
        "VALUES (1, 1, 'ch1', 'arc', 'Chapter One', 'segment')")
    conn.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (1, 1, 'g1', 'Ep One')")
    conn.commit()
    yield conn
    conn.close()


@pytest.fixture
def log(tmp_path):
    return tmp_path / "decisions.jsonl"


def read_log(path):
    if not path.exists():
        return []
    return [json.loads(l) for l in path.read_text().splitlines() if l.strip()]


# --- the three-places promise ---------------------------------------------------


def test_an_edit_lands_in_all_three_places(db, log):
    e = edits.apply(db, entity_type="show", entity_id=1, field="include_verdict",
                    after="keep", decisions_path=log)

    assert db.execute("SELECT include_verdict FROM shows WHERE id=1").fetchone()[0] == "keep"
    logged = db.execute("SELECT entity_key, field, before, after FROM edits WHERE id=?",
                        (e.edit_id,)).fetchone()
    assert logged == ("s-town", "include_verdict", "unreviewed", "keep")
    assert read_log(log)[-1]["after"] == "keep"


def test_edits_key_on_slug_not_integer_id(db, log):
    """Integer ids are assigned at import. An edit recorded against id 42 would land on
    a different row in a database rebuilt from source."""
    e = edits.apply(db, entity_type="theme", entity_id=1, field="name",
                    after="True Crime, Deep-Dive", decisions_path=log)
    assert e.entity_key == "true-crime"
    assert read_log(log)[-1]["key"] == "true-crime"


@pytest.mark.parametrize("entity_type,entity_id,expected", [
    ("show", 1, "s-town"),
    ("theme", 1, "true-crime"),
    ("subject", 1, "grief"),
    ("arc", 1, "s-town/ch1"),
    ("episode", 1, "s-town/g1"),
])
def test_every_entity_has_a_stable_key(db, entity_type, entity_id, expected):
    assert edits.entity_key(db, entity_type, entity_id) == expected


def test_nothing_is_written_when_the_log_cannot_be(db, tmp_path):
    """Two of three is worse than none -- it looks like it worked."""
    unwritable = tmp_path / "nope"
    unwritable.write_text("i am a file, not a directory")

    with pytest.raises(Exception):
        edits.apply(db, entity_type="show", entity_id=1, field="include_verdict",
                    after="cut", decisions_path=unwritable / "decisions.jsonl")

    assert db.execute("SELECT include_verdict FROM shows WHERE id=1").fetchone()[0] == "unreviewed"
    assert db.execute("SELECT count(*) FROM edits").fetchone()[0] == 0


# --- what may be edited ---------------------------------------------------------


@pytest.mark.parametrize("entity_type,field", [
    ("show", "slug"), ("theme", "slug"), ("subject", "slug"),
    ("episode", "guid"), ("arc", "slug"),
])
def test_identity_fields_are_locked(db, log, entity_type, field):
    """Everything references these. Changing one silently orphans whatever points at it."""
    with pytest.raises(edits.EditError, match="not editable"):
        edits.apply(db, entity_type=entity_type, entity_id=1, field=field,
                    after="anything", decisions_path=log)


def test_feed_url_is_editable_because_a_show_can_be_pointed_at_the_wrong_podcast(db, log):
    """It looks like identity but is not. Twenty shows were matched to a different
    podcast sharing their name, and fixing that means changing the feed. Nothing
    references feed_url the way things reference a slug -- episodes hang off show_id --
    and the partial unique index still stops two live shows landing on one feed."""
    edits.apply(db, entity_type="show", entity_id=1, field="feed_url",
                after="http://the-right-one", decisions_path=log)
    assert db.execute(
        "SELECT feed_url FROM shows WHERE id=1").fetchone()[0] == "http://the-right-one"


def test_unknown_entity_kinds_are_refused(db, log):
    with pytest.raises(edits.EditError, match="not editable"):
        edits.apply(db, entity_type="network", entity_id=1, field="name",
                    after="x", decisions_path=log)


def test_a_no_op_edit_is_refused(db, log):
    """Otherwise the log fills with taps that changed nothing."""
    with pytest.raises(edits.EditError, match="already"):
        edits.apply(db, entity_type="show", entity_id=1, field="include_verdict",
                    after="unreviewed", decisions_path=log)


def test_the_schema_still_guards_values(db, log):
    """The write path narrows *which fields*; CHECK constraints still police values."""
    with pytest.raises(sqlite3.IntegrityError):
        edits.apply(db, entity_type="show", entity_id=1, field="include_verdict",
                    after="maybe", decisions_path=log)
    assert db.execute("SELECT count(*) FROM edits").fetchone()[0] == 0


def test_moving_a_subject_to_another_theme(db, log):
    edits.apply(db, entity_type="subject", entity_id=1, field="theme_id",
                after=2, decisions_path=log)
    assert db.execute(
        "SELECT t.slug FROM subjects s JOIN themes t ON t.id=s.theme_id WHERE s.id=1"
    ).fetchone()[0] == "being-human"


# --- undo ------------------------------------------------------------------------


def test_undo_restores_the_previous_value(db, log):
    e = edits.apply(db, entity_type="theme", entity_id=1, field="name",
                    after="Murder Stuff", decisions_path=log)
    edits.undo(db, e.edit_id, decisions_path=log)
    assert db.execute("SELECT name FROM themes WHERE id=1").fetchone()[0] == "True Crime"


def test_undo_is_itself_an_edit(db, log):
    """`edits` is append-only. A log you can rewrite is not a log."""
    e = edits.apply(db, entity_type="theme", entity_id=1, field="name",
                    after="Murder Stuff", decisions_path=log)
    edits.undo(db, e.edit_id, decisions_path=log)
    assert db.execute("SELECT count(*) FROM edits").fetchone()[0] == 2
    assert "undo of edit" in db.execute(
        "SELECT note FROM edits ORDER BY id DESC LIMIT 1").fetchone()[0]
    assert len(read_log(log)) == 2


def test_an_undo_can_be_undone(db, log):
    first = edits.apply(db, entity_type="theme", entity_id=1, field="name",
                        after="Murder Stuff", decisions_path=log)
    second = edits.undo(db, first.edit_id, decisions_path=log)
    edits.undo(db, second.edit_id, decisions_path=log)
    assert db.execute("SELECT name FROM themes WHERE id=1").fetchone()[0] == "Murder Stuff"


def test_undoing_a_missing_edit_says_so(db, log):
    with pytest.raises(edits.EditError, match="no edit"):
        edits.undo(db, 999, decisions_path=log)


# --- the log ---------------------------------------------------------------------


def test_recent_shows_newest_first_and_skips_build_notes(db, log):
    db.execute(
        "INSERT INTO edits (at, actor, entity_type, entity_key, field, after, note) "
        "VALUES ('2026-07-26','agent:migrate','catalog','','duplicate_feeds','[]','import note')")
    db.commit()
    edits.apply(db, entity_type="show", entity_id=1, field="include_verdict",
                after="keep", decisions_path=log)
    edits.apply(db, entity_type="theme", entity_id=1, field="name",
                after="Renamed", decisions_path=log)

    got = edits.recent(db)
    assert [r["field"] for r in got] == ["name", "include_verdict"]
    assert all(r["entity"] != "catalog" for r in got)


def test_the_log_is_append_only_across_many_edits(db, log):
    for verdict in ("keep", "suspect", "cut"):
        edits.apply(db, entity_type="show", entity_id=1, field="include_verdict",
                    after=verdict, decisions_path=log)
    assert [r["after"] for r in read_log(log)] == ["keep", "suspect", "cut"]


# --- soft delete through the one door -------------------------------------------


def test_soft_deleting_is_just_an_edit(db, log):
    """Same audit trail, same undo, no special path."""
    e = edits.apply(db, entity_type="show", entity_id=1, field="deleted_at",
                    after="2026-07-27T00:00:00+00:00", note="dead feed", decisions_path=log)
    assert db.execute("SELECT count(*) FROM shows WHERE deleted_at IS NULL").fetchone()[0] == 0
    assert read_log(log)[-1]["field"] == "deleted_at"

    edits.undo(db, e.edit_id, decisions_path=log)
    assert db.execute("SELECT count(*) FROM shows WHERE deleted_at IS NULL").fetchone()[0] == 1


def test_a_deletion_can_carry_its_reason(db, log):
    edits.apply(db, entity_type="show", entity_id=1, field="deleted_reason",
                after="dead-feed", decisions_path=log)
    assert db.execute("SELECT deleted_reason FROM shows WHERE id=1").fetchone()[0] == "dead-feed"
