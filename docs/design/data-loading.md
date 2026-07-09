# Convention — sorting, caching, and lazy loading

Audience: any agent (or human) adding or touching a screen's data layer. This
is the referenceable convention for the three concerns every list-bearing
screen has to answer: what order it shows data in, how it avoids re-fetching,
and when it must defer offscreen row cost. Cite this doc by path
(`docs/design/data-loading.md`) rather than re-deriving these rules per PR.

## The four principles

### 1. Store-first render

A screen with an injected `ModelContext`/`@Query` reads **persisted SwiftData
first** and renders immediately from it. Network fetch/refresh runs in the
background and must **never** block a screen that already has cached data.
A failed background refresh is swallowed — the cached render stands; do not
surface an error over live data.

Canonical example: `PodcastDetailViewModel.load()`
(`IWantUrPod/Detail/PodcastDetailViewModel.swift`) — looks up the `Podcast` by
`feedURL`, and if a stored row already has episodes, sets `state = .loaded`
from it immediately, *then* fetches/upserts in the background inside its own
`do/catch` that discards failures. Only a genuinely empty store (nothing
cached yet) puts the fetch on the critical path.

New screens with a store-backed model should follow the same shape: resolve
from the store synchronously, show it, then refresh async and best-effort.

### 2. HTTP cache

`URLCache.shared` is configured once, at app launch, in
`IWantUrPodApp.init()` (`IWantUrPod/App/IWantUrPodApp.swift`) — 50 MB memory /
500 MB disk. Every read-path remote load goes through it:

- Artwork — `RemoteArtwork` (`Packages/DesignSystem/.../RemoteArtwork.swift`)
  uses plain `AsyncImage(url:)`, which reads `URLSession.shared`, which reads
  `URLCache.shared`.
- Feeds — `FeedFetcher(URLSession.shared)`, same story.

This means artwork and feed bodies persist across launches and aren't
re-downloaded just because a screen re-appeared. **Do not** stand up a
bespoke, cache-disabled `URLSession` for a read path — that silently opts a
screen out of this and reintroduces the re-fetch cost the shared cache exists
to remove.

### 3. Lazy containers

Any list whose length is bounded only by user data — all subscriptions, a
show's full episode list, full search results — **must** use a lazy
container (`LazyVStack` / `LazyVGrid` / `LazyHStack`). Unbounded eager
stacks force SwiftUI to build every row up front, which is the thing this
convention exists to prevent.

Short, capped peeks — roughly **≤ 10 items** — that prefix/cap their source
data (e.g. Home's shelves) may stay eager. When you do, comment the cap at
the call site so a future edit that removes the cap doesn't silently leave
an eager stack unbounded.

### 4. Sorting

Each surface has exactly **one default sort**, implemented in a pure,
testable provider — never inline in the view. Two precedents:
`PodcastsListProvider.sortedSubscribed` (`IWantUrPod/Library/PodcastsListProvider.swift`)
and `HomeFeedProvider.recentEpisodes` (`IWantUrPod/Home/HomeFeedProvider.swift`).
Screens fetch via `@Query`/`ModelContext` and hand the raw set to the
provider; the provider is a plain, side-effect-free function exercised
directly in unit tests. Future sort/filter options (e.g. a user-facing sort
picker) should layer on top of the existing provider function rather than
changing what the view passes in or where the view calls it.

Alphabetical sorts fold case + diacritics and strip a single leading article
("The" / "A" / "An") so "The Daily" sorts under D, not T.

## Per-surface table

| Surface | Default sort | Caching | Lazy |
|---|---|---|---|
| Home — Recent episodes | `publishDate` desc, capped | store-first (`@Query`) + URLCache | eager (capped) |
| Home — Up Next peek | queue order, capped | store-first | eager (capped) |
| Shows | alphabetical by title (leading article stripped) | store-first (`@Query`) + URLCache | `LazyVGrid` (2-up) |
| Podcast Detail — episodes | `publishDate` desc | store-first + URLCache | `LazyVStack` |
| Podcast Detail — Story-arcs rail | arc recency (newest arc first) | store-first | `LazyHStack` |
| Search — results | relevance (as returned), cap 8 | URLCache (artwork) | eager (capped) |
| Up Next | queue order | store-first | eager (currently short; switch to `LazyVStack` if it ever grows unbounded) |

## Future

A per-feed staleness TTL for background refresh (e.g. "don't re-fetch a feed
fetched in the last N minutes") is a deliberate future item, not built yet.
Store-first render + the shared `URLCache` already address the perceived
slowness that a TTL would otherwise target, so adding one is deferred until
there's a concrete case they don't cover.
