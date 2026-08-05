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


# --- the change sheet's quick picks -----------------------------------------------


@pytest.fixture
def db_likely():
    """A show with one doubtful episode, an escalation-demoted secondary, and a shelf
    of other primaries on the same show to fill from -- including a dead one, which
    must never be offered."""
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    migrations.apply_all(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("INSERT INTO themes (id, slug, name) VALUES (1,'true-crime','True Crime')")
    subjects = [
        (1, "grief", "Grief"), (2, "heist-and-robbery", "The Job"),
        (3, "organised-crime", "Organised Crime"), (4, "subject-four", "Subject Four"),
        (5, "subject-five", "Subject Five"), (6, "subject-six", "Subject Six"),
        (7, "subject-seven", "Subject Seven"),
    ]
    for sid, slug, name in subjects:
        conn.execute("INSERT INTO subjects (id, slug, name, description, theme_id) "
                     "VALUES (?,?,?,'def',1)", (sid, slug, name))
    conn.execute("UPDATE subjects SET deleted_at='2026-08-01' WHERE id=6")
    conn.execute("INSERT INTO shows (id, slug, title, feed_url, include_verdict, why) "
                 "VALUES (1,'s-town','S-Town','http://f','keep','x')")
    for i in range(1, 9):
        conn.execute("INSERT INTO episodes (id, show_id, guid, title, description, "
                     "published_at) VALUES (?,1,?,?,?,?)",
                     (i, f"g{i}", f"Chapter {i}", "desc", f"2017-03-0{i}"))

    # Episode 1: the card under review. Primary is grief at 1 of 3 agreed.
    conn.execute("INSERT INTO episode_labels (episode_id, subject_id, run_id, role, "
                "confidence, agreement, votes, model, at) VALUES "
                "(1,1,?,'primary','low',1,3,'claude-sonnet-5','2026-08-01T00:00:00+00:00')",
                (RUN,))
    # A secondary that escalation demoted -- a voter reached for it, so it is a real
    # contender and must outrank the show shelf.
    conn.execute("INSERT INTO episode_labels (episode_id, subject_id, run_id, role, "
                "confidence, agreement, votes, model, at) VALUES "
                "(1,2,?,'secondary','low',1,3,'claude-sonnet-5','2026-08-01T00:00:00+00:00')",
                (RUN,))
    # A secondary with no vote behind it -- never escalation evidence, must not appear.
    conn.execute("INSERT INTO episode_labels (episode_id, subject_id, run_id, role, "
                "confidence, agreement, votes, model, at) VALUES "
                "(1,3,?,'secondary','low',NULL,NULL,'claude-sonnet-5',"
                "'2026-08-01T00:00:00+00:00')", (RUN,))

    # The show's shelf: subject-four used twice, subject-five once, the dead
    # subject-six twice (must be excluded), subject-seven once.
    shelf = [(2, 4), (3, 4), (4, 5), (5, 6), (6, 6), (7, 7)]
    for eid, sid in shelf:
        conn.execute("INSERT INTO episode_labels (episode_id, subject_id, run_id, role, "
                     "confidence, model, at) VALUES (?,?,?,'primary','high',"
                     "'claude-sonnet-5','2026-08-01T00:00:00+00:00')", (eid, sid, RUN))
    conn.commit()
    yield conn
    conn.close()


def test_likely_leads_with_the_current_primary(db_likely):
    card = labelqueue.next_card(db_likely)
    assert card["likely"][0] == {
        "slug": "grief", "name": "Grief", "note": "1 vote · the current label"}


def test_likely_ranks_the_escalation_demoted_secondary_next(db_likely):
    card = labelqueue.next_card(db_likely)
    assert card["likely"][1] == {
        "slug": "heist-and-robbery", "name": "The Job", "note": "1 vote"}


def test_likely_excludes_a_secondary_with_no_vote(db_likely):
    card = labelqueue.next_card(db_likely)
    slugs = [p["slug"] for p in card["likely"]]
    assert "organised-crime" not in slugs


def test_likely_fills_from_the_show_shelf_most_used_first(db_likely):
    card = labelqueue.next_card(db_likely)
    shelf = [p for p in card["likely"] if "this show" in p["note"]]
    assert shelf[0] == {"slug": "subject-four", "name": "Subject Four",
                        "note": "this show ×2"}


def test_likely_excludes_a_dead_subject_from_the_shelf(db_likely):
    card = labelqueue.next_card(db_likely)
    slugs = [p["slug"] for p in card["likely"]]
    assert "subject-six" not in slugs


def test_likely_is_capped_at_five(db_likely):
    card = labelqueue.next_card(db_likely)
    assert len(card["likely"]) == 5


def test_likely_never_repeats_a_slug(db_likely):
    card = labelqueue.next_card(db_likely)
    slugs = [p["slug"] for p in card["likely"]]
    assert len(slugs) == len(set(slugs))
