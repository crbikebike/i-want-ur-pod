"""Read curation/source/ into the catalog: networks, shows, episodes, vocabulary links.

Runs after vocabulary.build(), because episode_subjects needs subject ids.

Shows are tagged with THEMES (the browsable 30). Episodes carry SUBJECTS (the finer 148).
The source files call both levels "themes" -- they are read-only inputs, so the
translation happens here rather than by rewriting them.

The join, and why it is on title rather than feed_url
-----------------------------------------------------
catalog.json carries no slug -- only an integer id and a feedUrl. Every other source
file is keyed by slug. The obvious join is therefore feedUrl, except that only feeds/
and descriptions/ carry a feedUrl and both are gitignored, so on a clean clone the key
would not exist.

Exact title match turns out to be a perfect key on tracked data alone: 303 of 303
labelled shows match, no title appears twice in either file, and the 12 that fail to
match are exactly the 12 shows with no episode labels. Measured against feeds/ while it
was present locally, title-joined pairs agreed on normalized feed_url 315 times out of
315, with zero disagreements. So feed_url is kept as a cross-check, not the key.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

from catalog.build.normalize import normalize_feed_url, slugify

RUN_ID = "2026-07-theming"

# Shows whose feed serves a different programme than the row claims. The list lives in
# admin/api/suspects.py so the workbench can explain each one rather than just flag it.
from admin.api.suspects import EXPLICIT_SUSPECTS  # noqa: E402

# Language is detected from EPISODE TITLES, not from the show description: descriptions
# in catalog.json were written by the curator in English, so they say nothing about the
# language the show is in.
#
# Markers are function words with little or no English collision. Words like "as", "no",
# "is" and "e" are deliberately absent -- including "as" was enough on its own to
# misread the English show "Hollywoodland" as Portuguese.
# Accented and unaccented forms are both listed: publishers often strip diacritics from
# RSS titles, so requiring the accent would miss real Spanish and Portuguese shows.
_LANG_MARKERS = {
    "es": {" el ", " los ", " las ", " que ", " para ", " con ", " una ", " del ", " por ",
           " como ", " más ", " mas ", " sin ", " sus "},
    "fr": {" le ", " les ", " des ", " une ", " qui ", " dans ", " pour ", " avec ", " est ",
           " sur ", " aux ", " leur "},
    "pt": {" uma ", " não ", " nao ", " dos ", " para ", " são ", " sao ", " pelo ", " nos ",
           " mais "},
    "de": {" der ", " die ", " das ", " und ", " ein ", " mit ", " von ", " nicht ", " sich ",
           " auf ", " eine "},
    "it": {" il ", " gli ", " che ", " per ", " con ", " del ", " nella ", " sono ", " dei "},
}

# A show must clear all three bars before it is called non-English: enough marker hits
# relative to length, enough DISTINCT markers, and enough titles to judge from.
#
# Distinct-marker count is the load-bearing test, and the corpus separates cleanly on it.
# The nine genuinely non-English shows all hit 6+ distinct markers (rate 0.045-0.137);
# the closest English shows hit at most 2. One repeated word therefore cannot carry a
# verdict, which is the failure mode a rate-only threshold has.
_LANG_MIN_RATE = 0.04
_LANG_MIN_DISTINCT = 5
_LANG_MIN_EPISODES = 5


@dataclass
class LoadReport:
    networks: int = 0
    shows: int = 0
    episodes: int = 0
    show_theme_links: int = 0
    episode_subject_links: int = 0
    recovered_episodes: int = 0
    recovered_shows: int = 0
    combed_episodes: int = 0
    combed_shows: int = 0
    tombstoned_shows: int = 0
    tombstoned_episodes: int = 0
    depth1_shows: list[str] = field(default_factory=list)
    unjoined: list[str] = field(default_factory=list)
    feed_url_mismatches: list[str] = field(default_factory=list)
    shared_feed_groups: list[list[str]] = field(default_factory=list)
    duplicate_pairs: list[tuple[str, str, int]] = field(default_factory=list)
    suspects: dict[str, str] = field(default_factory=dict)
    non_english: dict[str, str] = field(default_factory=dict)
    unknown_subject_slugs: dict[str, int] = field(default_factory=dict)
    repeated_guids: list[str] = field(default_factory=list)
    enriched_from_feeds: int = 0
    enriched_from_descriptions: int = 0
    optional_inputs_missing: list[str] = field(default_factory=list)

    def lines(self) -> list[str]:
        out = [
            f"loaded: {self.shows} shows, {self.episodes} episodes, {self.networks} networks",
            f"  show->theme links   : {self.show_theme_links}",
            f"  episode->subject links: {self.episode_subject_links}",
            f"  depth-1 shows (no episode labels): {len(self.depth1_shows)}",
            f"  recovered episodes: {self.recovered_episodes} across "
            f"{self.recovered_shows} shows (unlabelled; Phase 3 labels them)",
            f"  combed episodes   : {self.combed_episodes} across "
            f"{self.combed_shows} shows (the Phase 3 feed re-read)",
            f"  tombstones applied: {self.tombstoned_shows} shows, "
            f"{self.tombstoned_episodes} episodes",
        ]
        if self.optional_inputs_missing:
            out.append(f"  optional inputs absent: {', '.join(self.optional_inputs_missing)}")
        else:
            out.append(
                f"  enriched: {self.enriched_from_feeds} eps from feeds/, "
                f"{self.enriched_from_descriptions} from descriptions/"
            )
        if self.feed_url_mismatches:
            out.append(f"  WARN feed_url disagreements: {self.feed_url_mismatches}")
        if self.unjoined:
            out.append(f"  WARN catalog rows that failed to join: {self.unjoined}")
        if self.unknown_subject_slugs:
            out.append(
                f"  WARN episode subjects not in the vocabulary: {self.unknown_subject_slugs}"
            )
        if self.repeated_guids:
            out.append(f"  WARN episodes skipped for a repeated guid: {self.repeated_guids}")
        out.append(
            f"  shows sharing one feed: {len(self.shared_feed_groups)} groups; "
            f"overlapping content on separate feeds: {len(self.duplicate_pairs)} pairs"
        )
        out.append(f"  flagged 'suspect' for Phase 2 review: {len(self.suspects)}")
        if self.non_english:
            out.append(f"  non-English (heuristic): {self.non_english}")
        return out


# --- reading ---------------------------------------------------------------------


def _read_episode_themes(source: Path) -> dict[str, dict]:
    """slug -> the labelled-episodes record. Underscore files are run scratch."""
    out = {}
    for path in sorted((source / "episode-themes").glob("*.json")):
        if path.name.startswith("_"):
            continue
        data = json.loads(path.read_text())
        out[data.get("slug") or path.stem] = data
    return out


def _read_recovered(source: Path) -> dict[str, list[dict]]:
    """Episodes that exist in feeds/ but never reached the labelled corpus.

    Two causes, both recorded in the file itself: the 2026-07 theming run filtered its
    input to episodeType == 'full' (dropping every bonus, which is where mini-series live),
    and 12 shows were never themed at all. Tracked in git so the build does not depend on
    the gitignored raw corpus. These episodes carry no subjects -- Phase 3 labels them.
    """
    path = source / "recovered-episodes.json"
    if not path.is_file():
        return {}
    return json.loads(path.read_text()).get("recovered") or {}


def _read_combed(source: Path) -> dict[str, list[dict]]:
    """Episodes the Phase 3 feed comb added, whose only other source is the gitignored
    feeds/ corpus. Same contract as recovered-episodes.json -- additive, tracked in git
    so a rebuild does not depend on raw feeds -- but these carry their description and
    duration inline, because the comb is also the only thing that ever read those."""
    path = source / "comb-episodes.json"
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8")).get("combed") or {}


def _read_optional(source: Path, subdir: str, key: str) -> dict[str, dict]:
    """feeds/ and descriptions/ are gitignored and may simply not be here."""
    directory = source / subdir
    if not directory.is_dir():
        return {}
    out = {}
    for path in sorted(directory.glob("*.json")):
        if path.name.startswith("_"):
            continue
        data = json.loads(path.read_text())
        out[data.get(key) or path.stem] = data
    return out


def _detect_language(titles: list[str]) -> tuple[str, str]:
    """Guess a show's language from its episode titles. Returns (lang, evidence)."""
    if len(titles) < _LANG_MIN_EPISODES:
        return "en", ""

    # Titles often use "|" as a segment separator; treat it as whitespace so the words
    # either side are still delimited.
    blob = " " + " ".join(titles[:200]).lower().replace("|", " ") + " "
    words = max(len(blob.split()), 1)

    best_lang, best_rate, best_distinct = "en", 0.0, 0
    for lang, markers in _LANG_MARKERS.items():
        hits = {m: blob.count(m) for m in markers}
        total = sum(hits.values())
        distinct = sum(1 for v in hits.values() if v)
        rate = total / words
        if rate > best_rate:
            best_lang, best_rate, best_distinct = lang, rate, distinct

    if best_rate >= _LANG_MIN_RATE and best_distinct >= _LANG_MIN_DISTINCT:
        return best_lang, f"{best_rate:.2f} rate, {best_distinct} distinct markers"
    return "en", ""


def _find_shared_feeds(slug_by_title: dict[str, str], catalog: list[dict]) -> list[list[str]]:
    """Groups of catalogued shows pointing at the same feed. The authoritative signal.

    Eight groups exist in the corpus. Most are a limited series or season catalogued as
    its own show alongside its parent ("Slow Burn" and "Slow Burn: Biggie & Tupac"). One
    is not: "Making Obama" and "Making Oprah" are different programmes that WBEZ
    published in a single feed.

    This is the check that matters, because the schema permits at most one *reviewed*
    show per feed. It also works on a clean clone, since catalog.json is tracked.
    """
    groups: dict[str, list[str]] = {}
    for row in catalog:
        key = normalize_feed_url(row["feedUrl"])
        groups.setdefault(key, []).append(slug_by_title[row["title"]])
    return [sorted(slugs) for slugs in groups.values() if len(slugs) > 1]


def _find_duplicate_content(
    episode_themes: dict[str, dict], threshold: float = 0.5
) -> list[tuple[str, str, int]]:
    """Pairs whose episode GUIDs overlap heavily. Informational, not a constraint.

    Catches the cases a feed_url comparison cannot: two entries with *different* feed
    URLs serving overlapping episodes, e.g. "The Turning" and "The Turning: The Sisters
    Who Left". Cannot see shows that have no labelled episodes at all, which is exactly
    why it is the second signal rather than the first.
    """
    guids = {
        slug: {e["guid"] for e in (data.get("episodes") or [])}
        for slug, data in episode_themes.items()
    }
    guids = {s: g for s, g in guids.items() if g}

    pairs = []
    slugs = sorted(guids)
    for i, a in enumerate(slugs):
        for b in slugs[i + 1 :]:
            shared = len(guids[a] & guids[b])
            if shared and shared / min(len(guids[a]), len(guids[b])) >= threshold:
                pairs.append((a, b, shared))
    return pairs


def _pick_suspects(
    feed_groups: list[list[str]], content_pairs: list[tuple[str, str, int]]
) -> dict[str, str]:
    """Decide which shows to flag for the Phase 2 inclusion queue.

    Within a group sharing one feed, if every other member's slug is prefixed by one
    member's, that one is the parent and only the children are flagged ("slow-burn" ->
    "slow-burn-biggie-tupac"). Otherwise every member is flagged: the data does not say
    which is which, and guessing wrong would cut a real show.

    Flagging all members is always safe for the schema -- the partial unique index only
    requires that no more than one show per feed is left unflagged.
    """
    suspects: dict[str, str] = {}

    for group in feed_groups:
        parents = [c for c in group if all(o == c or o.startswith(c + "-") for o in group)]
        if len(parents) == 1:
            parent = parents[0]
            for slug in group:
                if slug != parent:
                    suspects[slug] = f"a series inside '{parent}' -- shares its feed"
        else:
            others = ", ".join(group)
            for slug in group:
                suspects[slug] = f"shares one feed with [{others}] -- relationship unclear"

    for a, b, shared in content_pairs:
        if a in suspects or b in suspects:
            continue
        if b.startswith(a + "-"):
            suspects[b] = f"repeats {shared} episodes of '{a}' from a different feed"
        elif a.startswith(b + "-"):
            suspects[a] = f"repeats {shared} episodes of '{b}' from a different feed"
        else:
            suspects[a] = f"shares {shared} episode guids with '{b}'"
            suspects[b] = f"shares {shared} episode guids with '{a}'"

    return suspects


# --- writing ---------------------------------------------------------------------


def load(conn: sqlite3.Connection, source: Path) -> LoadReport:
    report = LoadReport()

    catalog = json.loads((source / "catalog.json").read_text())
    episode_themes = _read_episode_themes(source)
    recovered = _read_recovered(source)
    combed = _read_combed(source)
    feeds = _read_optional(source, "feeds", "slug")
    descriptions = _read_optional(source, "descriptions", "slug")

    if not feeds:
        report.optional_inputs_missing.append("feeds/")
    if not descriptions:
        report.optional_inputs_missing.append("descriptions/")

    title_to_slug = {d["title"]: slug for slug, d in episode_themes.items() if d.get("title")}
    feeds_by_title = {d.get("title"): d for d in feeds.values() if d.get("title")}

    # Resolve every row's slug up front: duplicate detection needs slugs for all 315
    # rows, including the 12 that have no labelled episodes to match on.
    slug_by_title: dict[str, str] = {}
    seen: dict[str, str] = {}
    for row in catalog:
        title = row["title"]
        slug = title_to_slug.get(title) or slugify(title)
        if slug in seen:
            raise ValueError(f"slug collision on {slug!r}: {seen[slug]!r} and {title!r}")
        seen[slug] = title
        slug_by_title[title] = slug

    feed_groups = _find_shared_feeds(slug_by_title, catalog)
    content_pairs = _find_duplicate_content(episode_themes)
    report.shared_feed_groups = feed_groups
    report.duplicate_pairs = content_pairs
    suspects_by_slug = _pick_suspects(feed_groups, content_pairs)

    theme_ids = {slug: tid for slug, tid in conn.execute("SELECT slug, id FROM themes")}
    subject_ids = {slug: sid for slug, sid in conn.execute("SELECT slug, id FROM subjects")}

    network_ids: dict[str, int] = {}

    for row in catalog:
        title = row["title"]
        slug = slug_by_title[title]
        labelled = title in title_to_slug
        if not labelled:
            report.unjoined.append(f"{title} (no episode labels; slug derived: {slug})")

        network_id = _upsert_network(conn, network_ids, row.get("network") or row.get("author"))

        episode_titles = [
            e.get("display") or "" for e in (episode_themes.get(slug, {}).get("episodes") or [])
        ]
        lang, evidence = _detect_language(episode_titles)
        if lang != "en":
            report.non_english[slug] = f"{lang} ({evidence})"

        verdict, note = "unreviewed", None
        if title in EXPLICIT_SUSPECTS:
            verdict, note = "suspect", EXPLICIT_SUSPECTS[title]
        elif slug in suspects_by_slug:
            verdict, note = "suspect", suspects_by_slug[slug]
        if verdict == "suspect":
            report.suspects[slug] = note

        feed_url = row["feedUrl"]
        # Cross-check only. feeds/ is gitignored, so this is silent when absent.
        feed_row = feeds_by_title.get(title)
        if feed_row and feed_row.get("feedUrl"):
            if normalize_feed_url(feed_row["feedUrl"]) != normalize_feed_url(feed_url):
                report.feed_url_mismatches.append(slug)

        cur = conn.execute(
            "INSERT INTO shows (slug, title, author, network_id, feed_url, home_url, "
            "artwork_url, lang, apple_category, years, why, description, depth, include_verdict) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (
                slug,
                title,
                row.get("author"),
                network_id,
                feed_url,
                row.get("homeUrl"),
                row.get("artworkUrl"),
                lang,
                row.get("category") or None,
                row.get("years"),
                row.get("why"),
                row.get("description"),
                2 if labelled else 1,
                verdict,
            ),
        )
        show_id = cur.lastrowid
        report.shows += 1
        if not labelled:
            report.depth1_shows.append(slug)

        for theme_slug in row.get("themes") or []:
            tid = theme_ids.get(theme_slug)
            if tid is None:
                report.unknown_theme_slugs[theme_slug] = (
                    report.unknown_theme_slugs.get(theme_slug, 0) + 1
                )
                continue
            conn.execute(
                "INSERT OR IGNORE INTO show_themes (show_id, theme_id) VALUES (?, ?)",
                (show_id, tid),
            )
            report.show_theme_links += 1

        if labelled:
            _insert_episodes(
                conn,
                report,
                show_id,
                episode_themes[slug],
                feeds.get(slug),
                descriptions.get(slug),
                subject_ids,
            )
        if slug in recovered:
            _insert_recovered(
                conn, report, show_id, recovered[slug], descriptions.get(slug)
            )
        if slug in combed:
            _insert_combed(conn, report, show_id, combed[slug])

    if note_dupes := [f"{a}~{b}" for a, b, _ in content_pairs] + [
        "+".join(g) for g in feed_groups
    ]:
        # Recorded in the edits log so the Phase 2 queue can explain itself later.
        conn.execute(
            "INSERT INTO edits (at, actor, entity_type, entity_key, field, before, after, note) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (
                "2026-07-26",
                "agent:migrate",
                "catalog",
                "",
                "duplicate_feeds",
                None,
                json.dumps(note_dupes),
                "shows whose episode guids overlap: likely a series inside a parent feed",
            ),
        )

    _apply_tombstones(conn, report, source)

    report.networks = len(network_ids)
    conn.commit()
    return report


def _apply_tombstones(conn, report: LoadReport, source: Path) -> None:
    """Re-apply soft-deletions from tombstones.json, last, after every insert.

    Bulk deletes were logged as wildcard-and-count ("empire/*", rows: 658), which audits
    the decision but cannot replay it. Without this, a rebuild resurrects every merged
    duplicate and wrong-feed episode Phase 2 removed."""
    path = source / "tombstones.json"
    if not path.is_file():
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    for row in data.get("shows") or []:
        conn.execute(
            "UPDATE shows SET deleted_at = ?, deleted_reason = ? WHERE slug = ?",
            (row["at"], row.get("reason"), row["slug"]))
        report.tombstoned_shows += 1
    for slug, eps in (data.get("episodes") or {}).items():
        show = conn.execute("SELECT id FROM shows WHERE slug = ?", (slug,)).fetchone()
        if not show:
            continue
        for row in eps:
            cur = conn.execute(
                "UPDATE episodes SET deleted_at = ?, deleted_reason = ? "
                "WHERE show_id = ? AND guid = ?",
                (row["at"], row.get("reason"), show[0], row["guid"]))
            report.tombstoned_episodes += cur.rowcount


def _upsert_network(conn, cache: dict[str, int], name: str | None) -> int | None:
    if not name or not name.strip():
        return None
    try:
        slug = slugify(name)
    except ValueError:
        return None
    if slug in cache:
        return cache[slug]
    cur = conn.execute("INSERT INTO networks (slug, name) VALUES (?, ?)", (slug, name.strip()))
    cache[slug] = cur.lastrowid
    return cache[slug]


def _insert_episodes(
    conn, report: LoadReport, show_id: int, labelled: dict, feed: dict | None,
    described: dict | None, subject_ids: dict[str, int],
) -> None:
    feed_by_guid = {}
    if feed:
        feed_by_guid = {e["guid"]: e for e in (feed.get("episodes") or []) if e.get("guid")}
    texts = (described or {}).get("episodes") or {}

    seen_guids: set[str] = set()
    for ep in labelled.get("episodes") or []:
        guid = ep["guid"]
        # One show ("Serial (Season 1)", itself a test fixture) lists two different
        # episodes under one guid. Keep the first and report rather than crash: a
        # publisher's guid mistake should not be able to stop the whole build.
        if guid in seen_guids:
            report.repeated_guids.append(f"{labelled.get('slug')}:{guid}")
            continue
        seen_guids.add(guid)

        extra = feed_by_guid.get(guid) or {}
        if extra:
            report.enriched_from_feeds += 1
        description = texts.get(guid)
        if description:
            report.enriched_from_descriptions += 1

        cur = conn.execute(
            "INSERT INTO episodes (show_id, guid, title, season, episode_number, "
            "episode_type, published_at, description) VALUES (?,?,?,?,?,?,?,?)",
            (
                show_id,
                guid,
                ep.get("display") or "Untitled Episode",
                extra.get("season"),
                extra.get("episodeNumber"),
                extra.get("episodeType"),
                ep.get("iso"),
                description,
            ),
        )
        episode_id = cur.lastrowid
        report.episodes += 1

        model = (labelled.get("models") or {}).get("assign")
        # The source calls these "themes"; at episode level they are subjects.
        for entry in ep.get("themes") or []:
            sid = subject_ids.get(entry.get("slug"))
            if sid is None:
                slug = entry.get("slug")
                report.unknown_subject_slugs[slug] = report.unknown_subject_slugs.get(slug, 0) + 1
                continue
            # OR IGNORE: a handful of episodes name the same subject twice, once per role.
            conn.execute(
                "INSERT OR IGNORE INTO episode_subjects (episode_id, subject_id, role, "
                "confidence, agreement, model, run_id) VALUES (?,?,?,?,NULL,?,?)",
                (
                    episode_id,
                    sid,
                    entry.get("role") or "secondary",
                    entry.get("confidence") or "low",
                    model,
                    RUN_ID,
                ),
            )
            report.episode_subject_links += 1


def _insert_recovered(
    conn, report: LoadReport, show_id: int, episodes: list[dict], described: dict | None
) -> None:
    """Insert episodes the theming run never saw.

    Identical to a normal episode row except there are no subjects to attach. episode_type
    is always stored so arc detection and the UI can exclude trailers, which are adverts
    for the show rather than something anyone wants recommended.
    """
    texts = (described or {}).get("episodes") or {}
    added = 0
    for ep in episodes:
        guid = ep["guid"]
        try:
            conn.execute(
                "INSERT INTO episodes (show_id, guid, title, season, episode_number, "
                "episode_type, published_at, description) VALUES (?,?,?,?,?,?,?,?)",
                (
                    show_id,
                    guid,
                    ep.get("title") or "Untitled Episode",
                    ep.get("season"),
                    ep.get("episodeNumber"),
                    ep.get("episodeType"),
                    ep.get("iso"),
                    texts.get(guid),
                ),
            )
        except sqlite3.IntegrityError:
            # Already present from the labelled corpus. Recovery is additive only.
            continue
        added += 1
    report.recovered_episodes += added
    if added:
        report.recovered_shows += 1


def _insert_combed(conn, report: LoadReport, show_id: int, episodes: list[dict]) -> None:
    """Insert comb-added episodes. Additive only, like _insert_recovered, but the row is
    complete in itself -- description and duration come from the file, not from the
    optional gitignored directories."""
    added = 0
    for ep in episodes:
        try:
            conn.execute(
                "INSERT INTO episodes (show_id, guid, title, season, episode_number, "
                "episode_type, published_at, description, duration_s, available) "
                "VALUES (?,?,?,?,?,?,?,?,?,?)",
                (
                    show_id,
                    ep["guid"],
                    ep.get("title") or "Untitled Episode",
                    ep.get("season"),
                    ep.get("episodeNumber"),
                    ep.get("episodeType"),
                    ep.get("iso"),
                    ep.get("description"),
                    ep.get("durationS"),
                    ep.get("available", 1),
                ),
            )
        except sqlite3.IntegrityError:
            # Already present from the labelled corpus. Additive only.
            continue
        added += 1
    report.combed_episodes += added
    if added:
        report.combed_shows += 1
