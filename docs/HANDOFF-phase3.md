# Phase 3 handoff — 2026-07-27

Written mid-run. The relabel is not finished and does not need to be finished in one
sitting; everything below is resumable from the commands in the last section.

## Done

**Job 0 — descriptions.** 275 feeds re-read. Episode descriptions went from an average of
294 characters, hard-truncated at 299 by the original import, to **990**. `duration_s`
went from 2,073 to 27,484. A second pass added **1,685 episodes** the import never had —
three shows sat at exactly 800, which was a cap, and 7am alone was short 1,278.

**Job 0, the second time.** The first re-read reported success and had silently skipped a
quarter of the catalog. `feeds.py` took the **first** non-empty of `<itunes:summary>`,
`<description>`, `<content:encoded>` — and many publishers use `itunes:summary` as a
one-line teaser. 99% Invisible offers 178 characters there and 1,070 in `<description>`.
`refresh_episodes` never overwrites with less, so the comb read the teaser, correctly
declined to shrink the 299-character import text, and logged a clean run. Two rules that
are each right alone; the second hid the first.

Fixed to take the **fullest** description, measured on the prose so HTML markup does not
win on tag bytes. Re-combed: **10,587 descriptions grew**, catalog average now 1,195.

| show | before | after |
|---|---|---|
| Zeit Verbrechen | 446 | 3,292 |
| Behind the Bastards | 299 | 2,184 |
| Swindled | 283 | 1,408 |
| 99% Invisible | 299 | 1,070 |
| 7am | 299 | 1,041 |

**The cost:** roughly **2,250 episodes were relabelled on ~299 characters** before the fix,
including all 781 of 99% Invisible — the show that scored 0.45 agreement last time. They
are under-read rather than wrong. Redoing them means a fresh `run_id`; `pending()` will
not re-serve them under `2026-07-relabel-v176`. Not done, and it is a decision, not an
oversight.

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

**Vocabulary 148 → 182.** Driven by evidence, not guesswork — see below.

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

5. **The Job** (`heist-and-robbery`) — five agents, five different weak fallbacks.
6. **Killed by a Stranger** (`stranger-homicide`) — four agents. The vocabulary covered
   partner, family, neighbour, serial, for-hire and unsolved, so a single solved killing by
   a stranger had nowhere to go. Casefile and Zeit Verbrechen are full of them.
7. **A Shooting and What Followed** (`mass-shooting`) — five agents. A spree was landing on
   `serial-offender`, whose definition is a pattern *across time*, which is the opposite
   shape.

The tell each time was not agreement about the gap. It was **disagreement about the
fallback** — five agents reaching for five different wrong shelves means the shelf they
want does not exist.

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

**Set the subagent model to Sonnet explicitly on every launch.** The plan's locked
decision is *"Ceiling stays Sonnet, never Opus."*

The trap: **`.claude/agents/*.md` are not registered as agent types in this environment.**
`.claude/agents/episode-labeller.md` carries `model: sonnet` in its frontmatter and that
line has never taken effect — asking for `subagent_type: episode-labeller` fails with
"agent type not found". Those files are documentation of the contract, not configuration
that binds a model. The same is true of `arc-finder`, `arc-namer`, `vocab-splitter` and
`fit-analyst`.

So the model has to be set on the launch call itself. Miss it and the session model does
the reading while `label.py record` stamps its `claude-sonnet-5` default regardless. That
happened for **25,317 rows on 2026-07-29** — far over budget, and the `model` column
asserting something false. Restated to `claude-opus-5` through
`edits.restate_label_model`.

The 11,084 rows from 2026-07-28 are left as `claude-sonnet-5`. Since the agent type has
never been reachable, those were probably Opus too — but "probably" is not a provenance,
and inventing one is the failure this section exists to prevent.

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

## Resuming after a session limit

Nothing is lost when a run is cut off. Every batch commits the row, the `edits` entry and
the `decisions.jsonl` line in one transaction before the next batch is fetched, so the
worst case per agent is one batch of 20 episodes never started. There is no partial state
and nothing to clean up.

```bash
python3 -m admin.api.label status     # how far it got, and the confidence split
git status --short                    # decisions.jsonl is the only thing agents touch
```

Then relaunch. Briefs are at `scratchpad/lab-{0..7}.md`, one per slice, each capped at
10 batches so agents stop cleanly and write their report rather than being killed
mid-thought. Those reports are where every vocabulary fix has come from.

### Metering

**One wave of 8 agents ≈ 1,600–2,400 episodes.** At 25% done, roughly 9–13 waves remain.

Three dials, in the order worth reaching for:

1. **Fewer agents per wave.** Four instead of eight halves the burn rate and costs
   nothing but elapsed time — the slices are independent, so any subset makes progress.
2. **Lower the batch cap.** 10 batches is set in the briefs. Five makes each agent
   cheaper and the reports more frequent.
3. **Prioritise instead of completing.** The queue is already ordered so the most useful
   episodes come first: arcless shows, then biggest. Stopping at 60% would still cover
   every show where subjects are the only navigation.

**What not to do:** raise `--limit` above 20 per call. The batch size is what keeps each
episode getting read rather than skimmed, and the last pass's failure mode was exactly
that — 150 characters per episode and no time spent on any of them.

### If a wave is cut off mid-flight

Nothing. Check `status`, relaunch. The `NOT EXISTS` clause in `pending()` means an episode
already labelled is never offered again, so a relaunched agent picks up cleanly with no
duplicate work and no gap.
