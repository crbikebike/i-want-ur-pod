"""Re-reading feeds, and the run record that says what happened.

This exists because of a number: the 2026-07 labelling run showed its model **150
characters** of each episode's description, on top of a 299-character storage cap. Every
subject in the catalog was chosen from a sentence and a half. Getting the real text back
is the cheapest quality improvement available, and it has to happen before anything that
costs money per episode.
"""

import sqlite3
from pathlib import Path

import pytest

from admin.api import comb, feeds, runs
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


def add_show(conn, slug, title, verdict="keep", feed=None, eps=2, desc="x" * 299):
    cur = conn.execute(
        "INSERT INTO shows (slug, title, feed_url, include_verdict, why) VALUES (?,?,?,?,?)",
        (slug, title, feed or f"http://{slug}", verdict, "because"))
    sid = cur.lastrowid
    for i in range(eps):
        conn.execute(
            "INSERT INTO episodes (show_id, guid, title, description) VALUES (?,?,?,?)",
            (sid, f"{slug}-{i}", f"{title} ep {i}", desc))
    conn.commit()
    return sid


# --- which shows get read --------------------------------------------------------


def test_cut_shows_are_not_read(db):
    """A cut show is not in the product. Spending a request and a description refresh on
    it buys nothing."""
    add_show(db, "keeper", "Keeper")
    add_show(db, "gone", "Gone", verdict="cut")
    assert [r[1] for r in comb.live_shows(db)] == ["keeper"]


def test_unreviewed_shows_are_read(db):
    """They are still candidates, and judging one needs its real text as much as
    labelling does."""
    add_show(db, "maybe", "Maybe", verdict="unreviewed")
    assert len(comb.live_shows(db)) == 1


def test_soft_deleted_shows_are_not_read(db):
    add_show(db, "a", "A")
    db.execute("UPDATE shows SET deleted_at = '2026-07-27T00:00:00+00:00'")
    db.commit()
    assert comb.live_shows(db) == []


# --- the dump is a hint, and only a hint -----------------------------------------


def test_known_dead_feeds_are_skipped_and_reported(db, tmp_path, monkeypatch):
    """Skipping saves a request we expect to fail. Reporting matters more: a skipped show
    needs a person, not a retry, and silence would make it look healthy."""
    dump = tmp_path / "feeds.db"
    d = sqlite3.connect(dump)
    d.execute("CREATE TABLE podcasts (url TEXT, dead INTEGER, lastHttpStatus INTEGER)")
    d.execute("INSERT INTO podcasts VALUES ('http://dead', 1, 200)")
    d.execute("INSERT INTO podcasts VALUES ('http://gone', 0, 410)")
    d.execute("INSERT INTO podcasts VALUES ('http://fine', 0, 200)")
    d.commit(); d.close()

    assert comb.dead_feeds(dump) == {"http://dead", "http://gone"}

    add_show(db, "d", "Dead One", feed="http://dead")
    monkeypatch.setattr(feeds, "read", lambda *a, **k: pytest.fail("should not fetch"))
    run = comb.comb(db, dump=dump)
    assert run.tallies.get("skipped-dead") == 1
    assert any("dead" in p for p in run.problems)


def test_no_dump_means_read_everything(db, tmp_path):
    """The workbench has to run without a 4 GB file present, and 'I could not check' must
    never become 'it is dead'."""
    assert comb.dead_feeds(tmp_path / "absent.db") == set()


# --- the pass itself -------------------------------------------------------------


def feed_with(guid_prefix, n=2, desc="y" * 1200, duration=3600):
    return feeds.Feed(
        url="http://f", title="T", author="A", description="d",
        episodes=[feeds.Episode(guid=f"{guid_prefix}-{i}", title=f"ep {i}",
                                description=desc, duration_s=duration)
                  for i in range(n)])


def test_a_pass_lengthens_descriptions_and_records_a_run(db, log, monkeypatch):
    add_show(db, "a", "A Show", eps=2, desc="x" * 299)
    monkeypatch.setattr(feeds, "read", lambda url, **k: feed_with("a"))

    run = comb.comb(db, dry_run=False, decisions_path=log)
    assert run.tallies["descriptions"] == 2
    assert run.tallies["durations"] == 2
    lengths = [r[0] for r in db.execute("SELECT length(description) FROM episodes")]
    assert lengths == [1200, 1200]

    row = db.execute("SELECT kind, status, summary FROM runs").fetchone()
    assert row[0] == "refetch" and row[1] == "done"
    assert "descriptions 2" in row[2]


def test_a_dry_run_writes_nothing_but_still_counts(db, log, monkeypatch):
    """The point of a dry run is to be able to say what would change before it does."""
    add_show(db, "a", "A Show", eps=3, desc="x" * 299)
    monkeypatch.setattr(feeds, "read", lambda url, **k: feed_with("a", n=3))

    run = comb.comb(db, dry_run=True, decisions_path=log)
    assert run.tallies["would-lengthen"] == 3
    assert [r[0] for r in db.execute("SELECT length(description) FROM episodes")] == [299] * 3
    assert not log.exists()


def test_one_unreadable_feed_does_not_stop_the_pass(db, log, monkeypatch):
    """A feed that 404s is a fact about that feed, not a reason to abandon 287 others."""
    add_show(db, "broken", "Broken", feed="http://broken")
    add_show(db, "fine", "Fine", feed="http://fine")

    def read(url, **k):
        if "broken" in url:
            raise feeds.FeedError("http://broken -> HTTP 404")
        return feed_with("fine")

    monkeypatch.setattr(feeds, "read", read)
    run = comb.comb(db, decisions_path=log)
    assert run.tallies["unreadable"] == 1
    assert run.tallies["read"] == 1
    assert any("broken" in p for p in run.problems)
    # The run still closes as done -- one bad feed is not a failed pass.
    assert db.execute("SELECT status FROM runs").fetchone()[0] == "done"


def test_failures_reach_the_summary(db, log, monkeypatch):
    """"0 failures" and "we stopped counting" look identical in a summary. They must not."""
    add_show(db, "broken", "Broken")
    monkeypatch.setattr(feeds, "read",
                        lambda url, **k: (_ for _ in ()).throw(feeds.FeedError("nope")))
    comb.comb(db, decisions_path=log)
    assert "problems 1" in db.execute("SELECT summary FROM runs").fetchone()[0]


# --- the run record --------------------------------------------------------------


def test_a_run_that_did_nothing_still_closes(db):
    """Left 'running' forever, the surface is unreadable within a week."""
    run = runs.start(db, "refetch")
    runs.finish(db, run)
    status, summary = db.execute("SELECT status, summary FROM runs").fetchone()
    assert status == "done" and summary == "nothing to do"


def test_a_long_problem_list_is_truncated_not_dropped(db):
    run = runs.start(db, "refetch")
    for i in range(12):
        run.problem(f"show-{i} failed")
    runs.finish(db, run)
    summary = db.execute("SELECT summary FROM runs").fetchone()[0]
    assert "problems 12" in summary and "+7 more" in summary
