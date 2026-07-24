# Offline Catalog — Schema & Provenance

Bundled, no-API data for the future **browsable catalog + themed recommendations**
(static/editorial v1, personalization later). It is a **superset of the curated
"Start Here" schema** (`docs/spec/curated-list.schema.md`) so it reuses the same
loader / `SearchResult` projection / subscribe path — a catalog entry can be
subscribed to offline because it bundles a real `feedUrl`.

Two files, both built by `scripts/build-catalog.py` (re-runnable):

## `catalog.json`

A JSON **array** of the **315 subscribable** curated shows (atlas shows that
resolved to a live public feed; paywalled/exclusive shows are omitted). Each entry
(wire keys match `SearchResult` CodingKeys exactly — `feedUrl`/`homeUrl`/`artworkUrl`,
not camelCase):

| Key | Type | Req | Notes |
|---|---|---|---|
| `id` | int | yes | Stable atlas id. |
| `title` | string | yes | Show title. |
| `author` | string | yes | Publisher / studio (iTunes `artistName`, falls back to `network`). |
| `network` | string | no | Curated network label from the atlas. |
| `feedUrl` | string(URL) | yes | RSS feed — the subscribe handle + identity. Always present. |
| `homeUrl` | string(URL) | no | Show page (iTunes `collectionViewUrl`). |
| `artworkUrl` | string(URL) | no | 3000px square art (iTunes). ~20 shows lack it → placeholder. |
| `category` | string | no | iTunes `primaryGenreName`. |
| `years` | string | no | e.g. `2016–`. |
| `why` | string | no | One editorial sentence — why this show is notable. |
| `description` | string | no | 1–2 sentence show summary. |
| `themes` | [string] | yes* | Theme slugs into `themes.json` (`arcs[].showIds` membership). *Empty for the few shows in no curated arc.* |

## `themes.json`

A JSON **array** of the **30 curated theme-arcs** (taxonomy only; per-show
membership lives in `catalog.json`), sorted by `showCount` descending:

| Key | Type | Notes |
|---|---|---|
| `slug` | string | Stable id (e.g. `institutional-coverup`). |
| `name` | string | Display name (e.g. "The Institutional Cover-Up"). |
| `description` | string | One-line definition of the theme. |
| `showCount` | int | Number of catalog shows in this theme. |

## Provenance

- **Source of truth:** `curation/atlas-data.json` (hand-curated shows, themes, `why`,
  descriptions) + `curation/feeds/<slug>.json` (feed URLs resolved by
  `scripts/fetch-atlas-feeds.py`) + a **build-time** iTunes Search enrichment for
  artwork/author/home/category. **No network call ships in the app.**
- **Freshness:** as fresh as the last `build-catalog.py` run — feed URLs and artwork
  can drift; re-run to refresh (iTunes results are cached in `_itunes_cache.json`).
- **Not yet bundled** into `IWantUrPod/Resources/` — copying it into the app bundle
  is part of the later catalog-UI work.
