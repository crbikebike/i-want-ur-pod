"""Content hash over the catalog, for proving a rebuild is reproducible.

Deliberately NOT a hash of the .db file. A SQLite file carries page layout, freelist
state and a change counter that vary between runs without the data differing, and
releases.built_at is a timestamp by design. Hashing the bytes would fail for reasons
that have nothing to do with the catalog being different.

Instead: dump every table's rows in a deterministic order and hash that. This proves the
*data* is reproducible, which is the property a permanent catalog actually needs.
"""

from __future__ import annotations

import hashlib
import sqlite3

# built_at is a timestamp and content_hash is what we are computing, so a release row can
# never take part in its own fingerprint. `search` and its shadow tables are a derived
# index over text that is hashed anyway.
EXCLUDED_TABLES = frozenset({"releases", "search"})

# Anything SQLite owns: sqlite_sequence, and in particular sqlite_stat1, which PRAGMA
# optimize writes AFTER the hash is taken. Query-planner statistics are not content, and
# including them makes a rebuild look non-reproducible for no reason.
EXCLUDED_PREFIXES = ("search_", "sqlite_")


def _tables(conn: sqlite3.Connection) -> list[str]:
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
    ).fetchall()
    return [
        name
        for (name,) in rows
        if name not in EXCLUDED_TABLES and not name.startswith(EXCLUDED_PREFIXES)
    ]


def content_hash(conn: sqlite3.Connection) -> str:
    digest = hashlib.sha256()
    for table in _tables(conn):
        columns = [row[1] for row in conn.execute(f"PRAGMA table_info({table})")]
        # Order by every column so the result cannot depend on insertion order or on
        # how SQLite happens to lay out pages.
        order = ", ".join(f'"{c}"' for c in columns)
        select = ", ".join(f'"{c}"' for c in columns)
        digest.update(f"table:{table}({','.join(columns)})\n".encode())
        for row in conn.execute(f'SELECT {select} FROM "{table}" ORDER BY {order}'):
            digest.update(("\x1f".join("\x00" if v is None else str(v) for v in row) + "\n").encode())
    return digest.hexdigest()


def table_counts(conn: sqlite3.Connection) -> dict[str, int]:
    return {
        table: conn.execute(f'SELECT count(*) FROM "{table}"').fetchone()[0]
        for table in _tables(conn)
    }
