"""Insert the two-level vocabulary: 30 themes, 148 subjects.

Runs before the episode loader, because episode_subjects needs subject ids to exist.

  THEME    the broad hand-authored categories (30 in the source file, plus any in
           added-themes.json). The browsable layer -- the deck a person swipes -- and
           what a whole SHOW is tagged with.
  SUBJECT  the 148 finer labels. What an individual EPISODE is about. Every subject
           belongs to exactly one theme, which the schema enforces with a NOT NULL
           foreign key.

The source files still use the older word "theme" for both levels (themes.json holds the
30; _vocabulary.json's `themes` array holds the 148, with a `relatedShowThemes` hint).
Those are read-only inputs, so the translation happens here rather than by rewriting them.

Every subject's theme is resolved by three passes, strongest signal first:
  1. the slug exists at both levels, so it belongs to its own namesake        (6)
  2. `relatedShowThemes` in the source already names one                     (34)
  3. the committed hand-authored mapping in subject-themes.json             (108)
                                                                      total 148

Same-slug deliberately outranks the hint. `police-misconduct` exists at both levels but
its hint points at `institutional-coverup`; following the hint would file the subject
"Police Who Broke the Rules" under The Institutional Cover-Up and leave the Police
Misconduct theme with no subjects at all. An exact slug identity is the most specific
answer available, so it wins.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class VocabularyReport:
    themes: int = 0
    subjects: int = 0
    by_source: dict[str, int] = field(default_factory=dict)
    by_confidence: dict[str, int] = field(default_factory=dict)
    crowded: dict[str, int] = field(default_factory=dict)
    empty_themes: list[str] = field(default_factory=list)

    def lines(self) -> list[str]:
        out = [
            f"vocabulary: {self.themes} themes, {self.subjects} subjects",
            f"  theme resolved by: {self.by_source}",
            f"  confidence       : {self.by_confidence}",
        ]
        if self.crowded:
            out.append(f"  NOTE themes with >15 subjects: {self.crowded}")
        if self.empty_themes:
            out.append(f"  NOTE themes with no subjects: {self.empty_themes}")
        return out


def build(
    conn: sqlite3.Connection,
    source: Path,
    mapping_file: Path,
    added_themes_file: Path | None = None,
) -> VocabularyReport:
    theme_rows = json.loads((source / "themes.json").read_text())

    # curation/source/themes.json is a read-only input, so themes added after the original
    # 30 live in a committed additions file. The 30 were authored before the 27k episodes
    # were labelled; the mapping then surfaced clusters with no home.
    added_themes_file = added_themes_file or Path(__file__).parent / "added-themes.json"
    if added_themes_file.exists():
        added = json.loads(added_themes_file.read_text())["themes"]
        known = {t["slug"] for t in theme_rows}
        for row in added:
            if row["slug"] in known:
                raise ValueError(f"added theme {row['slug']!r} already exists in themes.json")
            theme_rows.append(row)
    subject_rows = json.loads((source / "episode-themes/_vocabulary.json").read_text())["themes"]
    authored = {r["slug"]: r for r in json.loads(mapping_file.read_text())["subjects"]}

    report = VocabularyReport()

    theme_ids: dict[str, int] = {}
    for row in theme_rows:
        cur = conn.execute(
            "INSERT INTO themes (slug, name, description) VALUES (?, ?, ?)",
            (row["slug"], row["name"], row.get("description")),
        )
        theme_ids[row["slug"]] = cur.lastrowid
    report.themes = len(theme_ids)

    for subject in subject_rows:
        slug = subject["slug"]
        theme_slug, how, confidence = _resolve_theme(slug, subject, theme_ids, authored)
        if theme_slug is None:
            raise ValueError(
                f"subject {slug!r} has no theme. Add it to {mapping_file.name}."
            )
        conn.execute(
            "INSERT INTO subjects (slug, name, description, theme_id) VALUES (?, ?, ?, ?)",
            (slug, subject["name"], subject.get("definition"), theme_ids[theme_slug]),
        )
        report.by_source[how] = report.by_source.get(how, 0) + 1
        report.by_confidence[confidence] = report.by_confidence.get(confidence, 0) + 1

    report.subjects = len(subject_rows)

    # The database's vocabulary moved past the baseline -- Phase 3 created 52 subjects,
    # retired one and rewrote descriptions -- and none of that replays on a clean build
    # (replay reads the edits table, which is empty here, and creations are not
    # replayable anyway). vocabulary-current.json is the export of where it ended up;
    # applied last, as an override layer, so a rebuild lands on the vocabulary the
    # catalog actually has rather than the one it started with.
    current_file = source / "vocabulary-current.json"
    if current_file.exists():
        current = json.loads(current_file.read_text(encoding="utf-8"))
        for row in current.get("subjects") or []:
            theme_id = theme_ids.get(row["theme"])
            if theme_id is None:
                raise ValueError(
                    f"vocabulary-current subject {row['slug']!r} names unknown theme "
                    f"{row['theme']!r}")
            updated = conn.execute(
                "UPDATE subjects SET name = ?, description = ?, theme_id = ? "
                "WHERE slug = ?",
                (row["name"], row["description"], theme_id, row["slug"]))
            if updated.rowcount == 0:
                conn.execute(
                    "INSERT INTO subjects (slug, name, description, theme_id) "
                    "VALUES (?,?,?,?)",
                    (row["slug"], row["name"], row["description"], theme_id))
                report.subjects += 1
        for row in current.get("retired") or []:
            conn.execute(
                "UPDATE subjects SET deleted_at = ?, deleted_reason = ? WHERE slug = ?",
                (row["at"], row.get("reason"), row["slug"]))

    counts = dict(
        conn.execute(
            "SELECT t.slug, count(*) FROM subjects s JOIN themes t ON t.id = s.theme_id "
            "GROUP BY t.slug"
        ).fetchall()
    )
    report.crowded = {slug: n for slug, n in counts.items() if n > 15}
    report.empty_themes = sorted(set(theme_ids) - set(counts))

    conn.commit()
    return report


def _resolve_theme(
    slug: str, subject: dict, theme_ids: dict[str, int], authored: dict[str, dict]
) -> tuple[str | None, str, str]:
    """Return (theme_slug, how_we_decided, confidence)."""
    if slug in theme_ids:
        return slug, "same-slug", "high"

    related = [r for r in (subject.get("relatedShowThemes") or []) if r in theme_ids]
    if len(related) == 1:
        return related[0], "source-hint", "high"
    if len(related) > 1:
        # No source row does this today. If one ever does, the choice is ambiguous, so
        # send it to review rather than guessing.
        return related[0], "source-hint-ambiguous", "low"

    row = authored.get(slug)
    if row:
        return row["theme"], "authored", row["confidence"]

    return None, "unresolved", "low"
