# Task — build one episode-theme index over the whole catalog

Autonomous brief. Self-contained: assume no memory of the session that wrote it.
Pure `python3` (standard library only — **no pip, no venv**). The model is reached only
through Claude Code `Workflow` subagents.

**Model ceiling: Sonnet. Do not use Opus for any subagent.**

## Why this exists

The catalog needs a second way in. Today you find an episode by knowing which show it is in.
There is no way to ask *what else is like this* across 307 shows and 28,112 episodes.

Themes are that second index. They sit beside arcs, not behind them.

**Arcs and themes are orthogonal.** An arc is a multi-episode story — Bear Grease's five-part
Civil War run. A theme is what an episode is *about*. An episode in an arc still has a
subject, so it still gets a theme. Radiolab is the shape that proves it: 5 arcs, 654
standalone episodes, one vocabulary over all of them.

An earlier draft got this wrong twice. It treated theming as mop-up for the 94 shows
`A8-cascade` could not reach, and it skipped every episode already inside an arc. Both cuts
came from the same mistake — thinking of themes as filling arc-shaped holes. They are not.
The index has to cover everything or it cannot answer *what else is like this*.

## Scope — every full episode in the catalog

**307 shows, 28,112 full episodes.** No size threshold. No arc filter.

- Take every episode with `episodeType == "full"`. Trailers and bonus items are out.
- Episodes inside arcs are **in**.
- Shows of any size are **in**, including the 90 shows with fewer than 10 episodes.

**Exclude only these 9 — they resolve to a different show than their metadata claims:**
`broken-record` (a teenager's music vlog, not Rick Rubin's), `hit-parade` (a Spanish radio
chart show), `homecoming` (a SoundCloud self-help podcast), `gun-machine`, `animal`,
`earshot`, `shift`, `startup`, and `making-oprah` (byte-identical feed to `making-obama`).

Regenerate the list rather than trusting a paste. The selector belongs in
`build-episode-themes.py`.

## The core design change — one shared vocabulary

The Swindled run built a **per-show** vocabulary: 14 themes tuned to Swindled, none under 3
episodes, none over 35%. Read `curation/arc-bakeoff/episode-themes/swindled.json` — it is the
precedent for pipeline shape and audit rigor.

**Do not reproduce its per-show vocabulary.** Per-show vocabularies do not compose. If Bear
Grease invents `appalachian-foodways` and Criminal invents `southern-food-history`, those are
one theme wearing two slugs, and cross-show discovery silently fails. The `mapsTo` field
patched this by pointing at a catalog theme, but it is lossy — many themes collapsed into one,
one hop, no way back.

A per-show vocabulary is also why the old brief needed a 40-episode floor. A 6-episode show
cannot yield 10–16 themes with 3 episodes each. The floor was a symptom, not a decision.
Delete the cause and the floor goes with it.

**Build one catalog-wide episode vocabulary and assign every episode against it.**

### The episode vocabulary is its own taxonomy

`curation/catalog/themes.json` holds 30 catalog themes that carry real definitions and
`showCount`, and already power show-level similarity. **Episode themes are not children of
those 30.** The two levels cut the catalog differently. A show-level theme describes what a
show is *for*; an episode theme describes what one episode is *about*, and it is far more
granular. Forcing every episode theme to nest under one of 30 would distort the ones that do
not fit that cut — and the episode level is where the granularity has to live.

So: build the episode vocabulary on its own terms, then **link softly**. Each theme carries
`relatedShowThemes[]` — zero or more slugs from the 30. Empty is a valid and expected answer.
The link exists so the workbench can navigate between levels, not to constrain the taxonomy.

Expect roughly 120–200 episode themes. Let the number fall out of the data; do not force it.

### What is and is not a theme

Two different tests. Keep them separate — an earlier draft merged them and would have thrown
away good themes.

**Test 1 — kind. Hard. Fails here never enter the vocabulary.**

Not themes, ever:

- **Segment names.** Bear Grease's `This Country Life` is 161 episodes — 38.5% of the show —
  and means nothing outside Bear Grease. It is a container, not a subject.
- Show names, host names, network names.
- Format labels: `interview`, `listener mail`, `live show`, `Q&A`.
- Anything defined by what it is not (see the junk-drawer note below).

An episode of `This Country Life` about cinnamon bears and chocolate gravy is about
Appalachian foodways, or folk tradition, or whatever the description supports. Theme the
content, not the wrapper.

**Test 2 — reach. Soft. Fails here get flagged, not dropped.**

Prefer themes that can apply to an episode of a different show — that is what makes the index
work. But a theme used by only one show is not automatically wrong. Some subjects genuinely
appear once in the catalog. That is a real finding, not a defect.

Mark any theme used by a single show as `showSpecific: true` and keep it. The catalog will
grow, and a one-off today may collect siblings later. Surface these in the workbench so you
can review them; do not let the pipeline delete them.

## Step 0 — fetch descriptions first. Everything gates on this.

`curation/feeds/*.json` holds six fields per episode and no description, because
`scripts/fetch-atlas-feeds.py:117` never asked for one. That is a limitation of one script,
not of the data. **Every feed serves descriptions and they are excellent.**

Verified on the three worst-scoring shows — 40 of 40 items carried a real description on
each:

> **125 Acres** *(Criminal, a 14-character title)* — "George Dinning was emancipated in 1865,
> when he was 10 years old. By the time he was in his mid-thirties, he'd bought the land on
> which he had been enslaved. Years later, 25 white men approached…"

Titles alone cannot carry this job. `Cinnamon Bears and Chocolate Gravy` is unthemeable
without its synopsis, and there are thousands like it.

Write **`scripts/fetch-feed-descriptions.py`** — stdlib only:

- Read `feedUrl` from `curation/feeds/<slug>.json` for each of the 307.
- Reuse `fetch-atlas-feeds.py`'s `http_get`, its `safe_fromstring` XXE guard (**not
  optional**), its retry logic and its 0.6s politeness delay.
- Per item take `description`, else `itunes:summary`, else `content:encoded`. Strip HTML,
  unescape entities, collapse whitespace, truncate at **300 characters** — the samples show
  the topic lands well inside that.
- Write a sidecar: `curation/arc-bakeoff/descriptions/<slug>.json` =
  `{slug, fetchedAt, episodes: {guid: description}}`. **Sidecar, not a corpus edit** —
  `curation/feeds/` is gitignored and regenerated by a script that skips existing files, so
  editing it would make the corpus non-reproducible.
- Gitignore the sidecar directory. These are third-party copyrighted blurbs.
- ~307 requests, under ten minutes. Resumable: skip a slug already on disk.

Live feeds have moved past the snapshot (Radiolab: 663 items live vs 659 stored). Match by
guid and accept that a few will not match. Report the miss rate per show; do not fail on it.

## Title parsing — generic, with segments split out

Swindled used a hand-written extractor in `SHOWS` in `build-episode-themes.py` — a regex to
strip `S10 Ep141:` and take the trailing parenthetical. **307 shows cannot each get bespoke
config.** Replace it with one generic best-effort extractor.

Order: trailing parenthetical (reject one containing `Chapter|Part|Pt|Vol|Episode|Ep` +
digits), then `Name: Subject`, then `Name | Subject`, then `Artist – Song`, else the whole
title.

**Then split recurring segment prefixes into their own field.** When a `Name - Subject` prefix
repeats across many episodes of one show, it is a segment. Verified on Bear Grease: 161
`This Country Life`, 58 `Render`, 34 `Backwoods University`. Detect it by frequency — a prefix
on 5+ episodes of a show — not by a hand-written list.

Pass the model three fields:

```
segment: This Country Life          <- metadata; never a theme
subject: Cinnamon Bears and Chocolate Gravy
desc:    <300-char synopsis from step 0>
```

Leaving the segment name glued to the subject is not neutral input. It appears in every row
and pushes the model to cluster on it — which is how the old draft would have produced a
`This Country Life` theme covering 38.5% of the show. Split it and the pressure goes away.

**Pass the raw title too.** A bad extraction then costs signal on one row instead of poisoning
a show. For Radiolab the guess is just the whole title, which is correct — the title *is* the
subject.

Keep the existing dedupe: drop a re-airing when the original is present, and prefer the
original's guid.

## Pipeline

Three passes, following `episode-theme-workflow.mjs`. The shape changes: consolidation is now
global and runs once for the catalog, not once per show.

1. **Open coding — one show at a time.** `model: 'sonnet'`, **80 episodes per call**, ~352
   calls. Free-form theme phrase per episode. No fixed vocabulary. Let categories emerge.

   **Batch within a show, never across shows.** Finish a show's episodes before moving on, and
   emit that show's complete candidate theme set as one unit. Consolidation cannot spot that
   `appalachian-foodways` and `southern-food-history` are one theme until it can see each
   show's full picture. A batch spanning three shows produces labels that belong to no
   show's set and merge badly.

   Per-show output: every raw label, its episode count within that show, and the show slug.

2. **Consolidate — global, two tiers.** Now that every show is complete, look for merges
   across them. 307 complete label sets will not fit one call.
   - First, in plain Python: lowercase, trim, and count distinct raw labels, keeping the set
     of shows each label came from. This collapses volume hard before any model sees it.
     Carry the counts and the show sets through — they decide `showSpecific` later.
   - Tier 1: `model: 'sonnet'`, ~24 calls, each over a slice of the distinct labels. Each
     returns merged candidate themes with definitions.
   - Tier 2: `model: 'sonnet'`, one call over every tier-1 candidate. Produces the final
     vocabulary: `slug`, `name`, one-sentence definition, and `relatedShowThemes[]` (zero or
     more of the 30 in `curation/catalog/themes.json`).
   - Apply **test 1 (kind)** here and drop what fails. Apply **test 2 (reach)** as a flag
     only — compute `showSpecific` from the show sets in plain Python, not by asking the model.

3. **Assign** — `model: 'haiku'`, 80 per call, ~352 calls. One primary plus up to two
   secondary from the frozen vocabulary.

   **Confidence goes on each theme application, not on the episode.** An episode with a
   primary and two secondaries produces three separate `high|medium|low` judgements. The
   primary is usually solid while the third pick is the shaky one — a single episode-level
   score hides exactly the rows worth pruning.

   **Record the score. Act on it nowhere.** Nothing is dropped, reweighted, or gated on
   confidence in this run. It exists so a later manual pass can find the weak applications.

**Skip the two-run agreement pass for the bulk** — it doubles assign cost. Run it on a 6-show
sample, and **always include `radiolab` and `99-invisible`**. Their titles state a topic rather
than name an entity, so they are where a vague, non-discriminating vocabulary is most likely
and least visible to the audit. Low agreement there is the signal that the vocabulary is not
cutting anything.

Roughly 352 + 25 + 352 + 12 ≈ **741 agents** for 28,112 episodes. Far above the normal
guideline; that is expected for an overnight job, and under the 1,000-agent cap. If it would
exceed the cap, split the assign pass across two runs rather than trimming shows.

## Audit — non-blocking

The old thresholds were per-show because the vocabulary was per-show. A shared vocabulary
needs both a catalog-level check and a per-show one. All of it lives in
`build-episode-themes.py`.

**Catalog level:**

- Vocabulary size lands in 120–200. Flag outside that; do not force it.
- No theme under 15 episodes across the catalog.
- No theme over 8% of all episodes.
- Every `relatedShowThemes[]` entry is a real slug from the 30. An empty array is valid.
- Zero out-of-vocabulary labels; exactly one `primary` per episode; at most two `secondary`.
- Every theme application carries a confidence value. No blanks.

**Per show:**

- No show collapses to a single theme — flag any show where one theme takes over 60%.
- Every show uses at least 2 themes, unless it has fewer than 4 episodes.
- Episodes in == episodes labelled. Assert it.

**A failing audit flags the object and the run continues. Nothing halts.**

Watch for the failure Swindled hit: a **junk-drawer category defined by what it is not**.
Swindled's `swindlers-and-grifters` was "an individual con artist… without a fund, a company,
or a religious front", and it swallowed everything ambiguous — 9 of the 17 low-confidence
episodes plus 4 of the 5 most-disagreed boundaries. If a definition is phrased mostly as
exclusions, flag it as a junk-drawer suspect.

## Standing decision

**Flag and categorize. Never drop.** A low-confidence or audit-failing result is marked, not
removed. Nothing is deleted from the corpus or from any show's output. The one exception is
consolidation, where a candidate theme that fails the cross-show test never enters the
vocabulary — that is vocabulary design, not dropping data.

## Output

- `curation/arc-bakeoff/episode-themes/_vocabulary.json` — the shared vocabulary. Per theme:
  `slug`, `name`, `definition`, `relatedShowThemes[]`, `episodeCount`, `showCount`,
  `showSpecific`, `junkDrawerSuspect`. Committed. **This is the primary artifact.**

- `curation/arc-bakeoff/episode-themes/<slug>.json` per show — `{slug, title, models,
  themesUsed[], episodes[], agreement{}}`. Committed.

  Each episode carries its applications as a list, so confidence rides on each one:

  ```json
  {
    "guid": "...", "display": "Ep. 480: This Country Life - Cinnamon Bears and Chocolate Gravy",
    "segment": "This Country Life", "subject": "Cinnamon Bears and Chocolate Gravy",
    "iso": "2026-07-18", "inArc": false,
    "themes": [
      {"slug": "appalachian-foodways", "role": "primary",   "confidence": "high"},
      {"slug": "folk-tradition",       "role": "secondary", "confidence": "medium"},
      {"slug": "rural-labor",          "role": "secondary", "confidence": "low"}
    ]
  }
  ```

  `themesUsed[]` is the show's own theme set, drawn from the shared vocabulary. It is what
  the show detail screen filters on — see below.
- `curation/arc-bakeoff/episode-themes/_run-report.json` — committed. Per show: episodes
  in/out, description miss rate, themes used, confidence spread, audit flags with reasons.
  Catalog level: vocabulary size, theme distribution, junk-drawer suspects, sample agreement.
  This is the recap. **It is data, not a document.**

Keep `inArc` on every episode. It is how the workbench shows that arcs and themes coexist
rather than compete.

## Everything has to land in the workbench

**Analysis that sits in a JSON file, or in a standalone HTML page nobody opens, is not doing
its job.** The workbench exists to understand the shape of the catalog that ships with the app.

Run `python3 scripts/serve-catalog.py --tailscale`; the UI is `tools/catalog-browser/`.

`build-catalog-index.py` already folds per-show theme data into `catalog-index.json`. Extend it
so every signal this run produces reaches an object you can browse:

| Signal | Attached to | Surfaced as |
|---|---|---|
| Confidence, **per application** | theme application | badge on each theme chip, not one badge per row; **Model confidence** facet (exists, currently covers only Swindled) |
| Primary + secondaries | episode | on the row, each a link to the theme |
| In an arc | episode | badge, so arc and theme read as coexisting |
| `themesUsed[]` | show | **theme filter on the show detail screen** — see below |
| Episode + show counts | theme | on the theme card |
| Related show themes | theme | soft links across to the 30; may be none |
| Show-specific | theme | badge, and a facet to review the one-offs |
| Junk-drawer suspect | theme | badge, and a facet to find them |
| Audit flags + reason | show and theme | badge, and a facet |
| Two-run agreement | show | shown where the Swindled number already is |
| Description miss rate | show | on the show |

**The show detail screen must filter by theme.** This is not optional and it is not covered by
the catalog-wide theme pages. Most shows have no arcs at all, so on those screens the theme
filter is the *only* structure a user has for digging through hundreds of episodes. Build the
filter from that show's `themesUsed[]`, showing an episode count per theme. It has to work on
a show with 665 episodes and no arcs, which is the common case, not the edge case.

The questions the workbench should answer after this run:

- *What else is like this episode?* → open its theme, see episodes from every show that shares
  it. **This is the whole point. If this does not work, the run failed.**
- *Within this show, show me only the episodes about X* → the show detail theme filter.
- *Which theme applications are shaky?* → the confidence facet, now per application, so a weak
  third pick is findable without the strong primary masking it.
- *Which themes only ever fired on one show?* → the show-specific facet. This is the review
  queue for the next consolidation pass.
- *Which shows or themes failed audit?* → a facet.
- *Which themes are junk drawers?* → a facet, across the catalog.
- *Does this show have arcs and themes both?* → open the show; arc'd episodes carry themes.

A run-level summary — shows processed, episodes labelled, vocabulary size, failures — can go at
the top of the **System** view. Keep it to numbers. The per-object flags above are the point;
the summary is a footnote.

Match the existing style: `tools/catalog-browser/app.css` tokens, no framework, no build step,
both themes, works at phone width. **Extend the workbench; do not restructure its navigation.**

## Verification before claiming success

- Every show: episodes in == episodes labelled. Assert it, do not assume.
- Catalog total labelled == 28,112 minus exclusions. Assert it.
- Sample agreement reported as a number, as Swindled's 0.7582 was.
- Cross-show check: pick 5 themes at random and confirm each has episodes from **3+ different
  shows**. A theme living in one show is a per-show vocabulary that leaked through.
- Hand-check three where the subject is judgeable: **`bear-grease`** (the recurring
  `THIS COUNTRY LIFE` segments must scatter across content themes, not collect into one),
  **`disgraceland`** (musician deaths vs crimes), **`30-for-30-podcasts`** (has arcs — themed
  episodes must sit alongside them, not fight them).
- `python3 curation/arc-bakeoff/approaches.py` smoke test still runs.
- `python3 curation/arc-bakeoff/score.py` — `A8-cascade` unchanged at memPrec 0.9685 /
  junk 0.0406 / arcRecall 0.8814. This job must not touch the detector.

## Do not

- Touch `approaches.py`, `score.py`, or `gold.json`.
- Touch `Packages/PodcastModels/Sources/PodcastModels/EpisodeArcs.swift`.
- Restructure the workbench navigation.
- Commit `curation/feeds/`, `curation/arc-bakeoff/descriptions/`, or `catalog-index.json` —
  all gitignored.
- Use Opus for any subagent.

## Context

`docs/design/the-catalog.md` is the architecture. Short version: The Catalog holds themes,
shows, arcs, and per-show themes; it ships with the app and refreshes from a static file;
regex covers any episode The Catalog does not know. Nothing waits on human approval —
confidence exists so the shaky handful can be found, not so anything gets gated.

Two follow-ups belong to a later run, not this one:

- **A second consolidation pass.** Once every show has its themes, the `showSpecific` set is
  the review queue — themes that fired on one show only and may merge with something now that
  the full picture exists. Recorded confidence is the other input: the weak applications are
  where the vocabulary is not cutting cleanly.
- **Per-show refinement vocabularies** on top of the shared one, for the 117 shows with 40+
  episodes. That recovers Swindled-level resolution without giving up cross-show matching.

**Do not attempt either in this run.** Prove the global index first. This run's job is to
record the signals — confidence on every application, `showSpecific` on every one-off — so the
later passes have something to work from.
