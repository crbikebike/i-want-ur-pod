# Phase 3 handoff — 2026-07-27

Written mid-run. The relabel is not finished and does not need to be finished in one
sitting; everything below is resumable from the commands in the last section.

## Done

**Job 0 — descriptions.** 275 feeds re-read. Episode descriptions went from an average of
294 characters, hard-truncated at 299 by the original import, to **990**. `duration_s`
went from 2,073 to 27,484. A second pass added **1,685 episodes** the import never had —
three shows sat at exactly 800, which was a cap, and 7am alone was short 1,278.

**Jobs 1–3 — arcs.** The A8 cascade had never been run on this catalog; `catalog/build/arcs.py`
reads an older `segment` field. Running it, then reading the 66 shows it cannot parse:

| | before | after |
|---|---|---|
| kept shows with an arc | 54 | **252** of 275 |
| arcs | 799 | 1,809 |
| episodes in an arc | 3,417 | 7,942 |
| `kind='series'` | 0 | 90 |

23 shows still have none and every one was read. This American Life, Swindled, Bodies —
anthologies where each episode stands alone. Recorded in `shows.arcs_checked_at` so
nothing reads them again.

**Job 2 — arc names.** 146 of 1,688 arcs had a name that said nothing. 126 renamed, 14
flagged as not actually stories. Every flagged arc carries its reason in
`arcs.description`.

**Vocabulary 148 → 179.** Driven by evidence, not guesswork — see below.

## The gate needs restating

PROGRAM.md says *"every show reaches depth 3."* Depth 3 means having an arc, and 23 shows
correctly have none. The reachable version, which is met: **every show has been read for
arcs, and has one wherever one exists.** 275 read, 252 have one.

## How the vocabulary grew, and the loop that did it

Four changes, all from the same mechanism: a labelling agent hits a gap, marks the episode
**low confidence** rather than forcing a fit, and when three independent agents report the
same gap it gets acted on.

1. **28 subjects** from splitting 12 crowded ones. 99% Invisible had put 82 of 100 pilot
   episodes on a single label because the built environment had one slug.
2. **The Betting Industry** — three agents, three slices, three different weak proxies,
   all low confidence. Used correctly by four agents since.
3. **A Relationship, Remembered** and **Talking About Love** — six agents flagged
   Transfert's 566 first-person memoir episodes.
4. **When a Government Falls** — was defined as *"outside the US and UK"*, which is
   geography relative to a reader this catalog does not have. A UK prime minister
   resigning had nowhere to go.

Two candidates were **declined** and that matters as much: an abusive-relationship subject
(real but only 2% of its parent, folded into a definition instead) and an industry-sector
split of Business Wars (divides by industry, so it has no natural end).

## Still open

**Politician profiles.** No subject for a political figure's career, where `celebrity-life`
covers everyone else's. Three mentions; clears the bar. Not added yet.

**Format, not subject.** Year-end roundups, podcast-recommendation episodes, cross-promo
bundles, trivia segments, Business Wars roundtables, Revisionist History essays. Four
agents, same conclusion: *"these aren't about a subject so much as a format the vocabulary
doesn't model."* No new subject fixes this. A `kind` field on episodes would.

**One primary is sometimes wrong.** Cautionary Tales pairs two unrelated stories per
episode; This American Life bundles three to five. Forcing one primary is real information
loss, and it is a rule, not a gap.

**Espions is a merged feed.** Three independent reports — one row carrying "Nid d'espions",
"L'État-Major" and "Control F", three unrelated programmes. This is a Phase 2 repair, same
family as the 27 wrong feeds, and belongs in the feed queue.

**Mumbai Crime** is a scripted audio drama catalogued as investigative journalism.

**A correction worth carrying.** Seven agents described 7am as a poor fit and I repeated
that as though the show did not belong. The data disagrees: 1,979 of 2,078 episodes
labelled, 1,156 high confidence against 193 low, and its titles are reported single-story
journalism. The agents were hitting a true-crime-skewed vocabulary, not a talk show.

## Resuming

```bash
python3 -m admin.api.label status        # relabel progress
python3 -m admin.api.vocab crowded       # subjects still too big to browse
python3 -m admin.api.vocab waiting       # proposals awaiting a person
python3 -m admin.api.arcname status      # 0 — done
python3 -m admin.api.arcfind status      # 0 — done
```

The relabel runs as waves of eight agents keyed on `id % 8`. Each does 200–300 episodes
before running out of room; relaunch against whatever `remaining` reports. Briefs are at
`scratchpad/lab-{0..7}.md`, and the agent definition is
`.claude/agents/episode-labeller.md`.

Queue order is deliberate: **arcless shows first**, then biggest first. The pass will not
finish in one sitting, so whatever fraction completes should be the fraction where
subjects are the only way anyone navigates.

Three label runs coexist by `run_id` and none overwrites another: `2026-07-theming`
(43,818 rows, the original Haiku pass), `2026-07-relabel` (319, the pilot against 148
subjects), and `2026-07-relabel-v176` (this one).
