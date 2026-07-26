"""Insert the two-tier theme vocabulary.

Runs before the episode loader, because episode_themes rows need theme ids to exist.

The 30 tier-1 themes are the browsable layer -- the deck a person swipes. The 148
tier-2 themes are what episodes actually carry. Every tier-2 theme must name a parent,
which the schema enforces, so this module's whole job is making sure all 148 have one.

Three passes, strongest signal first:
  1. the slug exists at both tiers, so it parents to its own namesake       (5)
  2. `relatedShowThemes` in the source vocabulary already names a parent   (34)
  3. the committed hand-authored mapping                                  (109)
                                                                     total 148

Same-slug deliberately outranks the vocabulary hint. `police-misconduct` exists at both
tiers but its hint points at `institutional-coverup`; taking the hint would parent
"Police Who Broke the Rules" under The Institutional Cover-Up and leave the Police
Misconduct browse category with no children at all. An exact slug identity is the most
specific parent available, so it wins.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class ThemeReport:
    tier1: int = 0
    tier2: int = 0
    by_source: dict[str, int] = field(default_factory=dict)
    by_confidence: dict[str, int] = field(default_factory=dict)
    overloaded: dict[str, int] = field(default_factory=dict)
    childless: list[str] = field(default_factory=list)

    def lines(self) -> list[str]:
        out = [
            f"themes: {self.tier1} tier-1, {self.tier2} tier-2",
            f"  parent resolved by: {self.by_source}",
            f"  parent confidence : {self.by_confidence}",
        ]
        if self.overloaded:
            out.append(f"  NOTE parents with >15 children: {self.overloaded}")
        if self.childless:
            out.append(f"  NOTE tier-1 themes with no children: {self.childless}")
        return out


def build(conn: sqlite3.Connection, source: Path, mapping_file: Path) -> ThemeReport:
    tier1_rows = json.loads((source / "themes.json").read_text())
    vocab = json.loads((source / "episode-themes/_vocabulary.json").read_text())["themes"]
    authored = {
        r["slug"]: r for r in json.loads(mapping_file.read_text())["themes"]
    }

    report = ThemeReport()

    # --- tier 1 ---------------------------------------------------------------
    tier1_ids: dict[str, int] = {}
    for row in tier1_rows:
        cur = conn.execute(
            "INSERT INTO themes (slug, tier, name, description, parent_id) "
            "VALUES (?, 1, ?, ?, NULL)",
            (row["slug"], row["name"], row.get("description")),
        )
        tier1_ids[row["slug"]] = cur.lastrowid
    report.tier1 = len(tier1_ids)

    # --- tier 2 ---------------------------------------------------------------
    for theme in vocab:
        slug = theme["slug"]
        parent_slug, source_kind, confidence = _resolve_parent(slug, theme, tier1_ids, authored)

        if parent_slug is None:
            # The schema would reject this anyway; failing here says which theme and why.
            raise ValueError(
                f"tier-2 theme {slug!r} has no parent. Add it to {mapping_file.name}."
            )

        conn.execute(
            "INSERT INTO themes (slug, tier, name, description, parent_id) "
            "VALUES (?, 2, ?, ?, ?)",
            (slug, theme["name"], theme.get("definition"), tier1_ids[parent_slug]),
        )
        report.by_source[source_kind] = report.by_source.get(source_kind, 0) + 1
        report.by_confidence[confidence] = report.by_confidence.get(confidence, 0) + 1

    report.tier2 = len(vocab)

    # --- sanity checks: reported, never fatal --------------------------------
    counts = dict(
        conn.execute(
            "SELECT p.slug, count(*) FROM themes c JOIN themes p ON p.id = c.parent_id "
            "WHERE c.tier = 2 GROUP BY p.slug"
        ).fetchall()
    )
    report.overloaded = {slug: n for slug, n in counts.items() if n > 15}
    report.childless = sorted(set(tier1_ids) - set(counts))

    conn.commit()
    return report


def _resolve_parent(
    slug: str,
    theme: dict,
    tier1_ids: dict[str, int],
    authored: dict[str, dict],
) -> tuple[str | None, str, str]:
    """Return (parent_slug, how_we_decided, confidence)."""
    if slug in tier1_ids:
        # "Political Scandal" the browse category, `political-scandal` the specific
        # episode theme beneath it. Same concept at two zoom levels, and the most
        # specific parent available -- so this outranks the vocabulary hint.
        return slug, "same-slug", "high"

    related = [r for r in (theme.get("relatedShowThemes") or []) if r in tier1_ids]
    if len(related) == 1:
        return related[0], "vocabulary", "high"
    if len(related) > 1:
        # No source row does this today. If one ever does, the choice is ambiguous, so
        # send it to review rather than guessing.
        return related[0], "vocabulary-ambiguous", "low"

    row = authored.get(slug)
    if row:
        return row["parent"], "authored", row["confidence"]

    return None, "unresolved", "low"
