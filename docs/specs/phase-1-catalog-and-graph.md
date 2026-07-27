# Phase 1 — Catalog and graph

Status: spec. Written 2026-07-26. Program context: `docs/PROGRAM.md`.

## Goal

Turn `curation/source/` into one queryable SQLite catalog with a graph on top, and prove
it by answering the three questions the app exists to answer.

Phase 1 does **not** improve the data. No relabelling, no LLM arc detection, no subject
extraction — those are Phase 3. Phase 1 makes the data *addressable* so that improving it
has somewhere to land.

---

## Inputs

Everything below is read-only. The build never writes to `curation/source/`.

| Path | Shape | Counts |
|---|---|---|
| `catalog.json` | `[{id, title, author, network, feedUrl, homeUrl, artworkUrl, category, years, why, description, themes[]}]` | 315 shows |
| `themes.json` | `[{slug, name, description, showCount}]` | 30 themes |
| `episode-themes/_vocabulary.json` | `{themes: [{slug, name, definition, relatedShowThemes[], episodeCount, showCount, junkDrawerSuspect, showSpecific}], models}` | 148 subjects |
| `episode-themes/<slug>.json` | `{slug, title, models, themesUsed[], episodes: [{guid, display, segment, subject, iso, inArc, themes:[{slug, role, confidence}]}], agreement, auditFlags}` | 303 shows, 27,444 episodes |
| `feeds/<slug>.json` | `{slug, title, network, feedUrl, itunesCollection, matchScore, episodeCount, episodes:[{guid, title, season, episodeNumber, episodeType, iso}]}` | 316 shows |
| `descriptions/<slug>.json` | `{slug, fetchedAt, feedUrl, liveItems, storedEpisodes, matched, episodes: {guid: text}}` | 306 shows |
| `gold/gold.json` | `{show_slug: [{name, members:[guid]}]}` — verified arcs | 50 shows, 590 arcs |
| `gold/human-verdicts.json`, `gold/gold-human.json` | hand-made arc verdicts | small, authoritative |
| `atlas/` | earlier exploration data, iTunes cache | reference only |

`feeds/` and `descriptions/` are gitignored (19MB, re-fetchable). The build must work
without them, degrading gracefully — see **Degradation** below.

### Facts established while writing this spec

- **`catalog.json` has no slug.** It has an integer `id` and a `feedUrl`. Every other
  source file is keyed by slug. **`feedUrl` is the join key.** Slugs come from the
  episode-themes / feeds filenames.
- **`segment` is the regex cascade's output**, already baked into the episode records: for
  `"American Revolution | Saratoga | 4"`, `segment` = `"American Revolution"` and
  `subject` = `"Saratoga | 4"`. Only **2,323 episodes** carry a non-empty segment, across
  **289 distinct** segment names.
- **`inArc` is true on 6,649 of 27,444 episodes (24.2%)** — the coverage ceiling that
  started this whole rewrite.
- **36 of 148** subjects already name a tier-1 parent in `relatedShowThemes`. Zero
  name a parent outside the 30. Zero name more than one. Zero are flagged
  `junkDrawerSuspect`.
- **5 slugs exist in both tiers**: `political-scandal`, `institutional-coverup`,
  `police-misconduct`, `wrongful-conviction`, `family-secret`.
- **12 shows have no episode labels** (315 in `catalog.json`, 303 with episode-themes).
- **No episode duration exists anywhere in the source.** Neither does an un-truncated
  description — `descriptions/` values are cut at roughly 250 characters with an ellipsis.
  Audio URLs are absent too, and that is correct — see **Audio and freshness**.

---

## Schema

`catalog/schema.sql`. Typed tables for facts, one `edges` table for traversal.

```sql
PRAGMA foreign_keys = ON;

CREATE TABLE networks (
  id    INTEGER PRIMARY KEY,
  slug  TEXT NOT NULL UNIQUE,
  name  TEXT NOT NULL
);

CREATE TABLE shows (
  id              INTEGER PRIMARY KEY,
  slug            TEXT NOT NULL UNIQUE,
  title           TEXT NOT NULL,
  author          TEXT,
  network_id      INTEGER REFERENCES networks(id),
  feed_url        TEXT NOT NULL,   -- see the partial unique index below
  home_url        TEXT,
  artwork_url     TEXT,
  lang            TEXT NOT NULL DEFAULT 'en',
  apple_category  TEXT,
  years           TEXT,
  why             TEXT,              -- the hand-written pitch; keep verbatim
  description     TEXT,
  depth           INTEGER NOT NULL DEFAULT 1 CHECK (depth BETWEEN 1 AND 4),
  include_verdict TEXT NOT NULL DEFAULT 'unreviewed'
                  CHECK (include_verdict IN ('unreviewed','keep','cut','suspect'))
);

CREATE TABLE episodes (
  id             INTEGER PRIMARY KEY,
  show_id        INTEGER NOT NULL REFERENCES shows(id),
  guid           TEXT NOT NULL,
  title          TEXT NOT NULL,     -- `display`, verbatim from the feed
  subject        TEXT,              -- title with the segment prefix stripped
  season         INTEGER,
  episode_number INTEGER,
  episode_type   TEXT,
  published_at   TEXT,              -- ISO date
  description    TEXT,              -- truncated at source; see Degradation
  duration_s     INTEGER,           -- DISPLAY HINT ONLY. Cached so browse can show
                                    -- "6 parts, 4h 20m" without fetching 300 feeds.
                                    -- The player always trusts the live feed.
                                    -- NULL until Phase 4 fetches it.
  available      INTEGER NOT NULL DEFAULT 1,  -- 0 when a reconcile finds it gone from
                                    -- the feed. Never delete: the labels are ours.
  arc_id         INTEGER REFERENCES arcs(id),
  UNIQUE (show_id, guid)
);

CREATE TABLE arcs (
  id          INTEGER PRIMARY KEY,
  show_id     INTEGER NOT NULL REFERENCES shows(id),
  slug        TEXT NOT NULL,
  kind        TEXT NOT NULL CHECK (kind IN ('series','arc')),
  name        TEXT NOT NULL,
  description TEXT,
  confidence  TEXT NOT NULL DEFAULT 'low'
              CHECK (confidence IN ('low','medium','high','verified')),
  source      TEXT NOT NULL CHECK (source IN ('gold','segment','llm','human')),
  UNIQUE (show_id, slug)
);

CREATE TABLE themes (
  id          INTEGER PRIMARY KEY,
  slug        TEXT NOT NULL,
  tier        INTEGER NOT NULL CHECK (tier IN (1,2)),
  name        TEXT NOT NULL,
  description TEXT,
  parent_id   INTEGER REFERENCES themes(id),
  UNIQUE (tier, slug),                          -- NOT slug alone: 5 slugs span both tiers
  CHECK ((tier = 1 AND parent_id IS NULL) OR (tier = 2 AND parent_id IS NOT NULL))
);

CREATE TABLE people   (id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE, name TEXT NOT NULL);
CREATE TABLE subjects (id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
                       kind TEXT CHECK (kind IN ('case','company','person','place','era','work')));

CREATE TABLE show_themes (
  show_id  INTEGER NOT NULL REFERENCES shows(id),
  theme_id INTEGER NOT NULL REFERENCES themes(id),
  PRIMARY KEY (show_id, theme_id)
);

CREATE TABLE episode_themes (
  episode_id INTEGER NOT NULL REFERENCES episodes(id),
  theme_id   INTEGER NOT NULL REFERENCES themes(id),
  role       TEXT NOT NULL CHECK (role IN ('primary','secondary')),
  confidence TEXT NOT NULL CHECK (confidence IN ('low','medium','high')),
  agreement  INTEGER,               -- votes agreeing; NULL for the 2026-07 Haiku run
  model      TEXT,
  run_id     TEXT,
  PRIMARY KEY (episode_id, theme_id)
);

CREATE TABLE edges (
  src_type TEXT NOT NULL,
  src_id   INTEGER NOT NULL,
  dst_type TEXT NOT NULL,
  dst_id   INTEGER NOT NULL,
  kind     TEXT NOT NULL,
  weight   REAL NOT NULL DEFAULT 1.0,
  why      TEXT,                    -- human-readable; this is what the UI displays
  PRIMARY KEY (src_type, src_id, dst_type, dst_id, kind)
);
CREATE INDEX edges_out ON edges (src_type, src_id, kind, weight DESC);
CREATE INDEX edges_in  ON edges (dst_type, dst_id, kind, weight DESC);

CREATE TABLE edits (
  id          INTEGER PRIMARY KEY,
  at          TEXT NOT NULL,
  actor       TEXT NOT NULL,        -- 'human' | 'agent:<name>'
  entity_type TEXT NOT NULL,
  entity_key  TEXT NOT NULL,       -- a STABLE key, never an internal id: see below
  field       TEXT NOT NULL,
  before      TEXT,
  after       TEXT,
  note        TEXT
);

CREATE TABLE releases (
  version       TEXT PRIMARY KEY,
  built_at      TEXT NOT NULL,
  show_count    INTEGER NOT NULL,
  episode_count INTEGER NOT NULL,
  content_hash  TEXT NOT NULL,
  notes         TEXT
);

CREATE VIRTUAL TABLE search USING fts5(
  title, subject, description, show_title,
  content='', tokenize='unicode61 remove_diacritics 2'
);
```

Four constraints doing real work:

- **`themes` is unique on `(tier, slug)`, not `slug`.** Five slugs legitimately exist at
  both levels. A slug-only key would silently collapse them.
- **The `themes` CHECK** makes an unparented subject impossible to insert. The
  two-level promise is enforced by the database, not by a convention someone remembers.
- **`feed_url` is covered by a partial unique index, not a plain UNIQUE:**
  `CREATE UNIQUE INDEX ... ON shows (feed_url) WHERE include_verdict <> 'suspect'`.
  Eight groups of catalogued shows share a feed and cannot be merged until Phase 2, so a
  plain constraint would block the build outright. The partial index keeps the invariant
  that matters — at most one *reviewed* show per feed — which makes an **undeclared**
  duplicate impossible to insert while letting a flagged one through.
- **`edits.entity_key` is a stable string, never an internal id.** Every build regenerates
  the integer ids, so an edit recorded against `id = 42` would silently land on a different
  row next time. Keys are `<show-slug>`, `<tier>:<theme-slug>`, `<show-slug>/<arc-slug>`,
  `<show-slug>/<guid>`.

---

## Audio and freshness

**The catalog never stores an audio URL.** Audio belongs to the show's host and is resolved
from the live feed at play time. This is not a preference — enclosure URLs are volatile.
Tracking prefixes (Podtrac, Chartable, Megaphone) rotate, and dynamic ad insertion can make
a URL session-specific. A URL cached three months ago is a dead play button.

| Concern | Owner |
|---|---|
| Audio URL | The show's host. Resolved from the live feed at play time. **Never stored.** |
| Duration | Catalog caches it for display. The player trusts the feed. |
| Episode list | Catalog renders first; the live feed reconciles by guid in the background. |

**Store-first reconcile**, carried over from the Swift app (see
`docs/patterns-from-swift.md`): render the catalog's episode list immediately, fetch the feed
in the background, merge on guid.

- New episodes append and get regex arcs from `detector/arc-cascade.py`.
- Episodes gone from the feed set `available = 0`. They are never deleted — the themes and
  arcs attached to them are our work, not the publisher's.
- Items with no usable audio enclosure are skipped, exactly as `FeedParser` did.
- **A failed fetch is swallowed.** The cached view stands. Never show an error over live data.

This is also what actually delivers the freshness promise: the app reads the feed anyway in
order to play anything, so it is current between catalog releases for free. The Phase 4
publisher's job is depth (labels, arcs, duration), not recency.

Nothing in `catalog/` may reference an enclosure or an audio URL. `verify.py` greps for it.

## Identity rules

- **Show slug** comes from the `episode-themes/` or `feeds/` filename. For the 12 shows
  present only in `catalog.json`, derive from the title (lowercase, non-alphanumeric →
  `-`, collapse repeats) and assert uniqueness.
- **`feed_url` joins `catalog.json` to everything else.** Normalize before comparing:
  strip trailing slashes, lowercase the host, drop `utm_*` query params. Report any
  catalog row that fails to join instead of dropping it.
- **Episode identity is `(show_id, guid)`.** GUIDs are only unique within a feed.
- **Integer ids are internal.** Slugs are the stable public identity. Incremental releases
  never renumber a slug.

---

## Two-tier theme resolution

All 148 subjects must end up with a parent. Three passes, cheapest first:

1. **`relatedShowThemes`** — 36 themes name exactly one tier-1 slug. Take it. Source
   recorded as `vocabulary`.
2. **Same-slug match** — the 5 cross-tier slugs parent to their tier-1 namesake. This is
   semantically right: "Political Scandal" the browse category, `political-scandal` the
   specific episode theme beneath it. Source recorded as `same-slug`.
3. **Assisted mapping** — the remaining ~107 go to a model, one batch, with all 30 tier-1
   names and descriptions plus each tier-2 name, definition, episode count, and the tier-1
   themes of the shows that actually use it. Output is a single parent per theme with a
   confidence. Source recorded as `llm`, and every one lands in the Phase 2 review queue
   ordered worst-confidence-first.

Write the mapping to `catalog/build/theme-parents.json` so it is inspectable and diffable
outside the database. The database is still the source of truth; this file is the build's
working record of how it got there.

**Sanity check, not a gate:** no theme should end up with more than ~15 children or
zero children. Either means the mapping or the top 30 needs a look. Report it; don't fail
the build.

---

## Arc seeding

Phase 1 seeds arcs from what already exists. Phase 3 replaces most of this with real LLM
arcs, so nothing here should be precious.

| Source | Yield | `source` | `confidence` |
|---|---|---|---|
| `gold/gold.json` — verified arcs, members by guid | 590 arcs over 50 shows | `gold` | `verified` |
| `segment` prefix grouping — episodes sharing a segment within a show | ~289 arcs over 2,323 episodes | `segment` | `low` |

Rules:
- Gold wins. If an episode is in a gold arc, a segment arc never claims it.
- A segment group of **one** episode is not an arc. Drop it.
- `kind` is `arc` for everything in Phase 1. Nothing in the source distinguishes a named
  limited series yet — `series` gets populated in Phase 3, and the two duplicate shows get
  merged into their parents through the Phase 2 inclusion queue.
- `episodes.arc_id` is set for members; everything else stays NULL. Do not invent an
  "unarced" bucket.

---

## Edges

Facts live in tables. `edges` is the traversal layer, built last, entirely derived. It is
always safe to delete and rebuild.

| kind | src → dst | weight | `why` |
|---|---|---|---|
| `show_theme` | show → theme (tier 1) | 1.0 | "tagged <theme>" |
Episode → theme edges were specified here and then deliberately dropped: there are 43,818
of them, they would be 76% of the graph and ~8 MB of the shipped file, and nothing
traverses them — they are always read through `episode_themes`, which is indexed for it.

| `shares_theme` | show → show | Jaccard over themes | "both cover <theme>" |
| `shares_fine_theme` | show → show | cosine over tier-2 episode-theme volume | "both dig into <theme>" |
| `same_network` | show → show | 0.3 | "both from <network>" |
| `theme_parent` | theme (2) → theme (1) | 1.0 | "a kind of <parent>" |
| `arc_of` | arc → show | 1.0 | "a story arc in <show>" |
| `entry_point` | show → episode or arc | see below | "a good place to start" |

`shares_*` edges are pruned: keep the top 20 per show by weight, and drop anything below
0.15. Without a cap this table is 315² and every traversal drowns in noise.

`entry_point` is computed, not curated, in Phase 1: prefer the earliest episode of the
highest-confidence arc; fall back to the show's earliest episode carrying a high-confidence
primary theme. Phase 2 lets a human override it, which is the real answer.

**`why` is not decoration.** It is the string the app shows when it explains a connection.
If an edge can't produce a sentence a person would accept, it shouldn't exist.

---

## The three named queries

Live in `catalog/build/queries/` as `.sql` files with a comment header stating the
question. Each has a matching `--explain` run in the gate.

**`next-thing.sql`** — given a show slug, return 3 shows that scratch the same itch and are
not obvious neighbours. Walk `shares_fine_theme` and `shares_theme`, then **penalize**
`same_network` so it doesn't just recommend the same publisher's back catalog. Return the
`why` of the strongest edge with each row.

**`explain.sql`** — given two show slugs, return the shortest path between them, up to 3
hops, as an ordered list of `(node, edge kind, why)`. The output is meant to be read aloud:
"both dig into police misconduct → which is a kind of The Institutional Cover-Up."

**`entry-point.sql`** — given a show slug with 200+ episodes, return the recommended
starting arc or episode, with its `why` and its episode count.

---

## Build pipeline

```
catalog/
  schema.sql
  build/
    migrate.py           orchestrates; the only entry point
    load_source.py       read + normalize curation/source/, join on feed_url
    themes.py            three-pass tier-2 parent resolution
    arcs.py              gold + segment seeding
    edges.py             derive the edges table, prune
    fts.py               populate the search index
    verify.py            the gate checks, exits non-zero on failure
    queries/             the three named queries
    theme-parents.json   mapping record (committed)
  releases/              build output (gitignored)
```

`migrate.py` is idempotent: it builds a new `.db` from scratch every run. It never migrates
an existing one. Corrections survive because the `edits` table is replayed onto the fresh
build as its last step — which is exactly the mechanism the admin tool depends on in
Phase 2, so it gets built and proven here.

### Degradation

`feeds/` and `descriptions/` may be absent on a clean clone. When they are:
- `season`, `episode_number`, `episode_type` stay NULL — only `feeds/` has them.
- `description` stays NULL.
- The build **succeeds** and prints exactly what it couldn't populate.

`verify.py` distinguishes "missing because the optional input was absent" from "missing
because the build lost it." The second fails the gate; the first doesn't.

---

## Gate

`python catalog/build/verify.py` must exit 0. It checks:

1. **Counts.** 315 shows. 27,444 episodes across 303 shows. 30 tier-1 and 148 tier-2
   themes. Every count asserted against the source files, not hardcoded.
2. **No orphans.** Zero foreign key violations (`PRAGMA foreign_key_check` empty). Every
   episode has a show. Every subject has a tier-1 parent. Every `episode_themes` row
   resolves to a real theme.
3. **Join integrity.** Every `catalog.json` row matched a slug by `feed_url`, or is
   explicitly listed as unmatched with a reason. The 12 label-less shows are present at
   `depth = 1`.
4. **Edges.** `shares_*` pruned to the stated caps. Every edge kind has a non-empty `why`.
5. **Traversal speed.** `explain.sql` at 3 hops completes in under 50ms, measured cold on
   this machine, reported as a number.
6. **The three queries return defensible rows.** Not "returns rows" — `verify.py` prints
   the actual output for `next-thing` on three hand-picked shows, `explain` on two pairs,
   and `entry-point` on the largest shows. **Chris reads it and judges.** This check is
   human, and the gate is not passed until he says so.
7. **Reproducibility.** Rebuild from scratch and confirm the **content hash matches** —
   a SHA-256 over a canonical dump (every table dumped with a deterministic ORDER BY,
   excluding `releases.built_at`). Recorded in `releases.content_hash`.
8. **Edits replay.** Insert an edit, rebuild, confirm it survives and is reflected.

> **Correction to the program plan.** PROGRAM.md says the rebuild must be *byte-identical*.
> That is the wrong test — a SQLite file carries page-layout and change-counter bytes that
> vary without the content differing, and `releases.built_at` is a timestamp by design. The
> content hash above is the stricter useful check: it proves the *data* is reproducible
> rather than that the file bytes are. Updating PROGRAM.md to match.

---

## Carried forward, not solved here

- **No duration.** Phase 4's publisher fetches it per episode while it's already combing
  feeds. The column exists now so that lands as an update, not a migration. Audio needs no
  such treatment — see **Audio and freshness**.
- **Descriptions are truncated** at ~250 characters with an ellipsis. Since Phase 3 extracts
  subjects from titles and descriptions only, this caps subject quality. Phase 4 should
  re-fetch them in full while it's already reading every feed.
- **The 24.2% arc coverage stands.** Phase 1 does not improve it. Phase 3 does.
- **Two duplicate shows** ("Fake Diana: Case of the Missing Blue Diamond", "Redhanded
  Presents / Today in Focus: The Coup") migrate as-is, flagged `include_verdict =
  'suspect'`, and get merged in Phase 2.
- **`agreement` is NULL** for every existing label. The 2026-07 run recorded per-show
  agreement, not per-episode. Phase 3's relabel populates it.

## Out of scope

Relabelling. LLM arc detection. Subject extraction. Inclusion audits. The admin tool. Any
React. Any hosting or publishing.
