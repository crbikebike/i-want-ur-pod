# Up Next Queue Semantics

**Single source of truth for Epic E5 (Up Next Queue).** Defines the ordering
invariants and the add / reorder / remove / auto-advance rules.

Backing model: `QueueItem` (`Packages/PodcastModels/.../QueueItem.swift`) — an
ordered list where `order` is the sort key (**ascending = plays sooner**) and each
item references an `Episode` with a `.nullify` delete rule.

---

## Invariants

1. **Contiguous, ascending `order`.** After any mutation, the queue's items have
   `order` values `0, 1, 2, …` with no gaps and no duplicates. The item with the
   smallest `order` is "next to play."
2. **No duplicate episodes.** An episode appears in the queue at most once. Adding an
   episode already queued is a no-op (it does not move or duplicate).
3. **No orphans.** A `QueueItem` whose `episode` was nullified (its podcast was
   deleted) is pruned by the queue store, per the model's doc comment.
4. **Persistence.** The queue survives app relaunch (it's SwiftData-backed).

---

## Operations

### Add (E5-S1)
Append to the tail: new `order = (current max order) + 1`, or `0` if empty. No-op if
the episode is already queued (invariant 2).

### Reorder — drag (E5-S2)
Moving an item to a new position rewrites `order` on the affected span so invariant 1
holds (contiguous ascending). Use the same index-shift semantics as SwiftUI's
`onMove`; then normalize `order` across the list.

> **UI mechanism.** `UpNextScreen` renders the queue as the kit's grouped-inset
> surface card (`design/kit/screens/up-next.html`), not a `List`, so it can carry
> the kit's `.grip` handle and `elev-list` shadow. Reorder is therefore a
> hand-rolled grip-drag gesture that computes a target index and calls
> `QueueStore.move(fromOffsets:toOffset:)` — the *order rules above are unchanged*;
> only the gesture source differs from `List.onMove`.

### Remove — left swipe (E5-S2)
Delete the `QueueItem` (not the `Episode`) and re-normalize `order` on the remaining
items. Removing an item that is **not** current has no effect on playback.

> **UI mechanism.** With no `List` to host `.swipeActions`, removal is offered via
> the row's context menu ("Remove from Queue") → `QueueStore.remove(_:)`. Same
> delete-the-`QueueItem`-not-the-`Episode` semantics.

### Removing the current item
If the currently-playing episode's queue entry is removed while it is playing,
**playback of the current episode continues** — removal affects the queue, not the
active audio. The removed episode simply won't be at the head anymore. (We don't
stop audio out from under the listener.)

---

## Auto-advance (E5-S3)

When playback reaches `finished` (see `playback-state-machine.md`):

1. The just-finished episode's `QueueItem`, if present, is **removed** from the queue
   (it's played; `isPlayed` is true).
2. The item now at the head (smallest `order`) becomes current and begins loading →
   playing.
3. If the queue is **empty**, the player returns to `idle` and stops cleanly (no error,
   mini-player hides).

**Relationship between "play this episode" and the queue:** tapping Play on an episode
from a detail screen plays it as the current item; it is not required to be in the
queue. The queue is specifically the *Up Next* ordered list that auto-advance walks.
An episode can therefore be "currently playing" without ever having been queued.

---

## Determinate behaviors (map to E5 tests)

- Adding appends to the tail; re-adding the same episode is a no-op; the queue
  persists across relaunch.
- Drag reorders and rewrites `order` contiguously (`0,1,2,…`, no gaps).
- Left-swipe removes the `QueueItem`; the referenced `Episode` is untouched.
- On `finished`, the next item by `order` becomes current; an empty queue stops
  cleanly at `idle`.
