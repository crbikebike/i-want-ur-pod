# Catalog browser

Browse all 315 shows, see the arcs the detector found and which rule found them, and record
whether each arc is right.

```sh
python3 curation/arc-bakeoff/build-catalog-index.py   # build data (needs curation/feeds/)
python3 scripts/serve-catalog.py --tailscale          # http://hfab.tailfa3bf9.ts.net:8420
```

Drop `--tailscale` to bind localhost only. That is the default on purpose — this box shares a
tailnet.

**Verdicts** land in `curation/arc-bakeoff/human-verdicts.json` (committed — it's the point).
Export them into a gold file `score.py` can read:

```sh
python3 curation/arc-bakeoff/export-verdicts-to-gold.py
```

A show marked *"no arcs here"* exports as an empty list. Those labelled negatives are the
valuable ones: with `score.evaluate(score_negatives=True)` an arc invented on an arcless feed
counts as pure junk, which is the failure mode the current 50-show gold set can't see.

## Three modes

The job is deciding whether ~1,600 detected groupings are real, so the tool is built around
that rather than around browsing.

- **Browse** — the catalog, faceted by review state, detection rule, feed status and category.
- **Review** — a queue. One grouping per screen with its episodes, judged by keyboard. Facets
  apply here too, so "review only limited-series arcs" is one click.
- **System** — what the pipeline is, with every box marked built / partly built / not built.

Colour marks where a grouping came from: grape for a model-proposed theme, plain for a
regex-detected arc, mint for anything you have looked at. Nothing waits on your approval —
see `docs/design/the-catalog.md`. Review is for spot-checking the low-confidence handful,
not for working through all 1,600.

**Keys:** `/` search · `j`/`k` move · `enter` open · `1` real · `2` not real · `3` unsure ·
`esc` back.

Regenerate the index after changing `approaches.py` — arc indices are positional, and the
exporter will flag any verdict that no longer lines up rather than mis-attach it.

## Episode themes

Themes are a **second index over the whole catalog**, sitting beside arcs rather than behind
them. An arc is a multi-episode story; a theme is what one episode is *about*. An episode
inside an arc still has a subject, so it still carries themes. Radiolab is the shape that
proves it: 5 arcs, 654 standalone episodes, one vocabulary over all of them.

Scope is every full episode — 303 shows, 27,444 episodes — with no size floor and no arc
filter. See `curation/arc-bakeoff/THEMING_PROMPT.md` for the full brief.

```sh
python3 scripts/fetch-feed-descriptions.py              # step 0, once: per-episode synopses
python3 curation/arc-bakeoff/build-episode-themes.py prepare
# run the assign workflow over the batch plan
python3 curation/arc-bakeoff/build-episode-themes.py finalize --vocab <path to vocabulary>
```

**One shared vocabulary, not one per show.** Per-show vocabularies do not compose: two shows
coin two slugs for the same idea and cross-show discovery silently fails. The 145 episode
themes are their own taxonomy — they are *not* children of the 30 show-level themes in
`curation/catalog/themes.json`, because the two levels cut the catalog differently and the
episode level is far more granular. Each carries `relatedShowThemes`, a soft link that may be
empty.

**Confidence rides on each theme application, not on the episode.** An episode has a primary
and up to two secondaries; a single score let a strong primary mask a weak third pick, which
is exactly the row worth pruning later. The score is recorded and acted on nowhere.

**Segment names are never themes.** Bear Grease repeats `This Country Life` across 161 of 418
episodes; as a theme it would mean nothing outside that show. `prepare` detects repeating
prefixes by frequency and splits them into their own field so the model themes the content
instead. Show names, host names and format labels are excluded the same way.

**A theme used by one show is flagged, not deleted** (`showSpecific`). Some subjects genuinely
appear once. Those flags are the review queue for a later merge pass.

### In the workbench

- **Theme filter on show detail** — built from that show's `themesUsed`. Most shows have no
  arcs, so there it is the only structure for digging through hundreds of episodes.
- **Theme pages** (`#/theme/<slug>`) — one theme, every show that uses it. This is the
  cross-show question the whole exercise exists to answer; click any theme badge to get there.
- **Facets** — model confidence (now per application), show-specific themes, junk-drawer
  suspects, audit-flagged shows.
- **System view** — run-level totals, kept to numbers.

Audits flag and never halt: a failing show or theme is marked and the run continues. Nothing
is dropped from the corpus or from any show's output.
