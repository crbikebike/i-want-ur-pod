"""Populate the full-text search index.

One row per episode, at rowid = the episode's id, so a MATCH gives back something the
caller can join on directly.

The table is contentless, so this module can neither read rows back nor DELETE them the
usual way -- clearing it uses FTS5's 'delete-all' command. That is fine because the
index is always rebuilt whole.
"""

from __future__ import annotations

import sqlite3


def build(conn: sqlite3.Connection) -> int:
    # A contentless FTS5 table rejects a plain DELETE; this is the supported way.
    conn.execute("INSERT INTO search (search) VALUES ('delete-all')")
    cur = conn.execute(
        "INSERT INTO search (rowid, title, description, show_title) "
        "SELECT e.id, e.title, coalesce(e.description, ''), s.title "
        "FROM episodes e JOIN shows s ON s.id = e.show_id"
    )
    count = cur.rowcount
    conn.commit()
    return count
