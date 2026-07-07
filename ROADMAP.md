# Roadmap — i want ur pod

An open-source iOS podcast app for **story-driven and investigative** podcasts —
*less talk show, more story arcs.* Native SwiftUI, local-first, MIT-licensed.

The product opens by explaining that point of view and offering a **hand-curated set
of places to start**, not a search box or an import prompt. This roadmap expresses
the near-term work as **seven user journeys**, decomposed into **epics → stories**,
each with **determinate (testable) acceptance criteria**.

**Status:** M0.5 (Design) and M1 (Foundations) complete — models, DirectoryKit
search, Discover, and the CarPlay seam exist. This roadmap covers what comes next.
Since M0.5 landed, the design kit picked up two more rounds of decisions: a
**2026-07-05 IA revision** (the tab bar is now a four-item dock — Home · Shows ·
Up Next · Search — replacing Discover/Podcasts/Up Next/Downloads/Settings) and
**2026-07-06** decisions (v1 searches **Apple only**, no source picker; **Podcast
Detail** gained real feed data + a story-arcs shelf). The kit is updated and
the SwiftUI translation shipped as **E8** (2026-07-06) — see below. Journeys/epics
below still describe screens by their pre-revision names where that's how they
shipped; each affected spot has a note pointing at the new names.

---

## How to read this

- **Journey → Epic → Story.** The seven journeys map to Epics **E0–E6**, listed in
  dependency order (E0 first).
- **Determinate tests.** Every story lists observable pass/fail criteria — an agent
  can tell whether it's done without a judgment call.
- **Supporting docs.** Each story cites the reference doc(s) that make it buildable
  without per-story hand-holding. These live in [`docs/spec/`](docs/spec/) and are the
  single source of truth for their area. Write/consult them before building the epic.
- **Definition of Done** ([`docs/spec/definition-of-done.md`](docs/spec/definition-of-done.md))
  applies to *every* story — builds, tests, design fidelity, model hygiene, typed
  errors. Stories don't restate it.

### The seven journeys

1. **First run** — we explain the story-driven focus, then show suggested places to start. → **E1**
2. **Podcast detail** — larger artwork, description, publisher, episode list. → **E2**
3. **Subscribe** — add a show; it appears on the Podcasts list; open its detail. → **E3** (+E2)
   *(the dock IA renames this surface Podcasts → Shows per the 2026-07-05
   revision; translation tracked in E8-S3.)*
4. **Played/unplayed** — a subscribed show marks which episodes are played. → **E2-S3 / E4-S3**
5. **Up Next queue** — add episodes, drag to reorder, swipe to remove. → **E5**
6. **Download & play** — download an episode, then play it. → **E4**
7. **Now Playing** — a mini view of what's playing, expandable to a full view. → **E6**

### Supporting docs (all in `docs/spec/`)

| Doc | Backs |
|---|---|
| [`feed-field-mapping.md`](docs/spec/feed-field-mapping.md) | E0 |
| [`curated-list.schema.md`](docs/spec/curated-list.schema.md) | E1-S2 |
| [`playback-state-machine.md`](docs/spec/playback-state-machine.md) | E4 |
| [`queue-semantics.md`](docs/spec/queue-semantics.md) | E5 |
| [`navigation-map.md`](docs/spec/navigation-map.md) | E2, E6 (all UI) |
| [`definition-of-done.md`](docs/spec/definition-of-done.md) | every story |

---

## Epics & stories

### E0 — Feed Parsing *(prerequisite for everything below)*

The first real domino: every journey past first-run needs "feed URL → `Podcast` +
`[Episode]`." Lands in `FeedParsingKit` (currently a namespace stub).
**Doc:** [`feed-field-mapping.md`](docs/spec/feed-field-mapping.md).

- **E0-S1 — Fetch + parse a feed.** Turn an RSS/iTunes feed URL into a `Podcast` and
  its `[Episode]`, decoding incrementally.
  - Given a known-good fixture feed, parsing yields the expected title/author/artwork
    and N episodes with `title`/`guid`/`publishDate`/`duration`/`audioURL` populated.
  - An `<item>` with no `<enclosure>` **and** no `<guid>` is skipped, not crashed.
  - A 404 or non-XML body throws a **typed** error (never traps).
  - A valid channel with zero playable items yields an empty `episodes` array.
- **E0-S2 — Field mapping + idempotent upsert.** Map feed elements to model fields per
  the doc; re-parsing the same feed matches on `feedURL`/`guid`.
  - Re-parsing updates feed-derived fields but **never clobbers** user-owned fields
    (`isSubscribed`, `dateAdded`, `downloadState`, `playbackProgress`).

### E1 — First-Run & Curated Discovery *(Journey 1; search kept)*

**Docs:** [`curated-list.schema.md`](docs/spec/curated-list.schema.md),
[`navigation-map.md`](docs/spec/navigation-map.md). Reuses live `DirectoryKit` +
`DiscoverScreen`. **Depends on:** E0, E2 (tap-through).

*The dock IA (2026-07-05) renames "Discover" throughout this epic: the
curated shelf moves to the new **Home** landing feed, and keyword search
moves to the **Search takeover** (no standalone Discover tab). This epic's
stories still describe the pre-revision Discover surface as originally
built; the SwiftUI translation to Home + Search takeover is tracked in E8-S1
and E8-S2.*

- **E1-S1 — First-run explainer.** A once-only intro to the story-driven focus, shown
  before Discover; re-openable from Settings.
  - Fresh install shows it before Discover; a relaunch does not.
  - The persisted flag is resettable from Settings, which re-shows it.
- **E1-S2 — Curated "start here" shelf.** Render the bundled
  `curated-start-here.json` on Discover.
  - The shelf renders every valid entry in file order.
  - A malformed entry is skipped, not fatal; a missing file yields an empty shelf, not
    a crash.
  - Tapping an entry opens the E2 detail for its `feedUrl`.
- **E1-S3 — Keyword search.** Search reachable from Discover, reusing
  `SearchCoordinator` and the existing states (typing/loading/results/no-results/error).
  - A query returns results from the primary source (Apple); v1 is Apple-only,
    no fallback source (§12).
  - An empty query shows the curated/idle state; a source error shows the error state
    without crashing.

### E2 — Podcast Detail *(Journeys 2 & 4-shell; one adaptive screen)*

One screen that adapts to subscribe state. **Doc:**
[`navigation-map.md`](docs/spec/navigation-map.md). **Depends on:** E0.

- **E2-S1 — Detail screen.** Large artwork, description, publisher/author, and an
  episode list (newest first).
  - Opening a show renders artwork + description + author + ≥1 episode row.
  - Long descriptions truncate with an expand affordance.
  - An episode with no artwork falls back to the show artwork.
  - *Note:* "hosts / channel / studio" resolves to the **author/publisher** string —
    feeds don't carry structured hosts (see `feed-field-mapping.md`); hosts are parked.
- **E2-S2 — Adaptive subscribe control.** Subscribe/Unsubscribe on the same screen,
  persisting `Podcast.isSubscribed`.
  - Tapping Subscribe flips and persists the state across relaunch.
  - After subscribing, the screen shows subscribed affordances.
- **E2-S3 — Played/unplayed markers (shell).** Episode rows render a played marker and
  a progress hint. *Built here; lit up by E4-S3.*
  - Rows read `Episode.isPlayed` (≥0.98) for the marker and `Episode.remainingTime`
    for the hint. With no playback yet, all rows read unplayed.

### E3 — Subscriptions & Library *(Journey 3)*

**Depends on:** E2.

- **E3-S1 — Podcasts tab.** A tabular list of subscribed shows (artwork + title +
  author), sorted by `dateAdded` (newest first). *(The dock IA renames this
  surface Podcasts → Shows per the 2026-07-05 revision; see `shows.html` and
  E8-S3.)*
  - Subscribing adds a row; unsubscribing removes it.
  - Tapping a row opens the E2 detail in subscribed state.
  - With no subscriptions, an empty state is shown (not a blank pane).
- **E3-S2 — Populate episodes on subscribe.** *(Follow-up surfaced by the detail
  episode-loading fix, commit `e62b912`.)* Subscribing from Discover/curated
  currently stores a **metadata-only** `Podcast` (title/author/artwork/feedURL, no
  episodes); the E2 detail backfills episodes on first open. Make the subscribe
  action itself fetch + parse + upsert the feed so a subscribed show has its episodes
  immediately — enabling episode counts on the Podcasts row and a non-empty
  offline-open — without requiring a detail visit. Reuses `FeedFetcher` +
  `FeedUpsert` (idempotent; preserves user-owned fields). **Depends on:** E0, E3-S1.
  - After subscribing **online**, the stored `Podcast` has its episodes
    (`episodes.count > 0`) without opening the detail screen.
  - Subscribing is **best-effort on the network**: subscribing **offline** still
    succeeds as a metadata-only row (no crash, no error surfaced), and episodes are
    backfilled on the next online detail open (the E2 fallback already in place).
  - Re-subscribing or later opening the detail does **not** duplicate episodes
    (idempotent upsert on `feedURL`/`guid`).

### E4 — Playback, download-first *(Journey 6; lights up Journey 4)*

Download-first: an episode plays only from a completed local file — no streaming.
**Doc:** [`playback-state-machine.md`](docs/spec/playback-state-machine.md).
`DownloadKit` + `PlaybackKit` (both stubs today). **Depends on:** E0, E2.

- **E4-S1 — Download an episode.** Drive `DownloadState` transitions via `DownloadKit`.
  - Tapping Download moves state `notDownloaded → downloading(progress) → downloaded`;
    progress updates monotonically.
  - A failed download lands in `.failed(message:)` and is retryable.
  - On completion the local file exists on disk.
- **E4-S2 — Play a downloaded episode.** *(Fully-worked sample.)*
  *As a listener, I can play an episode that's downloaded to my device.*
  - Play is offered **iff** `downloadState == .downloaded`; otherwise only Download is
    offered.
  - Playback in **airplane mode** proves no network use (plays from the local file).
  - Backgrounding continues audio and shows a lock-screen Now Playing entry with title
    + artwork.
  - Playing to ≥98% makes `Episode.isPlayed == true`.
  - Scrubbing to 50% persists `playbackProgress ≈ 0.5` across an app relaunch.
- **E4-S3 — Played markers go live (closes Journey 4).** With playback writing
  progress, E2-S3's markers become real.
  - After playing an episode to completion, its detail row shows the played marker.
  - A partially-played episode shows remaining time.

### E5 — Up Next Queue *(Journey 5)*

**Doc:** [`queue-semantics.md`](docs/spec/queue-semantics.md). Backed by `QueueItem`.
**Depends on:** E4.

- **E5-S1 — Add to Up Next.** Append an episode as a `QueueItem` with the next `order`.
  - Adding appends to the tail; re-adding the same episode is a no-op.
  - The queue persists across relaunch.
- **E5-S2 — Reorder & remove.** Drag to reorder; left-swipe to remove.
  - Drag rewrites `order` to stay contiguous ascending (`0,1,2,…`, no gaps).
  - Left-swipe removes the `QueueItem`; the referenced `Episode` is untouched.
  - Removing the current item leaves active audio playing (per the doc).
- **E5-S3 — Auto-advance.** Finishing the current item plays the next by `order`.
  - On `finished`, the head item becomes current and plays.
  - An empty queue stops cleanly at `idle` (no error).

### E6 — Now Playing UI *(Journey 7)*

**Doc:** [`navigation-map.md`](docs/spec/navigation-map.md). **Depends on:** E4.

- **E6-S1 — Mini-player.** A persistent bar above the tab bar showing the current
  episode (artwork thumb + title + play/pause), on every tab.
  - Starting playback shows the mini-player; it reflects play/pause.
  - It is hidden when the player is `idle`.
- **E6-S2 — Now Playing sheet.** Tapping the mini-player presents a full view: large
  artwork, show/episode details, transport (play/pause, skip, scrub).
  - Scrubbing seeks and updates `playbackProgress`.
  - Dismissing returns to the mini-player with playback state intact.

### E7 — Store resilience: recover instead of crash *(reliability; not one of the seven journeys)*

Today `IWantUrPodApp` traps (`fatalError`) when `ModelSchema.makeContainer()` can't
open the on-disk SwiftData store — so a schema change that lightweight migration
can't handle **hard-crashes the app on every launch** until the user deletes and
reinstalls (the `Podcast.summary` migration bug, fixed in commit `3220341`, was
exactly this). This story replaces the trap with a **graceful reset**: if the store
can't be opened, discard it and start fresh so the app always launches.

**Home:** `ModelSchema.makeContainer` (`Packages/PodcastModels/.../ModelSchema.swift`)
+ app-scope wiring in `IWantUrPod/App/IWantUrPodApp.swift`. **Depends on:** nothing
(pure hardening). **Doc:** self-contained (no `docs/spec/` doc needed).

**Explicit trade-off — this is "option 2", chosen deliberately.** A reset
**destroys all local data** — subscriptions, queue, download states, and playback
progress — with **no recovery**, because v1 has no sync/backup. It trades a *visible
crash* for *silent, unrecoverable data loss*, and is acceptable **only** while the
local store is treated as disposable (pre-release). The data-preserving alternative
(a `VersionedSchema` + `SchemaMigrationPlan`) is the correct answer once there is
data worth keeping; it is recorded under **Parked → "Versioned schema migration"**
and **supersedes this story before release**.

- **E7-S1 — Recover-on-failure container.** `makeContainer(inMemory: false)` attempts
  to open the on-disk store; on an **unrecoverable open/migration error** it deletes
  the store files (`default.store` plus the `-wal`/`-shm` sidecars) and recreates an
  empty container, returning a working container instead of throwing. Recovery is a
  **last resort**, not a routine wipe.
  - A fresh install (no existing store) opens normally and is **not** reset.
  - A valid, openable existing store opens with its data intact and is **not** reset.
  - A store that fails to open (simulate a corrupt/incompatible store file) yields a
    **working, empty** container — `makeContainer` returns rather than throwing, and
    `IWantUrPodApp.init` no longer reaches `fatalError`.
  - The reset is **not silent**: it emits an `os_log` diagnostic recording that a
    reset occurred and the underlying error, so it is observable in the field.
- **E7-S2 — Reconcile orphaned downloads after a reset.** Downloaded audio lives
  outside the SwiftData store (`DownloadStore`, keyed by `Episode.guid`), so a reset
  leaves **orphaned files** that no `Episode` references. After a reset the download
  directory is swept so freed space isn't leaked and no stale `.downloaded` state can
  desync from disk.
  - After a store reset, the `DownloadStore` directory contains no file lacking a
    corresponding persisted `Episode` (post-reset, with an empty store, it is emptied).
  - Determinate: seed the download dir with a file, trigger a store reset, assert the
    directory is reconciled (the orphan is removed).

*Testability:* the recovery + reconcile logic is a package-level seam exercised with a
simulated bad store and a temp download directory — unit-testable via `swift test`
without launching the app.

### E8 — Dock IA & design-kit translation pass *(✅ shipped 2026-07-06)*

The 2026-07-05/06 design rounds locked a new information architecture and a
real-data Podcast Detail screen into the kit — but the SwiftUI app still shows
the pre-revision five-tab bar (Discover, Podcasts, Up Next, Downloads,
Settings) and a Discover-era detail screen. This epic is the translation pass
that brings the app in line with the design's source of truth. **Docs:**
[`docs/design/direction.md`](docs/design/direction.md) §10–§12 (component/screen
inventory, open issues, navigation) and [`design/kit/MANIFEST.md`](design/kit/MANIFEST.md)
(per-file authoritative status). **Depends on:** E1–E3 (surfaces being
translated already exist in some form).

- **E8-S1 — Four-item dock + Search takeover.** Replace the five-item tab bar
  with **Home · Shows · Up Next · Search**; tapping Search turns the bar
  itself into a search field.
  - The tab bar shows exactly four destinations, in order: Home, Shows, Up
    Next, Search. Discover, Downloads, and Settings are no longer tab-bar
    items.
  - Tapping Search collapses the icons and presents a search field in the
    same bar position, with Home pinned to its left and a ✕ to cancel.
  - The takeover field rises to sit just above the keyboard when focused,
    and the results/suggestions region fills the rest of the screen.
  - Dismissing the takeover (✕ or a completed search's back action) restores
    the four-icon bar with the previously active tab still selected.
- **E8-S2 — Home landing feed.** A new Home screen replaces Discover as the
  first destination, per `design/kit/screens/home.html`.
  - Home renders, in order: an Up Next peek, a new-episodes shelf, a shows-
    for-you shelf, and an our-favorites shelf.
  - Each shelf that has no content renders nothing (no empty shelf chrome),
    rather than a blank gap or a crash.
  - Tapping an item in any shelf opens the E2 Podcast Detail (or the episode,
    for the Up Next peek) for its underlying feed/episode.
- **E8-S3 — Shows tab.** Rename/translate the existing Podcasts tab (E3-S1)
  to **Shows**, matching `design/kit/screens/shows.html`.
  - The tab bar label reads "Shows"; the screen content and behavior are
    otherwise unchanged from E3-S1 (subscribed shows, sorted by `dateAdded`).
  - No route, model, or persisted-state name changes are required — this is
    a UI-surface rename only.
- **E8-S4 — Settings as a pushed gear screen.** Move Settings off the tab bar
  to a top-right gear, and reduce its content to downloads management.
  - A gear glyph in the top-right corner of Home/Shows/Up Next pushes the
    Settings screen (with a Done/back affordance to return).
  - Settings is no longer a tab-bar destination.
  - Settings shows exactly one section, **Manage downloaded episodes** — a
    list of downloaded episodes, each removable (removing deletes the local
    audio file; the `Episode` record and its feed membership are untouched).
  - `SourcesView.swift` and any in-app source-picker UI are removed; the
    live source roster is trimmed to Apple only (§12). `DirectoryKit` keeps
    `PodcastIndexSource` + the fallback coordinator as dormant, unused code
    (not deleted) per the Key decisions note above.
- **E8-S5 — Inline download state on Up Next rows.** With Downloads no
  longer a tab, each Up Next row surfaces download state directly.
  - Each Up Next row shows the episode's current `DownloadState`
    (not-downloaded / downloading / downloaded / failed) via an inline icon.
  - Each row offers a download action when not already downloaded, reusing
    `DownloadKit` (E4-S1) — tapping it drives the same state machine.
  - There is no standalone Downloads tab or screen; downloaded-episode
    management lives only in Settings (E8-S4).
- **E8-S6 — Podcast Detail reconcile: compact controls + story arcs.**
  *(Shipped 2026-07-06.)* Bring `PodcastDetailView` in line with
  `design/kit/screens/podcast-detail-<slug>.html`.
  - Download / play / add-to-Up-Next controls render as compact icon-only
    buttons (no redundant "Downloaded" text label).
  - Episode rows show `season · episode` (when available) plus publish date
    and duration.
  - `FeedParser` parses `<itunes:season>`, `<itunes:episode>`, and
    `<itunes:episodeType>` when present; `Episode` gains `season` and
    `episodeNumber` fields (+ a derived-arc field) populated from parsing.
  - A horizontal **Story arcs** shelf renders above the episode list when
    the show's episodes carry derivable arc structure (season data, or
    title patterns `Arc | Title | N` / `Arc - Part N`); each arc card has an
    **"Add all"** control that enqueues every episode in the arc to Up Next.
  - A show with no derivable arcs (no seasons, no matching title structure)
    renders the episode list without the Story arcs shelf — no crash, no
    empty shelf.

---

## Parked

Deliberately out of scope for these journeys — recorded so they aren't lost.

- **CarPlay.** 🅿️ The scene-delegate seam and template skeleton exist
  (`IWantUrPod/CarPlay/*`, `docs/design/carplay-ia.md`) and the playback spec keeps
  remote-command handling CarPlay-compatible — but no CarPlay screens are built in
  this slice. **Still apply early** for the CarPlay Audio entitlement
  (`com.apple.developer.carplay-audio`) — it's manually approved and slow.
- **"Start here" for huge back-catalogs.** A curated entry point into shows like
  *This American Life* with hundreds of episodes and buried classics. Future.
- **Import your list (OPML).** The former first-run opener, on hold — the curated
  shelf replaces it as the way in.
- **Structured hosts / `podcast:person`.** Feeds don't reliably carry hosts; parked
  with the broader Podcasting 2.0 work.
- **Versioned schema migration (`SchemaMigrationPlan`).** The data-preserving
  alternative to **E7**'s reset-on-failure: define `VersionedSchema` versions and
  migration stages so schema changes carry existing local data forward instead of
  discarding it. **Supersedes E7 before release**, once there is on-device data
  (subscriptions, queue, playback progress) worth keeping — a no-sync, local-first
  app has no server to restore from.

---

## Key decisions

Carried forward and new:

- **Platform:** native iOS 17+, SwiftUI, Swift only. **No sync in v1** (local-first,
  designed so sync can be added later).
- **First run is curated, not imported.** A hand-maintained bundled JSON
  ([`curated-list.schema.md`](docs/spec/curated-list.schema.md)) — no backend, works
  offline. Editorial upkeep is an accepted, recurring chore.
- **Sources: Apple only for v1** — the keyless iTunes Search API (`ITunesSource`),
  zero-config, no in-app source picker. **PodcastIndex is deferred** to a later
  milestone (it would add an optional second source with its own key handling);
  the code keeps `PodcastIndexSource` + the fallback coordinator as dormant
  groundwork so adding it later is low-friction.
  - *Note for later:* PodcastIndex also exposes **keyless** Apple-shaped `/search`
    + `/lookup` endpoints — a client can search PodcastIndex with no key at all (a
    key only unlocks richer metadata: descriptions, episode enrichment,
    transcripts/chapters/V4V, trending). And PodcastIndex publishes a **weekly
    full-feeds SQLite dump** (~1.8 GB) they encourage for bulk use — if we ever
    run an optional proxy, it could back a **self-hosted search** with no
    live-API calls, no key, and no rate limits (trade-off: data up to a week
    stale, feeds-only, storage/refresh ops). Not for on-device; backend-only.
- **Dock IA (2026-07-05/06):** navigation is a **four-item dock** — Home · Shows ·
  Up Next · Search. Search has no standalone tab; tapping it turns the dock
  itself into a search field (**search takeover**). **Settings** moved to a
  top-right gear (pushed screen); **Downloads** left the dock — download state
  and a download button are inline on Up Next rows instead. See
  `direction.md` §10–§12 and **E8**.
- **Download-first playback.** An episode plays only from a completed local file; no
  streaming in v1. Simplest path, fully offline, no buffering/seek-over-network edge
  cases.
- **One adaptive podcast-detail screen** for both discovery and library contexts,
  keyed by `feedURL`.
- **CarPlay** remains a first-class goal, parked to a later slice with its seam intact.
- **Tooling:** XcodeGen generates the `.xcodeproj` (not committed). RSS parser package
  is `FeedParsingKit`. Builds run on macOS/Xcode.

---

## Building

```bash
brew install xcodegen
xcodegen generate
open IWantUrPod.xcodeproj
```
