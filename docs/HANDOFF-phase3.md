# Phase 3 handoff — 2026-07-27, updated 2026-08-01

**The relabel is finished. `python3 -m admin.api.label status` reports `remaining: 0`.**

29,215 episodes across 275 kept shows, all labelled against the v176 vocabulary. No kept
show is untouched. Final confidence split: **19,005 high, 22,624 medium, 4,996 low**.

The body below was written mid-run on 2026-07-27 and is kept as the record of how the pass
was reasoned about. Where it has been overtaken by events, the correction sits next to it
rather than replacing it — the mistakes are the useful part. Start at *Where it finished*
for the current state.

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

**Vocabulary 148 → 198.** Driven by evidence, not guesswork — see below. Every one of the
20 subjects added during the relabel has been used; none is dead weight. The heaviest are
`film-career-biography` (107), `founder-biography` (100), `political-persecution` (85) and
`heist-and-robbery` (85); the lightest are `offshore-secrecy` (4) and `talking-about-music`
(2), both added late with little left to catch.

One subject was **retired**: `music-scene-history`, a duplicate of `music-scene-movement`
in the same theme. Two agents said they could not tell them apart, and one named the
consequence — two agents labelling the same episode differently registers as *disagreement*
rather than as the vocabulary fault it is.

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

## Where it finished — 2026-08-01

The last 1,011 episodes were labelled in two waves of Sonnet 5 agents: four agents on
slices 0, 1, 3 and 4, then two more to empty the tail. 1,643 subject rows. Every row
carries `model = claude-sonnet-5` and that is true rather than a default stamped over Opus
work — the model was set on each launch call, per the section below.

| slice | left at 07-30 | now |
|---|---|---|
| 1 | 328 | 0 |
| 4 | 278 | 0 |
| 0 | 210 | 0 |
| 3 | 355 | 0 |

**Two gaps from the table below were acted on**, both having reached a third independent
report during the final waves:

- **`anti-queer-violence` ("Killed for Being Queer")** — added, subject 200, in the same
  theme as `racial-violence` and splitting from it. Four agents hit it on *Bondi Badlands*
  and filed it four different ways — `unsolved-murder`, `cold-case-reopened`,
  `stranger-homicide`, `vanishing-and-institutional-failure` — each naming the
  investigation and none naming the motive. That scatter is the tell this document
  describes: disagreement about the fallback, not about the gap.

  Widening `racial-violence` to cover any bias motive was the other option and matches the
  house pattern — `mass-shooting` widened past firearms, `presidential-power` past the US.
  Declined, because those widenings removed a distinction nobody browses by and this one
  would collapse a distinction people do. `racial-violence` carries 404 episodes.

- **Wildlife and rare-plant trafficking** — declined as a subject, named in
  `organised-crime`'s definition instead (edit 5093). Three reports, but the catalog behind
  it is six to ten episodes: *Bad Seeds*, Radiolab's Rhino Hunter, Snap Judgment's Chasing
  Thunder, a Bear Grease anti-poaching episode, *The Outlaw Ocean*. That is
  `offshore-secrecy` territory. Same handling as the abusive-relationship candidate.

**`anti-queer-violence` has zero episodes on it.** It was created after the pass that would
have used it. Nothing routes to it until someone relabels the episodes that argued for it —
the five in the proposal's `examples` are the known starting set. A subject with no episodes
is exactly the dead weight the vocabulary has avoided so far, so this is the first thing to
close.

**One known-wrong label.** A *Growing Joy with Plants* cross-promo sits on `food-and-drink`.
The agent that wrote it said so in the same breath — plants are not food. One row.

**A trap for the next person running waves.** The top-level `remaining` field returned by
`label next` counts **all eight slices**, not the caller's. Two agents in the first wave
read it as their own and reported wrong remaining counts — one claimed 236 left in a slice
that had 78. Their labelling was fine; only their arithmetic was wrong. Telling the second
wave to ignore the field and treat an empty `episodes` array as the only end-of-slice
signal fixed it completely. Say it explicitly in the launch prompt.

## For the redo pass: gaps that cleared the bar too late

These reached three or more independent reports **after** the shows that produce them were
already fully labelled. A new subject would have caught nothing, so none was added. They
are not open questions — the evidence is in — they are work for the pass that relabels.

Check `left_to_do` before adding any of them; that check is the whole reason they are here
rather than in the vocabulary.

| gap | reports | the shows | where it landed instead |
|---|---|---|---|
| A military commander or a monk — Crazy Horse, Joan of Arc, Ungern-Sternberg, Ikkyu Sojun | 2 | History on Fire | `pioneer-biography`, `war-and-its-conduct` |
| An act of kindness that changed a life | 4 | Kind World | `friendship`, `personal-transformation`, `chronic-illness` |
| Bail, pretrial detention, the release lever | 3 | Uncuffed, 70 Million, Ear Hustle | `prison-life`, `reentry-after-prison` |
| A non-musician performer's life — Houdini, Annie Oakley, Andre the Giant | 2 | Disgraceland, Hollywoodland | `celebrity-life`, `history-retold` |
| ~~Anti-LGBTQ bias killing, where `racial-violence` covers the race case~~ | ~~2~~ → 4 | Bondi Badlands | **Resolved 08-01: `anti-queer-violence` added** |
| A big company that is not a tech company | 2 | Land of the Giants | `tech-industry-power`, even for Disney |
| ~~Wildlife and rare-plant trafficking~~ | ~~2~~ → 3 | Bad Seeds, Criminal | **Resolved 08-01: named in `organised-crime`** |

Both resolved rows are kept rather than deleted, because the thing worth remembering is
that each sat at 2 reports for days and cleared the bar only in the last waves. The rule
held: neither was added on the strength of the first two.

The hate-crime one is worth a second look because it is an **asymmetry**, not just a hole:
`racial-violence` gives a bias motive a home when the bias is racial, and nothing does when
it is not. That is the same shape as the women-only scope I wrote into
`gendered-constraint` and had to widen a few hours later.

**The one that is not a vocabulary gap.** Recurring news-analysis shows — Elon Inc., The
Journal, Foundering, Background Briefing, Trump Inc. — drew something like fifteen reports
across the run. An agent put it exactly: `tech-industry-power` became the default for Elon
Inc. even on episodes about custody battles and platform moderation. This is the same
family as trailers, clip shows and legal explainers: the *format* is the problem, not the
subject. No new subject fixes it. A `kind` field on episodes would.

## Still open

**Format, not subject.** Year-end roundups, podcast-recommendation episodes, cross-promo
bundles, trivia segments, Business Wars roundtables, Revisionist History essays. Four
agents, same conclusion: *"these aren't about a subject so much as a format the vocabulary
doesn't model."* No new subject fixes this. A `kind` field on episodes would. By the end of
the run this had drawn roughly fifteen reports and is the single largest unaddressed thing.

**No `group` entity kind, and it is blocked rather than forgotten.** Four agents filed a
band, the Provisional IRA, Hezbollah, the CIA, the NRA and the White Helmets as `company`.
`entities.kind` carries a CHECK constraint over six literal values; SQLite can only widen a
CHECK by rebuilding the table, which the additive-only migration rule forbids. So it is a
decision about that rule. `test_a_group_is_still_refused_and_this_is_a_known_gap` is what
flips when someone makes it.

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

**Where it stopped on 07-30: 28,044 of 29,215 labelled — 96% — with 1,171 left in four
slices.** Two waves on 08-01 cleared the rest. `remaining` is now 0 and there is nothing to
relaunch; the rest of this section is kept for the next pass that needs waves.

The 07-30 run stopped on a **subagent cap** — 200 spawned in one session — not on tokens
and not on anything being wrong.

**Set the subagent model to Sonnet explicitly on every launch.** The plan's locked
decision is *"Ceiling stays Sonnet, never Opus."*

The trap, as written on 07-27: **`.claude/agents/*.md` are not registered as agent types in
this environment.** Asking for `subagent_type: episode-labeller` failed with "agent type
not found", so those files were documentation of the contract, not configuration.

**This changed by 08-01.** `episode-labeller` is now registered and reachable, and all six
agents in the final waves ran as that type. Set the model on the launch call anyway. The
frontmatter `model: sonnet` may or may not bind depending on how the type was resolved, and
"may or may not" is not a provenance — which is the whole lesson of the paragraph below.

So the model has to be set on the launch call itself. Miss it and the session model does
the reading while `label.py record` stamps its `claude-sonnet-5` default regardless. That
happened for **25,317 rows on 2026-07-29** — far over budget, and the `model` column
asserting something false. Restated to `claude-opus-5` through
`edits.restate_label_model`.

The 11,084 rows from 2026-07-28 are left as `claude-sonnet-5`. Since the agent type was not
reachable on that date, those were probably Opus too — but "probably" is not a provenance,
and inventing one is the failure this section exists to prevent. Leave them.

The relabel runs as waves of eight agents keyed on `id % 8`. Each does 200–300 episodes
before running out of room. Relaunch against a **per-slice** count —
`id % 8 = n AND NOT EXISTS(...)` — never against the `remaining` field, which spans all
eight slices and misled two agents on 08-01. Briefs are at
`docs/briefs/lab-{0..7}.md`, and the agent definition is
`.claude/agents/episode-labeller.md`. (Until 08-01 this document pointed at
`scratchpad/lab-{0..7}.md`, which never existed in the repo — the briefs lived only in a
session-scoped temp dir and were one cleanup away from being lost. They are committed now.)

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

Then relaunch. Briefs are at `docs/briefs/lab-{0..7}.md`, one per slice, each capped at
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
