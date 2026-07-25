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
