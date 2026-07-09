# Build note — tap a Story-arc card to filter the episode list

Audience: the macOS/Xcode agent building the SwiftUI app. This describes one
Podcast Detail interaction that the design kit now shows. Design source of truth:
`design/kit/screens/podcast-detail-*.html` (see `build-detail.py`). App code is the
source of truth for everything else — don't regress it.

## What the interaction does

On Podcast Detail, the **Story arcs** shelf sits above the **Episodes** list. Today
an arc card has one action: **Add all N** (queue the whole arc). Add a second one:

- **Tap the card body** (anywhere except the "Add all" button) → filter the Episodes
  list to just that arc's episodes.
- The tapped card shows a selected state (accent ring — kit `.arc-card.active`).
- The Episodes header swaps its count for a chip: **`Showing: <arc> ✕`**.
- **Clear** by tapping the active card again, or by tapping the chip. The list
  returns to all episodes and the count comes back.
- **Add all** must keep working and must NOT trigger the filter (the kit stops the
  click from bubbling; in SwiftUI an inner `Button` already consumes its own tap —
  just don't wrap the Add-all button inside the card's tap target).

## Kit vs. app — ignore the mock's hidden rows

The kit only renders the newest 24 episode rows, so it also renders each shelf
arc's deeper episodes as **hidden** rows (`.ep-extra`) and reveals them on filter.
**That is a mock-only workaround for the truncated fixture.** The Swift app has no
such limit — `PodcastDetailViewModel.episodes` returns the full list. So in the app
the filter is trivial: **show the selected arc's own episodes.** Do not port the
hidden-row mechanism.

## Where it maps in the app

All in `IWantUrPod/Detail/PodcastDetailView.swift`, plus the existing model.

- `PodcastDetailViewModel.arcs` → `[Arc]`. Each `Arc` (`Packages/PodcastModels/.../EpisodeArcs.swift`)
  has `id: String`, `name`, `season`, and `episodes: [Episode]` **newest-first**
  (same order as the main list — see the "Add all" comment at
  `PodcastDetailView.swift:183`). So the filtered list is simply `arc.episodes`; no
  name-matching needed.
- `PodcastDetailViewModel.episodes` → the full, newest-first list (the unfiltered
  view).

### Changes

1. **Selection state** on `PodcastDetailView`:
   `@State private var selectedArcID: Arc.ID?` (nil = no filter).

2. **`arcsShelf`** (`PodcastDetailView.swift:170`): pass an `isSelected` flag and a
   tap action into `ArcCard`.
   - `isSelected: selectedArcID == arc.id`
   - On card-body tap: `selectedArcID = (selectedArcID == arc.id) ? nil : arc.id`
     (toggle → tapping the active card clears).
   - Keep the existing trailing "Add all" closure exactly as-is.

3. **`ArcCard`** (`PodcastDetailView.swift:242`): add an `isSelected: Bool` and a
   card-tap closure. Put the tap on the cover + name + count region (a `Button` or
   `.contentShape(Rectangle()).onTapGesture`), leaving the Add-all button outside it
   so it keeps its own tap. When `isSelected`, draw the accent ring
   (kit `.arc-card.active { inset 0 0 0 2px var(--accent) }` → an
   `.overlay(RoundedRectangle(cornerRadius: Radius.rLg).stroke(palette.accent, lineWidth: 2))`).
   Add an accessibility label/trait so VoiceOver reads it as a filter toggle.

4. **`episodesSection`** (`PodcastDetailView.swift:201`): compute the displayed
   list — `let shown = selectedArcID.flatMap { id in viewModel.arcs.first { $0.id == id } }?.episodes ?? viewModel.episodes` — and `ForEach(shown, ...)`.
   - Header: when a filter is active, show the **`Showing: <arc> ✕`** chip instead of
     the count (kit `.ep-filter` — an accent-2 tinted pill, `Radius.rPill`). Tapping
     it sets `selectedArcID = nil`. Reuse `SectionHeader` if you extend it with a
     trailing accessory, or place the chip beside it. Keep `count` for the
     unfiltered state.

## Verify

- `xcodegen generate && open IWantUrPod.xcodeproj`, build, run.
- Podcast Detail → tap an arc card body: list narrows to that arc's episodes; card
  gets the ring; header shows `Showing: <arc> ✕`.
- Tap the active card again, and tap the chip: both restore the full list + count.
- Tap **Add all**: queues the arc, does not filter.
- Confirm on a show with seasons and one without (season badge is the only
  difference; filter behaves the same).
- Add/adjust a `PodcastDetailViewModel` or view test for the filter toggle if the
  logic moves into the view model.

## Reference in the kit

`design/kit/build-detail.py` — `applyFilter()` in `SCRIPT`, the `.arc-card`
tap/keydown handlers, and the `.ep-filter` chip in the Episodes `sec-head`. Open
`design/kit/screens/prototype.html` → **Detail · Explorers** to feel the interaction.

---

## Paste-ready prompt

```
You're adding one Podcast Detail interaction to an iOS podcast app (SwiftUI) to
match the design kit. Read docs/design/arc-filter.md first — it has the full
mapping to real symbols. Summary: on Podcast Detail, tapping a Story-arc card body
(not its "Add all" button) filters the Episodes list to that arc's episodes; the
tapped card shows an accent ring; the Episodes header shows a "Showing: <arc> ✕"
chip; tapping the active card or the chip clears it. The app has no row limit, so
the filtered list is just the selected arc's own `arc.episodes` — ignore the kit's
hidden-row mock workaround. Work in IWantUrPod/Detail/PodcastDetailView.swift.
Guardrails: design/kit is the source of truth for design; don't regress app code.
Build and run in Xcode to verify. Discuss before any large refactor; commit only
when I ask.
```
