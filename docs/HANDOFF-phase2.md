# Phase 2 — where things stand

Written 2026-07-27, mid-Job-1, when Chris called a stop to look at the user stories.

## Running right now

The workbench is live at `http://100.117.245.23:8828/` as a systemd user service
(`systemctl --user status workbench`). It survives reboots. Branch
`feat/catalog-workbench`, all pushed, 182 tests green.

## What is built

- **Job 0, complete.** Migrations (additive-only, checksummed), the single write path
  (`admin/api/edits.py`), the guard that stops `migrate.py` clobbering the catalog, soft
  delete across every table.
- **Job 1, built but not accepted.** Inclusion queue API and UI. Stop 1 has not cleared.

## The open question

Chris asked to see the user story list and said he expected it to make no sense. That is
the live thread. The stories are in
`/home/hf/.claude/plans/i-am-starting-to-soft-stallman.md` under "User stories".

My own read, written before hearing his: the stories are phrased as UI mechanics rather
than jobs. "I decide with one thumb" and "I see the size of the job" are interface
decisions wearing a user-story costume; they describe the screen I had already imagined
instead of what he is trying to get done. Job 1's real job is one sentence — *the catalog
is supposed to be story-driven shows only and nobody has ever checked* — and none of the
six stories say it.

Do not resume building until that is settled.

## Corrections he made during Job 1, all applied

Each of these was something I got wrong and he caught:

1. Dark mode → warm construction paper, dark ink, deep automotive pastels.
2. A gradient with a hard edge under the toast → removed entirely.
3. "7 episodes are also in The Loop" stated a fact with no consequence → notes now say
   what a flag means and which way it points. Also found the flags are three different
   problems, only two of which are inclusion questions.
4. "Does it belong?" then "Keep or Cut" → both bad. The first was vague, the second just
   repeated the buttons. Currently "Vetting the Catalog", unconfirmed.
5. Keyboard shortcuts existed but were invisible → stamped on the buttons.
6. Artwork was being served at 3.9 MB per card → 38 KB, plus a cachebust for when the
   comber notices art has changed.

## Facts worth not rediscovering

- The 16 flagged shows: 10 share a feed (real duplicates), 3 are cross-promotion (keep
  both, not an inclusion question), 3 have a feed serving a different programme.
- Apple category is useless for judging whether a show is narrative. Sorting by it puts
  30 for 30, Rough Translation, Bodies and Normal Gossip in the first ten.
- The episode-subjects queue is ~15,000 items and Phase 3 relabels all of them. It must
  never be presented as something to clear by hand.
