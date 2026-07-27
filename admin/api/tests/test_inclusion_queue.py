"""The inclusion queue: what it shows, in what order, and what a verdict does.

Ordering gets the most attention here because it decides which ten shows a short session
spends itself on.
"""

import sqlite3
from pathlib import Path

import pytest

from admin.api import edits, queues
from catalog.build import migrations

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "catalog/schema.sql"


@pytest.fixture
def db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    migrations.apply_all(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("INSERT INTO networks (id, slug, name) VALUES (1, 'wondery', 'Wondery')")
    conn.execute("INSERT INTO themes (id, slug, name) VALUES (1, 'true-crime', 'True Crime')")
    conn.execute(
        "INSERT INTO subjects (id, slug, name, theme_id) VALUES (1, 'murder', 'Murder', 1)")
    conn.commit()
    yield conn
    conn.close()


def add_show(conn, slug, title, verdict="unreviewed", feed=None, network_id=1, episodes=0):
    cur = conn.execute(
        "INSERT INTO shows (slug, title, feed_url, network_id, include_verdict, why, "
        "apple_category) VALUES (?,?,?,?,?,?,?)",
        (slug, title, feed or f"http://{slug}", network_id, verdict,
         f"why you should hear {title}", "Documentary"),
    )
    sid = cur.lastrowid
    for i in range(episodes):
        conn.execute("INSERT INTO episodes (show_id, guid, title, published_at) VALUES (?,?,?,?)",
                     (sid, f"{slug}-{i}", f"{title} ep {i}", f"2026-01-{i+1:02d}"))
    conn.commit()
    return sid


@pytest.fixture
def log(tmp_path):
    return tmp_path / "decisions.jsonl"


# --- counts ----------------------------------------------------------------------


def test_counts_describe_the_work(db):
    add_show(db, "a", "A")
    add_show(db, "b", "B", verdict="suspect")
    add_show(db, "c", "C", verdict="keep")
    add_show(db, "d", "D", verdict="cut")

    c = queues.inclusion_counts(db)
    assert c == {"waiting": 2, "flagged": 1, "decided": 2, "kept": 1, "cut": 1, "total": 4}


def test_a_soft_deleted_show_is_not_waiting(db):
    add_show(db, "a", "A")
    db.execute("UPDATE shows SET deleted_at = '2026-07-27' WHERE slug = 'a'")
    db.commit()
    assert queues.inclusion_counts(db)["waiting"] == 0


def test_counts_move_as_decisions_are_made(db, log):
    sid = add_show(db, "a", "A")
    add_show(db, "b", "B")
    assert queues.inclusion_counts(db)["waiting"] == 2
    edits.apply(db, entity_type="show", entity_id=sid, field="include_verdict",
                after="cut", decisions_path=log)
    after = queues.inclusion_counts(db)
    assert after["waiting"] == 1 and after["cut"] == 1


# --- ordering --------------------------------------------------------------------


def test_flagged_shows_come_first(db):
    """They carry evidence, so they are the fastest good decisions available."""
    for i in range(8):
        add_show(db, f"plain{i}", f"Plain {i}")
    add_show(db, "dupe", "A Duplicate", verdict="suspect")
    assert queues.inclusion_next(db)["slug"] == "dupe"


def test_order_is_stable_between_calls(db):
    """A queue that reshuffles on every load makes skipping feel broken."""
    for i in range(20):
        add_show(db, f"s{i}", f"Show {i}")
    assert queues.inclusion_next(db)["id"] == queues.inclusion_next(db)["id"]


def test_order_is_not_alphabetical_or_insertion_order(db):
    """Both would bias a ten-card session toward one corner of the catalog."""
    for i in range(30):
        add_show(db, f"s{i:02d}", f"Show {i:02d}")
    first = queues.inclusion_next(db)["slug"]
    assert first not in ("s00", "s29")


def test_skipping_moves_on_without_deciding(db):
    for i in range(5):
        add_show(db, f"s{i}", f"Show {i}")
    first = queues.inclusion_next(db)
    second = queues.inclusion_next(db, skipped=[first["id"]])
    assert second["id"] != first["id"]
    # and nothing was recorded
    assert db.execute("SELECT count(*) FROM edits").fetchone()[0] == 0
    assert queues.inclusion_counts(db)["waiting"] == 5


def test_the_queue_empties(db, log):
    sid = add_show(db, "only", "The Only One")
    edits.apply(db, entity_type="show", entity_id=sid, field="include_verdict",
                after="keep", decisions_path=log)
    assert queues.inclusion_next(db) is None


def test_decided_shows_do_not_come_back(db, log):
    a = add_show(db, "a", "A")
    add_show(db, "b", "B")
    edits.apply(db, entity_type="show", entity_id=a, field="include_verdict",
                after="keep", decisions_path=log)
    assert queues.inclusion_next(db)["slug"] == "b"


# --- what a card carries ---------------------------------------------------------


def test_the_card_has_enough_to_decide_without_tapping_through(db):
    sid = add_show(db, "s-town", "S-Town", episodes=7)
    db.execute("INSERT INTO show_themes (show_id, theme_id) VALUES (?, 1)", (sid,))
    db.execute("INSERT INTO arcs (show_id, slug, kind, name, source) "
               "VALUES (?, 'ch', 'arc', 'Chapter One', 'gold')", (sid,))
    db.commit()

    item = queues.inclusion_next(db)
    assert item["title"] == "S-Town"
    assert item["network"] == "Wondery"
    assert item["pitch"]
    assert item["episodeCount"] == 7
    assert item["arcCount"] == 1
    assert len(item["recentEpisodes"]) == 5      # newest first, capped
    assert item["themes"] == ["True Crime"]


def test_recent_episodes_are_newest_first(db):
    add_show(db, "a", "A", episodes=6)
    assert queues.inclusion_next(db)["recentEpisodes"][0] == "A ep 5"


def test_an_ordinary_show_carries_no_evidence(db):
    add_show(db, "a", "A")
    assert queues.inclusion_next(db)["evidence"] == []
    assert queues.inclusion_next(db)["flagged"] is False


def test_a_shared_feed_is_explained_on_the_card(db):
    """The 16 flagged shows must say why, or the flag is just an accusation."""
    add_show(db, "slow-burn", "Slow Burn", feed="http://shared")
    add_show(db, "slow-burn-biggie", "Slow Burn: Biggie & Tupac",
             verdict="suspect", feed="http://shared")
    item = queues.inclusion_next(db)
    assert item["flagged"] is True
    assert any("Shares its feed with Slow Burn" in e for e in item["evidence"])


def test_overlapping_episodes_are_explained(db):
    a = add_show(db, "turning", "The Turning", episodes=6)
    b = add_show(db, "turning-sisters", "The Turning: The Sisters", verdict="suspect")
    for i in range(6):
        db.execute("INSERT INTO episodes (show_id, guid, title) VALUES (?,?,?)",
                   (b, f"turning-{i}", f"dup {i}"))
    db.commit()
    item = queues.inclusion_next(db)
    assert any("also in The Turning" in e for e in item["evidence"])


def test_soft_deleted_episodes_are_not_counted(db):
    sid = add_show(db, "a", "A", episodes=4)
    db.execute("UPDATE episodes SET deleted_at='2026-07-27' WHERE show_id=? AND guid='a-0'", (sid,))
    db.commit()
    assert queues.inclusion_next(db)["episodeCount"] == 3


# --- verdicts --------------------------------------------------------------------


@pytest.mark.parametrize("verdict", ["keep", "cut"])
def test_a_verdict_is_recorded_through_the_one_door(db, log, verdict):
    sid = add_show(db, "a", "A")
    e = edits.apply(db, entity_type="show", entity_id=sid, field="include_verdict",
                    after=verdict, decisions_path=log)
    assert db.execute("SELECT include_verdict FROM shows WHERE id=?", (sid,)).fetchone()[0] == verdict
    assert e.entity_key == "a"


def test_suspect_is_not_a_verdict_a_human_can_pick(db):
    """It is what the importer says when unsure. A human who cannot decide skips."""
    assert queues.VERDICTS == {"keep", "cut"}


def test_a_verdict_can_be_undone(db, log):
    sid = add_show(db, "a", "A", verdict="suspect")
    e = edits.apply(db, entity_type="show", entity_id=sid, field="include_verdict",
                    after="cut", decisions_path=log)
    edits.undo(db, e.edit_id, decisions_path=log)
    assert db.execute("SELECT include_verdict FROM shows WHERE id=?", (sid,)).fetchone()[0] == "suspect"
    assert queues.inclusion_next(db)["slug"] == "a"


def test_an_empty_skip_list_does_not_empty_the_queue(db):
    """Regression: `id NOT IN (NULL)` is UNKNOWN for every row, so the obvious
    placeholder returns nothing -- which on screen is indistinguishable from
    "you have finished"."""
    add_show(db, "a", "A")
    assert queues.inclusion_next(db, skipped=[]) is not None
    assert queues.inclusion_next(db, skipped=None) is not None


# --- artwork ---------------------------------------------------------------------


def test_artwork_is_served_at_a_sane_size():
    """The catalog stores Apple's 3000x3000 original -- 3.9 MB for a 76px thumbnail.
    A thirty-card session on cellular would pull over 100 MB."""
    big = ("https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/84/75/9f/"
           "84759f65/mza_8038583962796645034.jpg/3000x3000bb.jpg")
    assert queues.thumbnail(big).endswith("/300x300bb.jpg")


def test_thumbnail_keeps_the_rest_of_the_url_intact():
    big = "https://is1-ssl.mzstatic.com/a/b/c.jpg/3000x3000bb.jpg"
    assert queues.thumbnail(big) == "https://is1-ssl.mzstatic.com/a/b/c.jpg/300x300bb.jpg"


def test_thumbnail_handles_png():
    assert queues.thumbnail("https://x/y/1200x1200bb.png").endswith("/300x300bb.png")


@pytest.mark.parametrize("value", [None, "", "   "])
def test_missing_artwork_becomes_none(value):
    """20 shows have none. An empty string would render a broken image box."""
    assert queues.thumbnail(value) is None


def test_a_url_we_do_not_recognise_is_left_alone(db):
    """Not every host is Apple. Better untouched than mangled."""
    other = "https://example.com/cover.jpg"
    assert queues.thumbnail(other) == other


def test_the_card_carries_the_thumbnail_not_the_original(db):
    sid = add_show(db, "a", "A")
    db.execute("UPDATE shows SET artwork_url = ? WHERE id = ?",
               ("https://is1-ssl.mzstatic.com/a/b.jpg/3000x3000bb.jpg", sid))
    db.commit()
    assert "300x300bb" in queues.inclusion_next(db)["artwork"]
