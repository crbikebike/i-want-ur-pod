# Program Plan: The Permanent Catalog

## Context

The on-device regex taxonomy answered its question: yes, you can group episodes into arcs on the fly, for about 30% of them. That proved the browsing experience works — users said it beats every other podcast app at finding things. But 30% coverage can't carry the product, and the reason isn't the detector. It's that the data underneath was never designed.

Today the catalog is hundreds of loose JSON files. The taxonomy exists in three unconnected places: 30 show-level themes, a separate fine-grained episode vocabulary, and regex arc labels. Nothing shares an identity. The app reads a flattened snapshot that throws most of it away. Two catalog entries are limited series pointed at their parent show's RSS feed, so they claim 700 episodes each. That is the convolution — a data model problem wearing a Swift costume.

This program starts over on the data. It builds one permanent, queryable catalog with a graph on top, an admin tool to keep it good, and a React app that works on web, iOS, and Android from one codebase.

**Goals, in priority order:**
1. Story-driven, investigative shows only. No host-interviews-guest talk shows.
2. A stranger finds an interesting narrative podcast within 3 minutes of opening the app.
3. Users can add their own premium feeds (on-device regex treatment, not deep catalog).
4. Users can see their listening history, per show and as a time series.

**Non-goal:** getting people to keep listening to the same shows. The point is pulling attention away from talk-show bros toward narrative work they'd never have found.

---

## Decisions locked

| Question | Decision |
|---|---|
| Sequence | Catalog + graph first. Admin tool second. App last. |
| Repo | Same repo, new branch off `main`. Clean tree, old work tagged. |
| Backend | None. Versioned static artifacts. |
| Ship format | One SQLite `.db` file per release. |
| Source of truth | The SQLite database itself, with an append-only `edits` table for audit and undo. |
| Schema shape | Normal typed tables + one generic `edges` table for traversal. |
| Node types | Show, Episode, Arc, Theme, Subject, Person, Network, Entity. Schema holds all; populate in waves. |
| Taxonomy | Two levels. **Themes** are the browsable set (32) tagged on shows. **Subjects** are the 148 finer labels carried by episodes; each belongs to one theme. |
| Series identity | `Arc.kind` = `series` \| `arc`. Duplicate shows merge into their parent feed via the inclusion queue. |
| Swipe unit | Theme cards, as today. Proven. |
| Episode labels | Re-run batched (20/call), escalate to 3 votes only on doubt. ~5–8k calls, not 82k. |
| Arcs | LLM-built with confidence, lowest-confidence reviewed first. Regex cascade retained for user feeds only. |
| Inclusion | Audit the ~40 suspicious shows, not all 310. |
| Publish gate | Tiered depth. Every show ships, carrying a depth level the UI respects. |
| Coverage | Accept remaining gaps. 4,210 episodes dropped by the 2026-07 run's `episodeType == 'full'` filter were recovered in Phase 1; the hfab agent backfills the rest, and gap-spotting is an admin tool report. |
| Language | Multilingual data, English vocabulary, filterable by language. |
| Vocabulary | Editable in the admin tool from day one. |
| Corrections | Both pin the value AND accumulate as few-shot examples for re-runs. |
| Admin stack | React + a localhost-only write API. Never deployed. |
| App runtime | Expo / React Native. Web target first. Local Xcode builds on the Mac — no paid cloud build. |
| CarPlay | Deferred, not blocked. Playback logic stays in shared code. |
| History | Local only, exportable to a file. No accounts. |
| Hosting | Cloudflare R2 free tier. |
| Freshness | Incremental releases published by an always-on agent on hfab. Auto-publish labels; alert on anomalies. Arcs and vocabulary changes wait for approval. |
| Success test | A written checklist of cold starts, timed by hand, re-run after each change. |
| Planning | This program plan, plus a fresh spec + plan written at the start of each phase. |

---

## Repo and branch mechanics

New branch `feat/permanent-catalog` off `main`. Before anything is removed:

1. Tag the current state: `git tag reference/swift-app-2026-07` on `feat/arc-detector-recall-bakeoff`.
2. Write `docs/patterns-from-swift.md` — what the Swift app got right that the React app should inherit (navigation map, playback state machine, queue semantics, the CarPlay IA). Source material already exists in `docs/spec/` and `docs/design/`.

**Carries over:** `curation/` raw source data (read-only inputs), `design/kit/`, `docs/spec/`, `docs/design/`, `curation/arc-bakeoff/approaches.py` (the A6 cascade, for user feeds).

**Removed from the tree:** `IWantUrPod/`, `IWantUrPodTests/`, `Packages/`, `project.yml`, `tools/catalog-browser/`, the ad-hoc `curation/arc-bakeoff/*.mjs` workflows. All recoverable from the tag.

New layout:

```
catalog/
  schema.sql
  build/              migration, vocabulary mapping, edge builder
  releases/           built .db files (gitignored)
docs/
  PROGRAM.md          this plan, committed
  specs/              one spec per phase, written just in time
  patterns-from-swift.md
curation/source/      existing JSON, read-only inputs
design/kit/
```

---

## Data model

Typed tables carry the facts. One `edges` table carries the relationships, so traversal and "explain the connection" are generic instead of hand-written per path.

**The vocabulary has two levels and two names.** A **Theme** is one of the 32 broad, hand-authored categories — the browsable layer, the deck a person swipes, and what a whole *show* is tagged with. A **Subject** is one of the 148 finer labels, what an individual *episode* is about, and every subject belongs to exactly one theme. Nothing is called "category": `shows.apple_category` is Apple's directory taxonomy and the two would be confused constantly.

```sql
shows       (id, slug, title, network_id, feed_url, home_url, artwork_url,
             lang, apple_category, years, why, description, depth, include_verdict)
episodes    (id, show_id, guid, title, season, episode_number, episode_type,
             published_at, description, duration_s, available, arc_id)
arcs        (id, show_id, slug, kind, name, description, confidence, source)
themes      (id, slug, name, description)                  -- the browsable 32
subjects    (id, slug, name, description, theme_id)        -- the 148, each under a theme
people      (id, slug, name, role)
networks    (id, slug, name)
entities    (id, slug, name, kind)      -- real-world: case, company, person, place, era

show_themes      (show_id, theme_id)
episode_subjects (episode_id, subject_id, role, confidence, agreement, model, run_id)
edges            (src_type, src_id, dst_type, dst_id, kind, weight, why)
edits            (id, at, actor, entity_type, entity_key, field, before, after, note)
releases         (version, built_at, show_count, episode_count, content_hash, notes)
```

Key rules:
- **The catalog never stores an audio URL.** Audio belongs to the show's host, resolved from the live feed at play time. Enclosure URLs are volatile — tracking prefixes rotate and dynamic ad insertion makes them session-specific, so a cached one is a dead play button. Duration is cached as a display hint only; the player trusts the feed.
- **Stable identity.** Every entity has an immutable slug. Incremental releases never renumber. **`edits.entity_key` is a stable string, never an internal id** — every build regenerates those integers, so an edit keyed on `id = 42` would silently land on a different row.
- **Themes and subjects are separate tables**, which makes `slug` plainly unique in each. Five slugs legitimately exist at both levels (`political-scandal`, `institutional-coverup`, `police-misconduct`, `wrongful-conviction`, `family-secret`); one shared table needed a composite key and a CHECK constraint to express what `subjects.theme_id NOT NULL` now says by itself.
- **`edges.why`** holds the human-readable reason a connection exists. This is what powers "explain the connection" — the path is displayable, not just computable.
- **Themes 31 and 32 were added after the first mapping pass.** `curation/source/themes.json` is a read-only input, so additions live in `catalog/build/added-themes.json` and the build appends them. The original 30 were authored before the 27k episodes were labelled; mapping subjects onto them surfaced two clusters with no home — **Being Human** (lived experience, now the 3rd-largest theme) and **A Sense of Place**. That cut low-confidence mappings from 24 subjects / 7,294 episodes to 8 / 2,415.
- **`shows.depth`** is 1–4 (metadata → episodes labelled → arcs → subjects). The UI reads it and never offers what a show doesn't have.
- **`edits`** is append-only. It is both the undo log and the few-shot example store for re-runs.
- **FTS5** virtual table over show and episode text for search.

---

## Phases

Each phase gets its own spec and plan, written when it starts — not now. Phases only advance when their gate passes.

### Phase 1 — Catalog + graph ✅ complete 2026-07-26
Build the schema, migrate everything, build the edges, prove the queries.

**Gate — passed.** All seven automated checks green, and Chris reviewed the query output
across all 315 shows and judged the rows defensible. Built artifact: 315 shows, 31,653
episodes, 32 themes, 148 subjects, 799 arcs (589 verified), 14,137 edges, 31 MB, seven
seconds, reproducible by content hash. 83 tests.

Re-run it any time with `python -m catalog.build.migrate && python -m catalog.build.verify`.

**Gate:**
- All 315 catalog shows migrated, every one carrying at least one episode. 31,653 episodes:
  27,443 labelled plus 4,210 recovered from the theming run's `episodeType` filter. Zero
  orphans. The 12 shows with no *labelled* episodes stay at depth 1 but are browsable.
- All 148 subjects belong to a theme. 5 resolve by same-slug match, 34 from
  `_vocabulary.json`'s `relatedShowThemes`, and the remaining 109 are hand-authored in
  `catalog/build/subject-themes.json` with a confidence each and reviewed in Phase 2.
- Edges built. Traversal under 50ms on device-class hardware.
- Three named queries return rows a human agrees with:
  - **next-thing** — given a show or arc, 3 unrelated shows that scratch the same itch
  - **explain** — a displayable path between any two shows
  - **entry-point** — for a 500+ episode show, where to start
- `edits` table works. Rebuild-from-scratch script works and is reproducible.

### Phase 2 — Admin tool
React + localhost write API. Four jobs, all day one: a worst-first review queue, vocabulary rename/merge/split, graph browsing for gap-spotting, and inclusion verdicts.

**Gate:** you can clear a review queue, rename a theme, merge the two duplicate shows into their parent feeds, and cut a talk show — all landing in `edits` and reflected in the next build.

### Phase 3 — Deep labelling runs
Batched relabel with escalation. LLM arc detection with confidence. Subject extraction everywhere, confidence-gated so a subject appearing once is dropped as noise. Reviewed through the phase-2 queue, lowest confidence first.

**Gate:** every show reaches depth 3. Corrections from review are feeding back into run prompts. ✅ **Closed 2026-08-05** — 275/275 at depth ≥ 3 (167 at 4); `agreement` filled on all 5,195 doubtful labels by 3-vote escalation; the label queue writes human verdicts to `docs/briefs/corrections.md`, which every labelling brief cites. See `docs/HANDOFF-phase3.md`.

### Phase 4 — hfab publisher
**Deferred 2026-08-05 — Phase 5 starts first, by decision.** Stub with scope, existing pieces, and the one dependency Phase 5 takes on (a static release export standing in for R2): `docs/specs/phase-4-hfab-publisher.md`.

Always-on agent: comb feeds, label new episodes, publish incremental releases to R2. Auto-publishes labels. Alerts on anomalies (new theme appearing, show going silent, confidence dropping). Holds arcs and vocabulary changes for approval.

**What the comber must do on every pass**, accumulated as each phase discovers it:

| Job | Why |
|---|---|
| New episodes → label them | The point of combing |
| Fill in `duration_s` | Absent from the whole corpus; browse needs "6 parts, 4h 20m" |
| Re-fetch descriptions at full length | The 2026-07 run truncated them at ~250 characters, which caps subject-extraction quality |
| **Compare `<itunes:image>` to `shows.artwork_url`; on change, update it and stamp `artwork_updated_at`** | Publishers replace cover art. Apple serves covers with `max-age=16480651` — 190 days — so a client that has one keeps it until next year. The API appends `?v=<artwork_updated_at>` to bust that, but only the comber can notice the change. Note `feeds/*.json` does not currently capture the feed's image at all, so the comber has to start recording it. |
| Stamp `artwork_checked_at` whether or not it changed | Lets it re-check the longest-unchecked shows rather than re-walking all 315 |
| Notice dead feeds and shows that stopped publishing | Fills the maintenance queue in the workbench for approval |
| Never fetch or store audio URLs | They belong to the host and rotate |

**The publisher's job is depth, not recency.** The app is already current between releases because store-first reconcile reads each show's live feed on open — it has to, in order to resolve audio at all. New episodes therefore appear immediately with regex arcs; the publisher is what later gives them real labels and real arcs.

**Gate:** a new episode appears in a release without you touching anything, and a deliberately broken feed raises an alert instead of shipping garbage.

### Phase 5 — React app
Expo, web target first. Theme-card swipe flow, show and episode views, playback. Informed by `patterns-from-swift.md` and by what phase 2 taught about navigating the catalog.

**Gate:** the timed cold-start checklist passes under 3 minutes, repeatedly.

### Phase 6 — User feeds + history
Port the A6 regex cascade to the app for user-added feeds. Local listening history with per-show and time-series views, plus file export.

**Gate:** a private premium feed added by hand gets arc grouping on device, and history survives an export/import round trip.

---

## Verification

**Phase 1, end to end:**
1. `python catalog/build/migrate.py` from a clean checkout → `catalog/releases/catalog-v1.db`
2. Integrity checks: row counts against source files, zero orphaned foreign keys, every subject has a parent, every episode has a show.
3. Run the three named queries from `catalog/build/queries/` and read the output. Not "it returned rows" — the rows have to be defensible. I'll show you the output for judgment.
4. Time the traversal query. Under 50ms.
5. Delete the `.db`, rebuild, confirm the **content hash matches** — a SHA-256 over a canonical dump of every table, deterministically ordered, excluding the build timestamp. Not byte-identical: a SQLite file carries page-layout bytes that vary without the data differing. Reproducibility of the *data* is the whole point of a permanent catalog.
6. Write an edit to the `edits` table, rebuild, confirm it survives.

**Every phase:** the gate checks above, run and shown, before the next spec gets written.

---

## Open, deliberately deferred

- What "aggregate over time series" means exactly in the history view (phase 6).
- Whether the fine episode vocabulary needs pruning after the parent mapping reveals overlaps (phase 2 will tell us).
- Apple Developer enrollment ($99/yr) — only needed if you want TestFlight or App Store. Not needed to run on your own phone.
