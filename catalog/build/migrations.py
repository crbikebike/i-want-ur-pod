"""Evolve the catalog's schema without rebuilding it.

Phase 1 built the database by deleting it and re-importing from curation/source/. That
was right for a one-time import and wrong as a permanent posture: the moment a human
makes a judgement call, the database holds something the source files do not, and a
rebuild would destroy it.

So the database is durable now, and schema changes arrive as numbered files in
catalog/migrations/, applied in order, exactly once, recorded in schema_version.

Two rules, both enforced below:

  ADDITIVE ONLY, where "additive" is about data rather than schema objects. A migration
  may CREATE, or ALTER TABLE ... ADD COLUMN, and it may DROP an INDEX -- an index holds
  no data, so dropping one destroys nothing and recreating it with a better condition is
  the only way to fix one. It may not DROP a table, DELETE, UPDATE, or rename. Anything
  that would destroy or rewrite data is a decision a human makes in the workbench, where
  it is logged and reversible, not something that happens silently at startup.

  IMMUTABLE ONCE APPLIED. Migrations are checksummed. Editing one after it has run is
  almost always a mistake -- the databases that already ran it will never see the change
  -- so it is refused rather than quietly ignored.
"""

from __future__ import annotations

import hashlib
import re
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "migrations"

# Statements a migration is allowed to start with. Anything else means the migration is
# trying to change or destroy existing data.
_ALLOWED = re.compile(
    r"^\s*(CREATE\s+(TABLE|INDEX|UNIQUE\s+INDEX|VIEW|VIRTUAL\s+TABLE|TRIGGER)"
    r"|ALTER\s+TABLE\s+\S+\s+ADD\s+COLUMN"
    r"|DROP\s+INDEX"
    r"|INSERT\s+INTO)",
    re.IGNORECASE,
)


@dataclass
class MigrationReport:
    applied: list[str] = field(default_factory=list)
    already: int = 0
    version: int = 0

    def lines(self) -> list[str]:
        if self.applied:
            return [f"migrations: applied {len(self.applied)} -> v{self.version}",
                    *(f"  + {name}" for name in self.applied)]
        return [f"migrations: up to date at v{self.version} ({self.already} applied)"]


def _ensure_table(conn: sqlite3.Connection) -> None:
    conn.execute(
        "CREATE TABLE IF NOT EXISTS schema_version ("
        "  version    INTEGER PRIMARY KEY,"
        "  name       TEXT NOT NULL,"
        "  checksum   TEXT NOT NULL,"
        "  applied_at TEXT NOT NULL DEFAULT (datetime('now'))"
        ")"
    )


def _discover(directory: Path) -> list[tuple[int, str, Path]]:
    found = []
    for path in sorted(directory.glob("*.sql")):
        match = re.match(r"^(\d+)-", path.name)
        if not match:
            raise ValueError(f"migration must start with a number: {path.name}")
        found.append((int(match.group(1)), path.name, path))
    versions = [v for v, _, _ in found]
    if len(set(versions)) != len(versions):
        raise ValueError(f"duplicate migration numbers in {directory}")
    return found


def _statements(sql: str) -> list[str]:
    """Split on semicolons, dropping comments and blanks.

    Trailing comments are stripped as well as whole comment lines. Only dropping whole
    lines meant `ALTER TABLE t ADD COLUMN c TEXT;  -- what c is for` split into the
    statement and a fragment starting with `--`, which then failed the additive check as
    though the comment were SQL.

    Good enough because migrations are additive DDL. A `--` or a semicolon inside a
    string literal would break this, which is a reason not to put either in a migration.
    """
    lines = []
    for line in sql.splitlines():
        code = line.split("--", 1)[0]
        if code.strip():
            lines.append(code)
    return [s.strip() for s in "\n".join(lines).split(";") if s.strip()]


def _check_additive(name: str, sql: str) -> None:
    for statement in _statements(sql):
        if not _ALLOWED.match(statement):
            first = statement.split("\n")[0][:70]
            raise ValueError(
                f"{name}: migrations are additive only, and this is not: {first!r}. "
                f"Destroying or rewriting data is a decision a human makes in the "
                f"workbench, where it is logged and reversible."
            )


def apply_all(conn: sqlite3.Connection, directory: Path | None = None) -> MigrationReport:
    directory = directory or MIGRATIONS_DIR
    report = MigrationReport()
    _ensure_table(conn)

    seen = {
        version: (name, checksum)
        for version, name, checksum in conn.execute(
            "SELECT version, name, checksum FROM schema_version"
        )
    }

    if not directory.is_dir():
        report.already = len(seen)
        report.version = max(seen, default=0)
        return report

    for version, name, path in _discover(directory):
        sql = path.read_text()
        checksum = hashlib.sha256(sql.encode()).hexdigest()[:16]

        if version in seen:
            _, applied_checksum = seen[version]
            if applied_checksum != checksum:
                raise ValueError(
                    f"{name} changed after it was applied. Databases that already ran it "
                    f"will never see the edit, so this is refused. Add a new migration "
                    f"instead."
                )
            report.already += 1
            continue

        _check_additive(name, sql)
        conn.executescript(sql)
        conn.execute(
            "INSERT INTO schema_version (version, name, checksum) VALUES (?, ?, ?)",
            (version, name, checksum),
        )
        conn.commit()
        report.applied.append(name)

    report.version = conn.execute(
        "SELECT coalesce(max(version), 0) FROM schema_version"
    ).fetchone()[0]
    return report


def current_version(conn: sqlite3.Connection) -> int:
    try:
        return conn.execute("SELECT coalesce(max(version), 0) FROM schema_version").fetchone()[0]
    except sqlite3.OperationalError:
        return 0
