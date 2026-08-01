# pod-sesh-1, final handoff

Written 2026-08-01 as this session ends. It hit the 200-subagent cap and cannot delegate
again, so it is being retired rather than kept alongside you. **Assume nobody can answer
questions about anything below.** Everything it knew that mattered is here, in
`HANDOFF-phase3.md`, in `SESSIONS.md`, or in a commit message.

You own everything now. `SESSIONS.md`'s split no longer applies.

---

## What this session did

Ran Phase 3 Jobs 0–4 and 6: re-read every feed, ran the A8 arc cascade into the catalog,
screened and rewrote arc names, relabelled 28,000 of 29,215 episodes (you finished the
last 1,011), grew the vocabulary from 148 to 199 subjects, and repointed the graph build
at the labels the relabel actually wrote.

---

## State, verified today

| | |
|---|---|
| kept shows | 275 |
| live episodes | 29,215 |
| subjects | 199 (1 with zero episodes — `anti-queer-violence`, which you added) |
| arcs | 1,809 across 252 shows; 23 anthologies correctly have none |
| labels, run `2026-07-relabel-v176` | 46,625 rows, `remaining: 0` |
| low-confidence primaries | **3,228** — the review backlog |
| `agreement` populated | **0** |
| entities | 14,339 |
| edges | 14,130 |
| depth 1 / 2 / 3 / 4 | 13 (all cut) / 0 / 208 / 67 |
| branch | `feat/catalog-workbench`, 90 commits ahead of `main` |

---

## Phase 3 is not finished. Two jobs remain.

The relabel was Job 4. The gate is *"every show reaches depth 3, and corrections from
review are feeding back into run prompts."* The first half is met. The second is not
started.

### Job 4.4 — escalation, and the `agreement` column

**This is the one thing Phase 3 was named for and it did not happen.** The plan says the
July run "never asked twice, so there is no record of which labels were solid and which
were coin flips." That is still exactly true. `agreement` is NULL on all 46,625 rows.

`confidence` is the model's opinion of itself. `agreement` was meant to be independent
votes — 3 reads of a doubtful episode, recording how many agreed. They are not the same
thing and only the second one is evidence.

Scope if you do it: the 3,228 low-confidence primaries, plus any subject used exactly once
in a show (the plan's noise rule, also never applied). Call it 4,000 episodes.

`edits.label_episodes()` already accepts `agreement` and `votes` per subject. Nothing else
exists.

### Job 5 — the review surfaces

`admin/api/queues.py` has two queues (feeds, inclusion) and `admin/web/src/App.jsx` renders
them. The plan calls for four more:

| surface | why |
|---|---|
| arc queue | 1,809 arcs, 8 flagged as not-a-story, none reviewed by a person |
| label queue, worst-first | the 3,228 lows exist to route here and currently route nowhere |
| vocabulary proposals | `admin.api.vocab waiting` is empty now but the door is built |
| runs surface | the `runs` table has 7 rows and nothing reads it |

The plan is explicit that the label queue must be **sampled, lowest agreement first, never
shown as a backlog to clear.** There is a warning in the Phase 2 handoff about a
15,000-item queue that nobody will ever finish. Do not reintroduce it.

Kit-first per `CLAUDE.md`: mock in `design/kit/`, get sign-off, then build.

---

## The redo set: 5,881 episodes

Episodes labelled correctly *for the vocabulary that existed at the time*, where the
vocabulary has since moved. Two overlapping causes:

1. **Under-read.** Labelled on ~299-character descriptions before the `feeds.py` parser fix
   (commit `1904adb`). 4,004 episodes still have descriptions ≤300 characters, though many
   of those are genuinely short in the source.
2. **Pre-split.** Sitting on a shelf that has since been carved up. All 236 Spooked
   episodes are on `supernatural-encounter`; 88 Hollywood labels predate the four-way cut;
   Casefile's 414 were all labelled before `stranger-homicide` existed.

```sql
SELECT count(DISTINCT l.episode_id) FROM episode_labels l JOIN subjects s ON s.id = l.subject_id
WHERE l.run_id = '2026-07-relabel-v176' AND l.role = 'primary'
  AND (s.slug IN ('hollywood-history','celebrity-life','history-retold','murder-close-to-home',
                  'unsolved-murder','serial-offender','kidnapping-and-captivity','courtroom-trial',
                  'education-system-failure','hacking-and-cybercrime','supernatural-encounter')
    OR l.episode_id IN (SELECT id FROM episodes WHERE length(description) <= 300));
```

**Run it under a new `run_id`, not this one.** `pending()` uses `NOT EXISTS` on
`(episode_id, run_id)`, so these will never be re-served under `2026-07-relabel-v176`.
A fresh id also keeps the comparison — that is the entire reason runs coexist.

`HANDOFF-phase3.md` has a table of six vocabulary gaps that cleared the evidence bar *after*
the shows producing them were already labelled. Those belong to this pass. **Check
`left_to_do` on the affected shows before adding any subject** — that check is why they are
notes rather than rows, and skipping it is how the four Old Hollywood subjects sat at zero
uses for hours.

---

## Decisions waiting on the human

1. **The `group` entity kind.** Four agents filed a band, the Provisional IRA, the CIA and
   the NRA as `company`. `entities.kind` has a CHECK constraint over six values; SQLite can
   only widen a CHECK by rebuilding the table, which the additive-only migration rule
   forbids. So it is a decision about that rule. `test_a_group_is_still_refused_and_this_is_a_known_gap`
   flips when someone makes it. My read: do the rebuild — `entities` is a build output and
   carries no audit history the rule exists to protect.
2. **A `kind` field on episodes.** ~15 agent reports. Trailers, cross-promos, clip shows,
   year-end roundups, recurring news-analysis shows. No subject fixes these and every one
   becomes a forced `low` in a human's queue. This is the largest unaddressed thing in the
   catalog.
3. **661 re-air duplicates.** Radiolab re-airs episodes years later with fresh GUIDs, so
   ingest correctly makes two rows. 608 title groups, 1,205 already labelled twice. Should a
   listener meet the same story twice? If not, which copy survives — the later one has the
   better text, the earlier one the true date.
4. **Push the branch.** 90 commits ahead of `main`, and this is the third handoff to say so.

---

## Traps. Every one of these cost real time.

**Name the run in every label query.** Three runs coexist in `episode_labels`. A reader that
forgets the `run_id` filter silently sums three eras — it does not error. This bit
`vocab.crowded()` (every crowding number was doubled, which pointed the whole splitting
effort at noise) and `edges.py`/`verify.py` (the graph was built from the July Haiku run
*after* the relabel finished). `catalog/build/labels.py:CURRENT_RUN` is the one place it is
named. Import it.

**`remaining` spans all eight slices.** `label next --slice n/8` returns a top-level
`remaining` for the whole catalog. Agents read it as their own and report nonsense. A slice
is empty when `episodes` comes back `[]`, and only then.

**Set the subagent model on the launch call.** `label.py record` stamps `claude-sonnet-5`
regardless of what did the reading. Getting this wrong wrote a false provenance for 25,317
rows. Repair door: `edits.restate_label_model()`.

**Derived values must be derived, not nudged.** `UPDATE shows SET depth = 3 WHERE depth = 2
AND ...` stranded Broken Record at depth 1 with seven arcs, forever. `catalog/build/depth.py`
recomputes the whole ladder in 0.2s.

**Correlated subqueries per show will lock the database for minutes.** The first
`depth.rebuild()` ran over four minutes holding the write lock. Grouped scans plus
`executemany`: 0.2s. If a build step holds the lock for minutes, that is a bug.

**Two rules that are each correct can hide a bug between them.** `feeds.py` read
`<itunes:summary>` first (a teaser for many publishers) and `refresh_episodes` never
overwrites with less. The comb read the teaser, correctly declined to shrink, and logged a
clean run — while silently skipping a quarter of the catalog. 10,587 descriptions grew when
it was fixed.

---

## How the vocabulary loop worked, because it is the useful part

An agent hits a gap, marks the episode **low** rather than forcing a fit, and says so in its
report. When three independent agents report the same gap, act.

**The signal is not that they agree there is a gap. It is that they disagree about the
fallback.** Five agents reaching for five *different* wrong shelves means the shelf they
want does not exist. One agent reaching for a wrong shelf is one agent being sloppy.

All 20 subjects added during the relabel got used — `film-career-biography` 107 times,
`founder-biography` 100, `political-persecution` 85. The best one came from a splitter that
argued **against** its own proposal (3 of 80 in its sample, below its own bar) and said to
judge it as a catalog-wide gap or reject it. That was `political-persecution`.

Two candidates were declined and that matters as much: an abusive-relationship subject at 2%
of its parent, and an industry-sector split with no natural end.

---

## What I would do next, in order

1. **Push the branch.** 90 commits, one machine.
2. **Job 5's label queue.** 3,228 low-confidence labels are the product of two days of
   deliberately truthful reporting and currently nothing reads them. Kit-first.
3. **The redo pass**, under a new `run_id`, with the six late-clearing gaps.
4. **Job 4.4 escalation** to fill `agreement`, which closes the gate honestly.
5. Then Phase 4. Half of it already exists — `admin/api/comb.py` has been run in anger twice.

---

## Mistakes this session made, so you do not repeat them

- Ran ~15,000 episodes on **Opus** when the plan said Sonnet, because it launched agents as
  `general-purpose` and never checked what model they were. It cost a lot and bought
  nothing measurable: Sonnet came in at 58.2% high / 11.0% low against Opus's 59.6% / 11.1%.
- Claimed the shared write lock **mid-run** instead of before, and then held it four
  minutes.
- Told the user twice that the fix for the model bug was `subagent_type: episode-labeller`.
  That agent type did not exist in this session. The second fix was wrong in a different way
  than the first.
- Wrote `gendered-constraint` scoped to women only, because the three reports that earned it
  were about women. An agent found masculinity had no symmetric slot hours later. A
  definition can be correct for its evidence and arbitrary one step outside it.
