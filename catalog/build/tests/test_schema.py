"""The schema's constraints must reject bad data, not merely document that it's bad.

A CHECK that isn't exercised is a comment. These tests are the difference between
"the two-level promise is enforced by the database" and "we remembered to be careful."
"""

import sqlite3
from pathlib import Path

import pytest

SCHEMA = Path(__file__).resolve().parents[2] / "schema.sql"


@pytest.fixture
def db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    conn.execute("PRAGMA foreign_keys = ON")
    yield conn
    conn.close()


@pytest.fixture
def seeded(db):
    """One theme and one show, so child rows have something to point at."""
    db.execute(
        "INSERT INTO themes (id, slug, name) VALUES (1, 'political-scandal', 'Political Scandal')"
    )
    db.execute("INSERT INTO shows (id, slug, title, feed_url) VALUES (1, 's', 'S', 'http://f')")
    db.commit()
    return db


def test_schema_applies_cleanly(db):
    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert {
        "shows", "episodes", "arcs", "themes", "subjects", "episode_subjects",
        "entities", "edges", "edits", "releases",
    } <= tables


def test_fts5_is_available(db):
    # FTS5 is compiled in on most builds but not all; failing here early beats failing
    # after a 27k-row insert.
    assert db.execute("SELECT 1 FROM search WHERE 0").fetchall() == []


# --- vocabulary: themes and subjects ------------------------------------------


def test_a_theme_needs_no_parent(db):
    db.execute("INSERT INTO themes (id, slug, name) VALUES (1, 't', 'T')")


def test_a_subject_without_a_theme_is_rejected(seeded):
    """The two-level promise. Now just a NOT NULL foreign key rather than a CHECK."""
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute("INSERT INTO subjects (id, slug, name) VALUES (1, 'orphan', 'Orphan')")


def test_a_subject_pointing_at_a_missing_theme_is_rejected(seeded):
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO subjects (id, slug, name, theme_id) VALUES (1, 's', 'S', 999)"
        )


def test_the_same_slug_may_be_a_theme_and_a_subject(seeded):
    """Five real slugs do this -- political-scandal, institutional-coverup,
    police-misconduct, wrongful-conviction, family-secret. Separate tables make it
    natural; the single-table version needed a composite key to allow it."""
    seeded.execute(
        "INSERT INTO subjects (id, slug, name, theme_id) "
        "VALUES (1, 'political-scandal', 'The Scandal That Broke', 1)"
    )
    assert seeded.execute("SELECT count(*) FROM themes WHERE slug='political-scandal'").fetchone()[0] == 1
    assert seeded.execute("SELECT count(*) FROM subjects WHERE slug='political-scandal'").fetchone()[0] == 1


def test_theme_slugs_are_unique(seeded):
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute("INSERT INTO themes (id, slug, name) VALUES (2, 'political-scandal', 'Dupe')")


def test_subject_slugs_are_unique(seeded):
    seeded.execute("INSERT INTO subjects (id, slug, name, theme_id) VALUES (1, 'x', 'X', 1)")
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute("INSERT INTO subjects (id, slug, name, theme_id) VALUES (2, 'x', 'Dupe', 1)")


def test_episode_subjects_reject_a_bad_role(seeded):
    seeded.execute("INSERT INTO subjects (id, slug, name, theme_id) VALUES (1, 'x', 'X', 1)")
    seeded.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (1, 1, 'g', 'E')")
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO episode_subjects (episode_id, subject_id, role, confidence) "
            "VALUES (1, 1, 'tertiary', 'high')"
        )


# --- shows ----------------------------------------------------------------------


def test_feed_url_is_unique(seeded):
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO shows (id, slug, title, feed_url) VALUES (2, 's2', 'S2', 'http://f')"
        )


@pytest.mark.parametrize("depth", [0, 5, 9])
def test_depth_stays_in_range(seeded, depth):
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO shows (id, slug, title, feed_url, depth) VALUES (2, 's2', 'S2', 'http://f2', ?)",
            (depth,),
        )


def test_include_verdict_is_constrained(seeded):
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO shows (id, slug, title, feed_url, include_verdict) "
            "VALUES (2, 's2', 'S2', 'http://f2', 'maybe')"
        )


# --- episodes -------------------------------------------------------------------


def test_guid_is_unique_within_a_show(seeded):
    seeded.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (1, 1, 'g', 'E')")
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (2, 1, 'g', 'E2')")


def test_the_same_guid_may_repeat_across_shows(seeded):
    """GUIDs are only unique within a feed. Two publishers can and do collide."""
    seeded.execute("INSERT INTO shows (id, slug, title, feed_url) VALUES (2, 's2', 'S2', 'http://f2')")
    seeded.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (1, 1, 'g', 'E')")
    seeded.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (2, 2, 'g', 'E elsewhere')")
    assert seeded.execute("SELECT count(*) FROM episodes WHERE guid = 'g'").fetchone()[0] == 2


def test_episode_needs_a_real_show(seeded):
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (1, 999, 'g', 'E')")


def test_available_is_boolean(seeded):
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO episodes (id, show_id, guid, title, available) VALUES (1, 1, 'g', 'E', 7)"
        )


def test_available_defaults_to_present(seeded):
    seeded.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (1, 1, 'g', 'E')")
    assert seeded.execute("SELECT available FROM episodes WHERE id = 1").fetchone()[0] == 1


# --- arcs and edges -------------------------------------------------------------


def test_arc_kind_is_constrained(seeded):
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO arcs (id, show_id, slug, kind, name, source) "
            "VALUES (1, 1, 'a', 'season', 'A', 'gold')"
        )


def test_arc_source_is_constrained(seeded):
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO arcs (id, show_id, slug, kind, name, source) "
            "VALUES (1, 1, 'a', 'arc', 'A', 'vibes')"
        )


def test_an_edge_must_be_able_to_explain_itself(seeded):
    """`why` is the sentence the UI shows. An edge that can't produce one shouldn't exist."""
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO edges (src_type, src_id, dst_type, dst_id, kind, why) "
            "VALUES ('show', 1, 'show', 1, 'x', NULL)"
        )


def test_no_column_can_reach_an_audio_file(db):
    """Audio belongs to the show's host, resolved from the live feed at play time.

    Checked against real column names rather than the file text, so the schema stays
    free to explain in a comment *why* it holds no enclosure URL.
    """
    offenders = []
    for (table,) in db.execute("SELECT name FROM sqlite_master WHERE type='table'"):
        for col in db.execute(f"PRAGMA table_info({table})"):
            name = col[1].lower()
            if "audio" in name or "enclosure" in name or name == "media_url":
                offenders.append(f"{table}.{col[1]}")
    assert offenders == [], f"catalog must not store audio locations: {offenders}"
