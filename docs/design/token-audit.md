# Design-Token Reconciliation Report

Read-only synthesis across four kit-surface extractions (search-screens, detail-screens, landing-screens, components), the existing tokens.html-vs-Swift baseline, and the Swift magic-number sweep. All px values are rem×16. No code changes proposed here — this is the sign-off document for Phase 2.

---

## 1. Type scale reconciliation

### 1a. Roles with an exact Swift token already (✅ — no action needed)

| Role | px / weight / face / tracking / uppercase | Kit selectors observed | Swift token |
|---|---|---|---|
| Large title | 37.12 / 800 / mono / ‑0.742pt(≈‑.02em) / no | `h1.big` | `Typography.displayLargeTitle` |
| Section header | 21.44 / 800 / mono / ‑0.322pt(≈‑.015em) / no | `.sec-head h2`, `.gh-title` | `Typography.section` |
| Nav bar inline title | 16.96 / 800 / mono / ‑0.170pt(≈‑.01em) / no | `.nav-title`, `.navbar .nav-title` | `Typography.navTitle` |
| Row title | 16 / 700 / ui / ‑0.160pt(≈‑.01em) / no | `.row .rtitle`, `.opt-name`, `.src-name` | `Typography.rowTitleStyle` |
| Body | 16 / 500 / ui / 0 / no | `.tb-field input`, `.search input`, `.tb-field input` | `Typography.body` |
| Subhead | 13.12 / 500 / ui / 0 / no | `.sec-sub`, `.row .rauthor`, `.src-sub`, `.src-pitch`, `.tr-author`* | `Typography.subheadStyle` |
| Eyebrow | 11.52 / 800 / ui / 1.382pt(.12em) / **yes** | `.eyebrow`, `.stage-cap` | `Typography.eyebrow` |
| Tag chip | 10.24 / 800 / ui / 0.205pt(.02em) / **yes** | `.row .tag`, `.pcard .tag` | `Typography.tag` |
| Tab bar label | 9.92 / 600 / ui / 0.099pt(.01em) / no | `.tab` | `Typography.tabLabel` |
| Badge | 9.92 / 800 / ui / 0.397pt(.04em) / **yes** | `.pin`, `.tag-open` | `Typography.badge` |
| Shelf title | 18.88 / 800 / mono / ‑0.283pt(≈‑.015em) / no | `.shelf-head .sh-title` (components extraction only — see Conflict #2) | `Typography.shelfTitle` |

\* `.tr-author` (13.44px) is 0.32px larger than `subhead` (13.12px) — a clean `.84rem` vs `.82rem`, not rounding noise. Recommend verifying against the kit source before folding it into `subheadStyle`; if confirmed distinct, promote as its own token (see 1b).

### 1b. Real recurring roles with **no** Swift token (➕ promote)

| Proposed token | Spec (px/weight/face/tracking/uppercase) | Kit roles it covers | Notes |
|---|---|---|---|
| `Typography.countBadge` | 11.84 / 800 / ui / 0 / no | `.sec-head .count` (search, detail, landing, components — consistent) | Currently hardcoded raw at `SectionHeader.swift:86` (sweep #9) |
| `Typography.shelfBadge` | 11.52 / 800 / ui / 0 / no | `.shelf-head .sh-count`, `.ep-played` | Distinct from `eyebrow` (same size but no tracking/uppercase) |
| `Typography.metaEmphasis` | 12.48 / 800 / ui / 0 / no | `.gh-count`, `.ep-arc` | `.ep-arc` additionally carries accent‑2 color, not a type distinction |
| `Typography.pillButtonLabel` | 12.8 / 800 / ui / 0.01em / no | `.sub` (subscribe pill), `.arc-add` | Sweep #6 shows `TopResultCard` faking this via `subheadStyle+.heavy` (wrong size, 13.12 vs 12.8); sweep #8 confirms no dedicated token exists |
| `Typography.heroTitle` | 17.28 / 800 / ui / ‑0.01em / no | `.tr-title` (top-result hero card) | Sweep #7: currently misuses `rowTitleStyle` (16/700) |
| `Typography.heroAuthor` | 13.44 / 500 / ui / 0 / no | `.tr-author` | See footnote above — verify vs. folding into `subhead` |
| `Typography.stateTitle` | 20.48 / 800 / mono / ‑0.015em / no | `.state-title` (empty/error states) | Consistent value across search-screens and components |
| `Typography.stateSub` | 14.72 / 500 / ui / 0 / no | `.state-sub` | Consistent |
| `Typography.buttonLabel` | 15.2 / 800 / ui / 0.01em / no | `.btn`, `.btn-primary/.secondary/.tertiary/.ghost` | Widely reused CTA label across every surface |
| `Typography.podcastDetailTitle` | 20.48 / 800 / ui / ‑0.02em / no | `.pd-title` | Face is `ui`, **not** mono — explicitly excluded from the title-override rule per detail-screens notes |
| `Typography.categoryLabel` | 11.52 / 800 / ui / 0.07em / **yes** | `.pd-cat` | Same size/weight as `eyebrow` but **different tracking** (0.07 vs 0.12em) — real distinct role, not a duplicate (see Conflict #8) |
| `Typography.detailAuthor` | 14.08 / 600 / ui / 0 / no | `.pd-author` | No existing match |
| `Typography.detailBody` | 14.08 / 400 / ui / 0 / no | `.pd-desc` | Only 400-weight body-copy role in the whole scale |
| `Typography.expandLabel` | 13.12 / 800 / ui / 0 / no | `.pd-more` | Same size as `subhead` at heavier weight |
| `Typography.arcCardTitle` | 14.72 / 800 / ui / ‑0.01em / no | `.arc-name` | Sweep #2: currently misuses `rowTitleStyle` (16/700 — wrong on both axes) |
| `Typography.arcCardMeta` | 12.16 / 600 / ui / 0 / no | `.arc-parts` | Sweep #3: currently misuses `subheadStyle` (13.12/500 — wrong on both axes) |
| `Typography.seasonBadge` | 10.88 / 800 / ui / 0 / no | `.arc-season` | Sweep #1: currently hardcoded `10.9` (rounding slip) |
| `Typography.episodeTitle` | 15.68 / 700 / ui / ‑0.01em / no | `.ep-title` | No existing match |
| `Typography.episodeMeta` | 12.48 / 600 / ui / 0 / no | `.ep-meta` | Apply `.fontWeight(.heavy)` + accent‑2 color override for `.ep-arc` rather than a second token |
| `Typography.linkAction` | 13.12 / 800 / ui / 0.01em / no | `.see-all`, likely `.pd-more` | `.pd-more` tracking unconfirmed — verify before merging |
| `Typography.metaLine` | 12.8 / 500 / ui / 0 / no | `.sug .s`, `.pcard-author`, `.opt-meta`, `.pod-studio`* (components value) | *See Conflict #3 — `.pod-studio` reported at both 12.48 and 12.8 across surfaces |

### 1c. Swift hardcodes it / maps to a near-miss token (⚠️ — fix call sites)

| # | File:line | Current Swift | Should be | Root cause |
|---|---|---|---|---|
| 1 | `PodcastDetailView.swift:300` | `.system(size: 10.9, weight: .heavy)` | `Typography.seasonBadge` (10.88/800) | Hand-computed rounding slip |
| 2 | `PodcastDetailView.swift:248-250` | `Typography.rowTitleStyle` (16/700) | `Typography.arcCardTitle` (14.72/800) | Nearest-token substitution, undocumented |
| 3 | `PodcastDetailView.swift:257-259` | `Typography.subheadStyle` (13.12/500) | `Typography.arcCardMeta` (12.16/600) | Same pattern |
| 4 | `PodcastDetailView.swift:315` | icon `.system(size: 13, weight: .heavy)` | 15×15pt frame to match kit `.arc-add svg` | Icon size drift |
| 5 | `SearchResultRow.swift:166` | bespoke `.shadow(alpha: 0.28, radius: 12, y: 8)` | `.elevList(hairline:)` (alpha 0.5) | Duplicated + wrong alpha; system helper already exists and is used elsewhere |
| 6 | `TopResultCard.swift:102-103` | `subheadStyle` (13.12/500) `+ .heavy` | `Typography.pillButtonLabel` (12.8/800/0.01em) | No dedicated token existed |
| 7 | `TopResultCard.swift:47-48` | `Typography.rowTitleStyle` (16/700) | `Typography.heroTitle` (17.28/800) | Wrong token reused |
| 8 | `TopResultCard.swift:90, 98` | icon `.system(size: 13, weight: .bold)` | 15×15pt frame to match kit `.sub .ico svg` | Same icon-size drift as #4; inconsistent with `SubscribeButton.swift:197/204` which already gets this right |
| 9 | `SectionHeader.swift:86` | raw `.system(size: 11.84, weight: .heavy)` | `Typography.countBadge` | Byte-exact value but bypasses the token system — silent-drift risk |
| 10 | `SearchResultRow.swift:62` | `Radius.rSm12` (12) for a 10px kit radius | documented, disclosed compromise — no action required | Already self-flagged in-file; lowest priority |

### 1d. Additional single-use / low-priority roles (appendix — first-run & settings screens)

These appear once each, in `first-run.html` or `settings.html`, and don't currently show up in the magic-number sweep. Recommend deferring — bundle into Phase 2 only if those screens are actively being built:

`.dl-total` 13.12/700, `.dl-title` 15.2/800/‑0.01em, `.dl-sub` 12.8/500, `.done-btn` 16/800, `.steps-ol .num` 14.4/800, `.steps-ol li>div` 15.2/500, `.dropzone` 14.72/700, `.pick-name` 12.48/700, `.topic` 15.2/700, `.ob-sub` 15.68/500, `.ob-skip` 14.4/700, `.key-hint` 11.84/600, `.addkey` 13.76/800/0.01em, `.linkbtn` 12.48/700, `.foot` 12.16/500 (see Conflict #9), `.gh-count` — already covered above as `metaEmphasis`.

Decorative-only (not typography, exclude from type scale): `.art/.pod-art/.pcard-art .glyph` (23.2/32/41.6px, weight 900) — placeholder-letter glyphs already governed by `GradientArtwork`'s proportional scaling per the sweep's excluded list. `.sk-line` (11px) is a skeleton bar height, not text.

---

## 2. Radii / Spacing / Color / Elevation

### Radii
All seven Swift `Radius.swift` tokens (`rSm12`=12, `rSeg9`=9, `rField11`=11, `rArt14`=14, `rMd16`=16, `rLg20`=20, `rPill999`=999) match the kit exactly — no changes needed.

Kit radii with **no** Swift token:
- **26px** — `.state-badge` (empty/error icon tile). Propose `Radius.rBadge26`.
- **13px** — `.src-ico`/`.opt-ico` (source & onboarding icon tiles). 1px off `rSm12`. Propose `Radius.rIcon13`, or accept as a documented compromise like the existing 10px avatar case (`SearchResultRow.swift:62`).
- **10px** — `.sug-av` avatar. Already disclosed as an accepted `rSm12` compromise (sweep #10) — no action.
- **30px / 18px / 54px** — tabbar / notch / phone-frame corners. Device chrome, not app content — exclude.
- **6px** — `.sk-line` skeleton radius. Low priority (loading state only).
- **50px** (perfect circle, `.sub` icon-circle variant, `.grid-back`) — achieved via `frame/2`, not a fixed-radius token — exclude.

### Spacing
All seven `Spacing.swift` tokens (`sp1`–`sp7`: 4/8/12/16/20/26/32) match the kit exactly.

Recurring off-scale spacing values worth arbitrating (not structural sizes, which are correctly excluded per the sweep):
- **9px** — pod-card internal gap (art→title→studio). Appears identically in search-screens, landing-screens, and components. Strong promotion candidate — recommend `Spacing.sp2b` or similar half-step, or accept as a documented one-off given it recurs identically everywhere (low risk either way).
- **10px** — count-badge h-padding, existing-app option-card gaps, topic-chip gaps, favorite-picker grid gap.
- **14px** — option-card h-padding, subscribe-pill h-padding, theme-toggle h-padding.
- **3px / 6px / 24px / 44px** — tag v-padding, search-field trailing padding, OPML dropzone padding, minimum tap-target height respectively.

None of these are currently flagged as Swift bugs — this is a "does the scale need an extra step" question for the user, not a correctness issue.

### Color
- **Dark theme**: every Theme.swift role matches tokens.html exactly — no action.
- **Light theme**: `bg`/`groupedBg`, `surface2`, `chip`, `segTrack`, `field` diverge between Swift and tokens.html. Per `Theme.swift`'s own comment this is *intentional* (direction.md §11 supersedes tokens.html for light neutrals) — but the two source docs are themselves out of sync. Repeated here as **Conflict #5** below since it's the largest confirmed doc-vs-doc gap and needs explicit user sign-off, not just a code fix.
- Structural overlay/shadow colors on artwork tiles (`rgba(255,255,255,.14/.16/.18/.28/.42)`, `rgba(0,0,0,.22/.28/.3/.35/.5/.55/.6)`) are formulaic per tile size and already appear to be handled by `ArtworkTile`'s elevation formula (see Elevation below) rather than needing individual Theme color tokens.
- Placeholder gradients (`.a1`–`.a6`, onboarding `.opt-ico[style]`) are per-instance brand colors, not shared tokens — no action needed beyond confirming `GradientArtwork`'s existing palette matches these six stops.

### Elevation
Baseline already confirms `elevList`, `elevCard`, and `elevPop` match the kit formulaically (`radius = blur/2`, alpha preserved). One confirmed disagreement:

- **`elevSub`**: kit CSS shadow `0 6px 14px -8px var(--accent)` uses the accent color at **full opacity**; Swift's `Elevation.swift` applies `.opacity(0.9)` to the accent before shadowing. **Conflict #6** below.

New elevation family worth formalizing — the "art tile" shadow pattern recurs with only inset-highlight alpha and blur/y varying by tile size:

| Proposed case | Value | Kit tile |
|---|---|---|
| `elevArtThumb` | inset `rgba(255,255,255,.16)` + `0 3px 8px -5px rgba(0,0,0,.5)` | `.sug-av`, `.dl-art`, episode thumbnails |
| `elevArtSmall` | inset `rgba(255,255,255,.16)` + `0 4px 10px -6px rgba(0,0,0,.5)` | `.art` (60px row art), `.pcard-art` |
| `elevArtMedium` | inset `rgba(255,255,255,.16)` + `0 8px 20px -12px rgba(0,0,0,.55)` | `.pod-art` (rail/poster, 138–150px) |
| `elevArtHero` | inset `rgba(255,255,255,.14)` + `0 8px 20px -10px rgba(0,0,0,.6)` | `.pd-art` (podcast-detail hero, 118px) |

---

## 3. Conflicts to arbitrate

These are genuine disagreements *inside the extraction data itself* (kit-vs-kit) or between kit and existing docs — none can be safely auto-resolved; each needs a user decision before Phase 2 locks the token set.

**#1 — Mono title weight: 800 or 700?**
Three of four surface extractions (search-screens, detail-screens, components) record `.sec-head h2`/`.nav-title`/`.state-title`/`.gh-title`/`h1.big` at **weight 800**, matching Swift's shipped values exactly. The landing-screens extraction instead argues a shared override rule (`h1.big, .sec-head h2, .nav-title, ... { font-weight: 700 }`) wins on CSS cascade order (equal specificity, later in source) — matching legacy tokens.html's 700 scale.
*Recommendation:* verify against actual computed styles in the rendered kit HTML (not deducible from static extraction alone). 3-of-4 independent extractions + already-shipped Swift code lean 800; tentatively keep 800 pending that check.

**#2 — `.shelf-head .sh-title` size: 18.24px or 18.88px?**
search-screens and landing-screens report **18.24px** (1.14rem); components reports **18.88px** (1.18rem), which matches Swift's `shelfTitle` token exactly. Could be a genuine two-context split (compact rail shelves vs. grid/discover shelves) rather than an extraction error.
*Recommendation:* confirm against raw kit source; if two contexts exist, split into `shelfTitle` (18.88) and `shelfTitleCompact` (18.24) rather than forcing one value.

**#3 — `.pod-title` / `.pcard-title` size+weight mismatch across files.**
`.pod-title`: 14.72px (search/landing) vs 15.36px (components). `.pcard-title`: 15.68px/800 (landing) vs 15.36px/700 (components). Likely two different card contexts labeled with overlapping class names by different kit files rather than one canonical size.
*Recommendation:* confirm against raw kit source whether rail-card and grid-card titles are meant to diverge; if so, keep as two tokens (e.g. `railCardTitle` vs `gridCardTitle`).

**#4 — `.pod-studio` size: 12.48px or 12.8px?**
Minor (0.32px) but a clean rem-step difference (.78rem vs .8rem), reported both ways across surfaces. Low-stakes; recommend picking 12.8 to align with `metaLine` (§1b) unless the raw source says otherwise.

**#5 — Light-theme neutrals: tokens.html or direction.md §11?**
`bg`/`groupedBg`, `surface2`, `chip`, `segTrack`, `field` differ between Swift (matches direction.md) and tokens.html. `Theme.swift`'s comment already asserts direction.md wins, but tokens.html itself hasn't been updated to match — leaving two "spec" documents in disagreement.
*Recommendation:* formally deprecate/update tokens.html's light-neutral rows to match direction.md §11, or restate explicitly that tokens.html is legacy-only for this section.

**#6 — `elevSub` accent opacity: 0.9 (Swift) or 1.0 (kit CSS)?**
Visual call — does the subscribe-button glow read better dimmed or full-strength? Needs a side-by-side visual check, not a numeric one.

**#7 — `groupLabel` (Swift) vs `provider` (tokens.html): same role renamed, or two roles?**
Swift: 11.52/800/ui/.06em uppercase. tokens.html: 11.84/700/ui/.04em uppercase. None of the four kit-screen extractions turned up a `.provider` or `.groupLabel`-equivalent class directly — both values are currently unverified against live kit markup.
*Recommendation:* locate the kit source class this token is meant to represent before deciding; it may be orphaned on one or both sides.

**#8 — `.pd-cat` (0.07em) vs `.eyebrow` (0.12em): same size/weight, different tracking.**
Both are 11.52/800/ui/uppercase. Confirm this tracking split is an intentional (category label reads slightly tighter than a page eyebrow) rather than a kit inconsistency — if intentional, keep as two tokens (`categoryLabel` vs `eyebrow`); if not, they should collapse to one.

**#9 — Footnote role: 12.16px (`.foot`, landing) or 12.48px (`.foot-note`, components)?**
Same conceptual role (small explanatory copy under a list), two different kit files, two different sizes. Pick one canonical `footnote` token or keep both as context-specific.

---

## 4. Proposed authoritative token set (Phase 2)

### `Typography.swift` — new cases
```
countBadge        11.84 / .heavy / ui   / tracking 0        / not uppercase
shelfBadge         11.52 / .heavy / ui   / tracking 0        / not uppercase
metaEmphasis        12.48 / .heavy / ui   / tracking 0        / not uppercase
pillButtonLabel      12.8  / .heavy / ui   / tracking .01em    / not uppercase
heroTitle            17.28 / .heavy / ui   / tracking -.01em   / not uppercase
heroAuthor*           13.44 / .medium/ ui   / tracking 0        / not uppercase   (*pending Conflict resolution — may fold into subhead)
stateTitle           20.48 / .heavy / mono / tracking -.015em  / not uppercase
stateSub             14.72 / .medium/ ui   / tracking 0        / not uppercase
buttonLabel           15.2  / .heavy / ui   / tracking .01em    / not uppercase
podcastDetailTitle    20.48 / .heavy / ui   / tracking -.02em   / not uppercase
categoryLabel         11.52 / .heavy / ui   / tracking .07em    / uppercase
detailAuthor          14.08 / .semibold / ui / tracking 0     / not uppercase
detailBody            14.08 / .regular / ui / tracking 0      / not uppercase
expandLabel            13.12 / .heavy / ui   / tracking 0        / not uppercase
arcCardTitle           14.72 / .heavy / ui   / tracking -.01em   / not uppercase
arcCardMeta            12.16 / .semibold / ui / tracking 0     / not uppercase
seasonBadge            10.88 / .heavy / ui   / tracking 0        / not uppercase
episodeTitle           15.68 / .bold / ui    / tracking -.01em   / not uppercase
episodeMeta            12.48 / .semibold / ui / tracking 0     / not uppercase
linkAction             13.12 / .heavy / ui   / tracking .01em    / not uppercase
metaLine               12.8  / .medium/ ui   / tracking 0        / not uppercase
```
(`shelfTitleCompact` at 18.24 to be added only if Conflict #2 resolves to a two-token split.)

### `Radius.swift` — new cases
```
rBadge26   26   // .state-badge
rIcon13    13   // .src-ico / .opt-ico  (pending Conflict resolution vs. rSm12 compromise)
```

### `Elevation.swift` — new cases
```
elevArtThumb    inset rgba(255,255,255,.16) + 0 3px 8px -5px rgba(0,0,0,.5)
elevArtSmall    inset rgba(255,255,255,.16) + 0 4px 10px -6px rgba(0,0,0,.5)
elevArtMedium   inset rgba(255,255,255,.16) + 0 8px 20px -12px rgba(0,0,0,.55)
elevArtHero     inset rgba(255,255,255,.14) + 0 8px 20px -10px rgba(0,0,0,.6)
```
Plus the `elevSub` opacity fix once Conflict #6 is resolved.

### `Theme.swift` — pending Conflict #5 (light-neutral doc sync); no code changes until user picks canonical source.

### `Spacing.swift` — no changes recommended unless user wants to formalize the 9px pod-card gap as a named half-step (optional, low risk either way).

---

## 5. Call-site sweep summary (Phase 2 fix list)

**Detail feature (`IWantUrPod/Detail/PodcastDetailView.swift`)**
- Line 300: `10.9` → `Typography.seasonBadge` (fixes rounding slip)
- Lines 248-250: `rowTitleStyle` → `Typography.arcCardTitle`
- Lines 257-259: `subheadStyle` → `Typography.arcCardMeta`
- Line 315: icon size `13` → `15` (match kit SVG)

**Search feature (`IWantUrPod/Search/`)**
- `SearchResultRow.swift:166`: bespoke shadow → `.elevList(hairline:)`
- `TopResultCard.swift:102-103`: `subheadStyle + .heavy` → `Typography.pillButtonLabel`
- `TopResultCard.swift:47-48`: `rowTitleStyle` → `Typography.heroTitle`
- `TopResultCard.swift:90, 98`: icon size `13` → `15`
- `SearchResultRow.swift:62`: no change — disclosed, accepted compromise

**Design System (`Packages/DesignSystem/Sources/DesignSystem/Components/SectionHeader.swift`)**
- Line 86: raw `.system(size: 11.84, weight: .heavy)` → `Typography.countBadge`

All ten items are read-only findings pending this sign-off; no fixes have been applied.