# Patterns worth keeping from the Swift app

Written 2026-07-26, just before the Swift app left the tree. The code is recoverable
at tag `reference/swift-app-2026-07`.

This is not a port guide. It's the list of things the Swift app got *right* — the
decisions that took real iterations to find. The React app should inherit these ideas,
not the code. Everything here names its old home so you can go read the original.

---

## 1. The two-tier explore flow, and why the gestures differ

This is the flow users praised. Its shape is deliberate and easy to get wrong.

**Tier 1 — browse the finite set.** A full-screen, scroll-snapped **vertical** pager
over all 30 themes. One theme per screen: gradient wash, "Theme N of 30" kicker, name,
hook, a row of up to 5 show covers with a "+N" chip, and a full-width "Dive in" button.
A progress pill (`n/30`) opens a "Jump to a theme" list.

**Tier 2 — judge the large pool.** A **horizontal** swipe deck over that one theme's
shows. Right = subscribe. Left = skip, nothing persisted. Already-subscribed shows are
filtered out before the deck is built.

> **The rule behind the split:** never make someone answer yes/no to a small structured
> set. 30 themes is a menu — you browse it, and vertical paging says "there's more
> below." Hundreds of shows is a pool — you triage it, and horizontal swiping says
> "accept or reject." Getting this backwards is what makes discovery feel like a chore.

Old homes: `IWantUrPod/Explore/ThemeFeedScreen.swift`,
`IWantUrPod/Explore/ThemeShowDeckScreen.swift`.

## 2. The swipe deck holds no state of its own

`SwipeDeck` was stateless over its data. It kept no current index. It rendered whatever
prefix of `items` it was handed, and the **caller** advanced the list by removing the
front element inside `onSwipeRight` / `onSwipeLeft`.

That one constraint bought two things:

- Exactly one place mutates the data, no matter what triggered the change.
- A **programmatic action** input: when someone subscribed from inside the detail sheet
  instead of swiping, the caller set that input, the deck played the identical fly-out
  animation, and fired the identical callback. The next card was already waiting behind
  the sheet when it closed.

Carry the constraint. A React deck should take `items` plus callbacks and own no index.

Old home: `Packages/DesignSystem/Sources/DesignSystem/Components/SwipeDeck.swift`.

Gesture constants that were tuned, not guessed: release threshold ±110pt, tap-vs-swipe
disambiguation at 8pt of total movement, fly-out 520pt with 60pt drift and 22° rotation,
resting cards offset 14pt and scaled 0.95 per depth.

## 3. One adaptive detail screen, keyed by feed URL

Podcast Detail was **one** screen, not a subscribed version and an unsubscribed version.
It showed a Subscribe button when not subscribed, and subscribed affordances plus
played/unplayed markers when subscribed. A curated shelf entry, a search result, a
library row, and the swipe deck's tap-peek all opened the *same* screen for the same
feed URL.

Keep this. The moment there are two detail screens they drift.

## 4. Shared services are created once and injected — never in the tab switch

The tab switch was a pure view switch. Search coordination, the playback engine, and the
queue store were constructed once at app scope and injected. Building a service inside a
tab's body means it gets rebuilt whenever the tab redraws, which silently resets state.

React equivalent: providers at the root, never inside a route element.

Old home: `IWantUrPod/App/AppShell.swift`, `IWantUrPod/App/AppSources.swift`.

## 5. Chrome is the shell's job, and content reserves room for it

The floating tab bar and the mini-player were shell chrome, not any screen's content.
The mini-player sat directly above the tab bar and persisted across tab switches
whenever the player wasn't idle. Every scrollable screen reserved a fixed bottom gap
(104pt, plus more when the mini-player was visible) so its last row cleared the bar.

The explore flow could **take over** — one call hid the tab bar and mini-player for the
whole two-tier flow, restored on dismiss, so it read as a single immersive screen. Worth
keeping as an explicit capability rather than something each screen improvises.

## 6. Playback state machine

Six states: `idle`, `loading`, `playing`, `paused`, `finished`, `failed(message)`.
`finished` is what triggers queue auto-advance, which is why it's a real state and not
just "paused at the end."

Rules that transfer directly:

- **Progress is persisted at least every 5s while playing, and always on pause, on
  finish, and on backgrounding.** Bounds loss to ~5s if the app dies.
- **`isPlayed` is computed in the model** as progress ≥ 0.98, in exactly one place. Never
  re-derive the threshold at a call site.
- **Resume seeks** when 0 < progress < 0.98 before entering playing/paused.
- Now Playing metadata updates on every state change and every progress write.

Old home: `docs/spec/playback-state-machine.md`, `Packages/PlaybackKit/`.

**What NOT to carry: download-first.** v1 refused to stream — an episode played only from
a completed local file. That was a deliberate v1 simplification to erase every
buffering and seek-over-network edge case, and it worked. But it's a bad default for a
discovery app where the whole point is trying something new immediately. The React app
should stream, and treat download as an explicit offline action.

## 6b. Audio comes from the feed, at play time

The catalog shipped metadata and a `feedUrl`. It never held an audio URL. The app resolved
audio at runtime: `FeedFetcher(URLSession.shared)` fetched the feed body,
`FeedParser.parse()` read `<enclosure url>` where `type` was `audio/*`, and the result became
`ParsedEpisode.audioURL`.

Three details that matter, all of which the React app must reimplement:

- **Items with no usable audio enclosure are skipped** before an episode object is ever
  constructed. There is no such thing as an unplayable episode in the store.
- **Feed bodies go through the shared HTTP cache.** `URLCache.shared` was configured once at
  launch (50MB memory / 500MB disk) and both artwork and feed fetches read it. Never stand up
  a bespoke, cache-disabled client for a read path — that silently opts out of this and
  reintroduces the re-fetch cost the cache exists to remove.
- **Store-first render.** Resolve from the local store synchronously and show it, *then*
  refresh from the network in the background, best-effort. A failed background refresh is
  swallowed — the cached render stands, and no error is surfaced over live data. Only a
  genuinely empty store puts a fetch on the critical path.

Why this stays true in the new architecture: enclosure URLs are volatile. Tracking prefixes
rotate and dynamic ad insertion can make them session-specific, so a cached URL is a dead
play button. Duration is the opposite — it never changes once published — so the catalog
caches it for display while the player still trusts the feed.

Old homes: `Packages/FeedParsingKit/`, `docs/design/data-loading.md`,
`IWantUrPod/Detail/PodcastDetailViewModel.swift`.

## 7. Queue invariants

- `order` is contiguous and ascending from 0 after **any** mutation. Smallest plays next.
- An episode appears at most once. Re-adding is a no-op — it does not move or duplicate.
- **Removing the currently-playing episode from the queue does not stop the audio.**
  Removal affects the queue, not the active sound. Never stop playback out from under a
  listener.
- On finish: remove the finished item, head becomes current, empty queue stops cleanly at
  idle with no error.
- "Play this episode" and "queue this episode" are independent. Something can be playing
  without ever having been queued.

Old home: `docs/spec/queue-semantics.md`.

## 8. Arc cards filter the episode list

On Podcast Detail, a Story-arcs shelf sat above the Episodes list. Tapping a card's
**body** filtered the list to that arc's episodes and drew an accent ring on the card.
The Episodes header swapped its count for a `Showing: <arc> ✕` chip. Tapping the active
card again, or the chip, cleared it. The card's "Add all N" button stayed a separate tap
target and never triggered the filter.

This is the interaction that makes a 700-episode show tractable. It gets more powerful in
the new catalog, where arcs are LLM-built rather than regex-matched.

Old home: `docs/design/arc-filter.md`, `IWantUrPod/Detail/PodcastDetailView.swift`.

## 9. Kit-first, with provenance in the code

The design kit (`design/kit/`) was the source of truth for design; Swift was translated
from it. Every translated file opened with a header naming the exact kit screen it came
from and citing the kit's real numbers.

That discipline is why the gesture constants above still exist as documented values
instead of magic numbers nobody dares change. **Keep it.** Design lives in the kit, code
cites the kit, and a reader can always find out why a number is what it is.

Also worth keeping: design tokens as a real layer (typography scale, radii, a palette
injected through context) rather than values sprinkled at call sites.

---

## Carried over, dropped, and open

| | |
|---|---|
| **Keep** | two-tier explore, gesture split, stateless deck, one adaptive detail screen, root-level providers, shell-owned chrome, feed-resolved audio, shared HTTP cache, store-first render, playback state machine, queue invariants, arc filtering, kit-first provenance, design tokens |
| **Drop** | download-first playback, the kit's hidden-row mock workaround, xcodegen and the whole Xcode project layer |
| **Deferred** | CarPlay IA — the template design is worth re-reading when a native car layer happens (`docs/design/carplay-ia.md`) |
