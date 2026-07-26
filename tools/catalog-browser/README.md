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

**Keys:** `j`/`k` move · `enter` open · `1` right · `2` wrong · `3` unsure · `0` clear ·
`n` no arcs here · `esc` back.

Regenerate the index after changing `approaches.py` — arc indices are positional, and the
exporter will flag any verdict that no longer lines up rather than mis-attach it.
