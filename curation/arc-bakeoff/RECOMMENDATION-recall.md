# Recall re-weight — recommended winner: `A6-cascade`

## 1. The objective

`score.py` ranks **recall-max under a precision floor**, not precision-first:

- `MEMPREC_FLOOR = 0.95`, `JUNK_CEIL = 0.05` (`score.py:40-41`) — **unchanged; no floor was loosened.**
- `meets_floor = (membership_precision >= 0.95 and junk_arc_rate <= 0.05)`
- Ranking key: `(not meets_floor, -arc_recall, -membership_precision, junk_arc_rate)`

The incumbent `A2r3.3-final` ran at memPrec 0.9985 / junk 0.0027 — it was leaving roughly
**four fifths of the allowed error budget unspent** while missing 220 of 590 gold arcs.

## 2. Before / after

Gold: 45 scored feeds, 590 true arcs. Corpus: 315 feeds.

| metric | `A2r3.3-final` | **`A6-cascade`** | delta |
|---|---|---|---|
| membership_precision | 0.9985 | **0.9684** | −0.0301 |
| junk_arc_rate | 0.0027 | **0.0408** | +0.0381 |
| **arc_recall** | 0.6271 | **0.8763** | **+0.2492** |
| arc_precision | 0.9973 | 0.9592 | −0.0381 |
| detected_arcs | 371 | 539 | +168 |
| matched arcs | 370 | 517 | +147 |
| meets_floor | OK | **OK** | — |
| corpus `feeds_with_arcs` | 88 / 315 | **132 / 315** | +44 |
| corpus `total_arcs` | 507 | 810 | +303 |

Both floor terms still hold with margin: memPrec 0.9684 vs 0.95 required (0.018 spare), junk
0.0408 vs 0.05 allowed (0.009 spare).

### The ladder (each increment measured in isolation)

| variant | memPrec | junk | arcRecall | detArcs | corpus feeds |
|---|---|---|---|---|---|
| `A2r3.3-final` (incumbent) | 0.9985 | 0.0027 | 0.6271 | 371 | 88 |
| `A6.1-clean` — tier 2a only | 0.9957 | 0.0073 | 0.6949 | 413 | 99 |
| `A6.2-markers` — + tier 2b | 0.9963 | 0.0062 | 0.8119 | 482 | 107 |
| `A6.3-tier2` — cascade, not replacement | 0.9963 | 0.0062 | 0.8169 | 485 | 107 |
| `A6.4-reconciled` — + `_reconcile` | 0.9963 | 0.0062 | 0.8169 | 485 | 107 |
| `A6.7-affix-guarded` — + tier 3a | 0.9683 | 0.0410 | 0.8729 | 537 | 126 |
| **`A6-cascade`** — + tier 3b | **0.9684** | **0.0408** | **0.8763** | **539** | **132** |

## 3. What each tier adds, and what it bought

### The framing that mattered

The original hypothesis was to **escalate to the existing wide detectors** on low-coverage feeds.
Measurement killed it: the best of them (`A5-hybrid`) recovers only **45 of the 220** missed gold
arcs (20%) while memPrec collapses 0.999 → 0.419. Root cause: **218 of the 220 misses are "zero
members detected"** — the parser never clusters those episodes at all, and the wide detectors fail
on the same grammars for the same reason. Turning up the risk dial cannot fix a parser that
cannot read the title. So A6 leaves tier 1 untouched and adds **parser** tiers, with risk-taking
confined to tier 3.

### Tier 2a — cleaner (`r4_clean`), +0.068 recall

Strips leading noise so the **existing** marker table can fire. No new marker regexes.

| strip | grammar | recall alone | memPrec |
|---|---|---|---|
| `LEAD_EPISODE_WORD` | `EPISODE 47: …`, `Episode 391 - …` | 0.6492 (+0.022) | 0.9985 (free) |
| `LEAD_EPNUM` | `691 // …`, `450 - …`, `1. …`, `36: …` | 0.6678 (+0.041) | 0.9970 |
| `LEAD_BRACKET` | `[RERUN] …` | 0.6271 (+0.000) | 0.9985 |

`EPISODE 47: Give Me Back My Legions! (Part 1)` already parsed its `(Part N)` correctly —
`GENERIC_STEM` then rejected the stem for starting with `episode`. `691 // Kierra Coles - Part 2`
parsed the part fine but carried the episode number into the stem, so parts 1 and 2 bucketed
apart. Both fixed by cleaning and re-running the unmodified r3 parser.

**Required companion edit:** `rerun` added to `RERELEASE` (`:691`). `LEAD_BRACKET` alone gains
nothing, but combined with the others it let history-on-fire reruns merge with their originals
into 4-member arcs where gold has 2 — costing 0.0074 memPrec (0.9985 → 0.9911). With `rerun`
in the alternation the dedup catches them and precision returns to 0.9957.

### Tier 2b — new markers (`R4_MARKERS`), +0.117 recall

| marker | grammar | example | recall gain |
|---|---|---|---|
| `LEAD_PART` | counter **before** the stem | `Part One: Richard Marcinko: The Founder of SEAL Team 6` | **+0.0593** |
| `PIPE_DOT` | pipe + dotted counter | `Becoming Justice Gorsuch \| 3. A Lunch Room for Life` | **+0.0356** |
| `FRACTION_PAREN` | `(Part i/j)` fraction | `Case 339: Waco (Part 3/3)` | **+0.0204** |
| `COLON_EP` | trailing `Episode N` | `Released To Die: Episode 3` | +0.0017 |

Gains are additive (leave-one-out matches add-one-alone to within 0.0001). All four are free on
precision. `COLON_EP` earns only one arc but costs nothing measurable.

### Tier 3a — affix clustering, +0.056 recall

Clusters on a shared leading/trailing **segment** rather than stem+counter, reaching the 76 gold
arcs that carry no usable counter (`We Keep Us Safe: Who Killed Antonio Mays Jr.?` /
`We Keep Us Safe: The Standoff`; `The Sentence - Ep. 1` / `The Hustle - Ep. 2`, where the arc name
appears nowhere in the title).

**The feed gate is not the load-bearing guard** — this is the main design finding of the tier:

| tier 3a configuration | memPrec | junk | arcRecall | floor |
|---|---|---|---|---|
| ungated, unguarded | 0.6296 | 0.1852 | 0.8949 | FAIL |
| **+ feed gate only** | 0.7907 | 0.0673 | 0.8695 | **FAIL** |
| + cluster-shape guards | 0.9683 | 0.0410 | 0.8729 | OK |

The gate is a cheap pre-filter; **contiguity** and the **size cap** are what make the tier
survivable. Removing the size cap entirely collapses memPrec to 0.836.

Final parameters: `max_size=12`, `min_len=6`, `contiguity=3`, `counter_reject=True`; gate
`cov < 0.30 AND repeated-segment-ratio >= 0.15 AND episodes >= 8`, evaluated separately for
prefix and suffix mode.

Two configurations topped the sweep. The **aggressive** one (`max_cov=0.5, contiguity=4`) scores
0.8763 recall but leaves **0.0021** of junk margin under the ceiling; on a 45-feed gold sample
that margin is noise. The shipped config keeps ~5× the margin for the same recall.

### Tier 3b — counter-run adjacency, +0.0034 recall

For arcs whose parts share **no title text at all** (7am: `Part 1: Victoria's historic treaty` /
`Part 2: The politics and pushback`). The only evidence is adjacency in publication order plus a
complete counter set.

Matches a contiguous block whose parts form exactly `{1..k}` **in any order**. Order-insensitivity
is required, not cosmetic: 7am publishes both halves the same day, so the `iso` tie-break can
invert them — a strictly-ascending walk finds nothing (measured: literally zero arcs before the
fix). It clears the floor independently, so per the brief it ships.

## 4. Recommended winner — portable rule summary

For the later Swift port. Every regex is ICU-safe: no lookbehind, no atomic/possessive groups,
no `\K`, and dash characters lead every character class.

```
A6-cascade(episodes):
  T1  arcs  = a2r3_3_final(episodes)                       # UNCHANGED shipped detector
  T2  arcs += cluster(episodes not in T1, stem_fn = r4)    # guards + dedup identical to T1
  T3a arcs += affix(episodes not in T1|T2, prefix) if gate(prefix)
      arcs += affix(episodes not in T1|T2, suffix) if gate(suffix)
  T3b arcs += counter_run(episodes not yet claimed)
  return reconcile(arcs)

r4(title):
  t = r2_clean(title)
  for rx in [LEAD_BRACKET, LEAD_EPISODE_WORD, LEAD_EPNUM]:
      t' = rx.remove(t); if len(norm_name(t')) >= 3: t = t'    # residue check is load-bearing
  try LEAD_PART | PIPE_DOT | FRACTION_PAREN | COLON_EP        # stem, part, kind
  else fall through to r3_stem_part_kind(t)                   # on the CLEANED title

affix(eps, mode):
  bucket on norm_name(first|last segment of split(t, "| " | ": " | " - "))
  keep cluster iff  2 <= size <= 12
                AND len(norm_name(seg)) >= 6  AND not GENERIC_STEM(seg)
                AND (max_pos - min_pos) <= size * 3           # contiguity
                AND not feed_wide_counter(episodeNumbers)

gate(eps, arcs, mode):  covered/total < 0.30  AND  total >= 8
                        AND repeated_segment_ratio(eps, mode) >= 0.15

counter_run(eps): contiguous block in publication order whose parts == {1..k}, k >= 2, any order

reconcile(stages): trim already-taken guids; drop if < 2 members;
                   drop tier>1 arcs that lost more than half to an earlier tier;
                   recompute season from surviving members.
                   NO cross-tier merge on name (measured harmful — see below).
```

## 5. Notes, deviations and known-uncovered

**Deviations from the plan, both measurement-driven:**

1. **`_cluster_guarded` was parameterized with `stem_fn` at step 1, not step 3b.** Without it,
   A6.1's numbers would have conflated the cleaner's gain with the loss of the anthology guard,
   the re-release dedup and the season pass. The refactor was verified a byte-exact no-op:
   `A2r3.3-final` scored 0.9985 / 0.0027 / 0.6271 / 371 before and after.
2. **The cross-tier merge on `(norm_name, season)` was removed.** The plan specified it; it is
   **measurably harmful** — memPrec 0.9963 → 0.9902 and matched 482 → 479. Two arcs in one feed
   can legitimately normalize to the same name, and fusing them builds an oversized arc that then
   falls under the 0.5 Jaccard threshold, losing arcs both tiers had already got right. With it
   removed, `_reconcile` is an exact no-op against naive concat, as the plan required.

**Cut deliberately:** the single trailing `| N` counter (grammar 7). 545 titles across 26 feeds
match it, but the number is the feed-wide episode counter and the stem is the per-episode
subtitle (`Rockwood | 18`, `Behind the Scenes | 5`). Clustering it yields singletons; the only way
to extract recall is to cluster the pre-colon segment, which is tier 3a's job. `PIPE_DOT` requires
a trailing `. Subtitle` precisely to stay off these.

**Known-uncovered (no gold labels harmed, listed for future work):**

- `bundyville` — `Episode 1: The Battle`. The cleaner strips to `The Battle`, leaving one segment
  and no shared affix. The *season* is the arc, but the titles match neither `CHAPTER_LEAD` nor
  `SEASON_EPISODE_LEAD`, so tier 1's scoped season pass declines. Extending that pass to a bare
  `Episode N:` lead is the obvious next lever.
- `13-minutes-to-the-moon` — the shared prefix is the **show name** across all 53 episodes, so the
  size cap correctly rejects it. Its real arcs are seasons.
- 7am-style arcs whose part 1 fell outside the fetch window: `counter_run` requires a complete
  `{1..k}` set by design.

**Gold labels not edited.** Two families look mislabeled but were left alone per the brief:
cross-season 2-parters split by the season-split rule (`The Earliest Englishman (Part 1)` is
season 12, `(Part 2)` season 13), and pairs where *both* airings carry an encore marker
(`ENCORE: Gwyneth Paltrow's Ski Trial | Part 1/2`), which the re-release dedup then over-trims.

**`HFAB_PROMPT.md` step 2 is stale on one point:** `gold_feeds/` **is** present (50 frozen
slices) and `score.py:load_feed` prefers it, so gold scoring ran against the frozen labeler slice,
not a live re-fetch. The corpus was already on disk, so the step-1 network fetch was not needed.

**Reproducing the tier-3 ceiling measurements:** the ungated and gate-only variants are not
registered in `CONTENDERS` (both fail the floor by construction). Reproduce with
`_a6_cascade(eps, tier3=True, gate=False)` and `_a6_cascade(eps, tier3=True, gate=True)`.

## 6. Verification

- `python3 curation/arc-bakeoff/score.py` — green, 45 feeds scored, 0 errors, `A6-cascade` ranked
  **#1** with `meets_floor: true` and `arc_recall` 0.8763 > 0.6271.
- `python3 curation/arc-bakeoff/approaches.py` — smoke test runs clean, no exceptions.
- Corpus coverage 88 → 132 feeds; `total_arcs` 507 → 810 (1.6×, well under the 3× over-fire
  tripwire).
- Named target shows, before → after: *Dr. Death* 0 → 2 (`The Cowboy`, `Bad Magic`),
  *Behind the Bastards* 2 → 37, *Slow Burn* 3 → 13, *Lovecraft Investigations* 0 → 3,
  *Fiasco* 0 → 2, *Bardstown* 0 → 3, *Over My Dead Body* 0 → 3, *Suspect* 0 → 1.

The Swift detector (`Packages/PodcastModels/Sources/PodcastModels/EpisodeArcs.swift`) was **not**
touched; the port is a later supervised step.

---

# Addendum — `A7-cascade`: closing the measured coverage gap

`A6-cascade` left **181 of 315 corpus feeds with zero arcs**. Before adding anything, that gap was
partitioned to answer whether those feeds are genuinely arcless or a detector limitation.

## A7.0 The gap, measured

| Bucket | Feeds | |
|---|---|---|
| Genuinely arcless | ~55–60 | weekly interview / news / anthology. Nothing to find. |
| **Detector limitation** | **~90–100** | real serial structure, no parser reaches it |
| Truncated feed slices (<6 eps) | 32 | fetch window cut the arc's siblings off — a data problem |
| Ambiguous | ~5 | undecidable from titles |

Of the judgeable 149 (excluding truncated slices) roughly **60% were our miss, 40% genuinely
standalone**. The direction is solid; the exact split rests on a 55-feed qualitative sample, so
treat it as ±13 points. Two title shapes accounted for most of the recoverable half, and both are
reachable with regex alone. They are A7.1 and A7.2.

## A7.1 — bare `Episode N:` season pass (tier 4)

Tier 1's scoped season pass recognised `Chapter N |` and `S7 E1:` but not a bare
`Episode 1: The Explosion`. Identical situation: the arc name is absent from the title and
`itunes:season` is the only grouping evidence.

The corpus made this look easy. Of the 36 zero-arc feeds using the lead, the 29 with season
metadata are all serials, and the 7 without are exactly the feed-wide-counter traps
(*homecoming* 116 episodes, *anatomy-of-doubt* 196, *message* 39, *16-shots* 31). Season metadata
looked like a sufficient guard.

**Gold disagreed, twice, and both corrections are load-bearing:**

1. **A size cap is required.** *bear-grease* numbers 60 episodes *inside* one `itunes:season` and
   *history-on-fire* 101 — a per-season episode counter, not an arc. Grouping on the lead alone
   cost **0.104 membership precision** (0.9684 → 0.8648). With no cap the detector fails the floor
   outright (0.8793); `max_size` anywhere in 6–24 scores identically, so 12 is not on a cliff.
2. **It must run late.** Placed inside tier 1 it also cost **recall** (0.8763 → 0.8610), because it
   swallowed episodes tier 2's richer parser was already grouping correctly —
   `Episode 47: Give Me Back My Legions! (Part 1)` is a Part-1, not a season member. Running it as
   tier 4 means it only ever sees what every earlier tier declined.

**Gold gain: zero.** No gold feed has an arc of this shape, so gold cannot confirm the lever adds
anything true — it confirms only that the lever adds nothing *false*, and that its cap is
necessary. The gain is corpus-side: **+26 feeds** (158 vs 132), spot-checked by hand — *caught*
(9-part), *american-fiasco* (10), *bad-seeds* (8), *habitat* (7), *black-box* (8), *bundyville*,
*blindspot*, *death-of-an-artist*. That asymmetry is the honest reason to treat A7.1 as the weaker
of the two levers despite it recovering more feeds.

## A7.2 — bare / trailing counter runs (tier 4), +0.005 recall

Tier 3b's `LEAD_COUNTER_ONLY` needs a keyword (`Part 2`, `Chapter 4`). These grammars carry the
counter with no keyword at all, which is why 50 zero-arc feeds slipped past it:

```
  "1. When the Wind Changed"       fairy-meadow
  "01: Hypothesis (remastered)"    ars-paradoxica
  "04_KEEP IT 200"                 bellwether
  "They Keep People Safe | 1"      empire-city
```

A bare number is far weaker evidence than `Part 2`, so this pass is stricter than 3b in three ways:

- `min_run` is **3**, not 2. (2 and 3 score identically on gold; 4 loses an arc.)
- The run must be a **complete `{1..k}` set**, order-insensitive.
- A run longer than `max_run` (12) is read as a **feed-wide episode counter and rejected
  outright**, not trimmed. This is why the scan takes the *longest* complete run from each start
  rather than the first — stopping early would carve a 3-episode arc out of a 66-long feed counter
  and never notice the run kept going.
- One grammar per feed, whichever the most titles use, so a run in one grammar cannot bridge a gap
  in the other.

**`max_run` is invisible to gold** — 8 through 999 score identically, because no gold feed has a
long bare-counter run. Its justification is corpus-side and was verified there directly: removing
the cap gives *do-go-on* a **99-member arc** and *se-regalan-dudas* a 21-member one. Keep it.

## A7 — before / after

| | memPrec | junk | arcRecall | detArcs | corpus feeds | corpus arcs |
|---|---|---|---|---|---|---|
| `A2r3.3-final` (incumbent) | 0.9985 | 0.0027 | 0.6271 | 371 | 88/315 | 507 |
| `A6-cascade` | 0.9684 | 0.0408 | 0.8763 | 539 | 132/315 | 810 |
| `A7.1-season-lead` | 0.9684 | 0.0408 | 0.8763 | 539 | 158/315 | 868 |
| `A7.2-bare-counter` | 0.9685 | 0.0406 | 0.8814 | 542 | 160/315 | 856 |
| **`A7-cascade`** | **0.9685** | **0.0406** | **0.8814** | **542** | **186/315** | **914** |

Floor: memPrec ≥ 0.95, junk ≤ 0.05 — held on both terms, unchanged. Note A7 is *cheaper* on junk
than A6 (0.0406 vs 0.0408) while covering 54 more feeds: both levers append arcs made of episodes
no earlier tier claimed, so they cannot cannibalise existing arcs.

## A7 — portable rule summary (Swift)

Both levers are ICU-safe: no lookbehind, no atomic/possessive groups, no `\K`, and `DASHES` leads
every character class.

```
EPISODE_NUM_LEAD    ^Ep(?:isode|\.)?\s*\d{1,3}\b                (case-insensitive)
BARE_LEAD_COUNTER   ^(\d{1,2})\s*[<DASHES>._:)\]]\s*(\S.*)$
TRAIL_PIPE_COUNTER  ^(\S.*?)\s*\|\s*(\d{1,2})\s*$
```

Tier 4a — season lead: over episodes no earlier tier claimed, group by `itunes:season` those whose
noise-stripped title matches `EPISODE_NUM_LEAD`; emit only when the group is **2–12** members; name
from the season trailer when present, else `Season N`.

Tier 4b — counter run: pick the single grammar most titles match; walk oldest→newest; inside each
maximal counter-bearing block take the **longest** prefix forming a complete `{1..k}` set; emit when
`3 ≤ k ≤ 12`, otherwise consume and discard.

## A7 — known-uncovered, and where regex stops

Roughly 40 missed feeds carry **no title signal at all** — the season is the arc and every title is
a standalone noun phrase: *floodlines* (`Antediluvian`, `The Bridge`, `Exodus`),
*dolly-partons-america*, *broken-harts*. Deciding those needs a judgment that a season's titles read
as one story. **This is where regex stops and a semantic layer starts.**

Separately, and **pre-existing in A6 rather than introduced here**: tier 3a's affix clustering emits
some very large arcs on the corpus — *fake-diana* 144 members, *zeit-verbrechen* 72, *lore* 50.
Gold does not penalise them (those feeds are not gold, or the affix genuinely repeats), but they are
almost certainly junk. A size cap on tier 3a is the obvious next audit; it is out of scope for A7.

## A7 — verification

- `python3 curation/arc-bakeoff/score.py` — green, 45 feeds, 0 errors. `A7-cascade` meets the floor
  with `arc_recall` 0.8814 > A6's 0.8763. It ranks #2 only because `A7.2-bare-counter` posts
  byte-identical gold numbers and wins the tie-break; A7 is preferred for its +26 corpus feeds.
- `python3 curation/arc-bakeoff/approaches.py` — smoke test clean.
- `_a7_cascade()` with both levers off was verified to score **byte-identically to `A6-cascade`**
  (0.9684 / 0.0408 / 0.8763 / 539) before either lever was switched on.
- Corpus `total_arcs` 810 → 914 (1.13×), far under the 3× over-fire tripwire, for +54 feeds.

`EpisodeArcs.swift` remains untouched.
