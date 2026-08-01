# Two sessions, one catalog

Live coordination file. Two Claude Code sessions are working this repo at the same time.
Both can write. Neither can see the other's conversation. This file is the only channel.

**Read this before your first write. Update it before you stop.**

Last updated: 2026-08-01, by pod-sesh-2.

---

## Who is who

| session | what it has been doing |
|---|---|
| **pod-sesh-2** | Phase 3 relabel. Finished it. Vocabulary edits. `docs/briefs/`, `HANDOFF-phase3.md`. |
| **the other tab** | The graph build. Porting `catalog/build/` off the stale label table. |

pod-sesh-2 inferred the second row from uncommitted diffs, not from talking to anyone.
**If you are that session, correct this line.** Guessing at what the other session means to
do is exactly the failure this file exists to prevent.

---

## The one hard rule

**Only one session runs a write pass at a time.**

The database protects itself. It does not protect the repo.

- `catalog/catalog.db` is a **binary** file. Two sessions committing it means a conflict you
  cannot merge — you pick a side and lose the other side's work.
- `pending()` and `NOT EXISTS` mean no episode gets labelled twice, so *the data* is safe
  even if two labelling waves overlap. The commit is what breaks.
- `curation/source/decisions.jsonl` is append-only. Two sessions appending gives you a
  textual conflict that is annoying but recoverable.

Claim the write below before you start. Release it when you stop.

### Write claim

    HELD BY: nobody
    SINCE:   2026-08-01 14:40 PDT
    DOING:   -

pod-sesh-2 released the claim after committing `46abccf`. It ran six labelling agents and
two vocabulary edits and is now idle.

---

## State right now

Branch `feat/catalog-workbench`, **5 commits ahead of origin, 87 ahead of main.** Nothing
here has been pushed. That is a third party's problem waiting to happen — see *Open
questions*.

**Committed by pod-sesh-2 today:**

| commit | what |
|---|---|
| `e3ef25c` | Rescued the eight slice briefs into `docs/briefs/` |
| `60db90f` | Relabel wave — slices 0, 1, 3, 4 |
| `3e298fb` | Finished the relabel — `remaining: 0` |
| `46abccf` | Vocabulary 198 → 199, handoff doc brought current |

**Uncommitted, not pod-sesh-2's:**

    M catalog/build/arcs.py
    M catalog/build/edges.py

---

## What changed under the graph build

This matters to the other session specifically, because its diffs touch all of it.

**The relabel is done.** `python3 -m admin.api.label status` returns `remaining: 0`.
29,215 episodes, 275 shows, 19,005 high / 22,624 medium / 4,996 low. Run id
`2026-07-relabel-v176`, which is what `catalog/build/labels.py:CURRENT_RUN` already points
at. Any query against that run now returns a complete catalog rather than a partial one.
If you measured coverage before today, **re-measure**. Your numbers are stale, not wrong.

**`episode_subjects` is the old table.** `episode_labels` is the current one, keyed by
`run_id`. Three runs coexist and none overwrites another:

| run_id | rows | what it is |
|---|---|---|
| `2026-07-theming` | 43,818 | the original Haiku pass |
| `2026-07-relabel` | 319 | the pilot against 148 subjects |
| `2026-07-relabel-v176` | ~46,600 | current |

Filtering on `run_id` is not optional. Without it you sum three passes.

**The vocabulary is 199 subjects, not 198.** Two changes today:

- `anti-queer-violence` added — id 200, "Killed for Being Queer".
- `organised-crime` description widened to name wildlife and rare-plant trafficking
  (edit 5093).

**`anti-queer-violence` has zero episodes on it.** It was created after the pass that would
have used it. If your build asserts every subject has at least one episode, or drops empty
subjects from the graph, **this one will trip it** — and that is a true report of a real
gap, not a bug in your code. Closing it needs a small relabel pass, which nobody has run.

---

## Things pod-sesh-2 found and did not fix

Left deliberately. None is claimed. Take any of them, but say so here first.

1. **One wrong label.** A *Growing Joy with Plants* cross-promo sits on `food-and-drink`.
   The agent that wrote it flagged it itself — plants are not food. One row.
2. **`anti-queer-violence` needs a backfill.** Candidates: *Bondi Badlands*, the Scott
   Johnson case, Matthew Shepard on RedHanded, Brianna Ghey on File on 4, several
   *This Is Actually Happening* episodes. Read them; do not pattern-match titles. A keyword
   sweep for this surfaced a Business Wars episode about Amazon.
3. **Merged and mismatched feeds.** Several shows carry a `showAbout` that does not match
   their episodes — *Boss Class* under "The Prince", *Cover Up* described as music history
   over a Chappaquiddick episode, *Unfinished Justice* described as an NYPD cold-case series
   over an unrelated murder. Same family as the Espions merged feed in `HANDOFF-phase3.md`.
   This is a **Phase 2 feed repair**, not a labelling problem.
4. **Format is not subject.** Trailers, year-end roundups, cross-promos and clip shows have
   no home in a subject vocabulary and never will. Roughly fifteen agent reports across the
   run. A `kind` field on episodes fixes it. Nobody has designed one.

---

## Traps, both learned the hard way

**The `remaining` field spans all eight slices.** `label next --slice n/8` returns a
top-level `remaining` that counts the whole catalog, not your slice. Two agents read it as
their own and reported wrong numbers — one claimed 236 left in a slice that had 78. A slice
is empty when `episodes` comes back empty, and only then.

**Set the subagent model on the launch call.** Do not trust `model:` in an agent's
frontmatter. `label.py record` stamps `claude-sonnet-5` regardless of what actually did the
reading, so getting this wrong writes a false provenance. It already did once, for 25,317
rows on 2026-07-29.

**`.claude/agents/*.md` are registered now.** `HANDOFF-phase3.md` says they are not. That
was true when it was written and stopped being true by 2026-08-01.

---

## Open questions, for the human

1. **Push, or keep going local?** 87 commits ahead of `main` and 5 ahead of the remote
   branch. Two sessions on one unpushed branch is the collision risk in its purest form.
2. **Which session owns which area from here?** The clean split looks like: catalog data and
   vocabulary to one, `catalog/build/` and the graph to the other. Neither session should
   pick that on its own.

---

## How to update this file

Edit the claim block and the date. Correct anything about your own session that the other
one guessed at. Keep entries short — this is a channel, not a log.
