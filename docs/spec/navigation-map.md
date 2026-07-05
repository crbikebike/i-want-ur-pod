# Navigation Map

**Single source of truth for how screens connect** (referenced by E2, E6, and every
UI story). Names the screens, the routes between them, and where the persistent
chrome (tab bar, mini-player) lives in the shell.

Shell today: `IWantUrPod/App/AppShell.swift`.

---

## The frozen navigation contract

`AppShell` draws the selected tab's screen full-bleed with a floating
`LiquidGlassTabBar` pinned over the bottom (direction.md §12). Two rules that
must not be broken when adding screens:

1. **The tab switch never constructs shared services.** The single
   `SearchCoordinator` lives in `AppSources` (`IWantUrPod/App/AppSources.swift`) and
   is injected via the environment — `AppShell`'s `switch selection` must stay a pure
   view switch. Same principle applies to the playback engine and queue store: create
   once at app scope, inject; never build inside the tab switch.
2. **Content reserves the bar gap.** Every screen reserves
   `AppShell.tabBarReservedPadding` (104pt) at the bottom so its last row clears the
   floating bar. New scrollable screens do the same.

---

## Tabs

Five tabs (`AppTab`): **Discover · Podcasts · Up Next · Downloads · Settings.**

| Tab | Screen | Ships in |
|---|---|---|
| Discover | `DiscoverScreen` (curated shelf + search) | live (E1) |
| Podcasts | Library list of subscribed shows | E3 |
| Up Next | Queue editor | E5 |
| Downloads | Downloaded-episodes list | E4 |
| Settings | `SettingsScreen` (Sources checklist, re-show first-run) | live |

---

## Routes

```
First launch ──(once)──► First-Run Explainer (E1-S1) ──► Discover
                                                          Settings ──► re-show explainer

Discover (E1)
  ├─ curated shelf entry ─(feedUrl)─► Podcast Detail (E2)
  └─ search result ──────(feedUrl)─► Podcast Detail (E2)

Podcasts (E3)
  └─ subscribed row ─────(feedUrl)─► Podcast Detail (E2, subscribed state)

Podcast Detail (E2, adaptive)
  ├─ Subscribe / Unsubscribe (toggles Podcast.isSubscribed)
  ├─ episode row ► Download (E4-S1) then Play (E4-S2)
  └─ episode row ► Add to Up Next (E5-S1)

Mini-player (E6-S1, persistent) ──tap──► Now Playing sheet (E6-S2) ──dismiss──► back to mini-player
```

**Podcast Detail is one adaptive screen** (not two). It shows a Subscribe button when
`isSubscribed == false` and subscribed affordances + played/unplayed episode markers
when `true`. Reached identically from Discover, search, and the Podcasts list — keyed
by `feedURL`.

---

## Persistent chrome placement

- **Tab bar:** floats 22pt off the bottom (`AppShell.tabBarBottomInset`).
- **Mini-player (E6-S1):** sits **directly above the tab bar**, spanning the width,
  present on every tab whenever the player is not `idle`. It is part of the shell
  chrome, not any single tab's content — so it stays put as the user switches tabs.
  When the player is `idle` it is hidden and screens use the normal 104pt reserve;
  when visible, screens reserve additional height for it (define the combined reserve
  as a shell constant alongside `tabBarReservedPadding`).
- **Now Playing sheet (E6-S2):** presented modally (sheet) over the whole shell when
  the mini-player is tapped; dismissing returns to the mini-player with state intact.

---

## Determinate behaviors (map to E2/E6 tests)

- A curated entry, a search result, and a Podcasts row all open the **same** detail
  screen for the same `feedURL`.
- The mini-player appears when playback starts, reflects play/pause, and hides at
  `idle`.
- Tapping the mini-player presents the Now Playing sheet; dismissing it preserves
  playback state.
