"""The fit assessment, and the bug that made it worth testing hard.

A model judged 25 shows and `record` reported "25 written, 0 skipped". Nothing had been
written: the fit_* fields were not on the write path's allow-list, every edit was
correctly refused, and record() caught the refusal, did nothing, and counted it a
success anyway. Silent loss is the one failure the single write path exists to prevent,
so it gets the most tests here.
"""

import json
import sqlite3
from pathlib import Path

import pytest

from admin.api import edits, fit
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


def add(conn, slug, title, episodes=0, verdict="unreviewed"):
    sid = conn.execute(
        "INSERT INTO shows (slug, title, feed_url, include_verdict, description) "
        "VALUES (?,?,?,?,?)", (slug, title, f"http://{slug}", verdict, "a show")).lastrowid
    for i in range(episodes):
        conn.execute("INSERT INTO episodes (show_id, guid, title, published_at) VALUES (?,?,?,?)",
                     (sid, f"{slug}-{i}", f"{title} {i}", f"2026-01-{i+1:02d}"))
    conn.commit()
    return sid


GOOD = {"verdict": "narrative", "confidence": "high", "reason": "Numbered multi-part runs."}


# --- the silent-loss bug ---------------------------------------------------------


def test_the_fit_fields_are_actually_writable():
    """The bug in one line: they were not, so every write was refused."""
    allowed = edits.WRITABLE["show"][1]
    assert {"fit_verdict", "fit_confidence", "fit_reason",
            "fit_checked_at", "fit_model"} <= allowed


def test_a_recorded_verdict_reaches_the_database(db, log):
    sid = add(db, "a", "A")
    out = fit.record(db, [{"id": sid, **GOOD}], model="claude-sonnet-5", decisions_path=log)
    assert out == {"written": 1, "skipped": [], "remaining": 0}
    row = db.execute("SELECT fit_verdict, fit_confidence, fit_reason, fit_model, "
                     "fit_checked_at FROM shows WHERE id=?", (sid,)).fetchone()
    assert row[0] == "narrative" and row[1] == "high" and row[3] == "claude-sonnet-5"
    assert row[2] and row[4]


def test_a_refused_write_is_reported_not_counted(db, log, monkeypatch):
    """The exact failure: refuse the write, and record must say so rather than claim it
    worked."""
    sid = add(db, "a", "A")
    narrowed = dict(edits.WRITABLE)
    narrowed["show"] = ("shows", {"title"})       # fit_* no longer permitted
    monkeypatch.setattr(edits, "WRITABLE", narrowed)

    out = fit.record(db, [{"id": sid, **GOOD}], model="m", decisions_path=log)
    assert out["written"] == 0
    assert out["skipped"] and "refused" in out["skipped"][0]
    assert db.execute("SELECT fit_verdict FROM shows WHERE id=?", (sid,)).fetchone()[0] is None


def test_recording_the_same_verdict_twice_is_not_an_error(db, log):
    """Only "already that value" is survivable, and it must stay survivable."""
    sid = add(db, "a", "A")
    fit.record(db, [{"id": sid, **GOOD}], model="m", decisions_path=log)
    again = fit.record(db, [{"id": sid, **GOOD}], model="m", decisions_path=log)
    assert again["written"] == 1 and again["skipped"] == []


# --- what it refuses -------------------------------------------------------------


@pytest.mark.parametrize("bad", [
    {"verdict": "good", "confidence": "high", "reason": "x"},
    {"verdict": "narrative", "confidence": "certain", "reason": "x"},
    {"verdict": "narrative", "confidence": "high", "reason": "   "},
])
def test_a_malformed_verdict_is_skipped_with_a_reason(db, log, bad):
    sid = add(db, "a", "A")
    out = fit.record(db, [{"id": sid, **bad}], model="m", decisions_path=log)
    assert out["written"] == 0 and len(out["skipped"]) == 1
    assert db.execute("SELECT fit_verdict FROM shows WHERE id=?", (sid,)).fetchone()[0] is None


def test_a_verdict_with_no_reason_is_refused(db, log):
    """A verdict you cannot review is one you can only trust."""
    sid = add(db, "a", "A")
    out = fit.record(db, [{"id": sid, "verdict": "talk", "confidence": "high"}],
                     model="m", decisions_path=log)
    assert "no reason" in out["skipped"][0]


def test_a_very_long_reason_is_trimmed_not_rejected(db, log):
    sid = add(db, "a", "A")
    fit.record(db, [{"id": sid, "verdict": "talk", "confidence": "low",
                     "reason": "x" * 500}], model="m", decisions_path=log)
    assert len(db.execute("SELECT fit_reason FROM shows WHERE id=?", (sid,)).fetchone()[0]) <= 240


# --- the batch -------------------------------------------------------------------


def test_pending_offers_only_undecided_unassessed_shows(db, log):
    a = add(db, "a", "A")
    add(db, "kept", "Kept", verdict="keep")
    assessed = add(db, "done", "Done")
    fit.record(db, [{"id": assessed, **GOOD}], model="m", decisions_path=log)

    assert [s["id"] for s in fit.pending(db)] == [a]


def test_remaining_falls_by_what_was_assessed(db, log):
    ids = [add(db, f"s{i}", f"S{i}") for i in range(5)]
    assert fit.remaining(db) == 5
    fit.record(db, [{"id": i, **GOOD} for i in ids[:3]], model="m", decisions_path=log)
    assert fit.remaining(db) == 2


def test_the_batch_carries_what_the_judgement_needs(db):
    add(db, "a", "A Show", episodes=20)
    item = fit.pending(db)[0]
    assert item["title"] == "A Show"
    assert len(item["recentEpisodes"]) == fit.EPISODE_SAMPLE   # newest first, capped
    assert item["recentEpisodes"][0] == "A Show 19"
    assert "description" in item and "curatorNote" in item


def test_the_assessment_is_not_the_verdict(db, log):
    """include_verdict stays the human's. A model fills fit_verdict and nothing else."""
    sid = add(db, "a", "A")
    fit.record(db, [{"id": sid, "verdict": "talk", "confidence": "high",
                     "reason": "all guest names"}], model="m", decisions_path=log)
    assert db.execute(
        "SELECT include_verdict FROM shows WHERE id=?", (sid,)).fetchone()[0] == "unreviewed"


def test_every_assessment_is_attributed_and_undoable(db, log):
    sid = add(db, "a", "A")
    fit.record(db, [{"id": sid, **GOOD}], model="m", decisions_path=log)
    actors = {r[0] for r in db.execute("SELECT actor FROM edits")}
    assert actors == {"agent:fit"}
    assert log.exists()


def test_slices_are_disjoint_and_cover_everything(db):
    """Several agents at once. An OFFSET would not work -- the set shrinks as verdicts
    land, so every agent's window would slide over the same shows."""
    ids = {add(db, f"s{i}", f"S{i}") for i in range(40)}
    seen, n = [], 4
    for i in range(n):
        seen += [s["id"] for s in fit.pending(db, limit=100, slice_of=(i, n))]
    assert sorted(seen) == sorted(ids)
    assert len(seen) == len(set(seen))
