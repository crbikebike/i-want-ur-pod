"""Splitting a subject that has grown too crowded to browse.

Measured, not guessed: 99% Invisible put 82 of 100 pilot episodes on one subject, because
`Why It Looks Like That` is the only slug in the whole 148 aimed at the built environment.
Swindled, on a well-served part of the vocabulary, used ~30 subjects across 100 episodes.
Unevenly deep, not bad.
"""

import sqlite3
from pathlib import Path

import pytest

from admin.api import edits, vocab
from catalog.build import migrations

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "catalog/schema.sql"


@pytest.fixture
def db():
    conn = sqlite3.connect(":memory:")
    conn.executescript(SCHEMA.read_text())
    migrations.apply_all(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("INSERT INTO themes (id, slug, name) VALUES (1,'media','Media & Internet Culture')")
    conn.execute("INSERT INTO subjects (id, slug, name, description, theme_id) "
                 "VALUES (1,'design-and-architecture','Why It Looks Like That','why things look so',1)")
    conn.execute("INSERT INTO subjects (id, slug, name, description, theme_id) "
                 "VALUES (2,'quiet-one','A Quiet Subject','not much here',1)")
    conn.execute("INSERT INTO shows (id, slug, title, feed_url, include_verdict, why) "
                 "VALUES (1,'99pi','99% Invisible','http://f','keep','x')")
    conn.commit()
    yield conn
    conn.close()


@pytest.fixture
def log(tmp_path):
    return tmp_path / "decisions.jsonl"


def load(conn, subject_id, n, show_id=1, run_id=vocab.CURRENT_RUN, role="primary"):
    for i in range(n):
        eid = conn.execute(
            "INSERT INTO episodes (show_id, guid, title, description) VALUES (?,?,?,?)",
            (show_id, f"g{subject_id}-{show_id}-{role}-{i}", f"Ep {i}",
             "<p>About a thing.</p>")).lastrowid
        conn.execute("INSERT INTO episode_labels (episode_id, subject_id, run_id, role, "
                     "confidence) VALUES (?,?,?,?,'high')", (eid, subject_id, run_id, role))
    conn.commit()


def relabel(conn, subject_id, run_id):
    """Label every existing episode again under a second run, as a real rerun would."""
    for eid, in conn.execute("SELECT id FROM episodes").fetchall():
        conn.execute("INSERT INTO episode_labels (episode_id, subject_id, run_id, role, "
                     "confidence) VALUES (?,?,?,'primary','high')", (eid, subject_id, run_id))
    conn.commit()


# --- the live vocabulary, for the label queue's change sheet ---------------------


def test_tree_groups_subjects_under_their_theme(db):
    got = vocab.tree(db)
    assert [t["slug"] for t in got["themes"]] == ["media"]
    assert [s["slug"] for s in got["themes"][0]["subjects"]] == \
        ["quiet-one", "design-and-architecture"]


def test_tree_orders_themes_by_name(db):
    db.execute("INSERT INTO themes (id, slug, name) VALUES (2,'arts','Arts')")
    db.commit()
    got = vocab.tree(db)
    assert [t["name"] for t in got["themes"]] == ["Arts", "Media & Internet Culture"]


def test_tree_orders_subjects_by_name_within_a_theme(db):
    got = vocab.tree(db)
    names = [s["name"] for s in got["themes"][0]["subjects"]]
    assert names == sorted(names)
    assert names == ["A Quiet Subject", "Why It Looks Like That"]


def test_tree_excludes_a_deleted_theme(db):
    db.execute("INSERT INTO themes (id, slug, name) VALUES (2,'gone','Gone')")
    db.execute("UPDATE themes SET deleted_at='2026-08-01' WHERE id=2")
    db.commit()
    assert [t["slug"] for t in vocab.tree(db)["themes"]] == ["media"]


def test_tree_excludes_a_deleted_subject(db):
    db.execute("UPDATE subjects SET deleted_at='2026-08-01' WHERE slug='quiet-one'")
    db.commit()
    got = vocab.tree(db)
    assert [s["slug"] for s in got["themes"][0]["subjects"]] == ["design-and-architecture"]


def test_tree_carries_slug_name_and_description(db):
    got = vocab.tree(db)
    subj = got["themes"][0]["subjects"][0]
    assert set(subj) == {"slug", "name", "description"}


# --- finding the crowded ones ----------------------------------------------------


def test_a_crowded_subject_is_flagged(db):
    load(db, 1, vocab.CROWDED + 10)
    load(db, 2, 20)
    got = vocab.crowded(db)
    assert [s["slug"] for s in got] == ["design-and-architecture"]
    assert got[0]["episodes"] == vocab.CROWDED + 10


def test_the_measure_is_per_subject_not_per_theme(db):
    """A theme-level ratio hides exactly the case both pilots found. Media & Internet
    Culture holds 18 subjects and looks healthy while one of them carries 406 episodes."""
    load(db, 1, vocab.CROWDED + 10)
    for i in range(3, 20):
        db.execute("INSERT INTO subjects (id, slug, name, description, theme_id) "
                   "VALUES (?,?,?,'x',1)", (i, f"s{i}", f"S{i}"))
    db.commit()
    assert [s["slug"] for s in vocab.crowded(db)] == ["design-and-architecture"]


def test_which_shows_lean_on_it_is_reported(db):
    """A subject used by 60 shows is a genuine category; one dominated by a single show is
    that show's beat needing its own words. The split differs."""
    db.execute("INSERT INTO shows (id, slug, title, feed_url, include_verdict, why) "
               "VALUES (2,'other','Other','http://g','keep','x')")
    db.commit()
    load(db, 1, vocab.CROWDED)
    load(db, 1, 20, show_id=2)
    got = vocab.crowded(db)[0]
    assert got["shows"] == 2
    assert got["leanedOnBy"][0]["show"] == "99% Invisible"


def test_soft_deleted_episodes_do_not_inflate_the_count(db):
    load(db, 1, vocab.CROWDED + 10)
    db.execute("UPDATE episodes SET deleted_at='2026-07-27T00:00:00+00:00'")
    db.commit()
    assert vocab.crowded(db) == []


# --- the evidence a split is argued from -----------------------------------------


def test_a_sample_arrives_as_prose(db):
    load(db, 1, 10)
    got = vocab.sample(db, "design-and-architecture", limit=5)
    assert len(got["episodes"]) == 5
    assert got["episodes"][0]["description"] == "About a thing."
    assert got["definition"] == "why things look so"


# --- proposing -------------------------------------------------------------------


def prop(**kw):
    return {"name": "The Building and Its Making", "slug": "buildings-and-places",
            "theme": "media", "splitsFrom": "design-and-architecture",
            "definition": "A building and the decisions that shaped it — not the objects inside.",
            "examples": ["The Hanging Gardens"], **kw}


def test_a_proposal_is_recorded_and_creates_nothing(db):
    """Growing the browsable vocabulary is a decision about the product."""
    assert vocab.propose(db, [prop()])["proposed"] == 1
    assert db.execute("SELECT count(*) FROM subjects").fetchone()[0] == 2
    assert vocab.waiting(db)[0]["name"] == "The Building and Its Making"


def test_a_proposal_without_a_definition_is_refused(db):
    """That sentence is what the next pass reads to decide. Vagueness there becomes noise
    across 29,000 episodes."""
    got = vocab.propose(db, [prop(definition="")])
    assert got["proposed"] == 0 and "definition" in got["skipped"][0]


def test_a_slug_that_already_exists_is_refused(db):
    got = vocab.propose(db, [prop(slug="quiet-one")])
    assert got["proposed"] == 0 and "already a subject" in got["skipped"][0]


def test_an_unknown_theme_is_refused(db):
    got = vocab.propose(db, [prop(theme="nope")])
    assert got["proposed"] == 0 and "does not exist" in got["skipped"][0]


def test_the_parent_it_splits_from_is_remembered(db):
    """Accepting one means the episodes under the parent need re-reading, and that is only
    knowable if the relationship was recorded."""
    vocab.propose(db, [prop()])
    assert db.execute("SELECT splits_from FROM subject_proposals").fetchone()[0] == 1


# --- accepting -------------------------------------------------------------------


def test_accepting_creates_the_subject_through_the_one_door(db, log):
    vocab.propose(db, [prop()])
    got = vocab.accept(db, decisions_path=log)
    assert got["created"] == 1
    row = db.execute("SELECT name, description, theme_id FROM subjects "
                     "WHERE slug='buildings-and-places'").fetchone()
    assert row[0] == "The Building and Its Making" and row[2] == 1
    assert db.execute("SELECT count(*) FROM edits WHERE field='created'").fetchone()[0] == 1


def test_each_acceptance_is_its_own_undoable_line(db, log):
    """Forty accepted in a sitting should still be forty decisions, not one lump nobody
    can pick apart later."""
    vocab.propose(db, [prop(), prop(name="The Object in Your Hand", slug="everyday-objects")])
    vocab.accept(db, decisions_path=log)
    assert db.execute("SELECT count(*) FROM edits WHERE field='created'").fetchone()[0] == 2


def test_an_accepted_proposal_does_not_come_back(db, log):
    vocab.propose(db, [prop()])
    vocab.accept(db, decisions_path=log)
    assert vocab.waiting(db) == []
    assert vocab.accept(db, decisions_path=log)["created"] == 0


def test_a_subject_needs_a_definition_at_the_door_too(db, log):
    """The proposal check can be bypassed; this one cannot."""
    with pytest.raises(edits.EditError):
        edits.create_subject(db, slug="x", name="X", description="", theme_id=1,
                             decisions_path=log)


def test_a_subject_cannot_be_orphaned_from_its_theme(db, log):
    with pytest.raises(edits.EditError):
        edits.create_subject(db, slug="x", name="X", description="d", theme_id=99,
                             decisions_path=log)


# Three label runs coexist by design -- the 2026-07 Haiku pass, the pilot, and the current
# relabel -- and none overwrites another. An unfiltered count therefore sums a subject
# across every run that touched it and reports roughly double, which flags subjects as too
# crowded to browse when they are not. A splitter caught this by hand-drawing its own
# sample after `sample` handed it exact duplicate episodes.


def test_an_earlier_run_does_not_inflate_the_count(db):
    load(db, 1, 200)
    relabel(db, 1, "2026-07-theming")
    assert vocab.crowded(db) == []                       # 200 in this run, not 400


def test_a_secondary_label_is_not_evidence_for_a_split(db):
    """The question a split answers is what a subject is the *main* home for."""
    load(db, 1, 4)
    load(db, 1, 4, role="secondary")
    assert len(vocab.sample(db, "design-and-architecture", limit=20)["episodes"]) == 4


def test_a_sample_holds_each_episode_once(db):
    load(db, 1, 6)
    relabel(db, 1, "2026-07-theming")
    got = vocab.sample(db, "design-and-architecture", limit=20)["episodes"]
    assert len(got) == len({e["title"] for e in got}) == 6


def test_an_older_run_can_still_be_asked_about(db):
    load(db, 1, 6, run_id="2026-07-theming")
    assert vocab.sample(db, "design-and-architecture", run_id="2026-07-theming")["episodes"]
    assert vocab.sample(db, "design-and-architecture")["episodes"] == []
