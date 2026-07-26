# Architecture — the curation taxonomy store

Audience: any agent (or human) working on story arcs, episode themes, or the
show taxonomy. This is the referenceable design for where curated structure
lives, how detectors and models contribute to it without destroying human
decisions, and how it reaches the app. Cite this doc by path
(`docs/design/taxonomy-architecture.md`) rather than re-deriving it.

## The problem this solves

Structure over the catalog comes from three places that until now had nowhere
to meet:

- **Regex detection** (`curation/arc-bakeoff/approaches.py`) finds multi-part
  story arcs from episode titles. It is genuinely good at this — *Border
  Trilogy*, `Part N`, `Name | Title | N` — and covers 221 of 315 shows.
- **Model proposal** (`curation/arc-bakeoff/episode-theme-workflow.mjs`) themes
  anthology episodes that no pattern can group, using world knowledge about the
  subject. Swindled's Ford Pinto, OceanGate and ValuJet episodes are one theme;
  nothing in a title says so.
- **Human authoring** — the calls only a person can make. "These four Radiolab
  episodes are the gut-bacteria ones." "That arc is junk." "This show genuinely
  has no multi-part stories."

Regex has hit its ceiling and that is fine; it was never going to reach the
semantic cases. The real failure is architectural: **there is no durable place
for a decision to live.** A recorded verdict points at *"arc #3 of Swindled"* —
a positional index. Change one regex and #3 is a different arc. You cannot
curate a taxonomy whose entries are renumbered underneath you.

## Three layers, one merge rule

```
detected   (regex)     regenerable, disposable
proposed   (model)     regenerable, disposable
authored   (human)     precious, never overwritten
```

**Authored always wins.** Re-running detection or a model pass may add
candidates and refresh unreviewed ones. It may never modify or delete an entry
a human has ruled on.

This is what turns "regex is at its limit" into a non-issue. Regex stops being
the thing that has to be smart enough and becomes one contributor of three.

Every row carries its `provenance` so the merge is a rule, not a heuristic, and
so you can always answer *"who claimed this, and did I agree?"*

## Durable identity — the load-bearing decision

Ids are assigned once and preserved across re-detection by **member overlap**,
not position.

Reuse `align()` in `curation/arc-bakeoff/score.py` — it already does exactly
this, matching detected arcs to known ones by greedy best-Jaccard at
`JACCARD_MATCH = 0.5`. Point it at the store instead of at gold:

- A candidate that overlaps an existing entry ≥ 0.5 **keeps that entry's id**;
  its membership is refreshed if unreviewed, left alone if authored.
- A candidate matching nothing gets a new id.
- An entry no longer produced by any detector is marked `stale`, never deleted.
  It may be an arc a regex change stopped seeing, and the human ruling on it is
  still worth more than the detector's opinion.

Consequence: verdicts survive detector changes. This is the whole reason the
store exists, so nothing may bypass it.

## Scope

The store owns **arcs, episode themes, and the show-level theme taxonomy**.

Show themes are included deliberately. Episode themes already carry a `mapsTo`
pointing at one of the 30 show-level themes in
`curation/catalog/themes.json` — Swindled's 14 themes each map to a parent.
Run this for four more anthologies and you have four vocabularies plus four
mapping tables, when what you actually have is **one theme tree**: the 30 as
roots, per-show vocabularies as children. `mapsTo` was a parent pointer without
a table to put it in. Discovering that after four shows of labels means
migrating all of them.

Show *metadata* (title, author, artwork, description, category) stays in
`curation/catalog/catalog.json`. The store references shows by slug; it does
not own them.

## Storage — SQLite

`sqlite3` is in the Python standard library, so this costs no dependency and
honours the stdlib-only rule in `curation/arc-bakeoff/HFAB_PROMPT.md`.

```sql
-- shows are referenced, not owned. slug is slugify(catalog title) --
-- see scripts/build-catalog.py:34. NOT feedUrl (8 URLs are shared by two
-- shows) and NOT catalog.id (a stale positional index; 231 of 315 are wrong).

CREATE TABLE theme (
  id          INTEGER PRIMARY KEY,
  slug        TEXT NOT NULL,
  name        TEXT NOT NULL,
  definition  TEXT,
  parent_id   INTEGER REFERENCES theme(id),   -- NULL for the 30 roots
  show_slug   TEXT,                           -- NULL for global themes
  provenance  TEXT NOT NULL,                  -- detected | proposed | authored
  UNIQUE(slug, show_slug)
);

CREATE TABLE arc (
  id          INTEGER PRIMARY KEY,
  show_slug   TEXT NOT NULL,
  name        TEXT NOT NULL,
  season      INTEGER,
  rule        TEXT,          -- which detector produced it: part, pipe, limited-series…
  provenance  TEXT NOT NULL,
  status      TEXT NOT NULL  -- active | stale
);

CREATE TABLE arc_member (
  arc_id      INTEGER NOT NULL REFERENCES arc(id) ON DELETE CASCADE,
  guid        TEXT NOT NULL,
  PRIMARY KEY (arc_id, guid)
);

CREATE TABLE episode_theme (
  show_slug   TEXT NOT NULL,
  guid        TEXT NOT NULL,
  theme_id    INTEGER NOT NULL REFERENCES theme(id),
  rank        INTEGER NOT NULL,   -- 0 = primary, 1..2 = secondary
  confidence  TEXT,
  provenance  TEXT NOT NULL,
  PRIMARY KEY (show_slug, guid, theme_id)
);

CREATE TABLE verdict (
  subject_kind TEXT NOT NULL,     -- arc | theme | show
  subject_id   TEXT NOT NULL,
  verdict      TEXT NOT NULL,     -- right | wrong | unsure | none
  note         TEXT,
  decided_at   TEXT NOT NULL,
  PRIMARY KEY (subject_kind, subject_id)
);

CREATE TABLE edit_log (
  id        INTEGER PRIMARY KEY,
  at        TEXT NOT NULL,
  actor     TEXT NOT NULL,        -- human | detector:a8 | model:haiku
  action    TEXT NOT NULL,
  detail    TEXT
);
```

`edit_log` is why a database beats files here: an append-only record of who
changed what, which a per-show JSON file cannot give you without inventing one.

**The `.db` is gitignored; a JSON export is committed** so every change stays
reviewable in a diff. Git remains the audit trail for humans; SQLite is the
working set.

## Pipeline

```
curation/feeds/<slug>.json ─┐
                            ├─► approaches.py ──► detected arcs ─┐
catalog.json (slug join) ───┘                                    │
                                                                 ├─► SQLite ──┐
episode-theme-workflow.mjs ────────► proposed themes ────────────┤            │
                                                                 │            │
catalog browser (you) ─────────────► authored decisions ─────────┘            │
                                                                              │
                        ┌─────────────────────────────────────────────────────┘
                        ▼
        export ──► IWantUrPod/Resources/  (bundled snapshot)
               └─► static host            (refreshable)
```

`scripts/build-catalog.py` becomes a **consumer** of the store for `themes.json`
rather than its producer. This is the one existing pipeline that changes; its
theme emission is roughly ten lines that invert `arcs[].showIds` and count. Two
known defects get fixed in the move: 12 `tags` in `atlas-data.json` never reach
`themes.json` at all, and three shows carry no theme.

## Delivery — bundle and refresh

Two consumers, deliberately different.

**The browser** (`scripts/serve-catalog.py`, port 8420) reads and writes the
store over HTTP. It binds localhost by default; `--tailscale` is an explicit
opt-in. **This is never exposed publicly.**

**The app** reads a static file. The export is 439 KB raw, **198 KB gzipped**
for all 221 shows' arcs plus Swindled's themes — so no service is required:

```
/manifest.json    ~80 bytes   {"version": 14, "url": "/arcs-v14.json", "sha256": "…"}
/arcs-v14.json    198 KB      immutable, Cache-Control: max-age=31536000
```

The app ships a snapshot in `IWantUrPod/Resources/` alongside `catalog.json`, so
a cold install works offline. On launch it fetches `manifest.json`; same version
means an 80-byte round trip and nothing else. A new version means one download,
cached forever — the filename changes on every publish, so it never revalidates.

Host: **Cloudflare Pages free tier** (static asset bandwidth is unlimited there;
GitHub Pages requires a paid plan for private repos). Publishing is
`wrangler pages deploy`. No Workers, no R2, no server logic — those are only
needed if live per-request arc computation is ever wanted.

If the host is unreachable the bundled snapshot stands. Failure is invisible.

**User-added feeds never get store data** — they are not in the catalog. They
fall back to on-device regex in
`Packages/PodcastModels/Sources/PodcastModels/EpisodeArcs.swift`. That is the
standing reason the regex detector still matters and must keep working.

## Migration

Existing artefacts become the store's seed, then stop being written:

| Source | Becomes |
|---|---|
| `approaches.py` run over the corpus | `arc` + `arc_member`, provenance `detected` |
| `curation/catalog/themes.json` (30) | `theme` roots, provenance `authored` |
| `catalog[].themes` | show↔theme edges |
| `curation/arc-bakeoff/episode-themes/<slug>.json` | `theme` children + `episode_theme`, provenance `proposed` |
| `curation/arc-bakeoff/human-verdicts.json` | `verdict`, provenance `authored` |

The verdict seed is the delicate one: those rows key on positional arc index, so
they must be resolved to durable ids **during** migration, while the detector
output that produced them is reproducible. Migrating them later is not possible.

## The corpus is not the show

A show's public RSS is often not its archive, and the store must never assume it is.

**This American Life** publishes a rolling window: its feed carries 15 items numbered
884–892, while roughly 892 episodes exist. **Twenty-six shows are samplers** — a trailer
and episode one, with the rest behind a subscription. The NYT and Serial Productions
catalogues are almost entirely this shape, and some publishers say so outright: Wondery
ships an item titled *"Where to find Episodes 2-6 of The Shrink Next Door"*.

This is **not** our truncation. `scripts/fetch-atlas-feeds.py` caps at 800 episodes, so a
feed holding two items served two. The only feeds we cut are the handful sitting exactly
at 800.

`build-catalog-index.py` labels every such feed, and the browser shows the reason on the
show rather than reporting "no arcs found", which would blame the detector for a
publisher's decision:

| Label | Shows | Meaning |
|---|---|---|
| `sampler` | 26 | Only the opening is public |
| `short-series` | 5 | A genuinely complete short run |
| `unknown-short` | 6 | Short, no numbering to reason from |
| `empty-feed` | 3 | Serves no full episodes at all |
| `windowed` | 1 | Recent episodes only (This American Life) |

Detection is deliberately conservative. `windowed` requires a *contiguous* run of episode
numbers starting far above 1 — a depth ratio alone produces false positives, because
Criminal and RedHanded both carry a stray `episodeNumber` of 10001 as a sort key while
numbering honestly from 1.

Consequences for the design:

- **Arcs in the store are derived from what was public.** A subscriber pasting their own
  premium feed URL sees strictly more episodes than the catalog ever will.
- **This is precisely the on-device regex path's job.** For a private feed there is no
  store entry and never will be, so `EpisodeArcs.swift` is the primary path for those
  shows, not a fallback. It has to keep working.
- `feedAccess` from `curation/atlas-source.json` (`free-public` / `early-access-paywall` /
  `subscription-only`) is carried through as supporting context, but it is **not** a
  reliable completeness signal on its own: *1619* and *Caliphate* are marked `free-public`
  and are still samplers.

## Open decisions

- **Is the published export public?** It contains nothing sensitive — everything
  derives from public RSS — but it is the curation work. An unguessable URL, or
  a bearer token checked by a small Worker, would cover it. Undecided.
- **Do the seed JSON files stay in git after migration** as the human-readable
  record, or are they retired in favour of the store's export? Leaning retire,
  since two records that can disagree is worse than one.

## Not in scope

- Live arc computation for arbitrary feeds. Requires hosted compute; deferred.
- Rewriting the atlas pipeline (`curation/atlas-source.json`,
  `curation/build-atlas.mjs`). The store consumes its output, not its job.
- **A known corpus defect, recorded here so it is not rediscovered:** eight
  "anthology" feeds resolve to the wrong show — `broken-record` is a teenager's
  music vlog, `hit-parade` a Spanish radio chart show, `homecoming` a self-help
  podcast, plus `animal`, `earshot`, `shift`, `startup`, `gun-machine`. And
  `making-obama` / `making-oprah` are byte-identical: one WBEZ umbrella feed
  resolved twice. Cause: `scripts/fetch-atlas-feeds.py` matches on title
  similarity alone, so a same-named podcast wins. Any taxonomy built over those
  feeds describes the wrong show.
