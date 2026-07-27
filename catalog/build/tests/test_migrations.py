"""Migrations let the catalog outlive its import.

Phase 1 rebuilt the database from source every run. That stops being safe the moment a
human makes a judgement call, because the database then holds something no source file
does. These tests hold the two rules that make a durable database safe to evolve:
additive only, and immutable once applied.
"""

import sqlite3
from pathlib import Path

import pytest

from catalog.build import migrations

REAL_MIGRATIONS = Path(__file__).resolve().parents[2] / "migrations"
SCHEMA = Path(__file__).resolve().parents[2] / "schema.sql"


@pytest.fixture
def db():
    conn = sqlite3.connect(":memory:")
    yield conn
    conn.close()


def write(dirpath: Path, name: str, sql: str) -> Path:
    p = dirpath / name
    p.write_text(sql)
    return p


# --- applying --------------------------------------------------------------------


def test_applies_in_order_and_records_the_version(db, tmp_path):
    write(tmp_path, "001-a.sql", "CREATE TABLE a (id INTEGER PRIMARY KEY);")
    write(tmp_path, "002-b.sql", "CREATE TABLE b (id INTEGER PRIMARY KEY);")
    r = migrations.apply_all(db, tmp_path)
    assert r.applied == ["001-a.sql", "002-b.sql"]
    assert r.version == 2
    assert migrations.current_version(db) == 2


def test_running_twice_changes_nothing(db, tmp_path):
    write(tmp_path, "001-a.sql", "CREATE TABLE a (id INTEGER PRIMARY KEY);")
    migrations.apply_all(db, tmp_path)
    second = migrations.apply_all(db, tmp_path)
    assert second.applied == []
    assert second.already == 1


def test_a_new_migration_applies_to_an_existing_database(db, tmp_path):
    write(tmp_path, "001-a.sql", "CREATE TABLE a (id INTEGER PRIMARY KEY);")
    migrations.apply_all(db, tmp_path)
    write(tmp_path, "002-b.sql", "CREATE TABLE b (id INTEGER PRIMARY KEY);")
    r = migrations.apply_all(db, tmp_path)
    assert r.applied == ["002-b.sql"]
    assert r.already == 1


def test_data_added_before_a_migration_survives_it(db, tmp_path):
    """The whole point: evolving the schema must not cost the judgement calls."""
    write(tmp_path, "001-a.sql", "CREATE TABLE a (id INTEGER PRIMARY KEY, v TEXT);")
    migrations.apply_all(db, tmp_path)
    db.execute("INSERT INTO a (id, v) VALUES (1, 'a decision')")
    db.commit()

    write(tmp_path, "002-col.sql", "ALTER TABLE a ADD COLUMN extra TEXT;")
    migrations.apply_all(db, tmp_path)

    assert db.execute("SELECT v FROM a WHERE id=1").fetchone()[0] == "a decision"


# --- additive only ---------------------------------------------------------------


@pytest.mark.parametrize("sql", [
    "DROP TABLE shows;",
    "DELETE FROM shows WHERE id = 1;",
    "UPDATE shows SET title = 'x';",
    "ALTER TABLE shows RENAME TO old_shows;",
    "ALTER TABLE shows DROP COLUMN why;",
])
def test_destructive_migrations_are_refused(db, tmp_path, sql):
    write(tmp_path, "001-bad.sql", sql)
    with pytest.raises(ValueError, match="additive only"):
        migrations.apply_all(db, tmp_path)


def test_a_refused_migration_is_not_recorded(db, tmp_path):
    write(tmp_path, "001-bad.sql", "DROP TABLE shows;")
    with pytest.raises(ValueError):
        migrations.apply_all(db, tmp_path)
    assert migrations.current_version(db) == 0


@pytest.mark.parametrize("sql", [
    "CREATE TABLE other (id INTEGER PRIMARY KEY);",
    "CREATE INDEX i ON t (id);",
    "CREATE UNIQUE INDEX u ON t (id);",
    "ALTER TABLE t ADD COLUMN c TEXT;",
    "CREATE VIEW v AS SELECT id FROM t;",
    "INSERT INTO t (id) VALUES (1);",
])
def test_additive_statements_are_allowed(db, tmp_path, sql):
    write(tmp_path, "001-t.sql", "CREATE TABLE t (id INTEGER PRIMARY KEY);")
    write(tmp_path, "002-x.sql", sql)
    migrations.apply_all(db, tmp_path)  # must not raise


def test_comments_do_not_trip_the_additive_check(db, tmp_path):
    write(tmp_path, "001-a.sql",
          "-- this migration does NOT DROP TABLE anything\n"
          "CREATE TABLE a (id INTEGER PRIMARY KEY);")
    migrations.apply_all(db, tmp_path)
    assert migrations.current_version(db) == 1


# --- immutability ----------------------------------------------------------------


def test_editing_an_applied_migration_is_refused(db, tmp_path):
    """Databases that already ran it will never see the edit, so silence is the worst
    possible response."""
    p = write(tmp_path, "001-a.sql", "CREATE TABLE a (id INTEGER PRIMARY KEY);")
    migrations.apply_all(db, tmp_path)
    p.write_text("CREATE TABLE a (id INTEGER PRIMARY KEY, sneaky TEXT);")
    with pytest.raises(ValueError, match="changed after it was applied"):
        migrations.apply_all(db, tmp_path)


def test_unnumbered_migrations_are_refused(db, tmp_path):
    write(tmp_path, "runs.sql", "CREATE TABLE r (id INTEGER PRIMARY KEY);")
    with pytest.raises(ValueError, match="must start with a number"):
        migrations.apply_all(db, tmp_path)


def test_duplicate_numbers_are_refused(db, tmp_path):
    write(tmp_path, "001-a.sql", "CREATE TABLE a (id INTEGER PRIMARY KEY);")
    write(tmp_path, "001-b.sql", "CREATE TABLE b (id INTEGER PRIMARY KEY);")
    with pytest.raises(ValueError, match="duplicate migration numbers"):
        migrations.apply_all(db, tmp_path)


# --- the real ones ---------------------------------------------------------------


def test_the_shipped_migrations_apply_to_a_real_catalog(db):
    db.executescript(SCHEMA.read_text())
    r = migrations.apply_all(db, REAL_MIGRATIONS)
    assert r.version >= 1
    tables = {t[0] for t in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert "runs" in tables


def test_runs_table_accepts_a_job_kind_it_has_never_heard_of(db):
    """`kind` is deliberately not a CHECK constraint: a new job kind in Phase 4 should
    not need a migration."""
    db.executescript(SCHEMA.read_text())
    migrations.apply_all(db, REAL_MIGRATIONS)
    db.execute("INSERT INTO runs (kind, status) VALUES ('something-phase-6-invents', 'pending')")
    assert db.execute("SELECT count(*) FROM runs").fetchone()[0] == 1


def test_runs_status_is_constrained(db):
    db.executescript(SCHEMA.read_text())
    migrations.apply_all(db, REAL_MIGRATIONS)
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("INSERT INTO runs (kind, status) VALUES ('relabel', 'vibing')")


# --- soft delete, the database-wide rule -----------------------------------------


def test_every_entity_table_can_be_soft_deleted(db):
    """Nothing here is ever removed. Every row cost a fetch, a model call, or a human
    deciding -- trading that for disk space is a bad deal."""
    db.executescript(SCHEMA.read_text())
    migrations.apply_all(db, REAL_MIGRATIONS)
    for table in ("shows", "episodes", "arcs", "themes", "subjects",
                  "entities", "people", "networks"):
        cols = {r[1] for r in db.execute(f"PRAGMA table_info({table})")}
        assert "deleted_at" in cols, f"{table} cannot be soft deleted"


def test_a_soft_delete_round_trips(db):
    db.executescript(SCHEMA.read_text())
    migrations.apply_all(db, REAL_MIGRATIONS)
    db.execute("INSERT INTO shows (id, slug, title, feed_url) VALUES (1,'s','S','http://f')")
    live = "SELECT count(*) FROM shows WHERE deleted_at IS NULL"

    db.execute("UPDATE shows SET deleted_at='2026-07-27', deleted_reason='dead-feed' WHERE id=1")
    assert db.execute(live).fetchone()[0] == 0
    db.execute("UPDATE shows SET deleted_at=NULL, deleted_reason=NULL WHERE id=1")
    assert db.execute(live).fetchone()[0] == 1


def test_soft_deleting_a_show_keeps_its_episodes(db):
    """Merging a duplicate into its parent used to destroy a row. Now it hides one."""
    db.executescript(SCHEMA.read_text())
    migrations.apply_all(db, REAL_MIGRATIONS)
    db.execute("INSERT INTO shows (id, slug, title, feed_url) VALUES (1,'s','S','http://f')")
    db.execute("INSERT INTO episodes (id, show_id, guid, title) VALUES (1,1,'g','E')")
    db.execute("UPDATE shows SET deleted_at='2026-07-27' WHERE id=1")
    assert db.execute("SELECT count(*) FROM episodes").fetchone()[0] == 1


def test_a_trailing_comment_is_not_mistaken_for_sql(db, tmp_path):
    """Regression: only whole comment lines were stripped, so `ALTER TABLE ...;  -- why`
    split into the statement and a fragment starting with `--`, which then failed the
    additive check as though the comment were a statement."""
    write(tmp_path, "001-t.sql",
          "CREATE TABLE t (id INTEGER PRIMARY KEY);\n"
          "ALTER TABLE t ADD COLUMN c TEXT;   -- what c is for\n")
    migrations.apply_all(db, tmp_path)
    assert "c" in {r[1] for r in db.execute("PRAGMA table_info(t)")}


def test_a_destructive_statement_still_fails_with_comments_around_it(db, tmp_path):
    write(tmp_path, "001-bad.sql",
          "-- innocent preamble\nDROP TABLE shows;  -- trailing note\n")
    with pytest.raises(ValueError, match="additive only"):
        migrations.apply_all(db, tmp_path)
