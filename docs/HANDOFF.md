# Handoff — step 2 of the design-kit → main reconciliation

Pick this up in a **macOS** Claude Code session (it needs Xcode to build). Paste
the prompt below, or just read this file.

## Context

- Branch **`kit-on-main`** (on origin) = `main`'s full app (epics E0–E6) with the
  design kit overlaid from branch `m1` as the winner. `main` itself is untouched.
  Start: `git fetch && git switch kit-on-main`, then branch off it:
  `git switch -c kit-reconcile kit-on-main`.
- The design kit (`design/kit/**`) is now the **source of truth for design intent**.
  main's Swift app is the source of truth for everything else — do **not** regress
  app code.
- Background: `docs/design/direction.md` §10/§11 and the last three commit messages
  on `kit-on-main`.

The kit renamed/added several screens vs what main's Swift references:

| old (main Swift cites) | new (kit) |
|---|---|
| `screens/typing.html` | `screens/search-typing.html` |
| `screens/no-results.html` | `screens/search-noresults.html` |
| `screens/error.html` | `screens/search-error.html` |
| `screens/loading.html` | `screens/search-loading.html` |
| `screens/settings-sources.html` | `screens/settings.html` |

`settings.html`: the Sources picker was removed — v1 is **Apple-only**, PodcastIndex
deferred; Settings now hosts **Manage downloaded episodes** only.

New kit screens: `home.html`, `shows.html`, `up-next.html`, `search-start.html`,
`search-results.html`, `podcast-detail-<slug>.html` (real-data detail + story arcs).

## Three tasks (get each green before the next)

1. **`scripts/verify-design-manifest.sh` is RED.** Update every Swift
   `// Translated from design/kit/*.html` header to the renamed screen, and
   regenerate/refresh `design/kit/MANIFEST.md` (it was removed) so it registers
   every current kit screen incl. the new ones. Run the script until `OK`.
2. **`docs/design/direction.md` and `ROADMAP.md` are still main's versions** — they
   changed on both branches. Do a careful **3-way merge**: KEEP main's app/spec
   content AND fold in m1's design notes (new dock IA, the Apple-only sources
   decision, the Podcast Detail + story-arcs entry). Don't blind-overwrite either
   side.
3. **Reconcile `IWantUrPod/Detail/PodcastDetailView.swift`** toward the new kit
   design: compact icon controls for download / play / add-to-Up-Next (drop the
   oversized buttons and the redundant "Downloaded" text), episode rows showing
   season/episode + publish date + duration, and a horizontal **Story arcs** shelf
   with **Add all** (queue a whole arc). Reference: `design/kit/screens/podcast-detail-*.html`.
   The arc/season data model doesn't exist yet — see the Swift follow-ups in
   `direction.md` §11 (parse `itunes:season` / `itunes:episode` / `itunes:episodeType`
   in `FeedParser`, add `season` / `episodeNumber` + a derived-arc field to `Episode`).

## Story arcs — how the kit derives them

The Apple *search* API is show-level only (no episodes/seasons). Episodes come from
the **RSS feed**. Arcs are derived from episode-title structure by
`scripts/fetch-podcast-episodes.py`:

- `Arc | Episode Title | N` → arc, title, part (art19 / American History Tellers)
- `Arc - Part N - Subtitle` → arc, subtitle, part (The Explorers Podcast)
- anything else → a "single" (no arc)

`<itunes:season>` is optional: AHT sets it (→ season badges + S·E), Explorers doesn't
(→ arc·Part, graceful degrade). Data lives in `design/kit/data/<slug>.json`.

## Verify

- `scripts/verify-design-manifest.sh` passes.
- `xcodegen generate && open IWantUrPod.xcodeproj`, build, run — Podcast Detail
  renders with the new controls + arcs shelf; nothing else regressed.

When it builds clean and verify is green, open a PR from your branch → `main`.

---

## Paste-ready prompt

```
You're picking up "step 2" of a design-kit → main reconciliation on an iOS
podcast app (SwiftUI). Read docs/HANDOFF.md on branch kit-on-main first — it has
the full context, the renamed-screen table, and the three tasks. Then:

git fetch && git switch kit-on-main && git switch -c kit-reconcile kit-on-main

Work through the three tasks in docs/HANDOFF.md in order (verify-design-manifest
green → 3-way merge direction.md + ROADMAP.md → reconcile PodcastDetailView to the
new kit's compact controls + Story arcs shelf). Guardrails: design/kit is the
source of truth for design; main's Swift is the source of truth for app code —
don't regress it. Verify with scripts/verify-design-manifest.sh and an Xcode
build/run. Discuss the approach before large refactors; commit only when I ask.
When verify is green and it builds, open a PR to main.
```
