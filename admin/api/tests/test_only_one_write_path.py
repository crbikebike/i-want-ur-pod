"""No module in the API may write to the catalog except edits.py.

This is a structural test rather than a behavioural one, and it is here because the
promise it protects cannot be tested any other way. Every guarantee the workbench makes
-- the audit trail, undo, decisions surviving in git -- holds only if there is exactly
one door. A single `UPDATE shows SET ...` in a route handler silently voids all three,
and nothing would fail.

Adding a table write outside edits.py should be uncomfortable. This makes it fail.
"""

import ast
import re
from pathlib import Path

import pytest

API = Path(__file__).resolve().parents[1]

# edits.py is the door. migrations own DDL. Tests set up their own fixtures.
EXEMPT = {"edits.py"}

WRITE_SQL = re.compile(
    r"\b(INSERT\s+INTO|UPDATE\s+\"?\w+\"?\s+SET|DELETE\s+FROM|REPLACE\s+INTO|"
    r"DROP\s+TABLE|ALTER\s+TABLE)\b",
    re.IGNORECASE,
)

# Tables the workbench may never write outside the door, even from edits.py's helpers.
CATALOG_TABLES = {
    "shows", "episodes", "arcs", "themes", "subjects", "episode_subjects",
    "show_themes", "edges", "entities", "people", "networks",
    # Phase 3's label storage. Added here the moment the tables existed: a guard that
    # lags the schema protects the tables nobody is writing yet.
    "episode_labels", "episode_entities",
}


def api_modules():
    return [
        p for p in sorted(API.glob("*.py"))
        if p.name not in EXEMPT and not p.name.startswith("_")
    ]


def string_literals(path: Path) -> list[str]:
    tree = ast.parse(path.read_text())
    out = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            out.append(node.value)
        elif isinstance(node, ast.JoinedStr):  # f-strings
            out.append("".join(
                p.value for p in node.values
                if isinstance(p, ast.Constant) and isinstance(p.value, str)
            ))
    return out


@pytest.mark.parametrize("path", api_modules(), ids=lambda p: p.name)
def test_module_contains_no_write_sql(path):
    offenders = []
    for literal in string_literals(path):
        match = WRITE_SQL.search(literal)
        if not match:
            continue
        # A write to a workbench-owned table (runs, sessions) is fine; a write to the
        # catalog is not.
        touches_catalog = any(
            re.search(rf"\b{t}\b", literal, re.IGNORECASE) for t in CATALOG_TABLES
        )
        if touches_catalog:
            offenders.append(f"{match.group(0).strip()} … in {literal.strip()[:60]!r}")

    assert not offenders, (
        f"{path.name} writes to the catalog directly:\n  "
        + "\n  ".join(offenders)
        + "\n\nEvery catalog change goes through edits.apply(), which updates the row, "
          "appends to `edits`, and appends to decisions.jsonl in one transaction. "
          "Writing around it means no audit trail, no undo, and decisions that never "
          "reach git."
    )


def test_the_guard_would_actually_catch_something(tmp_path):
    """A test that can never fail is decoration. Prove this one bites."""
    bad = tmp_path / "sneaky.py"
    bad.write_text('def go(conn):\n    conn.execute("UPDATE shows SET title = ? WHERE id = ?")\n')
    found = [
        lit for lit in string_literals(bad)
        if WRITE_SQL.search(lit) and re.search(r"\bshows\b", lit, re.IGNORECASE)
    ]
    assert found, "the guard failed to spot a direct catalog write"


def test_edits_is_the_only_exemption():
    """If this list grows, the single-door promise is being negotiated away."""
    assert EXEMPT == {"edits.py"}


# --- who gets the network traffic ------------------------------------------------

# Podcast Index gives us a 4.7M-row dump as a single file. It is generous, it is free, and
# it is a volunteer project. Hammering their API when the answer is already on disk would
# be rude and would eventually get us blocked.
PODCASTINDEX_API = re.compile(r"api\.podcastindex\.org", re.IGNORECASE)

# The one permitted mention: the download URL, which lives in a docstring so a person can
# find it. It is a different host from the API.
PODCASTINDEX_DUMP = re.compile(r"public\.podcastindex\.org", re.IGNORECASE)


@pytest.mark.parametrize("path", sorted(API.glob("*.py")), ids=lambda p: p.name)
def test_no_module_calls_the_podcastindex_api(path):
    """The dump is a file, not an API. One download, then zero requests.

    If a show is missing from it the fallback is Apple, which is a commercial service with
    a published search endpoint built for exactly this. Bulk episode text comes from the
    publisher's own feed, which is the only place it exists.
    """
    source = path.read_text()
    hits = [line.strip() for line in source.splitlines() if PODCASTINDEX_API.search(line)]
    assert not hits, (
        f"{path.name} reaches api.podcastindex.org:\n  " + "\n  ".join(hits)
        + "\n\nUse the local dump (admin/api/podcastindex.py) or fall back to Apple."
    )


def test_the_dump_url_is_still_documented_somewhere():
    """A guard that only forbids is a guard that eventually deletes the thing it protects.

    Somebody has to be able to find where the dump comes from, and the answer must not be
    'git log'.
    """
    mentions = [p.name for p in API.glob("*.py") if PODCASTINDEX_DUMP.search(p.read_text())]
    assert mentions, "nothing records where the Podcast Index dump is downloaded from"
