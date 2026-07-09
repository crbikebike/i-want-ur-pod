# Add Feed by URL — premium / private & custom feed support

Status: **Phase 1 (Kit) done. Phase 2 (Swift) not started — this doc is the handoff.**

## Why

Users subscribe to premium feeds delivered as per-user **tokenized RSS URLs** — e.g. the "This American Life Partners" ad-free feed (Supporting Cast), plus Patreon, Supercast. These are ordinary RSS; the secret token lives *inside* the URL and is the whole credential. The app today only lets feeds in through iTunes search (`ITunesSource`), and private feeds are in no directory — so there was no way to add one. This feature adds a manual **"Add feed by URL"** path.

**Out of scope (explicit):** HTTP Basic Auth (username/password feeds), OPML import. Apple Podcasts Subscriptions / Spotify exclusives have no RSS and are unaddressable by any third-party app.

## Design (signed off)

- **One shared "Add a feed by URL" sheet** behind two entry points: Search ("Have a podcast URL?" on start + no-results) and Settings ("Add premium or custom podcast URL").
- **On success:** sheet dismisses; the show opens in **Podcast Detail**, already subscribed (reuses the existing subscribe → detail path).
- **Token privacy:** the token-bearing URL is stored like any feed URL — no lock UI, just a footnote ("Private links are stored only on this device and never shared").

## Kit reference (Phase 1, done)

- **Sheet:** `design/kit/screens/add-feed-url.html` — four states via `data-state` on `.afu-sheet`: **ready** (URL field + Paste + neutral hint + full-width Add), **loading** (spinner + "Checking…"), **error** (the expiring-private-link message — the premium failure case), **success** (check badge → dismiss to detail). The top-left state switcher is an authoring aid, not UI. Classes are `afu-`-prefixed; built only on locked tokens.
- **Entry points:** the `.urlcta` row in `search-start.html`, the "Add a direct link" action in `search-noresults.html`, and the "Feeds" `.srow` in `settings.html`.
- **Registered** in `design/kit/MANIFEST.md`; the clickable `design/kit/screens/prototype.html` wires all three entry points → the sheet → happy path.

## Phase 2 — Swift build (this box can't compile SwiftUI; do it on the Mac)

The add flow reuses the **existing pipeline unchanged**: `FeedFetcher.fetch(url:)` → `FeedUpsert.upsert(_:into:)` → `modelContext.save()`. **No changes** to `FeedFetcher`, `FeedUpsert`, `FeedParser`, or any model.

### New: `AddFeedByURLViewModel` (app-level composition, mirror `PodcastDetailViewModel`)
- Init with an injected `FeedFetching` seam + `ModelContext` (same injection `PodcastDetailScreen` uses).
- `add(urlString:) async -> Result`:
  1. Trim + validate string → `URL` (reject empty / non-`http(s)`; optionally normalize a leading `feed://` → `https://`).
  2. Fetch via `fetcher.fetch(url:)` — tokenized URL fetched as-is (token rides in the URL).
  3. Upsert via `FeedUpsert.upsert(parsed, into: context)` — idempotent, matches by `feedURL`; re-adding an existing feed makes no duplicate.
  4. Set `podcast.isSubscribed = true` (upsert never writes it — VM owns subscribe intent, same as `PodcastDetailViewModel.toggleSubscribe()`).
  5. `try modelContext.save()`; return the `feedURL` on success.
- Errors: reuse `FeedError.errorDescription` (as `PodcastDetailViewModel.message(for:)` does). **Special-case `FeedError.httpStatus(401/403)`** with the expired-link copy: "Couldn't open this feed. Double-check the link — private feed links can expire." (matches the sheet's error state).

### New: `AddFeedSheet` (SwiftUI)
- `DesignSystem`-styled to match `add-feed-url.html`. URL `TextField` (`.keyboardType(.URL)`, autocap/autocorrect off), Paste, Add; inline loading + error states driven by the VM; privacy footnote.
- On success: dismiss and hand `feedURL` to the caller to navigate.

### Wire the two entry points
- The Search screen(s) and `SettingsScreen.swift` present `AddFeedSheet` via `.sheet`.
- On success, push `feedURL` into the existing `.navigationDestination(for: URL.self) { PodcastDetailScreen(feedURL:) }` (e.g. the pattern in `PodcastsScreen.swift`).

### Storage / privacy (no work now)
Token URL persists in SwiftData `Podcast.feedURL` like any feed. Exclude private feeds from any future OPML / share export. Rely on device-level store encryption.

## Verification (on the Mac)

- **Unit tests** (`IWantUrPodTests`, reuse the `FeedFetching` stub from `PodcastDetailViewModelTests`): valid feed → returns `feedURL`, persisted with `isSubscribed == true`; re-add same URL → no duplicate; invalid/empty → validation error, no fetch; `httpStatus(401)` → expired-link message.
- **Manual, on a running build:** Search → "Have a podcast URL?" → paste a real public RSS URL → subscribes, opens detail, an episode plays. Repeat from Settings with a real **This American Life Partners** tokenized URL → ad-free feed loads and plays end-to-end. Paste garbage → clean inline error, no crash.
