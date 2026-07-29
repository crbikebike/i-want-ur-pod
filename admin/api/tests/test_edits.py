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


# --- ingesting episodes: the insert door ----------------------------------------


def ep(guid, title, **kw):
    from admin.api.feeds import Episode
    return Episode(guid=guid, title=title, **kw)


def test_ingesting_lands_in_all_three_places(db, log):
    """apply() cannot do this -- it changes a field on a row that already exists, and
    there is no row yet -- but the promise has to hold anyway."""
    got = edits.ingest_episodes(db, show_id=1, episodes=[ep("n1", "New One"), ep("n2", "New Two")],
                                actor="agent:comber", note="feed corrected", decisions_path=log)
    assert got == {"added": 2, "existing": 0}
    assert db.execute("SELECT count(*) FROM episodes WHERE show_id=1").fetchone()[0] == 3
    assert db.execute("SELECT count(*) FROM edits WHERE field='ingest'").fetchone()[0] == 1
    assert read_log(log)[-1]["added"] == 2


def test_a_batch_is_one_log_line_not_one_per_episode(db, log):
    """Repointing Empire brings back 658 episodes. 658 log lines would bury the decision
    that mattered."""
    edits.ingest_episodes(db, show_id=1, episodes=[ep(f"g{i}", f"Ep {i}") for i in range(200)],
                          actor="agent:comber", note="backfill", decisions_path=log)
    assert len(read_log(log)) == 1
    # 199, not 200: the fixture's show already carries g1, and the count reports what
    # actually changed rather than what was offered.
    assert "199 added, 1 already present" in db.execute(
        "SELECT note FROM edits ORDER BY id DESC LIMIT 1").fetchone()[0]


def test_an_episode_already_present_is_left_alone(db, log):
    """Re-reading a feed should converge, not churn. Arcs, subjects and verdicts hang off
    these rows and they are our work, not the publisher's."""
    db.execute("UPDATE episodes SET title='Our Edited Title' WHERE id=1")
    db.commit()
    got = edits.ingest_episodes(db, show_id=1, episodes=[ep("g1", "Publisher's Title")],
                                actor="agent:comber", note="refresh", decisions_path=log)
    assert got == {"added": 0, "existing": 1}
    assert db.execute("SELECT title FROM episodes WHERE id=1").fetchone()[0] == "Our Edited Title"


def test_ingesting_restores_an_episode_a_bad_rematch_hid(db, log):
    """A wrong re-match hides every episode. Pointing the row back at the right feed has
    to bring them out again, or the fix leaves the show empty."""
    edits.apply(db, entity_type="episode", entity_id=1, field="deleted_at",
                after="2026-07-27T00:00:00+00:00", decisions_path=log)
    edits.ingest_episodes(db, show_id=1, episodes=[ep("g1", "Ep One")],
                          actor="agent:comber", note="feed corrected", decisions_path=log)
    assert db.execute("SELECT deleted_at FROM episodes WHERE id=1").fetchone()[0] is None


def test_ingesting_nothing_writes_nothing(db, log):
    assert edits.ingest_episodes(db, show_id=1, episodes=[], actor="agent:comber",
                                 note="empty feed", decisions_path=log) == {"added": 0, "existing": 0}
    assert db.execute("SELECT count(*) FROM edits WHERE field='ingest'").fetchone()[0] == 0
    assert read_log(log) == []


def test_nothing_is_ingested_when_the_log_cannot_be(db, tmp_path):
    unwritable = tmp_path / "nope"
    unwritable.write_text("i am a file, not a directory")
    with pytest.raises(Exception):
        edits.ingest_episodes(db, show_id=1, episodes=[ep("n1", "New")], actor="agent:comber",
                              note="x", decisions_path=unwritable / "decisions.jsonl")
    assert db.execute("SELECT count(*) FROM episodes WHERE show_id=1").fetchone()[0] == 1


# --- refreshing publisher facts --------------------------------------------------


def test_a_longer_description_replaces_a_truncated_one(db, log):
    """The 2026-07 import cut every description at 299 characters. 24,000 episodes carry
    a third of what the feed offers, and subject labelling reads that text."""
    db.execute("UPDATE episodes SET description = ? WHERE id = 1", ("x" * 299,))
    db.commit()
    got = edits.refresh_episodes(db, show_id=1, episodes=[ep("g1", "Ep One", description="y" * 1200)],
                                 actor="agent:comb", note="re-read", decisions_path=log)
    assert got["longer"] == 1
    assert len(db.execute("SELECT description FROM episodes WHERE id=1").fetchone()[0]) == 1200
    assert read_log(log)[-1]["descriptions"] == 1


def test_a_shorter_description_is_refused(db, log):
    """A publisher who shortens their blurb, or a feed serving a summary in place of the
    full text, must not cost us the longer version. A refresh that can lose data is not a
    refresh."""
    db.execute("UPDATE episodes SET description = ? WHERE id = 1", ("long " * 200,))
    db.commit()
    before = db.execute("SELECT description FROM episodes WHERE id=1").fetchone()[0]
    edits.refresh_episodes(db, show_id=1, episodes=[ep("g1", "Ep One", description="short")],
                           actor="agent:comb", note="re-read", decisions_path=log)
    assert db.execute("SELECT description FROM episodes WHERE id=1").fetchone()[0] == before


def test_duration_is_filled_but_never_overwritten(db, log):
    """Duration is cached as a display hint. Ours may have been corrected; theirs may
    rotate with a re-encode."""
    edits.refresh_episodes(db, show_id=1, episodes=[ep("g1", "Ep One", duration_s=3723)],
                           actor="agent:comb", note="re-read", decisions_path=log)
    assert db.execute("SELECT duration_s FROM episodes WHERE id=1").fetchone()[0] == 3723
    edits.refresh_episodes(db, show_id=1, episodes=[ep("g1", "Ep One", duration_s=9999)],
                           actor="agent:comb", note="re-read", decisions_path=log)
    assert db.execute("SELECT duration_s FROM episodes WHERE id=1").fetchone()[0] == 3723


def test_the_title_is_never_touched(db, log):
    """A title can be corrected by hand and a re-read would silently undo it. Nobody is
    hand-correcting 28,000 descriptions, so those are safe to replace."""
    db.execute("UPDATE episodes SET title = 'Our Corrected Title' WHERE id = 1")
    db.commit()
    edits.refresh_episodes(db, show_id=1,
                           episodes=[ep("g1", "Publisher's Title", description="z" * 500)],
                           actor="agent:comb", note="re-read", decisions_path=log)
    assert db.execute("SELECT title FROM episodes WHERE id=1").fetchone()[0] == "Our Corrected Title"


def test_an_episode_we_do_not_hold_is_ignored(db, log):
    """Refresh updates what is there. Adding what is missing is ingest_episodes' job, and
    conflating them would let a refresh quietly resurrect episodes a merge had hidden."""
    edits.refresh_episodes(db, show_id=1,
                           episodes=[ep("brand-new", "New", description="a" * 400)],
                           actor="agent:comb", note="re-read", decisions_path=log)
    assert db.execute("SELECT count(*) FROM episodes WHERE show_id=1").fetchone()[0] == 1


def test_a_pass_that_changes_nothing_writes_nothing(db, log):
    """288 feeds re-read weekly would otherwise put 288 empty lines in the log every time."""
    db.execute("UPDATE episodes SET description = ?, duration_s = 60 WHERE id = 1", ("z" * 900,))
    db.commit()
    got = edits.refresh_episodes(db, show_id=1, episodes=[ep("g1", "Ep One", description="short",
                                                            duration_s=60)],
                                 actor="agent:comb", note="re-read", decisions_path=log)
    assert got["longer"] == 0 and got["durations"] == 0
    assert read_log(log) == []
    assert db.execute("SELECT count(*) FROM edits WHERE field='refresh'").fetchone()[0] == 0


# --- creating arcs ---------------------------------------------------------------


def arc(slug, name, members, **kw):
    return {"slug": slug, "name": name, "members": members,
            "source": kw.pop("source", "llm"), **kw}


def add_eps(conn, show_id, n, start=2):
    for i in range(start, start + n):
        conn.execute("INSERT INTO episodes (show_id, guid, title) VALUES (?,?,?)",
                     (show_id, f"g{i}", f"Ep {i}"))
    conn.commit()


def test_creating_an_arc_attaches_its_episodes(db, log):
    add_eps(db, 1, 3)
    got = edits.create_arcs(db, show_id=1, arcs=[arc("hunt", "Hunting Season", ["g2", "g3", "g4"])],
                            actor="agent:arcs", note="A8", decisions_path=log)
    assert got == {"arcs": 1, "episodes": 3, "skipped": 0}
    aid = db.execute("SELECT id FROM arcs WHERE slug='hunt'").fetchone()[0]
    assert db.execute("SELECT count(*) FROM episodes WHERE arc_id=?", (aid,)).fetchone()[0] == 3
    assert read_log(log)[-1]["arcs"] == 1


def test_a_one_episode_arc_is_dropped(db, log):
    """A 'story' of one episode is a title that happened to match a pattern."""
    add_eps(db, 1, 1)
    got = edits.create_arcs(db, show_id=1, arcs=[arc("solo", "Solo", ["g2"])],
                            actor="agent:arcs", note="A8", decisions_path=log)
    assert got["arcs"] == 0 and got["skipped"] == 1
    assert db.execute("SELECT count(*) FROM arcs WHERE slug='solo'").fetchone()[0] == 0
    assert read_log(log) == []


def test_an_episode_already_in_an_arc_is_not_stolen(db, log):
    """episodes.arc_id is a single FK, so ordering decides. Hand-adjudicated gold arcs are
    written first and a detector's guess can never take an episode off one."""
    add_eps(db, 1, 3)
    db.execute("UPDATE episodes SET arc_id = 1 WHERE guid IN ('g2','g3')")
    db.commit()
    got = edits.create_arcs(db, show_id=1, arcs=[arc("greedy", "Greedy", ["g2", "g3", "g4"])],
                            actor="agent:arcs", note="A8", decisions_path=log)
    # Only g4 was free, so the arc falls under two members and is dropped whole.
    assert got["arcs"] == 0
    assert db.execute("SELECT arc_id FROM episodes WHERE guid='g2'").fetchone()[0] == 1


def test_soft_deleted_episodes_are_not_arc_members(db, log):
    add_eps(db, 1, 3)
    db.execute("UPDATE episodes SET deleted_at='2026-07-27T00:00:00+00:00' WHERE guid='g2'")
    db.commit()
    got = edits.create_arcs(db, show_id=1, arcs=[arc("a", "A", ["g2", "g3", "g4"])],
                            actor="agent:arcs", note="A8", decisions_path=log)
    assert got["episodes"] == 2


def test_a_batch_of_arcs_is_one_log_line(db, log):
    add_eps(db, 1, 8)
    edits.create_arcs(db, show_id=1, arcs=[
        arc("a", "A", ["g2", "g3"]), arc("b", "B", ["g4", "g5"]), arc("c", "C", ["g6", "g7"])],
        actor="agent:arcs", note="A8", decisions_path=log)
    assert len(read_log(log)) == 1
    assert "3 arcs over 6 episodes" in db.execute(
        "SELECT note FROM edits ORDER BY id DESC LIMIT 1").fetchone()[0]


def test_a_duplicate_slug_is_refused_by_the_schema(db, log):
    """UNIQUE (show_id, slug). Two arcs cannot share an identity within one show, so
    collisions have to be resolved before the write, not after."""
    add_eps(db, 1, 4)
    with pytest.raises(sqlite3.IntegrityError):
        edits.create_arcs(db, show_id=1, arcs=[
            arc("same", "One", ["g2", "g3"]), arc("same", "Two", ["g4", "g5"])],
            actor="agent:arcs", note="A8", decisions_path=log)
    assert db.execute("SELECT count(*) FROM arcs WHERE slug='same'").fetchone()[0] == 0


# --- labelling episodes ----------------------------------------------------------


def label(eid, slugs, entities=None):
    return {"episode_id": eid,
            "subjects": [{"slug": s, "role": r, "confidence": c, "agreement": a, "votes": v}
                         for s, r, c, a, v in slugs],
            "entities": entities or []}


def test_a_batch_of_labels_lands_with_its_votes(db, log):
    """`agreement` was NULL on all 43,818 rows of the last run. The schema comment says
    outright: "Phase 3's relabel populates it." """
    got = edits.label_episodes(
        db, labels=[label(1, [("grief", "primary", "high", 3, 3)])],
        run_id="2026-07-relabel", model="claude-sonnet-5", actor="agent:label",
        note="relabel", decisions_path=log)
    assert got["episodes"] == 1 and got["subjects"] == 1
    row = db.execute("SELECT role, confidence, agreement, votes, model FROM episode_labels "
                     "WHERE run_id='2026-07-relabel'").fetchone()
    assert row == ("primary", "high", 3, 3, "claude-sonnet-5")


def test_the_old_run_is_not_disturbed(db, log):
    """Two runs coexist because run_id is in the key. The 2026-07 pass is the only thing
    the new one can be measured against."""
    db.execute("INSERT INTO episode_labels (episode_id, subject_id, run_id, role, confidence) "
               "VALUES (1, 1, '2026-07-theming', 'primary', 'high')")
    db.commit()
    edits.label_episodes(db, labels=[label(1, [("grief", "primary", "low", 2, 3)])],
                         run_id="2026-07-relabel", model="m", actor="agent:label",
                         note="relabel", decisions_path=log)
    assert db.execute("SELECT count(*) FROM episode_labels").fetchone()[0] == 2
    assert db.execute("SELECT confidence FROM episode_labels WHERE run_id='2026-07-theming'"
                      ).fetchone()[0] == "high"


def test_a_subject_outside_the_vocabulary_is_refused_not_guessed_at(db, log):
    """The last run kept a hand-maintained near-miss map, including one entry that silently
    dropped the row. Nobody could then tell a real answer from a typo the pipeline had
    repaired."""
    got = edits.label_episodes(
        db, labels=[label(1, [("grief", "primary", "high", None, None),
                              ("invented-slug", "secondary", "low", None, None)])],
        run_id="r", model="m", actor="agent:label", note="relabel", decisions_path=log)
    assert got["subjects"] == 1
    assert got["unknown"] == {"invented-slug": 1}


def test_a_batch_is_one_log_line(db, log):
    """43,818 rows at one line each would bury every decision a person ever made."""
    for i in range(2, 12):
        db.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (?,1,?,?)",
                   (i, f"g{i}", f"Ep {i}"))
    db.commit()
    edits.label_episodes(db, labels=[label(i, [("grief", "primary", "high", None, None)])
                                     for i in range(1, 12)],
                         run_id="r", model="m", actor="agent:label", note="relabel",
                         decisions_path=log)
    assert len(read_log(log)) == 1
    assert read_log(log)[0]["episodes"] == 11


def test_entities_are_created_on_sight(db, log):
    """Open-world by nature -- there is no fixed list of every case and company."""
    edits.label_episodes(
        db, labels=[label(1, [("grief", "primary", "high", None, None)],
                          entities=[{"name": "Theranos", "kind": "company", "confidence": "high"}])],
        run_id="r", model="m", actor="agent:label", note="relabel", decisions_path=log)
    assert db.execute("SELECT name, kind FROM entities").fetchone() == ("Theranos", "company")
    assert db.execute("SELECT count(*) FROM episode_entities").fetchone()[0] == 1


def test_an_entity_name_means_different_things_in_different_kinds(db, log):
    """"Enron" the company and "Enron" the film are different things. Collapsing them
    would make the graph claim a connection that is only a coincidence of naming."""
    edits.label_episodes(
        db, labels=[label(1, [("grief", "primary", "high", None, None)], entities=[
            {"name": "Enron", "kind": "company", "confidence": "high"},
            {"name": "Enron", "kind": "work", "confidence": "medium"}])],
        run_id="r", model="m", actor="agent:label", note="relabel", decisions_path=log)
    assert db.execute("SELECT count(*) FROM entities").fetchone()[0] == 2


def test_relabelling_the_same_episode_in_one_run_replaces_rather_than_collides(db, log):
    edits.label_episodes(db, labels=[label(1, [("grief", "primary", "low", None, None)])],
                         run_id="r", model="m", actor="agent:label", note="a", decisions_path=log)
    edits.label_episodes(db, labels=[label(1, [("grief", "primary", "high", 3, 3)])],
                         run_id="r", model="m", actor="agent:label", note="b", decisions_path=log)
    rows = db.execute("SELECT confidence, agreement FROM episode_labels WHERE run_id='r'").fetchall()
    assert rows == [("high", 3)]


def test_a_soft_deleted_episode_is_not_labelled(db, log):
    db.execute("UPDATE episodes SET deleted_at='2026-07-27T00:00:00+00:00' WHERE id=1")
    db.commit()
    got = edits.label_episodes(db, labels=[label(1, [("grief", "primary", "high", None, None)])],
                               run_id="r", model="m", actor="agent:label", note="x",
                               decisions_path=log)
    assert got["episodes"] == 0 and got["subjects"] == 0


def test_a_batch_that_places_nothing_writes_nothing(db, log):
    got = edits.label_episodes(db, labels=[label(1, [("nope", "primary", "high", None, None)])],
                               run_id="r", model="m", actor="agent:label", note="x",
                               decisions_path=log)
    assert got["subjects"] == 0
    assert read_log(log) == []
    assert db.execute("SELECT count(*) FROM edits WHERE field='label'").fetchone()[0] == 0


def test_a_retired_subject_records_why(db, log):
    """Retiring a subject changes what a listener can navigate by. `arcs` and `episodes`
    both carried `deleted_reason`; `subjects` only had the timestamp, so the one door could
    soft-delete browsable vocabulary and leave no argument behind."""
    sid = db.execute("SELECT id FROM subjects LIMIT 1").fetchone()[0]
    edits.apply(db, entity_type="subject", entity_id=sid, field="deleted_at",
                after="2026-07-29T00:00:00+00:00", decisions_path=log)
    edits.apply(db, entity_type="subject", entity_id=sid, field="deleted_reason",
                after="duplicate of another subject in the same theme", decisions_path=log)
    assert db.execute("SELECT deleted_reason FROM subjects WHERE id=?",
                      (sid,)).fetchone()[0] == "duplicate of another subject in the same theme"
