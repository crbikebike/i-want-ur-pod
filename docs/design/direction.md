# i want ur pod — Design Direction

**Direction:** Playful Pulse, iOS-native (inspired-original).
**Identity:** coral primary + mint secondary, rounded system type, animated
equalizer/pulse accents, gradient artwork tiles, first-class iOS chrome.

This is the single source of truth. The locked base is
`design/directions/d2-native/index.html`. Every kit file
(`design/kit/**`) carries a **byte-identical color-role token block** — do
not fork hues per file.

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
| `--tabbar-icon` | `#8B8291` |

### Light

| Role | Value |
|---|---|
| `--bg` / `--grouped-bg` | `#F2F1F6` |
| `--surface` | `#FFFFFF` |
| `--surface-2` | `#F6F1EC` |
| `--text` | `#1A1420` |
| `--text-dim` | `#6B6472` |
| `--text-faint` | `#736A78` |
| `--accent` | `#CA340F` (coral-deep) |
| `--accent-2` | `#046B58` (mint-deep) |
| `--on-accent` | `#FFFFFF` |
| `--hairline` | `rgba(40,26,36,.10)` |
| `--separator` | `rgba(60,60,67,.18)` |
| `--chip` | `rgba(118,118,128,.12)` |
| `--seg-track` | `rgba(118,118,128,.16)` |
| `--seg-thumb` | `#FFFFFF` |
| `--field` | `rgba(118,118,128,.10)` |
| `--bar-material` | `rgba(248,246,250,.78)` |
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

---

## 3. Type scale

System rounded stack — no web fonts:

```
--font: ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont,
        "Segoe UI", system-ui, sans-serif;
```

| Role | Size | Weight | Tracking |
|---|---|---|---|
| Large title | 2.32rem | 800 | -0.02em |
| Section (h2) | 1.34rem | 800 | -0.015em |
| Nav title (inline) | 1.06rem | 800 | -0.01em |
| Row title | 1rem | 700 | -0.01em |
| Body / input | 1rem | 500 | — |
| Subhead / author | 0.82rem | 500 | — |
| Provider label | 0.74rem | 700 | 0.04em, uppercase |
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
tab-bar clearances in `.content` padding (`54`/`116`), the 60px artwork size,
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
named token. The segmented-control **inner** radius (button + thumb) is
`calc(var(--r-seg) - 2px)` = 7 — the standard nested-corner (track radius
minus the 2px track inset), so it stays coupled to `--r-seg`.

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
  Downloads = tray-down (from the locked base).
- State badges (empty/no-results/error) are 84px rounded-square gradient
  tiles with a white glyph — decorative, so contrast rules don't gate the
  glyph.
- Artwork placeholders are **CSS gradient tiles** (`.a1`–`.a6`) with a bold
  white initial glyph and an inset highlight — no raster images.
- Equalizer bars and the pulse-dot are the identity motifs; reuse them
  sparingly (eyebrow, inline nav, section captions).

---

## 10. Component & screen inventory

- **Foundations:** `tokens.html`.
- **Components:** app-shell, search-field, provider-picker, result-row,
  result-card, subscribe-button (default / subscribing / subscribed),
  section-header, buttons (primary / secondary / ghost), loading-skeleton,
  empty-prompt, no-results, error.
- **Discover screens (iPhone-framed):** first-run, typing, loading,
  results, no-results, error, provider-switched.

Every screen keeps the same header stack (large title → search → provider
segmented control) so the source-of-truth chrome is identical across
states; only the results region changes.

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
- Segmented-thumb position for `provider-switched` is set via inline style
  as a fallback; confirm the base thumb JS re-measures on load in the
  target renderer.
- **Artwork 14px radius — RESOLVED.** Promoted to `--r-art: 14px` (added
  byte-identically to every kit file's radii block) and referenced by `.art`
  and `.sk-art`. The locked-base chrome no longer hardcodes rhythm/radii px:
  spacing uses `--sp-*`, radii use `--r-*`, the segmented inner corner uses
  `calc(var(--r-seg) - 2px)`, and the row separator inset uses a `calc()` of
  tokens. Only device-chrome clearances (`54`/`116`), the 60px art size, and
  the 2px optical inset remain intentional raw constants.
- Voice/mic affordance is visual only; no dictation behavior specified yet.
