"""Seed arcs from what the 2026-07 work already established.

Phase 3 replaces most of this with LLM-built arcs, so nothing here is precious. The
point is to have real arcs in the graph now so the entry-point and next-thing queries
can be proven against something.

Two sources, and gold always wins:

  gold/gold.json  589 human/agent-verified arcs over 50 shows, members listed by guid.
                  Inserted at confidence 'verified'.
  the `segment`   The regex cascade's output, already baked into each episode record.
  field           287 groups of 2+ episodes. Inserted at confidence 'low' -- these are
                  title-prefix matches, and their names read mechanically because a
                  regex chose them.

An arc of one episode is not an arc, so single-member segment groups are dropped.

Stale gold guids
----------------
Publishers rewrite episode guids when they change hosts -- 99% Invisible moved to PRX
and every guid gained a `prx_96_` prefix -- which silently orphans gold arc members
recorded under the old guid. gold-guid-remap.json holds the resolutions, each matched by
a unique exact episode-title match against the gitignored gold_feeds snapshot. It is
committed so the build stays reproducible from tracked data alone.

53 members remain unresolvable, 45 of them 99% Invisible's "100 Objects" run, whose
episodes are simply not in the fetched corpus. That is the coverage gap Phase 1
deliberately accepts; the arcs it costs are reported, not hidden.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

from catalog.build.normalize import slugify


@dataclass
class ArcReport:
    gold_arcs: int = 0
    segment_arcs: int = 0
    episodes_in_arcs: int = 0
    shows_with_arcs: int = 0
    merged_duplicate_names: list[str] = field(default_factory=list)
    gold_shows_missing: list[str] = field(default_factory=list)
    gold_shows_with_no_arcs: list[str] = field(default_factory=list)
    gold_members_not_found: int = 0
    gold_members_remapped: int = 0
    segment_members_ceded_to_gold: int = 0
    singleton_segments_dropped: int = 0

    def lines(self) -> list[str]:
        out = [
            f"arcs: {self.gold_arcs} verified (gold) + {self.segment_arcs} low (segment) "
            f"= {self.gold_arcs + self.segment_arcs}",
            f"  episodes placed in an arc: {self.episodes_in_arcs}",
            f"  shows reaching depth 3   : {self.shows_with_arcs}",
            f"  single-episode segment groups dropped: {self.singleton_segments_dropped}",
            f"  segment members ceded to a gold arc  : {self.segment_members_ceded_to_gold}",
        ]
        if self.gold_members_remapped:
            out.append(
                f"  gold members recovered from a rewritten guid: {self.gold_members_remapped}"
            )
        if self.merged_duplicate_names:
            out.append(f"  merged same-named gold arcs: {self.merged_duplicate_names}")
        if self.gold_shows_with_no_arcs:
            out.append(
                f"  gold entries that list no arcs (not a failure): "
                f"{self.gold_shows_with_no_arcs}"
            )
        if self.gold_members_not_found:
            out.append(
                f"  WARN gold members whose episode is absent from the corpus: "
                f"{self.gold_members_not_found}"
            )
        if self.gold_shows_missing:
            out.append(f"  WARN gold shows with no episodes to attach to: {self.gold_shows_missing}")
        return out


def seed(conn: sqlite3.Connection, source: Path, remap_file: Path | None = None) -> ArcReport:
    report = ArcReport()
    remap_file = remap_file or Path(__file__).parent / "gold-guid-remap.json"

    show_ids = {slug: sid for slug, sid in conn.execute("SELECT slug, id FROM shows")}
    # (show_id, guid) -> episode id. Guids are only unique within a feed.
    episode_ids = {
        (sid, guid): eid
        for eid, sid, guid in conn.execute("SELECT id, show_id, guid FROM episodes")
    }

    claimed: set[int] = set()  # episode ids already inside a gold arc

    _seed_gold(conn, source, show_ids, episode_ids, claimed, report, remap_file)
    _seed_segments(conn, source, show_ids, episode_ids, claimed, report)

    conn.execute(
        "UPDATE shows SET depth = 3 WHERE depth = 2 AND id IN (SELECT DISTINCT show_id FROM arcs)"
    )
    report.shows_with_arcs = conn.execute(
        "SELECT count(DISTINCT show_id) FROM arcs"
    ).fetchone()[0]
    report.episodes_in_arcs = conn.execute(
        "SELECT count(*) FROM episodes WHERE arc_id IS NOT NULL"
    ).fetchone()[0]

    conn.commit()
    return report


def _seed_gold(conn, source: Path, show_ids, episode_ids, claimed, report, remap_file: Path) -> None:
    gold = json.loads((source / "gold/gold.json").read_text())
    remap = {}
    if remap_file.exists():
        remap = {k: v["to"] for k, v in json.loads(remap_file.read_text())["remap"].items()}

    for show_slug, arclist in sorted(gold.items()):
        if not arclist:
            # An empty entry means nobody recorded arcs for that show, which is not a
            # failure -- it just has none yet.
            report.gold_shows_with_no_arcs.append(show_slug)
            continue

        # Gold slugs predate the catalog's, and a few drop a leading article
        # ("gun-machine" vs "the-gun-machine").
        show_id = show_ids.get(show_slug) or show_ids.get(f"the-{show_slug}")
        if show_id is None:
            report.gold_shows_missing.append(f"{show_slug} (no such show)")
            continue

        # One show records the same arc twice with a typo'd guid, so same-named arcs are
        # merged into one rather than suffixed apart: they are the same story.
        merged: dict[str, dict] = {}
        for arc in arclist:
            slug = _arc_slug(arc["name"])
            if slug in merged:
                report.merged_duplicate_names.append(f"{show_slug}:{arc['name']}")
                merged[slug]["members"].extend(arc.get("members") or [])
            else:
                merged[slug] = {"name": arc["name"], "members": list(arc.get("members") or [])}

        attached_any = False
        for slug, arc in merged.items():
            member_ids = []
            for guid in dict.fromkeys(arc["members"]):  # de-dup, keep order
                eid = episode_ids.get((show_id, guid))
                if eid is None and guid in remap:
                    eid = episode_ids.get((show_id, remap[guid]))
                    if eid is not None:
                        report.gold_members_remapped += 1
                if eid is None:
                    report.gold_members_not_found += 1
                    continue
                member_ids.append(eid)

            if not member_ids:
                # An arc whose every episode has since left the feed carries no
                # information; skip it rather than store an empty arc.
                continue

            cur = conn.execute(
                "INSERT INTO arcs (show_id, slug, kind, name, confidence, source) "
                "VALUES (?, ?, 'arc', ?, 'verified', 'gold')",
                (show_id, slug, arc["name"]),
            )
            arc_id = cur.lastrowid
            report.gold_arcs += 1
            attached_any = True

            conn.executemany(
                "UPDATE episodes SET arc_id = ? WHERE id = ?",
                [(arc_id, eid) for eid in member_ids],
            )
            claimed.update(member_ids)

        if not attached_any:
            report.gold_shows_missing.append(f"{show_slug} (no member guids matched)")


def _seed_segments(conn, source: Path, show_ids, episode_ids, claimed, report) -> None:
    """Group episodes by the segment prefix the regex cascade already recorded."""
    for path in sorted((source / "episode-themes").glob("*.json")):
        if path.name.startswith("_"):
            continue
        data = json.loads(path.read_text())
        show_slug = data.get("slug") or path.stem
        show_id = show_ids.get(show_slug)
        if show_id is None:
            continue

        groups: dict[str, list[str]] = {}
        for ep in data.get("episodes") or []:
            segment = (ep.get("segment") or "").strip()
            if segment:
                groups.setdefault(segment, []).append(ep["guid"])

        taken_slugs = {
            slug for slug, in conn.execute("SELECT slug FROM arcs WHERE show_id = ?", (show_id,))
        }

        for name, guids in groups.items():
            member_ids = []
            for guid in dict.fromkeys(guids):
                eid = episode_ids.get((show_id, guid))
                if eid is None:
                    continue
                if eid in claimed:
                    # Gold said something more specific about this episode. Leave it.
                    report.segment_members_ceded_to_gold += 1
                    continue
                member_ids.append(eid)

            if len(member_ids) < 2:
                report.singleton_segments_dropped += 1
                continue

            slug = _arc_slug(name)
            if slug in taken_slugs:
                # A gold arc already owns this name for this show; gold wins.
                continue
            taken_slugs.add(slug)

            cur = conn.execute(
                "INSERT INTO arcs (show_id, slug, kind, name, confidence, source) "
                "VALUES (?, ?, 'arc', ?, 'low', 'segment')",
                (show_id, slug, name),
            )
            arc_id = cur.lastrowid
            report.segment_arcs += 1
            conn.executemany(
                "UPDATE episodes SET arc_id = ? WHERE id = ?",
                [(arc_id, eid) for eid in member_ids],
            )
            claimed.update(member_ids)


def _arc_slug(name: str) -> str:
    """Arc names are free text and a few are punctuation-only, so fall back on a hash."""
    try:
        return slugify(name)
    except ValueError:
        return f"arc-{abs(hash(name)) % 10**8}"
