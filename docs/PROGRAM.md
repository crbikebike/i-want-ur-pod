# Program Plan: The Permanent Catalog

## Context

The on-device regex taxonomy answered its question: yes, you can group episodes into arcs on the fly, for about 30% of them. That proved the browsing experience works — users said it beats every other podcast app at finding things. But 30% coverage can't carry the product, and the reason isn't the detector. It's that the data underneath was never designed.

Today the catalog is 329 loose JSON files. The taxonomy exists in three unconnected places: 30 show-level themes, a separate fine-grained episode vocabulary, and regex arc labels. Nothing shares an identity. The app reads a flattened snapshot that throws most of it away. Two catalog entries are limited series pointed at their parent show's RSS feed, so they claim 700 episodes each. That is the convolution — a data model problem wearing a Swift costume.

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
| Node types | Show, Episode, Arc, Theme, Person, Network, Subject. Schema holds all; populate in waves. |
| Taxonomy | Two tiers. The 30 stay browsable; every fine episode theme declares a parent. |
| Series identity | `Arc.kind` = `series` \| `arc`. Duplicate shows merge into their parent feed via the inclusion queue. |
| Swipe unit | Theme cards, as today. Proven. |
| Episode labels | Re-run batched (20/call), escalate to 3 votes only on doubt. ~5–8k calls, not 82k. |
| Arcs | LLM-built with confidence, lowest-confidence reviewed first. Regex cascade retained for user feeds only. |
| Inclusion | Audit the ~40 suspicious shows, not all 310. |
| Publish gate | Tiered depth. Every show ships, carrying a depth level the UI respects. |
| Coverage | Accept current gaps. The hfab agent backfills over time; gap-spotting is an admin tool report. |
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

```sql
shows       (id, slug, title, network_id, feed_url, home_url, artwork_url,
             lang, apple_category, years, why, description, depth, include_verdict)
episodes    (id, show_id, guid, title, subject, published_at, duration, arc_id)
arcs        (id, show_id, kind, name, description, start_ep, end_ep, confidence, source)
themes      (id, slug, name, description, parent_id, tier)
people      (id, slug, name, role)
networks    (id, slug, name)
subjects    (id, slug, name, kind)          -- case, company, person, place, era

episode_themes (episode_id, theme_id, role, confidence, vote_agreement, model, run_id)
edges          (src_type, src_id, dst_type, dst_id, kind, weight, why)
edits          (id, at, actor, entity_type, entity_id, field, before, after, note)
releases       (version, built_at, show_count, episode_count, notes)
```

Key rules:
- **Stable identity.** Every entity has an immutable slug. Incremental releases never renumber.
- **`themes.parent_id`** implements the two tiers. Tier-1 rows are the browsable 30; tier-2 rows are the fine episode themes and must have a parent.
- **`edges.why`** holds the human-readable reason a connection exists. This is what powers "explain the connection" — the path is displayable, not just computable.
- **`shows.depth`** is 1–4 (metadata → episodes labelled → arcs → subjects). The UI reads it and never offers what a show doesn't have.
- **`edits`** is append-only. It is both the undo log and the few-shot example store for re-runs.
- **FTS5** virtual table over show and episode text for search.

---

## Phases

Each phase gets its own spec and plan, written when it starts — not now. Phases only advance when their gate passes.

### Phase 1 — Catalog + graph
Build the schema, migrate everything, build the edges, prove the queries.

**Gate:**
- All 310 shows and ~27,600 episodes migrated. Zero orphans.
- Fine episode vocabulary extracted and every term mapped to one of the 30 parents.
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

**Gate:** every show reaches depth 3. Corrections from review are feeding back into run prompts.

### Phase 4 — hfab publisher
Always-on agent: comb feeds, label new episodes, publish incremental releases to R2. Auto-publishes labels. Alerts on anomalies (new theme appearing, show going silent, confidence dropping). Holds arcs and vocabulary changes for approval.

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
2. Integrity checks: row counts against source files, zero orphaned foreign keys, every tier-2 theme has a parent, every episode has a show.
3. Run the three named queries from `catalog/build/queries/` and read the output. Not "it returned rows" — the rows have to be defensible. I'll show you the output for judgment.
4. Time the traversal query. Under 50ms.
5. Delete the `.db`, rebuild, confirm byte-identical output. Reproducibility is the whole point of a permanent catalog.
6. Write an edit to the `edits` table, rebuild, confirm it survives.

**Every phase:** the gate checks above, run and shown, before the next spec gets written.

---

## Open, deliberately deferred

- What "aggregate over time series" means exactly in the history view (phase 6).
- Whether the fine episode vocabulary needs pruning after the parent mapping reveals overlaps (phase 2 will tell us).
- Apple Developer enrollment ($99/yr) — only needed if you want TestFlight or App Store. Not needed to run on your own phone.
