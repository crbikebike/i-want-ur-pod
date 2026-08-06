"""Group episodes into stories, using the detector we already measured.

An arc is a run of episodes that tell one story: "Hunting Season" parts 1-4, "The
Alabama Murders" across seven episodes. The app needs them to answer "where do I start
with this 800-episode show" with something better than "the beginning".

**A8** is a stack of text-matching rules that reads episode titles and finds those runs.
Eight tiers, each catching a naming style the tier before it missed -- "Part 2", "Chapter
5", "S3 E7", "Ep 4 |", a shared prefix, a complete numeric run, a season tag. It was built
and scored earlier this year against 50 hand-labelled shows: **88% of the real groupings
found, at 97% membership precision**. It costs nothing but CPU.

It has never been run on this catalog. `catalog/build/arcs.py` reads a `segment` field
baked into the 2026-07 theming files by an older, weaker version of the same idea, which
is why **221 of 275 kept shows have no arc at all**.

Two things this module does that the detector does not:

**Scores before it writes.** `curation/source/gold/gold.json` holds 590 adjudicated arcs
across 50 shows. Every run reports membership precision and junk rate against it, so a
regression is a number rather than a feeling. The bakeoff's floor was precision >= 0.95
and junk <= 0.05.

**Resolves name collisions.** American History Tellers ran "Great American Authors" twice,
years apart, as two separate 6- and 7-episode series. The detector emits both under one
name; `arcs` is `UNIQUE (show_id, slug)` so only one can be stored, and in any case a name
that does not say which story it is fails the same test "Season 1" fails. Both get a
distinct slug here and both go to the naming pass.
"""

from __future__ import annotations

import importlib.util
import json
import re
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

from catalog.build.normalize import slugify

ROOT = Path(__file__).resolve().parents[2]
GOLD = ROOT / "curation/source/gold/gold.json"

# Tier 3a clusters on a shared leading or trailing phrase with no counter, which is how
# it reaches shows that number nothing -- and also how it produced a 144-member "arc" for
# fake-diana, 72 for zeit-verbrechen and 50 for lore. The bakeoff called those "almost
# certainly junk" and left the cap as an open audit. A story is a run someone sat down and
# listened to in order; past this, it is a recurring segment or the whole feed.
MAX_MEMBERS = 24


def _cascade():
    """Load the detector by path. It is a script rather than a package, and renaming it
    into one would break the bakeoff branches that still import it under the old path."""
    spec = importlib.util.spec_from_file_location(
        "arc_cascade", ROOT / "detector/arc-cascade.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@dataclass
class ShowArcs:
    show_id: int
    slug: str
    title: str
    episodes: int
    arcs: list[dict] = field(default_factory=list)
    oversized: int = 0
    collisions: int = 0
    reruns: int = 0

    @property
    def covered(self) -> int:
        return sum(len(a["members"]) for a in self.arcs)


def episodes_for(conn: sqlite3.Connection, show_id: int) -> list[dict]:
    """The detector's input shape. Newest first, as feeds arrive."""
    return [
        {"guid": g, "title": t, "season": s, "episodeNumber": n,
         "episodeType": et or "full", "iso": (p or "")[:10]}
        for g, t, s, n, et, p in conn.execute(
            "SELECT guid, title, season, episode_number, episode_type, published_at "
            "FROM episodes WHERE show_id = ? AND deleted_at IS NULL "
            "ORDER BY published_at DESC", (show_id,))
    ]


# Words publishers put in front of a repeat. Stripped only to *compare* two arcs, never
# to rename one.
_RERUN = re.compile(
    r"^\s*(fan\s+favou?rite|encore|rerun|re-run|replay|revisit(ed)?|from\s+the\s+archive|"
    r"classic|best\s+of|listen\s+again|introducing)\s*[:\-–|]?\s*", re.IGNORECASE)
_TRAILING_YEAR = re.compile(r"\s*\((?:19|20)\d\d\)\s*$")


def _story_key(title: str) -> str:
    """A title stripped down to the story it tells, ignoring how it was re-packaged."""
    t = _TRAILING_YEAR.sub("", _RERUN.sub("", title or ""))
    return slugify(t) if t.strip() else ""


def _drop_reruns(arcs: list[dict], published: dict[str, str]) -> tuple[list[dict], int]:
    """Where a show has published the same story twice, keep the first run.

    Three shows made this obvious. Against the Odds re-ran "Crash in a Volcano" in 2026
    under a `FAN FAVORITE:` prefix; American History Tellers re-ran "Great American
    Authors"; 30 for 30 re-released "THE STERLING AFFAIRS" with `(2019)` appended. The
    detector correctly finds a run each time and correctly gives them the same name,
    because they *are* the same name.

    Merging the two would give one arc with two "Into the Crater"s in it. Renaming them
    apart would advertise a story twice. So the earlier run wins and the repeat is left
    unarced -- the episodes stay in the catalog, they simply are not offered as a second
    story to start.

    Compared on episode titles, not on the arc name. 30 for 30's third same-named arc is
    "Let's Talk Clipped", a discussion series that merely shares a prefix, and it survives
    -- which is the case a blunter "keep the earliest" rule would have destroyed.
    """
    by_name: dict[str, list[dict]] = {}
    for a in arcs:
        by_name.setdefault(slugify(a["name"]), []).append(a)

    kept, dropped = [], 0
    for group in by_name.values():
        if len(group) == 1:
            kept.extend(group)
            continue
        # Earliest first: the original is whichever ran first.
        group.sort(key=lambda a: min((published.get(g) or "9999") for g in a["members"]))
        stories = [{k for k in (_story_key(t) for t in a.get("member_titles", [])) if k}
                   for a in group]
        survivors: list[int] = []
        for i, mine in enumerate(stories):
            # Overlap, not equality. A re-release is often a partial one -- Against the
            # Odds re-ran two of "Crash in a Volcano"'s three parts -- so requiring the
            # episode sets to match exactly caught almost none of them.
            if mine and any(len(mine & stories[j]) / len(mine) >= 0.6 for j in survivors):
                dropped += 1
                continue
            survivors.append(i)
            kept.append(group[i])
    return kept, dropped


def propose(conn: sqlite3.Connection, show_id: int, cascade=None) -> ShowArcs:
    """Run the detector over one show and clean up after it. Writes nothing."""
    cascade = cascade or _cascade()
    slug, title = conn.execute(
        "SELECT slug, title FROM shows WHERE id = ?", (show_id,)).fetchone()
    eps = episodes_for(conn, show_id)
    out = ShowArcs(show_id, slug, title, len(eps))
    if not eps:
        return out

    found = cascade.a8_cascade(eps)
    show_words = set(slugify(title).split("-"))
    by_guid = {e["guid"]: e for e in eps}
    published = {e["guid"]: e.get("iso") or "" for e in eps}
    used: set[str] = set()

    # Attach the member titles so a repeat can be recognised, then drop repeats before
    # anything is given an identity.
    staged = []
    for a in found:
        members = list(dict.fromkeys(a.get("members") or []))
        if len(members) < 2:
            continue
        staged.append({**a, "members": members,
                       "member_titles": [by_guid[g]["title"] for g in members
                                         if g in by_guid]})
    staged, out.reruns = _drop_reruns(staged, published)

    for a in staged:
        members = a["members"]
        if len(members) > MAX_MEMBERS:
            out.oversized += 1
            continue

        name = (a.get("name") or "").strip()
        if not name:
            continue

        base = slugify(name)
        arc_slug, n = base, 1
        while arc_slug in used:
            # Two runs of the same name in one show. Both are real and both need a
            # distinct identity; the *name* is fixed later, by reading the episodes.
            n += 1
            arc_slug = f"{base}-{n}"
            out.collisions += 1
        used.add(arc_slug)

        out.arcs.append({
            "slug": arc_slug,
            "name": name,
            "kind": "arc",
            "source": "llm",
            # Medium, not high. A8 was measured at 97% membership precision, which is
            # good and is not "verified" -- that word is reserved for arcs a human
            # adjudicated by hand.
            "confidence": "medium",
            "members": members,
            "season": a.get("season"),
            "namesake": bool(show_words & set(base.split("-"))),
        })
    return out


# --- scoring ---------------------------------------------------------------------


def score(cascade=None) -> dict:
    """Reproduce the bakeoff's numbers, on the bakeoff's own inputs.

    Deliberately not scored against what this module proposes for the live catalog. Gold
    adjudicated a **150-episode slice** of each of 50 shows -- `gold/feeds/*.json` holds
    those exact slices -- and a show in the catalog may carry 800. Scoring catalog output
    against gold counts every arc found outside the slice as junk, which reads as a
    catastrophic regression and is an artefact of comparing different inputs. That first
    attempt reported precision 0.41 against the bakeoff's 0.97, and the detector had not
    changed at all.

    So: run the detector on the same 150 episodes gold saw, and compare. If this drifts
    from 0.97 / 0.04, the detector regressed. If it holds, a difference in the catalog
    numbers is a difference in the catalog, not in the rules.
    """
    cascade = cascade or _cascade()
    feeds_dir = GOLD.parent / "feeds"
    if not GOLD.exists() or not feeds_dir.is_dir():
        return {"shows": 0, "note": "no gold set on disk"}
    gold = json.loads(GOLD.read_text())

    hit = miss = junk = 0
    shows = 0
    gold_arcs_total = found_arcs_total = 0
    for show_slug, gold_arcs in gold.items():
        slice_path = feeds_dir / f"{show_slug}.json"
        if not slice_path.exists():
            continue
        shows += 1
        eps = json.loads(slice_path.read_text())["episodes"]

        truth: dict[str, str] = {}
        for ga in gold_arcs:
            for guid in ga.get("members", []):
                truth[guid] = ga["name"]
        gold_arcs_total += len(gold_arcs)

        for a in cascade.a8_cascade(eps):
            members = list(dict.fromkeys(a.get("members") or []))
            if len(members) < 2 or len(members) > MAX_MEMBERS:
                continue
            found_arcs_total += 1
            names = [truth.get(g) for g in members]
            grouped = [n for n in names if n]
            junk += len(names) - len(grouped)
            if not grouped:
                continue
            # The gold arc most of these belong to. Members agreeing with it are hits;
            # members dragged in from a different gold arc are misses.
            best = max(set(grouped), key=grouped.count)
            hit += grouped.count(best)
            miss += len(grouped) - grouped.count(best)

    placed = hit + miss + junk
    return {
        "shows": shows,
        "gold_arcs": gold_arcs_total,
        "arcs_found": found_arcs_total,
        "episodes_placed": placed,
        "membership_precision": round(hit / placed, 4) if placed else 0.0,
        "junk_rate": round(junk / placed, 4) if placed else 0.0,
        "wrong_arc": miss,
    }


def apply(conn: sqlite3.Connection, got: ShowArcs, *, decisions_path=None) -> dict:
    """Write one show's proposed arcs.

    Existing arcs win twice over. Their slugs are reserved, because `UNIQUE (show_id,
    slug)` would otherwise reject the whole batch on the first collision; and their
    episodes are already claimed, which `edits.create_arcs` respects. Between them, a
    hand-adjudicated `gold` arc cannot be displaced by a detector's guess.
    """
    from admin.api import edits

    taken = {
        r[0] for r in conn.execute(
            "SELECT slug FROM arcs WHERE show_id = ? AND deleted_at IS NULL", (got.show_id,))
    }
    ready = []
    for a in got.arcs:
        slug, n = a["slug"], 1
        while slug in taken:
            n += 1
            slug = f"{a['slug']}-{n}"
        taken.add(slug)
        ready.append({**a, "slug": slug})

    if not ready:
        return {"arcs": 0, "episodes": 0, "skipped": 0}
    return edits.create_arcs(
        conn, show_id=got.show_id, arcs=ready, actor="agent:arcs",
        note="A8 cascade", decisions_path=decisions_path)


# --- the naming screen -----------------------------------------------------------

# A name that could belong to any story in any show. Ordinals carry position, which is
# useful, but position is not a subject.
_SAYS_NOTHING = re.compile(
    r"^(season|series|part|chapter|episode|ep|vol|volume|book|act|arc)\s*[\d ivxlc]*$"
    r"|^[\d\W]+$"
    r"|^(bonus|extra|special|trailer|intro|introduction|update|updates|mini|minis|"
    r"interview|interviews|preview|previews|encore|rerun|replay|finale|prologue|epilogue)"
    r"e?s?$",
    re.IGNORECASE,
)


def says_nothing(name: str, *, show_title: str = "", duplicate: bool = False) -> str | None:
    """Why this name fails, or None if it is fine.

    Three ways to fail, and they are the same failure: after reading it you still do not
    know which story you are looking at.
    """
    nm = (name or "").strip()
    if not nm:
        return "no name at all"
    if _SAYS_NOTHING.match(nm):
        return "a position, not a subject"
    if slugify(nm) == slugify(show_title):
        return "just the show's own name"
    if duplicate:
        return "another arc in this show already uses it"
    return None


def needs_naming(proposals: dict[str, ShowArcs]) -> list[tuple[str, dict, str]]:
    """Every proposed arc whose name says nothing, with the reason."""
    out = []
    for show_slug, got in proposals.items():
        seen: dict[str, int] = {}
        for a in got.arcs:
            base = slugify(a["name"])
            seen[base] = seen.get(base, 0) + 1
        for a in got.arcs:
            why = says_nothing(a["name"], show_title=got.title,
                               duplicate=seen[slugify(a["name"])] > 1)
            if why:
                out.append((show_slug, a, why))
    return out
