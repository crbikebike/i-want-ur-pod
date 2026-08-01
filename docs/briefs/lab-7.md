Read /home/hf/claude/i-want-ur-pod/.claude/agents/episode-labeller.md first — it defines the task.

**Whoever launches this must set the subagent model to Sonnet explicitly.** As of 2026-08-01 the `episode-labeller` agent type *is* registered and reachable, which was not true when this brief was first written. Do not rely on the `model: sonnet` line in its frontmatter anyway — set the model on the launch call itself. Get this wrong and the session model does the reading while `label.py record` stamps `claude-sonnet-5` regardless, which is exactly how 25,317 rows came to assert a provenance that was false.

You are slice 7 of 8. Every command carries `--slice 7/8`:

    cd /home/hf/claude/i-want-ur-pod
    python3 -m admin.api.label vocab
    python3 -m admin.api.label next --limit 20 --slice 7/8

Write each batch to its own file under /tmp/claude-1000/-home-hf-claude-i-want-ur-pod/relabel-batches/ — `<prefix>-b1.json`, `<prefix>-b2.json`, … — then record it:

    python3 -m admin.api.label record /tmp/claude-1000/-home-hf-claude-i-want-ur-pod/relabel-batches/<prefix>-b1.json

**Stop after 10 batches (200 episodes) and write your report.** This is a hard cap, not a target — stopping cleanly at a known point beats being cut off mid-batch, and another wave picks up exactly where you left off. `remaining` counts all eight slices, so ignore it as a stop signal; count your own batches.

Work steadily rather than rushing. A wrong high-confidence label ships; a low-confidence one routes to a human, which is the correct outcome for a coin flip.

The vocabulary is 198 subjects. Newest: `literary-drama-fiction` ("A Novel, Performed") — scripted drama adapting a novel or telling a realist story about ordinary lives, with no crime to solve and nothing supernatural. The other seven fiction subjects are all genre-coded, so three agents had to force Dickens, Kipling and A Fine Balance into audio-drama-mystery. Newest: `invented-category` ("Where a Category Came From") — how race, whiteness, masculinity or class was built and what it was built to do, traced across centuries rather than through one event. Three agents were forcing Scene on Radio's Seeing White and MEN seasons onto history-retold, which one of them said no listener would ever search. Newest: `talking-about-music` (hosts talking about music as music — chart round-ups, trivia, listener mail; the music twin of `talking-about-film`, which agents have already used 25 times) and `ideas-and-argument` ("An Argument About How to Live" — a thinker making a case, which is what most of CBC's *Ideas* is; four agents were forcing those onto `psychology-of-belief` and `faith-and-doubt`).

Also changed: **`mass-shooting` is now "One Attack, Many Victims"** and the weapon no longer matters — a stabbing, a bombing or a vehicle all belong there. Two agents hit that edge, on Richard Speck and on the 1927 Bath School bombing. The distinction was always simultaneity, never firearms.

- **A life, told** now has shelves beyond music and film: `political-figure-biography` (a ruler or politician's life, any country), `founder-biography` (a founder or mogul, including the fight over an inheritance), `pioneer-biography` (explorers, inventors, reformers). Seven agents reported this gap; a splitter measured that 42% of `history-retold` was a life, not an era.
- `talking-about-film` — hosts talking about films as films: rankings, rewatches, listener mail. The pleasure is the conversation. Four agents were parking these on `hollywood-history`.
- `authorised-intrusion` — a red team, a pen test, a bug bounty. Nobody is a victim and nobody is pursued, so `hacking-and-cybercrime` was the wrong frame.
- `law-explained`, `schooling-and-policy`, `gendered-constraint`.
- `stranger-homicide`, `mass-shooting`, `heist-and-robbery`.
- The Old Hollywood cut: `film-career-biography`, `studio-system`, `screen-representation`, and `political-persecution` — blacklists, loyalty oaths, dissidents hunted abroad. That last one is catalog-wide, not a Hollywood subject, and has already fired on Manzanar, Weimar Germany, Xinjiang and an Egyptian singer.

Two housekeeping notes: **`presidential-power` is now "Holding the Office"** and covers any country's highest office — the office and what a leader does with it, never the leader's life. And **`music-scene-history` is retired** as a duplicate of `music-scene-movement`; use the latter.


Many of the 186 are fine-grained splits, added because a pilot found one show putting 82% of its episodes on a single label — four for the built environment, five for hacking, four for survival, two for personal relationships, four for Old Hollywood. Read their definitions and use the distinctions; that is the point of this pass.

Before your first batch, run `ls w7*.json` and pick a prefix nobody has used yet (`w7c-b1.json`, `w7d-b1.json`, …). The scratchpad is shared with seven other agents and with every earlier wave on your own slice, so `w7-b1.json` is very likely taken. Overwriting a recorded file loses nothing, but overwriting a live one loses a sibling's batch.

Report at the end: episodes labelled, the confidence split, which of the newer subjects you reached for, and any show where the vocabulary still did not fit.
