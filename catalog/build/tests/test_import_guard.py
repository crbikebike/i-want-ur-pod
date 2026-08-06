"""Importing must not be able to erase an afternoon of review.

Phase 1's importer deleted and rebuilt the database every run, which was safe only while
the database was purely derived. It no longer is: judgement calls live in it and nowhere
else. So the importer refuses, loudly, and says what it would have destroyed.
"""

import sqlite3
from pathlib import Path

import pytest

from catalog.build import migrate

SCHEMA = Path(__file__).resolve().parents[2] / "schema.sql"


def make_catalog(path: Path, human_edits: int = 0) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(SCHEMA.read_text())
    conn.execute("INSERT INTO shows (slug, title, feed_url) VALUES ('s', 'S', 'http://f')")
    conn.execute(
        "INSERT INTO edits (at, actor, entity_type, entity_key, field, after) "
        "VALUES ('2026-07-26', 'agent:migrate', 'catalog', '', 'note', 'x')")
    for i in range(human_edits):
        conn.execute(
            "INSERT INTO edits (at, actor, entity_type, entity_key, field, after) "
            "VALUES ('2026-07-27', 'human', 'show', 's', 'include_verdict', ?)", (f"keep{i}",))
    conn.commit()
    conn.close()


def test_guard_allows_a_fresh_import(tmp_path):
    migrate.guard(tmp_path / "nothing-here.db")  # must not raise


def test_guard_refuses_an_existing_catalog(tmp_path):
    db = tmp_path / "catalog.db"
    make_catalog(db)
    with pytest.raises(migrate.WouldDestroyWork):
        migrate.guard(db)


def test_the_refusal_says_what_would_be_lost(tmp_path):
    """A refusal you can't act on is just an obstacle."""
    db = tmp_path / "catalog.db"
    make_catalog(db, human_edits=37)
    with pytest.raises(migrate.WouldDestroyWork) as e:
        migrate.guard(db)
    message = str(e.value)
    assert "37 human decisions" in message
    assert "--force" in message
    assert "migrations" in message


def test_agent_edits_are_not_counted_as_decisions(tmp_path):
    """The importer writes its own note about duplicate feeds. That is not review work."""
    db = tmp_path / "catalog.db"
    make_catalog(db, human_edits=0)
    with pytest.raises(migrate.WouldDestroyWork) as e:
        migrate.guard(db)
    assert "0 human decisions" in str(e.value)


def test_a_corrupt_file_still_refuses(tmp_path):
    """If we cannot read it we certainly should not delete it."""
    db = tmp_path / "catalog.db"
    db.write_bytes(b"this is not a database")
    with pytest.raises(migrate.WouldDestroyWork):
        migrate.guard(db)


def test_build_refuses_without_force(tmp_path):
    db = tmp_path / "catalog.db"
    make_catalog(db, human_edits=3)
    with pytest.raises(migrate.WouldDestroyWork):
        migrate.build(out=db, quiet=True)
    # and the file is untouched
    conn = sqlite3.connect(db)
    assert conn.execute("SELECT count(*) FROM shows").fetchone()[0] == 1
    conn.close()


def test_the_cli_exits_nonzero_rather_than_clobbering(tmp_path, capsys):
    db = tmp_path / "catalog.db"
    make_catalog(db, human_edits=1)
    code = migrate.main(["--out", str(db)])
    assert code == 2
    assert "refusing to import" in capsys.readouterr().err
