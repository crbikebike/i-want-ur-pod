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

**2026-07-06 kit reconciliation:** the design kit was regenerated on branch
`m1` and overlaid onto `main`. Several `screens/*.html` files were renamed
(the old Discover/search screens all gained a `search-` prefix; the Settings
screen dropped its Sources content) and eight new files were added (`home.html`,
`shows.html`, `up-next.html`, `search-start.html`, `search-results.html`, two
`podcast-detail-<slug>.html` real-data mocks, and a generated `prototype.html`),
alongside new non-UI tooling (`build-detail.py`, `build-prototype.py`,
`data/`, `art/`). See each section below for the current names and content.

When translating or auditing a kit file: identify its bespoke content first
(usually everything before the "SHARED KIT EXTRAS" comment marker), and treat
the shared block as decoration it also happens to consume — never as the
file's defining content.

## Foundations

| Path | Real content |
|---|---|
| `tokens.html` | Canonical CSS variable reference (colors, spacing, radii, motion, elevation) — copied verbatim into every other kit file's `:root`. |
| `styles.css` | 3-line root stylesheet (`@import "fonts/fonts.css"`). Not UI. |
| `fonts/*.css` (`fonts.css`, `ibm-plex-mono.css`, `roboto.css`) | `@font-face` declarations for IBM Plex Mono + Roboto. Not UI. |
| `fonts/IBMPlexMono-Regular.ttf` | The actual font binary `ibm-plex-mono.css` points at. Not UI. |

## Components (`design/kit/components/`)

| Path | Real bespoke content | Swift implementation | Status |
|---|---|---|---|
| `buttons.html` | Primary (filled) / Secondary (outline) / Tertiary (soft tint) pill buttons. | `Components/Buttons.swift` (`PrimaryButton`/`SecondaryButton`/`GhostButton` — `ghost` ⇔ kit's `.btn-tertiary`, documented in-code). | ✅ Implemented |
| `search-field.html` | The search input in default/focused/filled states. | `Components/SearchField.swift` | ✅ Implemented |
| `section-header.html` | The generic label band above a content group (title / title+subtitle / title+count). Explicitly notes a shelf uses its own header instead. | `Components/SectionHeader.swift` | ✅ Implemented |
| `sources-checklist.html` | **RETIRED, still present on disk.** Isolated Apple/PodcastIndex source-selection rows (toggle, Primary badge, lock + Add API key). v1 ships Apple-only — no source picker in the app — so this file is no longer live design intent, but it's kept in the kit and this entry stays registered because `Components/SourcesChecklistRow.swift` still cites it (see below); don't delete either side until that Swift file is retired too. | `Components/SourcesChecklistRow.swift` | ✅ Implemented (component itself unused by any current screen — its former consumer, `IWantUrPod/Settings/SourcesView.swift`, was deleted in the E8-S4 dock-IA pass; `AppSources` now seeds only `ITunesSource`, Apple-only, §12) |
| `subscribe-button.html` | Circular +/check control: default / subscribing (spinner) / subscribed, plus in-context on artwork. | `Components/SubscribeButton.swift` | ✅ Implemented |
| `tab-bar.html` | **Updated 2026-07-06.** Floating "Liquid Glass" bottom dock — now **four** items (Home · Shows · Up Next · Search, was five), plus a **search-takeover** variant (the dock's Search slot expands into the full-screen search flow rather than switching a tab). | `Components/LiquidGlassTabBar.swift` | ✅ Implemented — four-item `AppTab` (home/shows/upNext/search) + the search-takeover state (Home glyph pinned left, `--field`-styled text field, ✕ cancel), driven by bindings the app (`AppShell`) supplies. |
| `loading-skeleton.html` | Flat shimmering `.sk-row` placeholder list (art + 3 lines + trailing pill). **Dead pattern**: no current screen shows results as a flat list, so this has no consumer. | — | ❌ Not implemented / superseded by `screens/loading.html`'s shelf skeleton (see below). Do not build a flat-row skeleton against this file. |
| `no-results.html` | Isolated empty-state card: badge, "No shows found" title, message, actions. | `Components/EmptyStateView.swift` (`EmptyKind.noResults`) | ✅ Implemented |
| `result-card.html` | 2-up poster grid card: square gradient artwork + subscribe + title/author. | `Components/ResultCard.swift` | ✅ Implemented |
| `result-row.html` | **Category shelves** — horizontal scrolling rails of podcasts grouped by taxonomy ("Trending now", "True Crime", …), each with "View all" → expandable 2-up grid. **Not a flat row** despite the name — confirmed the kit's *only* current results pattern (verified against actual `<body>` usage across every screen, not just this file's `<style>`). | `Components/ResultShelf.swift` (`ResultShelf`, `PodCard`, `PodGrid`) | ✅ Implemented |

## Search takeover screens (`design/kit/screens/`, iPhone-framed)

**Renamed 2026-07-06** — these four used to live under a Discover tab
(`typing.html`, `loading.html`, `no-results.html`, `error.html`); the kit now
treats search as a full-screen **takeover** reached from the dock's Search
slot (see `tab-bar.html`'s new search-takeover variant, above), not a
standalone tab, hence the `search-` prefix.

| Path | Real bespoke content | Swift implementation | Status |
|---|---|---|---|
| `search-typing.html` (was `typing.html`) | Search field mid-typing + a typeahead **Suggestions** list (`.sug` rows: art + bold-matched name + publisher + chevron) over the browse shelves (`.under`). | `IWantUrPod/Search/SearchScreen.swift` (`.typing([SearchResult])` state) → `IWantUrPod/Search/SearchResultRow.swift` (`SearchResultRow` in a `GroupedList`, chevron trailing) over the `CuratedShelf` browse rails. | ✅ Implemented — live suggestions fetched by `DiscoverViewModel`'s debounce (before commit); tapping a row opens the show; the browse rails stay visible beneath. |
| `search-loading.html` (was `loading.html`) | "Searching for '…'" header over shimmering shelf/rail skeletons (`.sk-shelf`/`.sk-rail`/`.sk-pod`). | `Components/LoadingSkeleton.swift`, used by `IWantUrPod/Search/SearchScreen.swift` (`.loading` state) | ✅ Implemented |
| `search-noresults.html` (was `no-results.html`) | Full search-takeover screen (status bar, nav bar, search field with a query) wrapping the `.state` empty card. **2026-07-09:** added an "Add a direct link" primary action (→ `add-feed-url.html`) beside "Clear search", and reworded the sub to nudge it. | `IWantUrPod/Search/SearchScreen.swift` (`.noResults` state) | ✅ Implemented |
| `search-error.html` (was `error.html`) | Full search-takeover screen, `.state` card reading "Couldn't reach the directory" + Retry action. | `IWantUrPod/Search/SearchScreen.swift` (`.error` state) | ✅ Implemented |
| `search-start.html` | **New.** The takeover's rest state before typing starts — a `.sec-sub` hint over browse shelves/rails of `.pod` cards. | `IWantUrPod/Search/SearchScreen.swift` (`.firstRun` state) → `IWantUrPod/Search/CuratedShelf.swift` | ✅ Implemented — the field lives in `LiquidGlassTabBar`'s takeover; the content is the kit hint copy over `CuratedShelf`'s browse rails (the bundled curated picks grouped by category into `ResultShelf` rails — no trending API in v1). The earlier vertical-editorial-card treatment was dropped for the kit's shelf/rail pattern. **2026-07-09:** gained a quiet `.urlcta` "Have a podcast URL? Add it directly →" row under the shelves → opens `add-feed-url.html`. |
| `search-results.html` | **New.** Results layout: a featured "top result" (the strongest match, called out distinctly) above a flat "More shows" list, each row offering inline Subscribe. **Note:** despite the shared-block `.shelf`/`.rail` CSS, this screen's real `<body>` is a `.topresult` hero + a single grouped-inset `.list`, NOT category shelves. | `IWantUrPod/Search/SearchScreen.swift` (`.results` state) → `IWantUrPod/Search/TopResultCard.swift` (hero) + `IWantUrPod/Search/SearchResultRow.swift` (`GroupedList` of `.reslist` rows, circular Subscribe). | ✅ Implemented — top result featured as `TopResultCard`; remaining matches in a flat `More shows` list. The prior category-shelf `ShelvesList` path was retired (Apple-only genre data collapsed it to a single degenerate rail). |
| `add-feed-url.html` | **New (2026-07-09, Phase 1).** The shared **"Add a feed by URL"** bottom sheet — the single destination behind both direct-link entry points (Search's "Have a podcast URL?" affordance on `search-start.html`/`search-noresults.html`, and Settings' "Add premium or custom podcast URL" row). One presented sheet, four states driven by `data-state` on `.afu-sheet`: **ready** (URL field + Paste + neutral hint + full-width Add), **loading** (spinner + "Checking…"), **error** (the expiring-private-link message — the premium/tokenized-feed failure case), **success** (check badge → dismisses to Podcast Detail, subscribed). Token-bearing premium URLs (Supporting Cast / Patreon / Supercast) are stored like any feed URL — **no lock UI**, only a privacy footnote. `afu-`-prefixed classes, built only on locked tokens. A top-left state switcher is an authoring aid, not part of the UI. | `IWantUrPod/Search/AddFeedSheet.swift` + `AddFeedByURLViewModel.swift` (validate → fetch via `FeedFetching` → `FeedUpsert` → set `isSubscribed`), presented from the Search screen(s) and `SettingsScreen.swift`; success pushes `feedURL` into the existing `.navigationDestination(for: URL.self)`. | ❌ **Kit only — Swift is Phase 2 (Mac build).** No `FeedFetcher`/`FeedUpsert`/model changes needed. |
| `first-run.html` | **A multi-step guided onboarding wizard**: "Do you already listen to podcasts?" (app picker → OPML import walkthrough, or "starting fresh") → favorite-shows picker → topic picker → personalized category-shelf recommendations → "Start listening". Has a progress bar and back/skip navigation. **Not a static empty state.** Unchanged by the 2026-07-06 rename. | — | ❌ Not implemented. `SearchScreen.swift`'s `.firstRun` state renders a placeholder `EmptyStateView(kind: .firstRun, …)` instead — explicitly documented as a placeholder in `EmptyStateView.swift`, not a translation of this file. Building the real wizard is a separate, tracked feature. |

## Home / Shows / Up Next screens (`design/kit/screens/`, iPhone-framed) — new 2026-07-06

Three new top-level dock destinations (Home replaces Discover as the default
landing tab; Shows and Up Next get their own top-level mocks for the first
time, superseding the composed-no-kit-mock Podcasts/Up Next entries further
below).

| Path | Real bespoke content | Swift implementation | Status |
|---|---|---|---|
| `home.html` | The Home landing feed: status bar + top-right Settings gear (pushed, not a tab), then a scrolling stack of — **redesigned 2026-07-08** — an "Up Next" **horizontal square-tile slider** (`.pn` tiles ~112px with an overlaid circular play button + title/"·NN min left" label; playable from the tile; keeps "See all"), a "New episodes" **tall-card horizontal carousel** (`.ep-card` ~200px: big artwork, an arc/season `.tag` chip, display-font episode title, podcast name, publish date, and a corner play button; keeps "See all"), and a single "Our favorites" editorial `.shelf`/`.rail`/`.pod` (placeholder). The former "Shows for you" recommendation shelf was **removed** (merged into "Our favorites"). Reuses only existing tokens — the redesign added **no new CSS custom properties**. | `IWantUrPod/Home/HomeScreen.swift` | ⚠️ **Kit ahead of Swift (2026-07-08).** `HomeScreen.swift` still renders the pre-redesign layout (vertical `.list`/`.row` Up Next + New episodes via `GroupedRowList`, plus both a "Shows for you" and an "Our favorites" shelf). Reconciling it to this redesigned mock — Up Next tile slider, New-episodes tall-card carousel, and removing `showsForYouSection` (and, if it becomes unused, `HomeFeedProvider.recommendedEntries`) — is a **tracked follow-up**, deferred because SwiftUI can't be compiled/verified on Linux. Original E8-S2 note retained: Home is the dock's default/first destination; the first-run explainer gate (E1-S1) lives here. |
| `shows.html` | The subscribed-shows screen: status bar + Settings gear, a grid/list of shows the person has subscribed to, with room reserved below for recommendations (placeholder). Supersedes the composed `PodcastsScreen.swift` entry's plain vertical list (see "Podcasts tab (E3-S1)" below) — kit now specifies a grid. | `IWantUrPod/Library/PodcastsScreen.swift` | ⚠️ Tab label + large title now read "Shows" (E8-S3) and the top-right Settings gear was added (E8-S4), but the list is still a plain vertical list per the E3-S1 composed-no-kit-mock precedent — not yet reconciled to this kit mock's grid layout. |
| `up-next.html` | The queue screen: status bar + Settings gear, each row with two trailing controls in a `.controls` group — a **`.play` button** (40px accent→accent2 gradient, `play.fill` triangle, matching Home's `.pn-play`) beside the inline `.dl` **download** state control (downloaded / not-downloaded treatments) — over the dock. **Updated 2026-07-09:** added the per-row play button and a **swipe-left-to-remove** affordance (row slides to uncover a full-height destructive `.row-remove` action on the trailing edge, using the new `--danger` token; the mock shows one row `.open` in its revealed state). Play + swipe replace nothing existing — download stays; the old long-press remove menu becomes a secondary path. | `IWantUrPod/UpNext/UpNextScreen.swift` | ⚠️ **Kit ahead of Swift (2026-07-09).** Play button + swipe-to-remove speced here; Swift reconcile is the active task. Prior: E8-S5 added the inline per-row `DownloadState` icon/action (reusing `PodcastDetailView`'s `EpisodeIconButton`); E8-S4 added the top-right Settings gear. |

## Explore by theme — swipe deck (`design/kit/screens/explore-*.html`) — new 2026-07-23

A **guided, two-tier discovery flow** for finding shows by editorial theme, entered from a
hero card on Home. The two tiers use **different gestures on purpose**: Tier 1 is a
**vertical feed** — you swipe up/down to browse the 30 curated **theme-arcs**
(`curation/catalog/themes.json`), each a full-screen card that also previews the shows
inside it, so nothing is a blind yes/no. Tapping **Dive in** opens Tier 2, a **horizontal
swipe deck** of that theme's shows (`curation/catalog/catalog.json`) where right = subscribe
(via the app's existing subscribe path), left = skip. Real theme/show data (names, counts,
`why` lines, sample cover art) is inlined from the offline catalog. The three files are wired
into a clickable funnel: hero card → `explore-themes.html` → (dive in)
`explore-theme-shows.html?theme=<slug>` → (back) themes.

**Why the split gesture:** an early version made Tier 1 a Tinder-style yes/no swipe too;
that failed the "how do I know what else is there / I don't want to skip something I'd want"
test — 30 themes is a small, finite menu you want to *survey*, not judge blind one at a time.
So themes became a browsable vertical feed with show-art peeks; the addictive swipe is
reserved for the shows tier, where the pool is large and low-stakes.

**Bespoke, not the SHARED KIT EXTRAS block** — these files carry only the token `:root`
verbatim plus their own deck CSS; they do **not** include the shared `.pod`/`.shelf`/`.sk-row`
authoring block. The deck card, stamps, and action dock are the real content.

| Path | Real bespoke content | Swift implementation | Status |
|---|---|---|---|
| `components/explore-hero-card.html` | The **Home entry point**: a full-width gradient hero card ("Explore by theme" / "Flip through 30 story-worlds", `315 shows`·`30 themes` pills, a tilted mini-deck motif, trailing arrow) shown between "New episodes" and "Our favorites". Tapping opens the theme deck. Rendered here in a Home-scroll context slice. | `IWantUrPod/Explore/ExploreThemeHeroCard.swift` (the card itself + the `ExploreRoute` route enum), wired into `IWantUrPod/Home/HomeScreen.swift`'s `exploreThemeSection` + `.navigationDestination(for: ExploreRoute.self)` | ⚠️ **Swift authored (Phase C, 2026-07-23) — not yet compiled/verified (no Swift toolchain on the authoring machine; Mac build pending).** |
| `screens/explore-themes.html` | **Tier 1 — vertical theme feed.** Full-screen, scroll-snapped theme cards (`scroll-snap-type: y mandatory`) browsed by **swiping up/down** — no yes/no. Overlay chrome: back button, "Explore by theme" eyebrow, `n/30` progress pill, a right-edge scroll-dot rail, and a floating "Swipe up" cue that fades after the first scroll. Each card is a per-theme gradient wash + giant watermark emoji, a "Theme N of 30" kicker, display-font `name`, one-line hook, an **"Inside this theme"** row of ~5 show-cover thumbnails (real `art/<slug>.jpg` where available, else initial-on-gradient tiles) + a `+N` more chip, and a full-width **"Dive in — swipe the shows →"** button that opens Tier 2. Tapping the **`n/30` progress pill** opens a **"Jump to a theme"** bottom sheet — a condensed, quick-scroll list of all 30 themes (emoji tile + name + show count, current theme highlighted) to jump straight to any theme instead of scrolling the whole feed. | `IWantUrPod/Explore/ThemeFeedScreen.swift` — a native vertical paging view (`ScrollView` + `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`, iOS 17+), NOT the `SwipeDeck` (that's Tier 2 only); thumbnails reuse `RemoteArtwork` over `CatalogLoader.shows(inTheme:)` | ⚠️ **Swift authored (Phase C, 2026-07-23) — not yet compiled/verified.** Right-edge scroll-dot rail and the fading "Swipe up" cue's exact kit choreography were simplified (a plain fade-out, no dot rail) — flagged as a deliberate scope trim, not an oversight. |
| `screens/explore-theme-shows.html` | **Tier 2 — show deck (per theme).** Same deck shell; header shows the theme name + `n/<showCount>`. Each show card fills with artwork (real `art/<slug>.jpg` when available, else an `.a1–.a6` gradient fallback with an initial glyph — mirrors `RemoteArtwork`), a theme badge, and a bottom scrim carrying display-font `title`, `author`, and the editorial `why` (quote rule). Swipe stamps: "Subscribed ✓" (mint, right) / "Skip" (danger, left). Right-swipe subscribes; end-of-deck tallies "＋ N added to your Shows" and offers "Back to themes". Reads `?theme=<slug>`; already-subscribed shows would be filtered out in the app. **Tap (vs swipe) a card → a detail "toast" bottom sheet that renders the full Podcast Detail screen** (header art/title/author/category·years chips, Subscribe, description, **all** story arcs as `.sh-arc` cards with season badge + parts + "Add all", then the Episodes list with arc-filter chips and per-row download/add/play controls) — literally `PodcastDetailScreen` presented as a sheet rather than pushed; in the app the arcs + episode list come **live from the show's feed on open** (all arcs via the `EpisodeArcs` detector). Drag-down / backdrop-tap dismisses back to the same card. **Subscribing from the sheet dismisses the card behind it** (flies off, advances the deck) so the next card is waiting when the sheet closes — the sheet then shows "Subscribed ✓" + "Back to swiping →". | `Packages/DesignSystem/Sources/DesignSystem/Components/SwipeDeck.swift` (the reusable generic deck) + `IWantUrPod/Explore/ThemeShowDeckScreen.swift`; reuses `RemoteArtwork`, `PodcastDetailScreen` (presented as a `.sheet`, not rebuilt) + the existing `persist(_:)` subscribe path | ⚠️ **Swift authored (Phase C, 2026-07-23) — not yet compiled/verified.** "Subscribing from the sheet" is detected by watching the live `@Query`'s subscribed-`feedURL` set change while the sheet is open (rather than a bespoke sheet-local subscribe control, since the sheet is the real, unmodified `PodcastDetailScreen`); the sheet itself keeps that screen's own chrome (a "Close" toolbar button + system sheet drag) rather than the kit's bespoke drag-handle/"Back to swiping" sheet footer. |

## Settings screen (`design/kit/screens/settings.html`)

**Replaces `settings-sources.html` (removed 2026-07-06).** v1 ships **Apple-only**
search — PodcastIndex and the source picker are deferred — so Settings no longer
hosts a Sources section at all.

| Path | Real bespoke content | Swift implementation | Status |
|---|---|---|---|
| `settings.html` | A **pushed** screen (reached via the top-right gear on Home/Shows/Up Next — not a tab, and not itself in the dock), whose only section is **"Manage downloaded episodes"**: a list of local downloads, each row with a Remove control that deletes the local audio file while leaving the episode in its feed (not un-subscribing or hiding it). Has its own "Done" affordance back to the tab the gear was tapped from. **2026-07-09:** gained a **"Feeds"** section above Downloaded episodes — one `.srow` "Add premium or custom podcast URL" (reusing the retired-but-present `.srclist`/`.srow`/`.src-ico` vocabulary) → opens `add-feed-url.html`. **2026-07-09 (later):** gained a **"History"** section — one `.srow` "Listening history" (`.ic-history` icon tile, `.srow-history` class) → opens `listening-history.html`. | `IWantUrPod/Settings/SettingsScreen.swift` | ✅ Implemented (E8-S4) — `SourcesView.swift` was deleted; `SettingsScreen` lists every `Episode` with `downloadState == .downloaded`, each row removable via the new `DownloadManager.remove(_:context:)` seam. **Deviation:** a minimal "Show first-run intro again" footer row is kept below the one section (not literally "exactly one section") because E1-S1/`FirstRunGateTests` require Settings to re-open the first-run explainer — see the CAVEAT note in `SettingsScreen.swift`'s header comment. **The "History" section (`historySection`) is now implemented too — pushes `ListeningHistoryScreen` via `.navigationDestination(isPresented:)`.** |
| `listening-history.html` | A **pushed** screen reached from Settings' "History" row (Done returns to Settings, same push pattern as `settings.html` itself). Content: a large title + lede, then a reverse-chronological grouped-inset list of played episodes, grouped by day (`.lh-daygroup`/`.lh-daylabel`: "Today" / "Yesterday" / "3 days ago" / "Last week"). Each `.lh-row` is an artwork tile + episode title + podcast subtitle, with a trailing stack showing a relative "when" label ("Today"/"Yesterday"/"3d ago") over a listened-duration label ("24 min listened"). Episodes played more than once (Song Exploder's "Cold Open, Warm Ending" appears twice, 3 days apart) get a small mint **"Played 2×"** chip under the title, derived from the count of log entries for that episode. Two states via `data-state` on `#lhScreen`: **populated** (the log) and **empty** (a `.state`-style block — badge, "No listening history yet", a short sub, and a "Browse your shows" secondary action), toggled here only by the top-left state switcher (an authoring aid, not part of the UI, same convention as `add-feed-url.html`). `lh-`-prefixed classes; locked tokens only; dark + light both correct. | `IWantUrPod/History/ListeningHistoryScreen.swift` + `IWantUrPod/History/ListeningHistoryProvider.swift` | ✅ Implemented — `@Query(sort: \PlayEvent.playedAt, order: .reverse)`, grouped by day and play-count-derived in plain Swift (`ListeningHistoryProvider`, never a `#Predicate`). Row tap pushes `PodcastDetailScreen` via this screen's own `.navigationDestination(for: URL.self)` when `feedURL != nil`. New exact-value tokens added for kit values with no existing match: `Typography.playCountLabelStyle` (`.lh-playcount`, 0.64rem/800/0.03em, not uppercased), `Typography.footNoteLabelStyle` (shared `.foot-note`, 0.78rem/500), `Typography.lhWhenLabelStyle` (`.lh-when`, 0.78rem/700), `Typography.lhDurationLabelStyle` (`.lh-dur`, 0.74rem/500) — see each token's doc comment in `Typography.swift`. Empty state's "Browse your shows" is `NeutralButton` (kit's `.btn-secondary` chip fill) calling `dismiss()` (this screen has no direct route to the Shows tab). |

## Podcast Detail (E2) — composed, no kit mock (historical); kit mocks now exist

**Update 2026-07-06: this is no longer true as originally written.** The kit
now ships two real, data-driven Podcast Detail mocks —
`screens/podcast-detail-american-history-tellers.html` and
`screens/podcast-detail-explorers-podcast.html` (see the new section just
below) — and reconciling `PodcastDetailView.swift` toward them (compact icon
controls, arc/season episode metadata, a Story-arcs shelf) is in progress on
this branch (`kit-reconcile`). The paragraph and table below describe the
screen's **original, pre-kit-mock composed history**; they're kept for
context, not overwritten, since most of the files they document (`RemoteArtwork`,
`ExpandableText`, `HTMLText`) remain accurate and un-superseded. Once the
reconciliation lands, this section should gain a `Swift implementation`
pointer to the new kit files the same way other sections do.

There was no `design/kit/screens/podcast-detail.html` at the time — ROADMAP.md E2
explicitly said to compose this screen from `docs/design/direction.md` tokens +
existing components rather than wait on a kit mock. Every new file below carries a
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

## Podcast Detail kit mocks (`design/kit/screens/podcast-detail-*.html`) — new 2026-07-06

Two real-data-driven Podcast Detail mocks, generated by `build-detail.py` (see
"Non-UI tooling & assets" below) from `data/<slug>.json`. Both share layout:
header (art, title, author, category, Subscribe, clamped description), a
horizontal **Story arcs** shelf (each card: season badge when the feed has one,
arc name, episode count, an "Add all" control to queue the whole arc), then the
episode list with **compact icon controls** (download / play / add-to-Up-Next
— replacing the oversized buttons + redundant "Downloaded" text the current
`PodcastDetailView.swift` uses) and each row showing `arc · S·E · date ·
duration` (or `arc · Part N · date · duration` when there's no season number).

| Path | Real bespoke content | Swift implementation | Status |
|---|---|---|---|
| `podcast-detail-american-history-tellers.html` | Real episode/arc data from `data/american-history-tellers.json`. This feed sets `<itunes:season>`, so arcs render **with season badges** and `S·E` in each row. | `IWantUrPod/Detail/PodcastDetailView.swift` (reconciliation in progress, this branch) | ⚠️ In progress — current `PodcastDetailView.swift` predates this mock; compact icon controls and the Story-arcs shelf are not yet built. |
| `podcast-detail-explorers-podcast.html` | Real episode/arc data from `data/explorers-podcast.json`. This feed has **no** `<itunes:season>`, so it's the graceful-degrade case: arcs render as `arc · Part N` with no season badge, falling back to date · duration only for singles. | `IWantUrPod/Detail/PodcastDetailView.swift` (reconciliation in progress, this branch) | ⚠️ In progress — same as above; also needs `FeedParser`/`Episode` to gain `season`/`episodeNumber`/derived-arc fields (see `docs/design/direction.md` §11 Swift follow-ups). |

## Prototype & non-UI tooling/assets — new 2026-07-06

| Path | Real content | Notes |
|---|---|---|
| `screens/prototype.html` | A **generated**, self-contained clickable prototype stitching every screen together (each screen isolated in an `<iframe srcdoc>`, plus a small parent controller wiring dock navigation, the Settings gear, the search takeover, and an edge-state jump control). | **Not a design source to translate** — it's an artifact of the other screens, regenerated by `build-prototype.py` whenever a screen changes. No Swift citation should ever point at this file. |
| `build-detail.py` | Generator script: reads `data/<slug>.json` and emits `screens/podcast-detail-<slug>.html`. | Tooling, not UI. Not a translation target. |
| `build-prototype.py` | Generator script: stitches all current screens into `screens/prototype.html`. | Tooling, not UI. Not a translation target. |
| `data/README.md` | Explains the `data/<slug>.json` schema (`show`, `episodes[]`, `arcs[]`, `counts`) and how story arcs are derived from RSS episode-title structure (`scripts/fetch-podcast-episodes.py`), plus how `<itunes:season>` is optional and drives the season-badge / graceful-degrade split. | Docs, not UI. |
| `data/american-history-tellers.json`, `data/explorers-podcast.json` | Real per-show episode + derived-arc fixtures backing the two `podcast-detail-*.html` mocks above (and, eventually, `FeedParser`/`Episode` test fixtures for the same season/arc fields). | Data, not UI. Not a translation target — a data source for the detail screens. |
| `art/README.md` | Explains the `art/<slug>.jpg` cover-art cache and `art/podcasts.json` metadata (title/author/feedUrl/artworkUrl/genre), and how to regenerate via `scripts/fetch-podcast-art.py`. | Docs, not UI. |
| `art/podcasts.json` | Directory metadata (one entry per slug) backing real names/authors/feeds/artwork used across the newer mocks (home/shows/detail screens) instead of invented fixtures. | Data, not UI. |
| `art/*.jpg` — `20k-hertz.jpg`, `99pi.jpg`, `acquired.jpg`, `american-history-tellers.jpg`, `behind-the-bastards.jpg`, `bone-valley.jpg`, `crime-junkie.jpg`, `dead-to-me.jpg`, `empire.jpg`, `explorers-podcast.jpg`, `ezra-klein.jpg`, `fall-of-civilizations.jpg`, `hardcore-history.jpg`, `radiolab.jpg`, `rest-is-history.jpg`, `revolutions.jpg`, `search-engine.jpg`, `serial.jpg`, `song-exploder.jpg`, `the-ancients.jpg`, `the-daily.jpg`, `theory-of-everything.jpg` | 300×300 real podcast cover art, Apple-sourced, used by the newer mocks for realistic artwork instead of gradient placeholders. | Assets, not UI markup. Not a translation target — same role as remote artwork URLs the app already fetches via `RemoteArtwork`. |

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
| `IWantUrPod/Home/FirstRunExplainerView.swift` | A small, once-only intro screen (badge, headline, one-paragraph pitch, "Get started") presented as a `fullScreenCover` on `HomeScreen` (moved from the retired Discover tab, E8-S1), gated by `FirstRunGate`. Deliberately lightweight — not the kit's unbuilt multi-step wizard. | ✅ Implemented |
| `IWantUrPod/Home/FirstRunGate.swift` | A `UserDefaults`-backed flag (`hasSeenFirstRun` / `markSeen()` / `reset()`) gating the explainer. Not a UI component — no kit citation needed; listed here for completeness since it's new in E1. | ✅ Implemented |
| `IWantUrPod/Search/CuratedShelf.swift` | Renders the bundled `curated-start-here.json` picks (`DirectoryKit.CuratedEntry`, decoded by `CuratedListLoader`) as the kit's **browse shelf/rails** (search-start.html): grouped by `category` into one `ResultShelf` rail per taxonomy (uncategorised → "Popular now"), in file order. Backs both the `.firstRun` rest state and the browse area beneath `.typing` suggestions. Per-item `SubscribeButton` state lives here; tap a pod → E2 detail by `feedUrl`. **History:** superseded the earlier vertical-editorial-card treatment (with `blurb`) when search was reconciled to the kit's shelf/rail pattern. | ✅ Implemented |

## Podcasts tab (E3-S1) — composed, no kit mock (historical); superseded by `shows.html`

**Update 2026-07-06:** this is no longer literally true — see `shows.html` in
"Home / Shows / Up Next screens" above, which now specifies this tab (renamed
"Shows" in the kit) as a grid, not a vertical list. The paragraph and table
below describe the screen's original composed history and remain accurate for
what's actually built today; `PodcastsScreen.swift` has not yet been
reconciled to `shows.html`'s grid layout.

At the time, there was no `design/kit/screens/podcasts.html` or list-row mock —
the kit's only flat-row pattern (`components/loading-skeleton.html`'s
`.sk-row`) is called out above as a dead pattern with no consumer, and
`result-row.html`'s real content is the horizontal category-shelf gallery,
not a vertical list. Per the same precedent as Podcast Detail (E2), both
files below carry a `// Composed from docs/design/direction.md tokens — no
design/kit source (see design/kit/MANIFEST.md).` header instead of a
`design/kit/*.html` citation.

| Swift file | Real bespoke content | Status |
|---|---|---|
| `IWantUrPod/Library/PodcastsScreen.swift` | The Podcasts tab: a vertical list of subscribed shows, newest `dateAdded` first, each row a `RemoteArtwork` tile + title/author (mirrors `PodcastDetailView.swift`'s `EpisodeRow` shape, scaled down) that pushes its `feedURL` into the shared E2 detail screen. Empty state via `EmptyStateView(kind: .firstRun, …)`. Owns its own `NavigationStack` and reserves `AppShell.tabBarReservedPadding`. | ✅ Implemented |
| `IWantUrPod/Library/PodcastsListProvider.swift` | The testable seam behind the list: fetches every `Podcast` from a `ModelContext` (or takes an already-fetched `[Podcast]`, for the live `@Query` case) and filters/sorts in plain Swift — avoiding the non-Sendable `KeyPath` warning a `#Predicate { $0.isSubscribed }` triggers under this project's strict concurrency setting (same precedent as `PodcastDetailViewModelTests.swift`). Not a UI component — no kit citation needed; listed here for completeness since it's new in E3. | ✅ Implemented |

## Up Next tab (E5) — now reconciled to `up-next.html`

**Update 2026-07-08:** `UpNextScreen.swift` has been rebuilt to match
`design/kit/screens/up-next.html` exactly (see "Home / Shows / Up Next
screens" above) — the historical "composed, no kit mock" note below is
retained for provenance only. The screen no longer uses a `List`: matching
the kit's grouped-inset surface card (with `.grip` handle + `elev-list`
shadow) required a hand-built card, so reorder is a grip-drag gesture and
remove is a row context menu (the order rules are unchanged — see
`docs/spec/queue-semantics.md`'s "UI mechanism" notes).

_Historical:_ At first there was no `design/kit/screens/up-next.html` — same
precedent as Podcast Detail (E2) and the Podcasts tab (E3): compose from
`docs/design/direction.md` tokens + existing components, using a real `List`
for native `.onMove`/`.swipeActions`. That precedent no longer applies now
that the kit screen exists and the screen cites it.

| Swift file | Real bespoke content | Status |
|---|---|---|
| `IWantUrPod/UpNext/UpNextScreen.swift` | The Up Next tab, translated from `up-next.html`: pulse-dot large title + Settings gear, a "Queue" `SectionHeader` (count pill + `.sec-sub`), and a grouped-inset surface card (`palette.surface` / `rLg20` / `.elevList`) of rows — each a `.grip` 2×3 dot handle, 60pt `RemoteArtwork`, title + "Show · time" subtitle (`HomeFeedProvider.durationLabel`), and a 40pt `EpisodeIconButton` download control — plus the centered `.foot` note. Reorder = hand-rolled grip-drag → `QueueStore.move(fromOffsets:toOffset:)`; remove = row context menu → `QueueStore.remove(_:)`. Empty state via `EmptyStateView(kind: .firstRun, …)`. Owns its own `NavigationStack` and reserves `AppShell.tabBarReservedPadding`. **Follow-up 2026-07-09 (in progress):** add the `PlayButton` (→ `PlaybackIntentCoordinator.play`) beside the download control, and a swipe-left-to-remove gesture (→ `QueueStore.remove(_:)`) that coexists with the grip's vertical drag, per the updated `up-next.html`. | ⚠️ Kit ahead — play + swipe in progress |
| `IWantUrPod/UpNext/QueueStore.swift` | The app-scoped `@Observable` queue service (E5-S1/S2/S3): add-to-tail with re-add no-op, contiguous-order reorder/remove, and orphan pruning (docs/spec/queue-semantics.md's four invariants). Not a UI component — no kit citation needed; listed for completeness since it's new in E5. Created once in `IWantUrPodApp`, injected via `.environment` (`AppQueue.swift`), same pattern as `DownloadManager`/`PlaybackEngine`. | ✅ Implemented |
| `IWantUrPod/UpNext/QueueAutoAdvanceCoordinator.swift` | Couples `PlaybackEngine.onFinished` to `QueueStore` for E5-S3 auto-advance, kept out of `PlaybackKit` itself so that package stays decoupled from `QueueItem`/`QueueStore`. Not a UI component — no kit citation needed. | ✅ Implemented |
| `IWantUrPod/Detail/PodcastDetailView.swift` (`EpisodeRow.queueControl`) | The "Add to Up Next" control (E5-S1) added to the existing episode row: a `GhostButton` calling `QueueStore.add(episode)` when not yet queued, or an "In Up Next" checkmark label when it is. Composed from tokens, no kit mock (same precedent as the row's existing download/play controls). | ✅ Implemented |

## Now Playing (E6) — mostly composed; seek control now has a kit mock

There is no `design/kit/screens/now-playing.html` or mini-player-container
mock — navigation-map.md's "Persistent chrome placement" specifies the
mini-player's *placement* (shell chrome, above the tab bar) and the Now
Playing sheet's *content* (large artwork, details, transport) but no kit file
backs either container. Same precedent as Podcast Detail (E2)/Podcasts
(E3)/Up Next (E5): compose from `docs/design/direction.md` tokens + existing
components. Every new file below still carries a `// Composed from
docs/design/direction.md tokens — no design/kit source (see
design/kit/MANIFEST.md).` header instead of a `design/kit/*.html` citation,
**except** the rewind/skip-ahead transport control itself, which is now a
proper `DesignSystem` component backed by a kit mock (see below) — the two
containers (mini-player bar, Now Playing sheet) that host it remain
composed-no-mock.

| Swift file | Real bespoke content | Status |
|---|---|---|
| `IWantUrPod/NowPlaying/MiniPlayer.swift` | E6-S1's persistent bar: `RemoteArtwork` thumb + title/show + a trailing play/pause control, drawn as translucent glass (mirrors `LiquidGlassTabBar`'s material/hairline/shadow treatment so the two chrome pieces read as one system) directly above the tab bar. Reads the app-scoped `PlaybackEngine` from the environment; visible iff `PlaybackTransport.isMiniPlayerPresented(for:)`. Tapping the row presents the Now Playing sheet; tapping the trailing control toggles play/pause without presenting it. | ✅ Implemented |
| `IWantUrPod/NowPlaying/NowPlayingSheet.swift` | E6-S2's full view, presented as a `.sheet` from `AppShell`: large `RemoteArtwork`, episode/show title, a `Slider` scrubber (seeks via `PlaybackEngine.seek(toFraction:)` on release, persisting `Episode.playbackProgress`), and skip-back-15/play-pause/skip-forward-30 transport. Reads the same injected `PlaybackEngine`; dismissing returns to the mini-player with state intact since this view owns no playback state itself. | ✅ Implemented |
| `Packages/DesignSystem/Sources/DesignSystem/Components/SeekButton.swift` | The icon-only rewind/skip-ahead transport control (`SeekButton(direction:seconds:diameter:accessibilityLabel:action:)`), translated from `design/kit/components/seek-button.html`'s `.seek-btn`: an SF Symbol curved arrow (`gobackward`/`goforward`) with the seconds numeral (from `PlaybackKit`'s `SkipInterval`) overlaid as data-driven text so one component serves both the 15s rewind and 30s skip-ahead at both the mini-player's ~30pt size and the Now Playing sheet's ~44pt size. Not yet wired into `MiniPlayer.swift`/`NowPlayingSheet.swift` — component only. | ✅ Implemented |
| `IWantUrPod/NowPlaying/PlaybackTransport.swift` | The testable seam behind both views: `isMiniPlayerPresented(for state:)` (mini-player visibility), `playPauseAction(for state:)`, and `playPauseSymbolName(for state:)` — pure `PlaybackState` → behavior mappings, exercised directly by `IWantUrPodTests/NowPlayingTests.swift` without needing a live engine. Not a UI component — no kit citation needed; listed for completeness since it's new in E6. | ✅ Implemented |
| `IWantUrPod/App/AppShell.swift` (`miniPlayerHeight`/`miniPlayerReservedPadding`, mini-player + `.sheet` wiring) | The frozen-nav-contract-preserving integration: `AppShell` draws `MiniPlayer` as shell chrome above `LiquidGlassTabBar` (never inside a tab's content), applies the combined bottom reserve to `content`'s own frame when the mini-player is visible (so every screen's existing 104pt internal reserve still clears both the bar and the mini-player, with no screen needing to change), and presents `NowPlayingSheet` via `.sheet(isPresented:)` when the mini-player is tapped. | ✅ Implemented |

## Shared Swift-side infrastructure (no single kit file; cross-cutting)

| Swift file | Source | Notes |
|---|---|---|
| `IWantUrPod/Search/SearchResultRow.swift` | The compact `.sug` search row (40pt art + optional bold-matched name + publisher + a caller-supplied trailing slot) and the `.list` grouped-inset surface container (`GroupedList`, 64pt-inset separators). Shared by the `.typing` Suggestions list (chevron trailing) and the `.results` "More shows" list (circular `SubscribeButton` trailing). Translates `search-typing.html`/`search-results.html`'s row + list. | App-side composition. |
| `IWantUrPod/Search/TopResultCard.swift` | The `search-results.html` `.topresult` hero — the strongest match featured above "More shows": 76pt `RemoteArtwork`, title/author, and a full pill Subscribe (idle/subscribing/subscribed). | App-side composition. |
| ~~`IWantUrPod/Search/ShelvesList.swift`~~ | **Deleted.** Grouped `.results` by `category` into `ResultShelf` rails — retired when the results screen was rebuilt to the kit's top-result hero + flat "More shows" list (`search-results.html`'s real layout), which needs no category grouping (and avoided the Apple-only single-genre collapse). `ResultShelf`/`PodCard`/`PodGrid` remain, now consumed by `CuratedShelf`'s browse rails. | — |
| `Components/ArtworkTile.swift` (`ArtworkStyle`/`GradientArtwork`/`ArtworkTile`) | The `.a1`–`.a6` gradient tile classes, shared across the result-card poster grid and the shelf gallery's `PodCard`. | Extracted to its own file rather than owned by any one card component — see file header. |
| `Theme.swift` (`KitLiteralColors`) | One-off decorative kit hues with no theme role (currently: the PodcastIndex icon blue, shared with the `.a2` artwork stop). | Named constant instead of a hand-copied hex literal per call site. |
| `Typography.swift` (`Typography.shelfTitle`/`shelfTitleStyle`) | `result-row.html`'s `.sh-title` (1.18rem/800/-0.015em, display face) — a type role direction.md §3's prose calls out ("shelf headers" use `--font-display`) but the table itself omitted. | Table gap filled in `docs/design/direction.md` §3 alongside this addition. |
| `IWantUrPod/Detail/PodcastDetailView.swift` + `PodcastDetailViewModel.swift` + `PodcastDetailScreen.swift` | The one adaptive Podcast Detail screen (navigation-map.md) — artwork/title/author/category header, `SubscribeButton`-driven subscribe control (E2-S2), the episode list newest-first with played markers / remaining-time hints (E2-S3 shell), and each row's Download/Downloading/Downloaded/Retry control (E4-S1, driven by `DownloadKit.DownloadManager`). | App-side composition (like `DiscoverViewModel`/`DiscoverView`); composed from tokens + `RemoteArtwork`/`ExpandableText`/`SubscribeButton`/`SecondaryButton`/`SectionHeader`/`EmptyStateView`/`LoadingSkeleton`, plus a plain `ProgressView` for in-flight download percent — no kit mock for the download affordance (composed-no-source, same precedent as the rest of this screen). |
