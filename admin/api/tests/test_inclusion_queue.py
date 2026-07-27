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


def test_the_card_carries_only_what_the_decision_needs(db):
    """Three things: what it is, why you are looking at it, and where to go and check.

    Everything else came off. Pitch, description, episode counts, theme chips and a
    sample of episode titles were all on here, and none of them could settle the actual
    question -- whether this is narrated storytelling or two people chatting. Only
    listening settles that, so the card frames the question and hands over the door."""
    add_show(db, "s-town", "S-Town", episodes=7)
    item = queues.inclusion_next(db)

    assert set(item) == {"id", "slug", "title", "network", "years", "artwork", "note", "links"}
    assert item["title"] == "S-Town"
    assert item["network"] == "Wondery"
    assert item["note"]["label"]
    assert item["links"][0]["href"].startswith("https://podcasts.apple.com/")


def test_every_card_says_why_it_is_being_reviewed(db):
    """A queue that does not say why is asking you to guess at its reasoning."""
    add_show(db, "a", "A")
    note = queues.inclusion_next(db)["note"]
    assert note is not None
    assert note["label"] and note["detail"] and note["meaning"]


def test_an_odd_category_is_stated_as_the_reason(db):
    """Not a verdict -- sorting by category is useless -- but as a stated fact it is
    honest about why this one is worth a look."""
    sid = add_show(db, "a", "A Comedy Show")
    db.execute("UPDATE shows SET apple_category='Comedy' WHERE id=?", (sid,))
    db.commit()
    assert "Comedy" in queues.inclusion_next(db)["note"]["meaning"]


def test_an_ordinary_category_admits_there_is_no_specific_doubt(db):
    sid = add_show(db, "a", "A")
    db.execute("UPDATE shows SET apple_category='Documentary' WHERE id=?", (sid,))
    db.commit()
    assert "No specific doubt" in queues.inclusion_next(db)["note"]["meaning"]


def test_a_show_with_a_stored_apple_link_uses_it(db):
    sid = add_show(db, "a", "A")
    db.execute("UPDATE shows SET home_url='https://podcasts.apple.com/us/podcast/a/id1' "
               "WHERE id=?", (sid,))
    db.commit()
    link = queues.inclusion_next(db)["links"][0]
    assert link["href"] == "https://podcasts.apple.com/us/podcast/a/id1"
    # Opens in place rather than in a tab: the embed player is frameable where the
    # ordinary page is not.
    assert link["embed"] == "https://embed.podcasts.apple.com/us/podcast/id1"


def test_a_show_we_cannot_embed_falls_back_to_a_tab(db):
    add_show(db, "a", "A")   # no home_url, so no id to embed
    link = queues.inclusion_next(db)["links"][0]
    assert link["embed"] is None
    assert "search?term=" in link["href"]


def test_a_show_without_one_gets_a_search_instead(db):
    """20 shows have no stored link. A search is worse than a direct link and much
    better than a dead end."""
    add_show(db, "a", "Alice Isn't Dead")
    link = queues.inclusion_next(db)["links"][0]
    assert "search?term=Alice+Isn%27t+Dead" in link["href"]
    assert link["label"] == "Find in Apple Podcasts"


def test_a_shared_feed_says_one_of_them_is_a_duplicate(db):
    """A warning that states a fact and stops is not actionable. It has to say which
    button that implies."""
    add_show(db, "slow-burn", "Slow Burn", feed="http://shared")
    add_show(db, "slow-burn-biggie", "Slow Burn: Biggie & Tupac",
             verdict="suspect", feed="http://shared")
    note = queues.inclusion_next(db)["note"]
    assert note["kind"] == "duplicate-entry"
    assert note["tone"] == "warn"
    assert "Slow Burn" in note["detail"][0]
    assert "duplicate" in note["meaning"] and "Keep the parent" in note["meaning"]


def test_cross_promotion_is_not_dressed_up_as_a_problem(db):
    """Ear Hustle carried all seven episodes of The Loop. Both are real shows and both
    should be kept -- showing that in red sends you to the wrong decision."""
    a = add_show(db, "ear-hustle", "Ear Hustle", episodes=6, feed="http://eh")
    b = add_show(db, "loop", "The Loop", verdict="suspect", feed="http://loop")
    for i in range(6):
        db.execute("INSERT INTO episodes (show_id, guid, title) VALUES (?,?,?)",
                   (b, f"ear-hustle-{i}", f"The Loop Ep. {i}"))
    db.commit()
    note = queues.inclusion_next(db)["note"]
    assert note["kind"] == "cross-promotion"
    assert note["tone"] == "info"
    assert "Ear Hustle" in note["detail"][0]
    assert "keep both" in note["meaning"].lower()


def test_a_wrong_feed_says_what_the_feed_actually_serves(db):
    """Empire is catalogued as Goalhanger's history series; the feed is a crypto show."""
    add_show(db, "empire", "Empire", verdict="suspect")
    note = queues.inclusion_next(db)["note"]
    assert note["kind"] == "wrong-feed"
    assert note["tone"] == "warn"
    assert "crypto" in note["detail"][0]


def test_every_note_says_what_it_means_for_the_decision(db):
    """The whole point. A note without a `meaning` is the old useless warning."""
    add_show(db, "a", "A", verdict="suspect")
    note = queues.inclusion_next(db)["note"]
    assert note["meaning"] and len(note["meaning"]) > 20


def test_a_soft_deleted_show_never_reaches_the_queue(db):
    add_show(db, "gone", "Gone")
    add_show(db, "here", "Here")
    db.execute("UPDATE shows SET deleted_at='2026-07-27' WHERE slug='gone'")
    db.commit()
    for _ in range(3):
        assert queues.inclusion_next(db)["slug"] == "here"


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


def test_no_cachebust_until_the_art_is_known_to_have_changed():
    """Inventing a version would defeat a 190-day cache for nothing."""
    u = "https://is1-ssl.mzstatic.com/a/b.jpg/3000x3000bb.jpg"
    assert "?" not in queues.thumbnail(u)


def test_a_changed_cover_gets_a_new_url():
    """Apple sends cache-control: max-age=16480651 -- 190 days. Once a phone holds a
    copy, only a different URL will dislodge it."""
    u = "https://is1-ssl.mzstatic.com/a/b.jpg/3000x3000bb.jpg"
    first = queues.thumbnail(u, updated_at="2026-07-27T02:00:00+00:00")
    later = queues.thumbnail(u, updated_at="2026-11-03T09:15:00+00:00")
    assert "v=" in first and first != later


def test_the_cachebust_is_stable_for_the_same_timestamp():
    """It must not change per request, or every load re-downloads the cover."""
    u = "https://is1-ssl.mzstatic.com/a/b.jpg/3000x3000bb.jpg"
    stamp = "2026-07-27T02:00:00+00:00"
    assert queues.thumbnail(u, updated_at=stamp) == queues.thumbnail(u, updated_at=stamp)


def test_the_cachebust_joins_an_existing_query_correctly():
    u = "https://example.com/cover.jpg?token=abc"
    assert queues.thumbnail(u, updated_at="2026-07-27") == "https://example.com/cover.jpg?token=abc&v=20260727"


def test_the_card_carries_the_cachebust(db):
    sid = add_show(db, "a", "A")
    db.execute("UPDATE shows SET artwork_url = ?, artwork_updated_at = ? WHERE id = ?",
               ("https://is1-ssl.mzstatic.com/a/b.jpg/3000x3000bb.jpg",
                "2026-07-27T02:00:00+00:00", sid))
    db.commit()
    art = queues.inclusion_next(db)["artwork"]
    assert "300x300bb" in art and "v=20260727020000" in art
