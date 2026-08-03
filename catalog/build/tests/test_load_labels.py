"""The half of the round-trip that was missing until 2026-08-01.

`export_labels` wrote 275 files and nothing read them, so a rebuild from a clean checkout
produced the July labels while looking entirely healthy. These tests pin the reading half.
"""

from __future__ import annotations

import json
import sqlite3

import pytest

from catalog.build import load_labels


RUN = "2026-07-relabel-v176"


@pytest.fixture()
def conn():
    conn = sqlite3.connect(":memory:")
    conn.executescript(
        """
        CREATE TABLE shows (id INTEGER PRIMARY KEY, slug TEXT UNIQUE);
        CREATE TABLE episodes (id INTEGER PRIMARY KEY, show_id INTEGER, guid TEXT,
                               deleted_at TEXT);
        CREATE TABLE subjects (id INTEGER PRIMARY KEY, slug TEXT UNIQUE);
        CREATE TABLE entities (id INTEGER PRIMARY KEY, slug TEXT UNIQUE, name TEXT,
                               kind TEXT);
        CREATE TABLE episode_labels (episode_id INTEGER, subject_id INTEGER, run_id TEXT,
                                     role TEXT, confidence TEXT, agreement INTEGER,
                                     votes INTEGER, model TEXT, at TEXT,
                                     PRIMARY KEY (episode_id, subject_id, run_id));
        CREATE TABLE episode_entities (episode_id INTEGER, entity_id INTEGER, run_id TEXT,
                                       confidence TEXT, at TEXT,
                                       PRIMARY KEY (episode_id, entity_id, run_id));
        INSERT INTO shows VALUES (1, 'a-show'), (2, 'other-show');
        INSERT INTO episodes VALUES (10, 1, 'guid-1', NULL), (11, 1, 'guid-2', NULL),
                                    (20, 2, 'guid-1', NULL);
        INSERT INTO subjects VALUES (5, 'space-exploration'), (6, 'unsolved-murder');
        """
    )
    return conn


def write(tmp_path, payload):
    directory = tmp_path / "episode-labels"
    directory.mkdir(exist_ok=True)
    (directory / f"{payload['slug']}.json").write_text(
        json.dumps(payload), encoding="utf-8")
    return tmp_path


def test_a_label_lands_on_the_episode_with_that_guid_in_that_show(conn, tmp_path):
    source = write(tmp_path, {
        "slug": "a-show", "run": RUN,
        "episodes": [{"guid": "guid-2", "subjects": [
            {"subject": "space-exploration", "role": "primary", "confidence": "high",
             "model": "claude-sonnet-5", "at": "2026-08-01T00:00:00+00:00"}]}],
    })
    report = load_labels.load(conn, source)

    assert report.label_rows == 1
    assert conn.execute(
        "SELECT episode_id, subject_id, run_id, role, confidence, model, at "
        "FROM episode_labels").fetchall() == [
        (11, 5, RUN, "primary", "high", "claude-sonnet-5", "2026-08-01T00:00:00+00:00")]


def test_a_guid_shared_across_shows_does_not_cross_over(conn, tmp_path):
    """1,264 guids repeat across the catalog because shows share feeds. A catalog-wide
    guid map would hang this label on the wrong programme."""
    source = write(tmp_path, {
        "slug": "other-show", "run": RUN,
        "episodes": [{"guid": "guid-1", "subjects": [
            {"subject": "unsolved-murder", "role": "primary", "confidence": "medium"}]}],
    })
    load_labels.load(conn, source)

    assert conn.execute("SELECT episode_id FROM episode_labels").fetchall() == [(20,)]


def test_at_comes_from_the_file_so_a_rebuild_is_reproducible(conn, tmp_path):
    """`at` is inside the content hash. Stamping a fresh time per row would make every
    rebuild differ from the last for a reason that is not the catalog changing."""
    source = write(tmp_path, {
        "slug": "a-show", "run": RUN,
        "episodes": [{"guid": "guid-1", "subjects": [
            {"subject": "space-exploration", "role": "primary", "confidence": "low",
             "at": "2026-07-28T12:00:00+00:00"}]}],
    })
    load_labels.load(conn, source)

    assert conn.execute("SELECT at FROM episode_labels").fetchone()[0] == \
        "2026-07-28T12:00:00+00:00"


def test_loading_twice_is_a_no_op(conn, tmp_path):
    source = write(tmp_path, {
        "slug": "a-show", "run": RUN,
        "episodes": [{"guid": "guid-1", "subjects": [
            {"subject": "space-exploration", "role": "primary", "confidence": "high"}]}],
    })
    load_labels.load(conn, source)
    load_labels.load(conn, source)

    assert conn.execute("SELECT count(*) FROM episode_labels").fetchone()[0] == 1


def test_an_entity_is_created_once_and_keyed_on_name_and_kind(conn, tmp_path):
    """Enron the company and Enron the film are different things."""
    source = write(tmp_path, {
        "slug": "a-show", "run": RUN,
        "episodes": [
            {"guid": "guid-1", "subjects": [], "entities": [
                {"name": "Enron", "kind": "company", "confidence": "high"},
                {"name": "Enron", "kind": "work", "confidence": "low"}]},
            {"guid": "guid-2", "subjects": [], "entities": [
                {"name": "Enron", "kind": "company", "confidence": "medium"}]},
        ],
    })
    report = load_labels.load(conn, source)

    assert report.entities_created == 2
    assert report.entity_rows == 3
    kinds = dict(conn.execute("SELECT slug, kind FROM entities"))
    assert kinds == {"company:enron": "company", "work:enron": "work"}


def test_an_unknown_subject_slug_is_reported_not_raised(conn, tmp_path):
    """A file written against a newer vocabulary must not abort the whole build."""
    source = write(tmp_path, {
        "slug": "a-show", "run": RUN,
        "episodes": [{"guid": "guid-1", "subjects": [
            {"subject": "not-a-real-subject", "role": "primary", "confidence": "high"},
            {"subject": "space-exploration", "role": "secondary", "confidence": "high"}]}],
    })
    report = load_labels.load(conn, source)

    assert report.unknown_subjects == {"not-a-real-subject": 1}
    assert report.label_rows == 1


def test_a_guid_the_catalog_does_not_have_is_counted_per_show(conn, tmp_path):
    source = write(tmp_path, {
        "slug": "a-show", "run": RUN,
        "episodes": [{"guid": "guid-missing", "subjects": [
            {"subject": "space-exploration", "role": "primary", "confidence": "high"}]}],
    })
    report = load_labels.load(conn, source)

    assert report.unmatched_guids == {"a-show": 1}
    assert report.label_rows == 0


def test_the_run_id_comes_from_the_file_so_runs_stay_separate(conn, tmp_path):
    """Three runs coexist in this table. A loader that hardcoded CURRENT_RUN would
    relabel the July pass as the current one on the way in."""
    source = write(tmp_path, {
        "slug": "a-show", "run": "2026-07-theming",
        "episodes": [{"guid": "guid-1", "subjects": [
            {"subject": "space-exploration", "role": "primary", "confidence": "high"}]}],
    })
    load_labels.load(conn, source)

    assert conn.execute("SELECT run_id FROM episode_labels").fetchone()[0] == \
        "2026-07-theming"


def test_a_missing_directory_is_reported_not_crashed(conn, tmp_path):
    report = load_labels.load(conn, tmp_path)

    assert report.missing_dir is True
    assert report.lines() == ["episode-labels/ is not present -- no run to load"]
