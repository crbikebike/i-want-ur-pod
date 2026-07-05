# Roadmap — i want ur pod

An open-source iOS podcast app for **story-driven and investigative** podcasts —
*less talk show, more story arcs.* Native SwiftUI, local-first, MIT-licensed.

The product opens by explaining that point of view and offering a **hand-curated set
of places to start**, not a search box or an import prompt. This roadmap expresses
the near-term work as **seven user journeys**, decomposed into **epics → stories**,
each with **determinate (testable) acceptance criteria**.

**Status:** M0.5 (Design) and M1 (Foundations) complete — models, DirectoryKit
search, Discover, and the CarPlay seam exist. This roadmap covers what comes next.

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
  - A query returns results from the primary source (Apple) with PodcastIndex fallback
    per §12.3.
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
  author), sorted by `dateAdded` (newest first).
  - Subscribing adds a row; unsubscribing removes it.
  - Tapping a row opens the E2 detail in subscribed state.
  - With no subscriptions, an empty state is shown (not a blank pane).

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

---

## Key decisions

Carried forward and new:

- **Platform:** native iOS 17+, SwiftUI, Swift only. **No sync in v1** (local-first,
  designed so sync can be added later).
- **First run is curated, not imported.** A hand-maintained bundled JSON
  ([`curated-list.schema.md`](docs/spec/curated-list.schema.md)) — no backend, works
  offline. Editorial upkeep is an accepted, recurring chore.
- **Search stays** alongside curated browse. Apple (`ITunesSource`) primary, no key;
  PodcastIndex opt-in with your own free key in Keychain. Primary + fallback, **never
  merged** (§12.3). Sources are chosen in Settings, not inline.
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
