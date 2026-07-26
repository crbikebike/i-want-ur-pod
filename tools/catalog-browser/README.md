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

## Episode themes (anthologies)

Anthology shows have no arcs — every episode is a different story — but their episodes still
cluster by subject. Swindled's Ford Pinto, OceanGate, ValuJet and Peanut Corporation episodes are
one theme: a company knew and shipped it anyway.

```sh
python3 curation/arc-bakeoff/build-episode-themes.py extract --slug swindled
# run curation/arc-bakeoff/episode-theme-workflow.mjs  (args: {slug, count, showThemes})
python3 curation/arc-bakeoff/build-episode-themes.py merge --slug swindled --result <workflow.json>
```

Three passes: Sonnet open-codes every episode with no fixed vocabulary, Sonnet consolidates the
raw labels into 10–16 defined themes, Haiku assigns primary + up to two secondary from that frozen
list. The assignment runs **twice with different batching**; where the two runs disagree the theme
boundary is fuzzy, and that percentage is reported in the UI. It is the honest measure — the audit
only proves the shape is sane, not that the categories are real.

Adding another anthology means adding an entry to `SHOWS` in `build-episode-themes.py` describing
how to pull the subject out of its titles. Nothing else changes.
