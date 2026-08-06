"""Which labelling run the catalog is built from.

Label runs coexist. `episode_labels` is keyed `(episode_id, subject_id, run_id)` precisely
so a new pass never destroys the old one's answers, and three runs live in the database
right now:

    2026-07-theming        43,818 rows, Haiku, shown 150 characters per episode
    2026-07-relabel           319 rows, the pilot against the 148-subject vocabulary
    2026-07-relabel-v176   46,625 rows, the full pass against 198 subjects

That design is right, and it has one sharp edge: **every reader has to say which run it
means**, and a reader that forgets does not fail — it quietly returns the wrong era. That
happened. `edges.py` and `verify.py` were still reading `episode_subjects`, the July run's
table, after the relabel had finished. The graph that decides what the app recommends was
built from the pass the relabel replaced, and nothing complained, because a stale answer
looks exactly like a fresh one.

So the run is named here, once, and imported. Four modules had been about to hardcode it.

Changing this constant re-points the whole build at a different pass, which is a real
thing to want: it is how you would rebuild the graph from the old labels to compare, and
how a redo pass under a new `run_id` becomes live. Rebuild and re-run the named queries
after changing it.
"""

from __future__ import annotations

CURRENT_RUN = "2026-07-relabel-v176"

# The historical runs, kept so a comparison can name them without a magic string.
THEMING_2026_07 = "2026-07-theming"
PILOT_2026_07 = "2026-07-relabel"
