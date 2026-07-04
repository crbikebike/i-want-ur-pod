# i want ur pod — CarPlay Information Architecture (v1)

CarPlay is **not** a visual reskin of the phone app. It is a
template-driven experience assembled from Apple's `CPTemplate` types. The
system renders it; we only choose templates, supply list rows, and wire
now-playing controls. This doc defines the IA and control set, not pixels.

**Design rule:** CarPlay is glance-and-go. No search, no discovery, no
subscribe. It surfaces what the driver already follows and what's queued.
All logic (ordering, progress, availability) stays on the server /
shared engine — CarPlay templates just display it.

---

## 1. Root — `CPTabBarTemplate`

Three tabs. Discover/Search is intentionally **out** on CarPlay (no
browsing/typing while driving).

1. **Up Next** (default selected)
2. **Podcasts**
3. **Downloads**

Each tab hosts a `CPListTemplate`.

---

## 2. Tab: Up Next — `CPListTemplate`

The active queue. This is the primary CarPlay surface.

- **Section: Now / Continue** (single row, the current or last-played
  episode)
- **Section: Up Next** (ordered queue)

**Row hierarchy (`CPListItem`):**
- `text` — episode title
- `detailText` — show name · time left (e.g. "Orbit Notes · 18 min left")
- Leading image — show artwork (rendered from the gradient tile / cached
  art)
- Trailing — progress via `playbackProgress` (0–1); download/`isExplicit`
  accessory as needed
- Tap → start playback and push `CPNowPlayingTemplate`

Empty state: single non-selectable row, "Your queue is empty — add
episodes from your phone."

---

## 3. Tab: Podcasts — `CPListTemplate` (two levels)

**Level 1 — subscribed shows (list of `CPListItem`):**
- `text` — show title
- `detailText` — author · unplayed count (e.g. "Mara Okonkwo · 3 new")
- Leading image — show artwork
- Tap → push Level 2

**Level 2 — episodes for the selected show (`CPListTemplate`):**
- `text` — episode title
- `detailText` — publish date · duration (e.g. "Jul 2 · 42 min")
- Trailing — `playbackProgress`; downloaded accessory if local
- Tap → play + push `CPNowPlayingTemplate`

Sort: newest first. No filtering UI in v1.

---

## 4. Tab: Downloads — `CPListTemplate`

Episodes available offline — the safe-to-play-anywhere list.

- **Section: Downloaded** (grouped by show, newest first)

**Row hierarchy:**
- `text` — episode title
- `detailText` — show name · duration · file state (e.g. "Signal & Static
  · 38 min")
- Leading image — show artwork
- Trailing — downloaded/checkmark accessory; `playbackProgress` if started
- Tap → play offline + push `CPNowPlayingTemplate`

Empty state: single row, "No downloads yet."

---

## 5. `CPNowPlayingTemplate` — button set

Apple renders the artwork, scrubber, title, and elapsed/remaining
automatically. We supply the **up-to-two** standard transport-adjacent
buttons plus the `CPNowPlayingButton` accessories.

**Transport (system-provided):**
- Play / Pause (primary, always present)

**Custom now-playing buttons (`CPNowPlayingButton` set):**
- **Skip back** — `CPNowPlayingImageButton`, 30s interval, glyph shows
  "30"
- **Skip forward** — `CPNowPlayingImageButton`, 30s interval, glyph shows
  "30"
- **Chapters** — `CPNowPlayingButton` → pushes a `CPListTemplate` of
  chapter markers (title · start time); tap seeks. Shown only when the
  episode has chapters.
- **Queue / Up Next** — enable `isUpNextButtonEnabled`; tapping surfaces
  the system Up Next list backed by our queue.

**Explicitly deferred in v1:**
- **Playback speed** — out of v1 (no speed control on CarPlay yet).
- Star/favorite, share, sleep timer — not in v1.

**Intervals:** skip = 30s both directions for v1 (matches a single
server-owned default; phone-side custom intervals are not yet mirrored to
CarPlay).

---

## 6. Notes / open questions

- Skip intervals are fixed at 30s for v1; syncing the user's phone-chosen
  interval to CarPlay is a follow-up.
- Chapters button visibility depends on feed chapter data — hide the button
  entirely (don't disable) when absent.
- Artwork on CarPlay should reuse cached raster art; the CSS gradient
  placeholders are a phone-side fallback and must be rasterized before use
  here.
- All list contents come from the shared engine already used by the phone
  app — CarPlay adds no new business logic.
