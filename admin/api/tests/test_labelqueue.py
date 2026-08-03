"""The label queue: sampled worst-first, decisions through the one door, and a
corrections file the next run's briefs can cite."""

import sqlite3
from pathlib import Path

import pytest

from admin.api import edits, labelqueue
from catalog.build import migrations

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "catalog/schema.sql"
RUN = labelqueue.RUN_ID


@pytest.fixture
def db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    migrations.apply_all(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("INSERT INTO themes (id, slug, name) VALUES (1,'true-crime','True Crime')")
    for i, slug in enumerate(["grief", "heist-and-robbery", "organised-crime"], start=1):
        conn.execute("INSERT INTO subjects (id, slug, name, description, theme_id) "
                     "VALUES (?,?,?,?,1)", (i, slug, slug.title(), "def"))
    conn.execute("INSERT INTO shows (id, slug, title, feed_url, include_verdict, why) "
                 "VALUES (1,'s-town','S-Town','http://f','keep','x')")
    for i in range(1, 4):
        conn.execute("INSERT INTO episodes (id, show_id, guid, title, description, "
                     "published_at) VALUES (?,1,?,?,?,?)",
                     (i, f"g{i}", f"Chapter {i}", "desc", f"2017-03-0{i}"))
    # agreement 1, 2, and NULL (never escalated -- must not be served)
    rows = [(1, 1, 1, "low"), (2, 2, 2, "medium"), (3, 3, None, "high")]
    for eid, sid, agreement, conf in rows:
        conn.execute(
            "INSERT INTO episode_labels (episode_id, subject_id, run_id, role, "
            "confidence, agreement, votes, model, at) VALUES (?,?,?,'primary',?,?,?,"
            "'claude-sonnet-5','2026-08-01T00:00:00+00:00')",
            (eid, sid, RUN, conf, agreement, 3 if agreement else None))
    conn.commit()
    yield conn
    conn.close()


def test_the_worst_agreement_is_served_first(db):
    card = labelqueue.next_card(db)
    assert card["episodeId"] == 1
    assert card["primary"]["agreement"] == 1


def test_an_unescalated_label_is_never_served(db):
    served = set()
    card = labelqueue.next_card(db)
    while card:
        served.add(card["episodeId"])
        card = labelqueue.next_card(db, skipped=list(served))
    assert 3 not in served


def test_counts_reports_no_total_and_no_remaining(db):
    got = labelqueue.counts(db)
    assert "total" not in got and "waiting" not in got and "remaining" not in got


def test_confirm_marks_human_and_stops_serving_that_episode(db, tmp_path):
    labelqueue.decide(db, 1, "confirm",
                      decisions_path=tmp_path / "d.jsonl",
                      corrections_path=tmp_path / "corrections.md")
    row = db.execute(
        "SELECT confidence, model, agreement FROM episode_labels "
        "WHERE episode_id=1 AND role='primary' AND run_id=?", (RUN,)).fetchone()
    assert row == ("high", "human", 1)
    assert labelqueue.next_card(db)["episodeId"] == 2


def test_change_promotes_the_pick_and_demotes_the_machine_read(db, tmp_path):
    labelqueue.decide(db, 1, "change", subject_slug="organised-crime",
                      decisions_path=tmp_path / "d.jsonl",
                      corrections_path=tmp_path / "corrections.md")
    rows = dict(db.execute(
        "SELECT s.slug, l.role FROM episode_labels l JOIN subjects s ON s.id=l.subject_id "
        "WHERE l.episode_id=1 AND l.run_id=?", (RUN,)))
    assert rows == {"organised-crime": "primary", "grief": "secondary"}


def test_change_to_a_dead_subject_is_refused(db, tmp_path):
    db.execute("UPDATE subjects SET deleted_at='2026-08-01' WHERE slug='organised-crime'")
    with pytest.raises(ValueError):
        labelqueue.decide(db, 1, "change", subject_slug="organised-crime",
                          decisions_path=tmp_path / "d.jsonl",
                          corrections_path=tmp_path / "corrections.md")


def test_every_decision_lands_in_corrections_md(db, tmp_path):
    corrections = tmp_path / "corrections.md"
    labelqueue.decide(db, 1, "confirm",
                      decisions_path=tmp_path / "d.jsonl", corrections_path=corrections)
    labelqueue.decide(db, 2, "change", subject_slug="grief",
                      decisions_path=tmp_path / "d.jsonl", corrections_path=corrections)
    text = corrections.read_text()
    assert text.startswith("# Corrections From Review")
    assert "grief -> confirmed" in text
    assert "heist-and-robbery -> grief" in text


def test_decisions_go_through_the_edits_door(db, tmp_path):
    log = tmp_path / "d.jsonl"
    labelqueue.decide(db, 1, "confirm",
                      decisions_path=log, corrections_path=tmp_path / "c.md")
    assert db.execute("SELECT count(*) FROM edits WHERE actor='human:labelqueue'"
                      ).fetchone()[0] == 1
    assert log.exists()
