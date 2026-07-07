# i want ur pod — Design Direction

**Direction:** Playful Pulse, iOS-native (inspired-original).
**Identity:** coral primary + mint secondary, rounded system type, animated
equalizer/pulse accents, gradient artwork tiles, first-class iOS chrome.

This is the single source of truth. The Claude Design project
"i-want-ur-pod" is the system of record; `design/kit/**` is a synced
mirror of it. Every kit file (`design/kit/**`) carries a **byte-identical
color-role token block** — do not fork hues per file.

Dark is the hero. Both themes ship with a fixed top-right toggle that flips
`data-theme` on the root.

---

## 1. Color roles

Brand ramp is theme-agnostic. Roles remap per theme.

### Brand ramp (both themes)

| Token | Hex |
|---|---|
| `--coral` | `#FF6A4D` |
| `--coral-deep` | `#CA340F` |
| `--mint` | `#34E0C4` |
| `--mint-deep` | `#046B58` |
| `--grape` | `#7C6BFF` |

### Dark (hero)

| Role | Value |
|---|---|
| `--bg` / `--grouped-bg` | `#0E0B12` |
| `--surface` | `#1C1722` |
| `--surface-2` | `#262030` |
| `--text` | `#F8F3EF` |
| `--text-dim` | `#ABA1B4` |
| `--text-faint` | `#988DA1` |
| `--accent` | `#FF6A4D` (coral) |
| `--accent-2` | `#34E0C4` (mint) |
| `--on-accent` | `#2A0E04` |
| `--hairline` | `rgba(255,255,255,.09)` |
| `--separator` | `rgba(255,255,255,.12)` |
| `--chip` | `rgba(255,255,255,.08)` |
| `--seg-track` | `rgba(120,120,128,.24)` |
| `--seg-thumb` | `#38313F` |
| `--field` | `rgba(120,120,128,.24)` |
| `--bar-material` | `rgba(20,16,26,.72)` |
| `--tabbar-glass` | `rgba(14,11,18,.94)` |
| `--tabbar-hairline` | `rgba(255,255,255,.14)` |
| `--tabbar-shadow` | `0 10px 34px -8px rgba(0,0,0,.6), 0 2px 10px -4px rgba(0,0,0,.5)` |
| `--tabbar-icon` | `#8B8291` |

### Light

| Role | Value |
|---|---|
| `--bg` / `--grouped-bg` | `#FBF5EF` (warm cream) |
| `--surface` | `#FFFFFF` |
| `--surface-2` | `#FCEFE7` (warm peach) |
| `--text` | `#1A1420` |
| `--text-dim` | `#6B6472` |
| `--text-faint` | `#736A78` |
| `--accent` | `#CA340F` (coral-deep) |
| `--accent-2` | `#046B58` (mint-deep) |
| `--on-accent` | `#FFFFFF` |
| `--hairline` | `rgba(40,26,36,.10)` |
| `--separator` | `rgba(60,60,67,.18)` |
| `--chip` | `#F1E7DF` (warm) |
| `--seg-track` | `#EFE4DB` (warm) |
| `--seg-thumb` | `#FFFFFF` |
| `--field` | `#F3EAE2` (warm) |
| `--bar-material` | `rgba(248,246,250,.78)` |
| `--tabbar-glass` | `rgba(250,248,252,.96)` |
| `--tabbar-hairline` | `rgba(60,60,67,.18)` |
| `--tabbar-shadow` | `0 10px 34px -10px rgba(20,16,26,.22), 0 2px 10px -4px rgba(20,16,26,.12)` |
| `--tabbar-icon` | `#6C6C70` |

---

## 2. Accessibility — honest AA

Measured WCAG contrast ratios (sRGB). AA = **4.5:1** normal text, **3:1**
large text (≥24px, or ≥18.66px bold) and UI component boundaries.

### Passes AA for normal text in BOTH themes

| Pair | Dark | Light |
|---|---|---|
| `text` on `bg` | 17.7 | 16.0 |
| `text` on `surface` | 16.0 | 18.0 |
| `text-dim` on `bg` | 7.9 | 5.1 |
| `text-dim` on `surface` | 7.1 | 5.7 |

Use `text` and `text-dim` for all real body copy, titles, authors,
subheads, tags. Every text role — including `text-faint` (light 4.6) — now
clears 4.5, so `text-faint` in light is the dimmest readable floor. Do not
go below `text-faint` for any text.

### Accent — passes normal text in BOTH themes

| Pair | Dark | Light |
|---|---|---|
| `accent` (coral) on `bg` | 6.9 | 4.7 |
| `accent` (coral) on `surface` | 6.2 | 5.2 |
| `accent-2` (mint) on `bg` | 11.7 | 5.8 |
| `accent-2` (mint) on `surface` | 10.6 | 6.5 |

- **Dark:** coral (`#FF6A4D`) and mint (`#34E0C4`) clear 4.5 — safe as text.
- **Light:** coral-deep is now `#CA340F` and mint-deep `#046B58`. Both clear
  4.5 as text on bg and surface, so eyebrows, ghost-button labels, active
  tab, count pill, and the section-header count all pass.

### text-faint — muted labels, passes both themes

| Pair | Dark | Light |
|---|---|---|
| `text-faint` on `bg` | 6.2 | 4.6 |
| `text-faint` on `surface` | 5.6 | 5.2 |

Light `#736A78` / dark `#988DA1`. Both clear 4.5 for the provider label,
section subtitle, footnotes, and token-spec metadata. Still the dimmest
text role — kept lighter than `text-dim` in light, dimmer than `text-dim`
in dark. The **search placeholder** uses `text-dim` on the `--field` fill
(now 10% grey): `text-dim` on field = 4.5, so the placeholder clears AA.

### On-accent labels

White-on-`coral-deep` (light `#CA340F`) = **5.2**. The Subscribe pill and
`.btn-primary` label clear normal-text AA (4.5). Dark on-accent (`#2A0E04`
on coral) = 6.38, passes. The hot tag (`🔥 Hot`) is a **solid accent chip
with on-accent text** — white on coral-deep 5.2 in light, `#2A0E04` on
coral 6.4 in dark — instead of tinted coral-on-coral, which never cleared
4.5.

### Floating tab bar — labels pass over bright content

Tab labels are small text (`.62rem` / ~9.9px, weight 600) and need **4.5:1**.
The bar floats over scrolling content, so the worst case is **saturated album
artwork** bleeding through the blur — not just white. Ratios below are measured
against that worst backdrop (the app's own art gradient: grape `#7C6BFF`, pink
`#FF4D8D`, blue `#2E8BFF`, mint `#34E0C4`), which lowers the effective bar
luminance more than white does.

The dark `--tabbar-glass` scrim is `rgba(14,11,18,.94)` — a dark base at high
opacity, so it dominates any backdrop and was already safe. The light
`--tabbar-glass` was a near-white fill at only 86% opacity, so saturated art
bled through and dropped the effective bar, pulling both labels to ~4.2:1. It
was raised to **`rgba(250,248,252,.96)`** (same color, higher opacity) so the
bar stays near-white regardless of backdrop.

Note the worst backdrop differs by theme: the dark bar is darkest, so its label
contrast is *lowest over white* (art only makes the bar darker → higher ratio);
the light bar is lightest, so its label contrast is *lowest over saturated art*.

| Pair | Dark worst (over white) | Dark over art | Light worst (over art) | Light over surface/white |
|---|---|---|---|---|
| inactive `--tabbar-icon` | 4.69 | 4.88–5.04 | 4.74 | 4.94–4.97 |
| active `--accent` (coral) | 6.10 | 6.35–6.56 | 4.74 | 4.95–4.97 |

Both roles clear 4.5:1 in **both** themes across the full range of backdrops,
bright and dark; the 26px icons clear the 3:1 graphical-object bar with room.
Only opacity changed — the color roles (`--tabbar-icon`, `--accent`) and the
glass fill color are unchanged.

---

## 3. Type scale

Self-hosted brand fonts — **IBM Plex Mono** for display/titles, **Roboto**
for body and UI. Both are pulled in via `design/kit/styles.css` (which
imports `fonts/fonts.css`, which imports `fonts/ibm-plex-mono.css` and
`fonts/roboto.css`):

```
--font: "Roboto", -apple-system, BlinkMacSystemFont, "Segoe UI",
        system-ui, sans-serif;
--font-display: "IBM Plex Mono", ui-monospace, "SF Mono", Menlo, monospace;
```

`--font-display` is used for large titles, section headers, inline nav
titles, shelf headers, and state titles; everything else (body copy, row
titles, labels, tabs) uses `--font`.

| Role | Size | Weight | Tracking |
|---|---|---|---|
| Large title | 2.32rem | 800 | -0.02em |
| Section (h2) | 1.34rem | 800 | -0.015em |
| Nav title (inline) | 1.06rem | 800 | -0.01em |
| Shelf header (`.sh-title`) | 1.18rem | 800 | -0.015em |
| Row title | 1rem | 700 | -0.01em |
| Body / input | 1rem | 500 | — |
| Subhead / author | 0.82rem | 500 | — |
| Settings group label | 0.72rem | 800 | 0.06em, uppercase |
| Source name (row) | 1rem | 700 | -0.01em |
| Badge / tag (Primary, Open index) | 0.62rem | 800 | 0.04em, uppercase |
| Count pill | 0.74rem | 800 | — |
| Eyebrow | 0.72rem | 800 | 0.12em, uppercase |
| Tag | 0.64rem | 800 | 0.02em, uppercase |
| Tab label | 0.62rem | 600 | 0.01em |

---

## 4. Spacing

4-based ramp. **Gutter = `--sp-5` = 20px** — the page inset and the
default horizontal/vertical rhythm. Use tokens, not raw px.

| Token | px | Typical use |
|---|---|---|
| `--sp-1` | 4 | micro nudge |
| `--sp-2` | 8 | icon gaps, chip gaps |
| `--sp-3` | 12 | card padding, list-to-list gaps |
| `--sp-4` | 16 | block separation |
| `--sp-5` / `--gutter` | 20 | **page gutter** |
| `--sp-6` | 26 | section top margin |
| `--sp-7` | 32 | large-state vertical padding |

The locked-base chrome now **references these tokens** instead of raw px, so
chrome and the shared kit extras use the same scale. Off-ramp values were
snapped to the nearest token (row gap 13→`--sp-3`, row padding 11/14→`--sp-3`/
`--sp-4`, title-dot gap 10→`--sp-2`, provider top 18→`--sp-4`, list top
14→`--sp-3`). The row separator inset is derived, not a rhythm step, so it is
`calc(var(--sp-4) + 60px + var(--sp-3))` (gutter + 60px art + row gap = where
the title starts). Three non-rhythm constants stay raw on purpose: the status/
tab-bar clearances in `.content` padding (`54`/`104`, the `104` reserving
room under the floating tab bar), the 60px artwork size,
and the 2px sub-token optical inset that aligns the section header to the
title. Everything else on the rhythm scale uses a `--sp-*` token.

---

## 5. Radii

| Token | px | Use |
|---|---|---|
| `--r-sm` | 12 | small fills |
| `--r-seg` | 9 | segmented track/thumb |
| `--r-field` | 11 | search field |
| `--r-art` | 14 | row / skeleton artwork tile |
| `--r-md` | 16 | card artwork |
| `--r-lg` | 20 | grouped lists, cards |
| `--r-pill` | 999 | buttons, tags, count, subscribe |

Artwork tiles in the row use `--r-art` (14, between `--r-field` and
`--r-md`) — an intentional component detail carried from the base, now a
named token. Source icon tiles in the Settings checklist use a fixed 13px
corner (one step under `--r-art`) to read tighter at the 46px size.

`--r-seg` (9) is **retained but no longer used by any screen** — the inline
segmented provider control it powered was retired when sources moved to
Settings (see §12). It stays in the token block for byte-identity across kit
files; if a future segmented control returns, its inner corner is the
standard nested value `calc(var(--r-seg) - 2px)` = 7. The iOS toggle switch
in the sources checklist uses `--r-pill` for both track and knob.

---

## 6. Elevation

| Token | Value |
|---|---|
| `--elev-list` | `0 1px 0 var(--hairline), 0 8px 24px -18px rgba(0,0,0,.5)` |
| `--elev-card` | `0 1px 0 var(--hairline), 0 12px 30px -20px rgba(0,0,0,.55)` |
| `--elev-sub` | `0 6px 14px -8px var(--accent)` (coral glow on subscribe) |
| `--elev-pop` | `0 20px 50px -24px rgba(0,0,0,.6)` |

Restrained. Grouped lists float; only the subscribe pill carries a colored
glow.

---

## 7. Motion

Two easings, four durations. Everything collapses under
`prefers-reduced-motion`.

| Token | Value |
|---|---|
| `--ease-soft` | `cubic-bezier(.22, .61, .36, 1)` |
| `--ease-spring` | `cubic-bezier(.34, 1.56, .64, 1)` |
| `--dur-fast` | 0.2s — state tint, row press |
| `--dur-mid` | 0.3s — press scale, color change |
| `--dur-row` | 0.55s — staggered row entrance |
| `--dur-rise` | 0.6s — title / section reveal |

Signature motions: equalizer bars (`pulseBar`), title pulse-dot
(`idlePulse`), subscribe pulse ring (`ringOut`), segmented-thumb spring,
tab bounce-in, large-title → inline-nav condense on scroll.

**Reduced motion:** all animation durations drop to ~0 and entrance
opacity/transform reset to visible — no content is hidden behind an
animation.

---

## 8. Accent usage rules

1. **Coral is the primary action color.** Subscribe, active tab, eyebrow,
   focus ring, primary button, matched-substring emphasis (as weight, not
   color — see below).
2. **Mint is the secondary/confirmation accent.** Count pill, subscribe
   gradient tail, success glints. Mint-deep now clears AA as text in light,
   so the count pill label stays mint.
3. **Grape is a tertiary brand pop** for artwork gradients and the empty
   badge — never text.
4. **One accent per surface.** Do not stack coral + mint text in the same
   cell.
5. **Light-theme text discipline:** body copy uses `text` / `text-dim`.
   Coral-deep (`#CA340F`) and mint-deep (`#046B58`) now clear AA as text on
   bg/surface, so accent labels (eyebrow, count, ghost buttons) are allowed;
   keep them to labels and emphasis, not long-form copy.
6. **Emphasis in lists (e.g. search-match):** use `text` at weight 800,
   not accent color, so it survives light-theme AA.
7. **Focus:** 2px `--accent` ring (`box-shadow`) on the search field and
   any focusable control.

---

## 9. Iconography

- **All icons are inline SVG**, `currentColor`, ~1.6–2px strokes, rounded
  caps/joins. No icon fonts, no external assets.
- Tab icons: Discover = compass, Podcasts = grid, Up Next = queue,
  Downloads = tray-down (from the locked base), Settings = gear.
- Sources checklist icons: Apple Podcasts = apple glyph on a coral→grape
  tile, PodcastIndex = broadcast-wave glyph on a mint→blue tile, plus a
  lock badge (not-yet-configured), a key glyph (Add API key), and a
  three-line drag handle (reorder primary/fallback).
- State badges (empty/no-results/error) are 84px rounded-square gradient
  tiles with a white glyph — decorative, so contrast rules don't gate the
  glyph.
- Artwork placeholders are **CSS gradient tiles** (`.a1`–`.a6`) with a bold
  white initial glyph and an inset highlight — no raster images.
- Equalizer bars and the pulse-dot are the identity motifs; reuse them
  sparingly (eyebrow, inline nav, section captions).

---

## 10. Component & screen inventory

**This section is a summary only. `design/kit/MANIFEST.md` is the enforced,
authoritative, per-file inventory** (path, real bespoke content, Swift
implementation, status) — check it, not just this list, before translating
or extending anything.

**The "SHARED KIT EXTRAS" trap:** every file under `design/kit/` mixes a
unique, bespoke top section with an identical copy-pasted boilerplate CSS
block near the bottom (`.state`, `.chips`, `.sk-row`, `.cardgrid`, `.btn`,
etc. — repeated verbatim across files for authoring consistency). That
shared block is **not** the file's real content. Two components were
mistranslated by reading the shared block instead of the file's actual
bespoke markup — `ResultRow.swift` (fixed: rebuilt as `ResultShelf`/`PodCard`/
`PodGrid`, the kit's actual results pattern) and the Discover first-run state
(not yet fixed — see `design/kit/MANIFEST.md`). Always identify a file's
bespoke content first, and confirm it's actually *instantiated in the body* —
not just declared in the `<style>` block — before treating a CSS class as
real; `.list`/`.row` looked like a legitimate shared pattern but turned out to
be dead code nowhere used in any current screen.

- **Foundations:** `design/kit/tokens.html`.
- **Components** (`design/kit/components/`):
  - `search-field.html` — search input (default/focused/filled states).
  - `sources-checklist.html` — **retired** (2026-07-06). Formerly the
    canonical demonstration of source selection (Apple primary + opt-in
    PodcastIndex); the checklist and its screen were removed when v1 settled
    on Apple-only, no source picker. See §11/§12.
  - `result-row.html` — **category shelves** (horizontal rails grouped by
    taxonomy, "View all" → 2-up grid), despite the name. Not a flat row —
    confirmed the kit's only current results pattern. Implemented as
    `ResultShelf`/`PodCard`/`PodGrid`.
  - `result-card.html` — 2-up poster grid card.
  - `subscribe-button.html` — circular +/check control (default/subscribing/subscribed).
  - `section-header.html` — the generic label band (simpler, non-shelf
    header; shelves get their own header with a "View all" link).
  - `buttons.html` — primary / secondary / ghost (ghost ⇔ kit's `.btn-tertiary`).
  - `tab-bar.html` — the floating Liquid Glass tab bar, rebuilt (2026-07-05)
    as a **four-item dock** — Home · Shows · Up Next · Search — plus its
    **search-takeover** variant (the bar itself collapses into a search
    field; see §12).
  - `no-results.html` — the empty-state card in isolation (badge/title/message/actions).
  - `loading-skeleton.html` — flat shimmering `.sk-row` list placeholder.
    **Dead pattern, no consumer**: `screens/search-loading.html`'s shelf/rail
    skeleton is the one actually used (below).
- **Primary screens** (`design/kit/screens/`, iPhone-framed):
  - `home.html` — the new landing feed (2026-07-05): an Up Next peek, new
    episodes, shows for you, and our favorites, in that order.
  - `shows.html` — the renamed/translated Podcasts list (subscribed shows).
  - `up-next.html` — the queue; each row now carries inline download state
    and a download button (Downloads left the tab bar — see §11/§12).
- **Search screens** (iPhone-framed):
  - `search-start.html`, `search-typing.html` — search field mid-typing + a
    typeahead suggestions drawer.
  - `search-loading.html` — in-screen "Searching for…" over shimmering
    shelf/rail skeletons.
  - `search-results.html` — the success state: a featured **top result**
    (larger artwork + Subscribe) over a **"More shows"** list of result rows,
    each with an inline subscribe (+/✓) button. Tapping a result row (or any
    show tile) opens the **Podcast Detail** screen.
  - `search-noresults.html` — full screen wrapping the `no-results.html`
    component card.
  - `search-error.html` — full screen wrapping the same `.state` card, error
    copy.
- **Detail screens** (iPhone-framed): `podcast-detail-<slug>.html` — a
  **pushed** screen (back chevron top-left) built from **real feed data**,
  not fixtures. Header (artwork, title, author, category, Subscribe, clamped
  description) → a horizontal **Story arcs** shelf (each card: season badge
  when the feed sets `<itunes:season>`, arc name, N episodes, **"Add all"**
  to queue the whole arc) → the **Episodes** list with **compact icon
  controls** (download / play / add-to-Up-Next) and per-row
  `arc · S·E · date · duration`. Arcs are derived from episode-title
  structure; the screen degrades gracefully when a feed has no seasons/arcs.
  Generated by `design/kit/build-detail.py` from `design/kit/data/<slug>.json`.
  Live examples: American History Tellers (seasons + arcs) and The
  Explorers Podcast (arcs, no seasons).
- **Settings screens:** `settings.html` — reached from the top-right gear,
  pushed over the current tab (not a tab itself). Its only section for now
  is **Manage downloaded episodes** — a list of downloaded episodes, each
  removable (deleting the local audio; the episode stays in the feed). The
  source-picker screen (`settings-sources.html`) was removed (§11,
  2026-07-06).
- **Onboarding screens:** `first-run.html` — **a multi-step guided
  onboarding wizard** (existing-app import via OPML, or favorite-show/topic
  pickers → personalized shelf results), not a static empty state. **No
  Swift implementation exists**; the Discover `.firstRun` state currently
  renders a placeholder `EmptyStateView`, not this flow — see
  `EmptyStateView.swift`. Adopts the four-item dock like every other screen.

Navigation is a **floating Liquid Glass tab bar** (iOS 26 style) of four
destinations — **Home · Shows · Up Next · Search**. There are **no inline
search boxes**: tapping **Search** takes the bar over, turning it into a
search field (Home pinned left, ✕ to cancel) that rises above the keyboard
while the screen fills with suggestions/results. **Settings** moved off the
bar to a **top-right gear**; **Downloads** left the bar too — download state
and a download button live inline on **Up Next** rows. **Settings** now hosts
one section — **Manage downloaded episodes** (remove downloaded files). v1
searches **Apple's directory only** — no source picker, no sources list (§12);
PodcastIndex is deferred to a later milestone.

---

## 11. Open issues / follow-ups

- **AA gap — RESOLVED.** `--coral-deep` darkened to `#CA340F` and
  `--mint-deep` to `#046B58` (applied byte-identically to every kit file).
  White-on-coral-deep Subscribe / primary label = 5.2, clears normal-text
  AA. The hot tag became a solid accent chip (on-accent text) instead of a
  tinted coral-on-coral chip. Text roles also adjusted: `text-faint` light
  `#736A78` / dark `#988DA1`, light `--tabbar-icon` `#6C6C70`, light
  `--field` lowered to 10% so the `text-dim` placeholder clears 4.5.
- **Mint-deep in light** now clears AA as text (5.8–6.5 on bg/surface); the
  count pill label stays mint.
- **Dark tab-bar labels over bright content — RESOLVED.** The floating bar's
  dark `--tabbar-glass` scrim was strengthened from `rgba(28,22,34,.86)` to
  `rgba(14,11,18,.94)` (applied byte-identically to every kit file), so the
  blurred bar stays dark over bright artwork/white (effective ≈ `rgb(28,26,32)`).
  Inactive `--tabbar-icon` now clears 4.69:1 and active coral 6.10:1 over
  white; both were already fine over the app's own dark bg. No color roles
  changed. See §2.
- **Light tab-bar labels over bright content — RESOLVED.** The earlier rework
  fixed dark but left light asymmetric: the near-white `--tabbar-glass` fill sat
  at only 86% opacity, so saturated album art bled through the blur and dropped
  the effective bar, pulling inactive `#6C6C70` and active `#CA340F` labels to
  ~4.2:1 over grape/pink/blue art (they only reached ~5.0 over pure white). The
  light `--tabbar-glass` opacity was raised `.86 → .96` (same color, applied
  byte-identically to every kit file), so the bar stays near-white regardless of
  backdrop: worst-case labels now clear **4.74:1** over the app's own artwork.
  No color roles changed; the glass fill color is unchanged. See §2.
- **Search-order badge tint — RESOLVED.** The `.ord-num` digit
  (`settings-sources`) is small bold accent text on an accent tint over white;
  at 14% the tint pulled it to 4.23:1 in light. Lowered the tint `14% → 8%`
  (accent-on-accent, so a lighter tint *raises* contrast): light now 4.64:1,
  dark 5.60:1. Position still conveys order as a backstop.
- **Kit convergence — RESOLVED.** The duplicate theme-toggle script (which
  broke all JS on 6 of 7 screens) was removed; the three floating-tab-bar
  tokens were added to `tokens.html` and the 10 components that lacked them;
  the retired segmented `.provider`/`.seg` CSS was deleted from `tokens`,
  `app-shell`, and the 9 other components (markup was already gone); every
  tab bar now carries the same **five** items (Discover, Podcasts, Up Next,
  Downloads, Settings) with byte-identical padding (`0 6px`) and 26px icons
  *(superseded 2026-07-05 — see the dated entry below: the dock is now four
  items, Home · Shows · Up Next · Search)*; and `tokens.html` now documents
  the `.tabbar` sample and its tokens.
- **Provider picker retired — RESOLVED.** The inline segmented source
  control (and its `provider-switched` screen) was removed. Search sources
  then moved to a **Settings → Sources** checklist. *(Superseded 2026-07-06:
  the Sources checklist itself was removed — v1 uses Apple only, no picker.
  See the dated entry above and §12.)* `--r-seg` is retained-but-unused.
- **Artwork 14px radius — RESOLVED.** Promoted to `--r-art: 14px` (added
  byte-identically to every kit file's radii block) and referenced by `.art`
  and `.sk-art`. The locked-base chrome no longer hardcodes rhythm/radii px:
  spacing uses `--sp-*`, radii use `--r-*`, the segmented inner corner uses
  `calc(var(--r-seg) - 2px)`, and the row separator inset uses a `calc()` of
  tokens. Only device-chrome clearances (`54`/`104`), the 60px art size, and
  the 2px optical inset remain intentional raw constants.
- **Light neutrals warmed — RESOLVED (2026-07-04).** The iOS system-grey light
  neutrals read as generic and dropped the coral brand in light mode. Warmed the
  light-only neutral roles back toward the original d2 cream/peach, applied
  byte-identically to every kit file and the locked base: `--bg` / `--grouped-bg`
  `#F2F1F6 → #FBF5EF`, `--surface-2` `#F6F1EC → #FCEFE7`, `--chip` `→ #F1E7DF`,
  `--seg-track` `→ #EFE4DB`, `--field` `→ #F3EAE2` (supersedes the 10% grey field
  noted above), plus the gallery backdrop to warm cream. Accents, text roles, and
  the tab-bar glass/icon were left untouched, so all documented AA holds. Re-measured
  every text/accent pair on the warm surfaces — all clear 4.5 (tightest: text-dim on
  chip 4.67, text-faint on surface-2 4.59, accent on surface-2 4.65). Dark mode
  unchanged.
- Voice/mic affordance is visual only; no dictation behavior specified yet.
- **IA revised — new dock (2026-07-05).** First round of post-M0.5 feedback
  reshaped navigation around a single dock. The floating tab bar went from
  **five** items to **four** — **Home · Shows · Up Next · Search** —
  superseding the earlier "every tab bar now carries the same five items"
  note. Moves: **Discover** is no longer a tab (its search became the
  **Search takeover** — the bar itself becomes the field, suggestions fill the
  screen); **Podcasts → Shows**; a new **Home** landing feed leads (Up Next
  peek · new episodes · shows for you · our favorites); **Downloads** left the
  bar (download state + button now inline on Up Next rows; a Manage-downloads
  section comes to Settings later); **Settings** moved to a top-right gear.
  Kit: rebuilt `tab-bar.html` (new Home + Search glyphs + takeover variant);
  added `home`, `shows`, `up-next`; renamed the Discover states to
  `search-{start,typing,loading,noresults,error}`; `settings-sources` is now a
  pushed screen; `first-run` (the onboarding wizard, previously grouped under
  "Discover") keeps its role and just adopts the four-item bar. Design kit
  first; the SwiftUI translation follows as a separate pass.
- **Sources picker removed; Settings = downloads (2026-07-06).** Feedback: axe
  all in-app notion of *changing* search sources. The Sources screen
  (`settings-sources.html`, its Apple/PodcastIndex checklist + search-order UI)
  was deleted and replaced by a general **`settings.html`** whose only section
  for now is **Manage downloaded episodes** — a list of downloaded episodes,
  each with a Remove control that deletes the local audio (the episode stays in
  the feed). Also this round: the iOS large-title **condense-on-scroll header**
  was removed from Home/Shows/Up Next (the dock already tells you where you are;
  the top-right gear stays pinned); the search-results **top-result** circular
  subscribe glyph was re-centered; and the top-right **Settings glyph** reverted
  to the sliders/toggles icon it used as a tab. **Source model decided:** v1
  uses **Apple only** — keyless, zero-config, no source picker, no sources list
  in Settings. **PodcastIndex** is deferred to a later milestone. §12 and
  ROADMAP updated to match. DirectoryKit still carries `PodcastIndexSource` +
  the fallback coordinator as dormant groundwork; removing the in-app
  **Sources** screen (`SourcesView.swift`) and trimming the live roster to
  Apple is part of the pending SwiftUI pass.
- **Podcast Detail screen — real data + story arcs (2026-07-06).** The kit gained
  its first Podcast Detail screen (`podcast-detail-<slug>.html`), reversing main's
  "composed, no kit mock" note for E2. Feedback fixes: the oversized Download /
  Add-to-Up-Next buttons became **compact icon controls**; the redundant
  "Downloaded" text is now icon-only; rows show **season/episode + publish date +
  duration**. New differentiator: **story arcs** — episodes grouped into named
  narrative series with **"Add all"** (queue the whole arc). Built from **real feed
  data**: `scripts/fetch-podcast-episodes.py` pulls the RSS and derives arcs from
  title structure (`Arc | Title | N` and `Arc - Part N`); `design/kit/build-detail.py`
  renders the screen. Two live examples — **American History Tellers** (has
  `<itunes:season>` → season badges + S·E) and **The Explorers Podcast** (no season
  tags → arc·Part, graceful degrade). **Swift follow-ups** (later, on `main`): parse
  `<itunes:season>` / `<itunes:episode>` / `<itunes:episodeType>` in `FeedParser.swift`;
  add `season` / `episodeNumber` (+ a derived-arc field) to `Episode`; reconcile
  `PodcastDetailView` to this design (compact controls, arcs shelf, add-all — this
  reconcile is in progress on this branch).

---

## 12. Search sources & navigation

Search uses **Apple's podcast directory**. There is no in-app source picker.

**Navigation.** A **floating Liquid Glass tab bar** (iOS 26 style) carries
four destinations — **Home**, **Shows**, **Up Next**, and **Search**. It
floats inset from the screen edges (`left/right: 12px; bottom: 22px`, radius
30) over a `--tabbar-glass` blur with a `--tabbar-hairline` edge and
`--tabbar-shadow`. `.content` reserves 104px of bottom padding so the last
row clears the bar.

**Search takeover.** There are no inline search boxes. Tapping **Search**
collapses the icons and the same glass bar becomes a search field — **Home
stays pinned on the left**, a **✕** cancels on the right — and in-app it
detaches from `bottom: 22px` to rise just above the keyboard while the screen
fills with suggestions/results (the old Discover whitespace). The takeover
reuses the locked `--field` / `--r-field` tokens inside the bar.

**Settings & downloads off the bar.** **Settings** is reached from a
**top-right gear** on Home/Shows/Up Next and pushed over the current tab
(with a Done affordance), not a tab. **Downloads** is no longer a
destination: each **Up Next** row shows whether the episode is downloaded and
a visible **download button**. **Settings** carries one section — **Manage
downloaded episodes** (a list of downloads, each with a Remove control that
deletes the local audio; the episode stays in the feed).

**Source model (v1).** Search runs against **Apple's iTunes podcast
directory** — keyless, zero-config, always on. There is **no source picker**,
and **Settings carries no sources list**. **PodcastIndex** may be added as an
optional second source in a later milestone (it would bring its own key
handling); it is out of scope for v1's UI.
