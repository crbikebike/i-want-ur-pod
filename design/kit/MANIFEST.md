# design/kit manifest

The enforced, authoritative inventory of every file under `design/kit/`. This
supersedes `docs/design/direction.md` §10 as the first thing to check before
translating a kit file to SwiftUI, building a new component, or touching an
existing one. `scripts/verify-design-manifest.sh` checks Swift header comments
against this file — keep both in sync.

## Read this first: the "SHARED KIT EXTRAS" trap

Every file below mixes two things:

1. **Unique, bespoke content** — the actual UI that file exists to specify.
2. **An identical, copy-pasted "SHARED KIT EXTRAS" CSS block** near the bottom
   of the file (`.state`, `.chips`, `.sk-row`, `.cardgrid`, `.pcard`,
   `.suggest`, `.btn`, etc.) — repeated verbatim across most kit files purely
   for authoring convenience.

**The shared block is not the file's content.** Two components were
mistranslated by grabbing classes from the shared block instead of reading
the file's real, bespoke markup:

- `ResultRow.swift` claimed to translate `result-row.html`, but grabbed the
  shared `.sk-row` list-row shape instead of that file's real content (a
  category-shelf gallery). First fix attempt renamed it to `SearchResultRow`
  and attributed it to a "shared `.list`/`.row` pattern" supposedly used
  across the screen files — **that attribution was itself wrong**: checking
  actual `<body>` markup (not just each file's `<style>` block) showed `.list`/
  `.row` is never instantiated anywhere in the current kit. Every real results
  view (`typing.html`'s matches, `first-run.html`'s recommendations) renders
  the shelf/rail/pod gallery. Fixed for real by deleting `ResultRow.swift`/
  `SearchResultsList.swift` entirely and building `ResultShelf`/`PodCard`/
  `PodGrid` (below) — the kit's actual, only current results pattern.
  **Lesson: verify a CSS class is instantiated in a file's `<body>`, not just
  declared in its `<style>`, before treating it as real.**
- The Discover `.firstRun` state claimed to translate `first-run.html`, but
  reused the shared `.state` empty-card block instead of that file's real
  content (a multi-step onboarding wizard). Not yet fixed — flagged as a
  placeholder in `EmptyStateView.swift`; building the real wizard is tracked
  separately and out of scope.

When translating or auditing a kit file: identify its bespoke content first
(usually everything before the "SHARED KIT EXTRAS" comment marker), and treat
the shared block as decoration it also happens to consume — never as the
file's defining content.

## Foundations

| Path | Real content |
|---|---|
| `tokens.html` | Canonical CSS variable reference (colors, spacing, radii, motion, elevation) — copied verbatim into every other kit file's `:root`. |
| `styles.css` | 3-line root stylesheet (`@import "fonts/fonts.css"`). Not UI. |
| `fonts/*.css` | `@font-face` declarations for IBM Plex Mono + Roboto. Not UI. |

## Components (`design/kit/components/`)

| Path | Real bespoke content | Swift implementation | Status |
|---|---|---|---|
| `buttons.html` | Primary (filled) / Secondary (outline) / Tertiary (soft tint) pill buttons. | `Components/Buttons.swift` (`PrimaryButton`/`SecondaryButton`/`GhostButton` — `ghost` ⇔ kit's `.btn-tertiary`, documented in-code). | ✅ Implemented |
| `search-field.html` | The search input in default/focused/filled states. | `Components/SearchField.swift` | ✅ Implemented |
| `section-header.html` | The generic label band above a content group (title / title+subtitle / title+count). Explicitly notes a shelf uses its own header instead. | `Components/SectionHeader.swift` | ✅ Implemented |
| `sources-checklist.html` | Isolated Apple/PodcastIndex source-selection rows (toggle, Primary badge, lock + Add API key). Canonical for source-selection behavior. | `Components/SourcesChecklistRow.swift` | ✅ Implemented |
| `subscribe-button.html` | Circular +/check control: default / subscribing (spinner) / subscribed, plus in-context on artwork. | `Components/SubscribeButton.swift` | ✅ Implemented |
| `tab-bar.html` | Floating "Liquid Glass" 5-item bottom tab bar. | `Components/LiquidGlassTabBar.swift` | ✅ Implemented |
| `loading-skeleton.html` | Flat shimmering `.sk-row` placeholder list (art + 3 lines + trailing pill). **Dead pattern**: no current screen shows results as a flat list, so this has no consumer. | — | ❌ Not implemented / superseded by `screens/loading.html`'s shelf skeleton (see below). Do not build a flat-row skeleton against this file. |
| `no-results.html` | Isolated empty-state card: badge, "No shows found" title, message, actions. | `Components/EmptyStateView.swift` (`EmptyKind.noResults`) | ✅ Implemented |
| `result-card.html` | 2-up poster grid card: square gradient artwork + subscribe + title/author. | `Components/ResultCard.swift` | ✅ Implemented |
| `result-row.html` | **Category shelves** — horizontal scrolling rails of podcasts grouped by taxonomy ("Trending now", "True Crime", …), each with "View all" → expandable 2-up grid. **Not a flat row** despite the name — confirmed the kit's *only* current results pattern (verified against actual `<body>` usage across every screen, not just this file's `<style>`). | `Components/ResultShelf.swift` (`ResultShelf`, `PodCard`, `PodGrid`) | ✅ Implemented |

## Discover screens (`design/kit/screens/`, iPhone-framed)

| Path | Real bespoke content | Swift implementation | Status |
|---|---|---|---|
| `typing.html` | Search field mid-typing + a typeahead suggestions drawer; its actual "matches" content (the `.under` section) renders shelves of `.pod` cards, confirming `result-row.html`'s shelf pattern is the real results design, not a flat list. | `IWantUrPod/Discover/DiscoverView.swift` (`.typing` state for the drawer; `.results` state → `ShelvesList` for the shelf content) | ✅ Implemented |
| `loading.html` | "Searching for '…'" header over shimmering shelf/rail skeletons (`.sk-shelf`/`.sk-rail`/`.sk-pod`). | `Components/LoadingSkeleton.swift`, used by `IWantUrPod/Discover/DiscoverView.swift` (`.loading` state) | ✅ Implemented |
| `no-results.html` | Full Discover screen (status bar, nav bar, search field with a query) wrapping the `.state` empty card. | `IWantUrPod/Discover/DiscoverView.swift` (`.noResults` state) | ✅ Implemented |
| `error.html` | Full Discover screen, `.state` card reading "Couldn't reach the directory" + Retry action. | `IWantUrPod/Discover/DiscoverView.swift` (`.error` state) | ✅ Implemented |
| `first-run.html` | **A multi-step guided onboarding wizard**: "Do you already listen to podcasts?" (app picker → OPML import walkthrough, or "starting fresh") → favorite-shows picker → topic picker → personalized category-shelf recommendations → "Start listening". Has a progress bar and back/skip navigation. **Not a static empty state.** | — | ❌ Not implemented. `DiscoverView.swift`'s `.firstRun` state renders a placeholder `EmptyStateView(kind: .firstRun, …)` instead — explicitly documented as a placeholder in `EmptyStateView.swift`, not a translation of this file. Building the real wizard is a separate, tracked feature. |

## Settings screens

| Path | Real bespoke content | Swift implementation | Status |
|---|---|---|---|
| `settings-sources.html` | Full Settings screen (title, lede copy, grouped label) wrapping the same rows as `components/sources-checklist.html`. | `IWantUrPod/Settings/SourcesView.swift` | ✅ Implemented |

## Podcast Detail (E2) — composed, no kit mock

There is no `design/kit/screens/podcast-detail.html` — ROADMAP.md E2 explicitly
says to compose this screen from `docs/design/direction.md` tokens + existing
components rather than wait on a kit mock. Every new file below carries a
`// Composed from docs/design/direction.md tokens — no design/kit source (see
design/kit/MANIFEST.md).` header instead of a `design/kit/*.html` citation, so
`scripts/verify-design-manifest.sh` has nothing to check against them.

| Swift file | Real bespoke content | Status |
|---|---|---|
| `Components/RemoteArtwork.swift` | A remote-image counterpart to `ArtworkTile`: renders a podcast/episode's real artwork URL via `AsyncImage`, falling back to the same `.a1`–`.a6` gradient tile (via the internal `GradientArtwork`, honoring the caller's `cornerRadius`) when the URL is `nil` or hasn't resolved. First screen to show artwork loaded from a feed rather than a synthetic seed. | ✅ Implemented |
| `Components/ExpandableText.swift` | A generic truncate/expand body-copy block (clamped line limit + "More"/"Less" toggle, shown only when the text actually overflows). Built for E2-S1's "long descriptions truncate with an expand affordance" requirement. | ✅ Implemented |
| `HTMLText.swift` | **Data-only utility, no design source.** `String.htmlToPlainText()` / `decodingHTMLEntities()`: converts a feed's raw HTML description/summary into readable plain text (block tags → line breaks, other tags stripped, named + numeric entities decoded, whitespace collapsed). Applied at the two `ExpandableText` call sites in `PodcastDetailView` because `feed-field-mapping.md` keeps raw HTML in the model and leaves rendering/stripping to the display layer. | ✅ Implemented |

**Show description source:** the detail screen's description is
`Podcast.summary` — a feed-derived channel field (`<channel><description>` →
`<channel><itunes:summary>` → `""`) added end-to-end in E0 (`Podcast.summary`,
`ParsedFeed.summary`, and the `FeedUpsert` mapping) per
`feed-field-mapping.md`. `ExpandableText` renders it in the header, and also
each episode's `summary` in the rows. (Author/publisher and category are still
shown alongside, since RSS carries no structured host list — see E2-S1's
"hosts / channel / studio" note.)

## E1 — First-Run & Curated Discovery — composed, no kit mock

E1-S1's once-only explainer is **not** a translation of `screens/first-run.html`
(that file's real content is the multi-step onboarding wizard above, still
unbuilt and out of scope). E1-S2's curated shelf reuses `result-row.html`'s
shelf pattern (via `ResultShelf`, already implemented) rather than needing a
new kit mock. Both new files below carry a `// Composed from
docs/design/direction.md tokens — no design/kit source (see
design/kit/MANIFEST.md).`-style header instead of a `design/kit/*.html`
citation.

| Swift file | Real bespoke content | Status |
|---|---|---|
| `IWantUrPod/Discover/FirstRunExplainerView.swift` | A small, once-only intro screen (badge, headline, one-paragraph pitch, "Get started") presented as a `fullScreenCover` on `DiscoverView`, gated by `FirstRunGate`. Deliberately lightweight — not the kit's unbuilt multi-step wizard. | ✅ Implemented |
| `IWantUrPod/Discover/FirstRunGate.swift` | A `UserDefaults`-backed flag (`hasSeenFirstRun` / `markSeen()` / `reset()`) gating the explainer. Not a UI component — no kit citation needed; listed here for completeness since it's new in E1. | ✅ Implemented |
| `IWantUrPod/Discover/CuratedShelf.swift` | Renders the bundled `curated-start-here.json` picks (`DirectoryKit.CuratedEntry`, decoded by `CuratedListLoader`) as a **vertical list of editorial cards** under a `SectionHeader`, in file order. Deliberately distinct from search's horizontal gradient `ResultShelf`: each card shows **real artwork** (`RemoteArtwork`, gradient fallback), title, author · category, corner `SubscribeButton`, and the editorial `blurb` as the hero — marked by a coral→mint gradient hairline (the section's one signature, echoing the Discover title's pulse-dot). Same per-item `SubscribeButton` state pattern as `ShelvesList`; tap a card → E2 detail by `feedUrl`. | ✅ Implemented |

## Podcasts tab (E3-S1) — composed, no kit mock

There is no `design/kit/screens/podcasts.html` or list-row mock — the kit's
only flat-row pattern (`components/loading-skeleton.html`'s `.sk-row`) is
called out above as a dead pattern with no consumer, and `result-row.html`'s
real content is the horizontal category-shelf gallery, not a vertical list.
Per the same precedent as Podcast Detail (E2), both files below carry a
`// Composed from docs/design/direction.md tokens — no design/kit source (see
design/kit/MANIFEST.md).` header instead of a `design/kit/*.html` citation.

| Swift file | Real bespoke content | Status |
|---|---|---|
| `IWantUrPod/Library/PodcastsScreen.swift` | The Podcasts tab: a vertical list of subscribed shows, newest `dateAdded` first, each row a `RemoteArtwork` tile + title/author (mirrors `PodcastDetailView.swift`'s `EpisodeRow` shape, scaled down) that pushes its `feedURL` into the shared E2 detail screen. Empty state via `EmptyStateView(kind: .firstRun, …)`. Owns its own `NavigationStack` and reserves `AppShell.tabBarReservedPadding`. | ✅ Implemented |
| `IWantUrPod/Library/PodcastsListProvider.swift` | The testable seam behind the list: fetches every `Podcast` from a `ModelContext` (or takes an already-fetched `[Podcast]`, for the live `@Query` case) and filters/sorts in plain Swift — avoiding the non-Sendable `KeyPath` warning a `#Predicate { $0.isSubscribed }` triggers under this project's strict concurrency setting (same precedent as `PodcastDetailViewModelTests.swift`). Not a UI component — no kit citation needed; listed here for completeness since it's new in E3. | ✅ Implemented |

## Up Next tab (E5) — composed, no kit mock

There is no `design/kit/screens/up-next.html` or reorderable-list mock —
same precedent as Podcast Detail (E2) and the Podcasts tab (E3): compose from
`docs/design/direction.md` tokens + existing components. Unlike
`PodcastsScreen.swift`'s plain `ScrollView`, this screen uses a real `List`
because drag-to-reorder (`.onMove`) and swipe-to-remove (`.swipeActions`) are
native `List` affordances. Every new file below carries a `// Composed from
docs/design/direction.md tokens — no design/kit source (see
design/kit/MANIFEST.md).` header instead of a `design/kit/*.html` citation.

| Swift file | Real bespoke content | Status |
|---|---|---|
| `IWantUrPod/UpNext/UpNextScreen.swift` | The Up Next tab: a `List` of queued episodes in `QueueStore.items` order, each row a `RemoteArtwork` tile + episode/show title `VStack` (mirrors `PodcastsScreen.swift`'s `PodcastRow` shape). Drag reorders via `.onMove` → `QueueStore.move(fromOffsets:toOffset:)`; left swipe removes via `.swipeActions` → `QueueStore.remove(_:)`. Empty state via `EmptyStateView(kind: .firstRun, …)`. Owns its own `NavigationStack` and reserves `AppShell.tabBarReservedPadding`. | ✅ Implemented |
| `IWantUrPod/UpNext/QueueStore.swift` | The app-scoped `@Observable` queue service (E5-S1/S2/S3): add-to-tail with re-add no-op, contiguous-order reorder/remove, and orphan pruning (docs/spec/queue-semantics.md's four invariants). Not a UI component — no kit citation needed; listed for completeness since it's new in E5. Created once in `IWantUrPodApp`, injected via `.environment` (`AppQueue.swift`), same pattern as `DownloadManager`/`PlaybackEngine`. | ✅ Implemented |
| `IWantUrPod/UpNext/QueueAutoAdvanceCoordinator.swift` | Couples `PlaybackEngine.onFinished` to `QueueStore` for E5-S3 auto-advance, kept out of `PlaybackKit` itself so that package stays decoupled from `QueueItem`/`QueueStore`. Not a UI component — no kit citation needed. | ✅ Implemented |
| `IWantUrPod/Detail/PodcastDetailView.swift` (`EpisodeRow.queueControl`) | The "Add to Up Next" control (E5-S1) added to the existing episode row: a `GhostButton` calling `QueueStore.add(episode)` when not yet queued, or an "In Up Next" checkmark label when it is. Composed from tokens, no kit mock (same precedent as the row's existing download/play controls). | ✅ Implemented |

## Now Playing (E6) — composed, no kit mock

There is no `design/kit/screens/now-playing.html` or mini-player mock —
navigation-map.md's "Persistent chrome placement" specifies the mini-player's
*placement* (shell chrome, above the tab bar) and the Now Playing sheet's
*content* (large artwork, details, transport) but no kit file backs either.
Same precedent as Podcast Detail (E2)/Podcasts (E3)/Up Next (E5): compose
from `docs/design/direction.md` tokens + existing components. Every new file
below carries a `// Composed from docs/design/direction.md tokens — no
design/kit source (see design/kit/MANIFEST.md).` header instead of a
`design/kit/*.html` citation.

| Swift file | Real bespoke content | Status |
|---|---|---|
| `IWantUrPod/NowPlaying/MiniPlayer.swift` | E6-S1's persistent bar: `RemoteArtwork` thumb + title/show + a trailing play/pause control, drawn as translucent glass (mirrors `LiquidGlassTabBar`'s material/hairline/shadow treatment so the two chrome pieces read as one system) directly above the tab bar. Reads the app-scoped `PlaybackEngine` from the environment; visible iff `PlaybackTransport.isMiniPlayerPresented(for:)`. Tapping the row presents the Now Playing sheet; tapping the trailing control toggles play/pause without presenting it. | ✅ Implemented |
| `IWantUrPod/NowPlaying/NowPlayingSheet.swift` | E6-S2's full view, presented as a `.sheet` from `AppShell`: large `RemoteArtwork`, episode/show title, a `Slider` scrubber (seeks via `PlaybackEngine.seek(toFraction:)` on release, persisting `Episode.playbackProgress`), and skip-back-15/play-pause/skip-forward-30 transport. Reads the same injected `PlaybackEngine`; dismissing returns to the mini-player with state intact since this view owns no playback state itself. | ✅ Implemented |
| `IWantUrPod/NowPlaying/PlaybackTransport.swift` | The testable seam behind both views: `isMiniPlayerPresented(for state:)` (mini-player visibility), `playPauseAction(for state:)`, and `playPauseSymbolName(for state:)` — pure `PlaybackState` → behavior mappings, exercised directly by `IWantUrPodTests/NowPlayingTests.swift` without needing a live engine. Not a UI component — no kit citation needed; listed for completeness since it's new in E6. | ✅ Implemented |
| `IWantUrPod/App/AppShell.swift` (`miniPlayerHeight`/`miniPlayerReservedPadding`, mini-player + `.sheet` wiring) | The frozen-nav-contract-preserving integration: `AppShell` draws `MiniPlayer` as shell chrome above `LiquidGlassTabBar` (never inside a tab's content), applies the combined bottom reserve to `content`'s own frame when the mini-player is visible (so every screen's existing 104pt internal reserve still clears both the bar and the mini-player, with no screen needing to change), and presents `NowPlayingSheet` via `.sheet(isPresented:)` when the mini-player is tapped. | ✅ Implemented |

## Shared Swift-side infrastructure (no single kit file; cross-cutting)

| Swift file | Source | Notes |
|---|---|---|
| `IWantUrPod/Discover/ShelvesList.swift` | Groups the Discover `.results([SearchResult])` state by `category` into one `ResultShelf` per taxonomy (`result-row.html`'s shelf pattern), with a `PodGrid` sheet for "View all". | App-side composition; not itself a kit translation. |
| `Components/ArtworkTile.swift` (`ArtworkStyle`/`GradientArtwork`/`ArtworkTile`) | The `.a1`–`.a6` gradient tile classes, shared across the result-card poster grid and the shelf gallery's `PodCard`. | Extracted to its own file rather than owned by any one card component — see file header. |
| `Theme.swift` (`KitLiteralColors`) | One-off decorative kit hues with no theme role (currently: the PodcastIndex icon blue, shared with the `.a2` artwork stop). | Named constant instead of a hand-copied hex literal per call site. |
| `Typography.swift` (`Typography.shelfTitle`/`shelfTitleStyle`) | `result-row.html`'s `.sh-title` (1.18rem/800/-0.015em, display face) — a type role direction.md §3's prose calls out ("shelf headers" use `--font-display`) but the table itself omitted. | Table gap filled in `docs/design/direction.md` §3 alongside this addition. |
| `IWantUrPod/Detail/PodcastDetailView.swift` + `PodcastDetailViewModel.swift` + `PodcastDetailScreen.swift` | The one adaptive Podcast Detail screen (navigation-map.md) — artwork/title/author/category header, `SubscribeButton`-driven subscribe control (E2-S2), the episode list newest-first with played markers / remaining-time hints (E2-S3 shell), and each row's Download/Downloading/Downloaded/Retry control (E4-S1, driven by `DownloadKit.DownloadManager`). | App-side composition (like `DiscoverViewModel`/`DiscoverView`); composed from tokens + `RemoteArtwork`/`ExpandableText`/`SubscribeButton`/`SecondaryButton`/`SectionHeader`/`EmptyStateView`/`LoadingSkeleton`, plus a plain `ProgressView` for in-flight download percent — no kit mock for the download affordance (composed-no-source, same precedent as the rest of this screen). |
