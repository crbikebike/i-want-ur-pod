# The Catalog

Audience: anyone working on story arcs, themes, or the show taxonomy. This is the
referenceable design. Cite it by path (`docs/design/the-catalog.md`).

Supersedes `taxonomy-architecture.md`, which described a curation store with human
sign-off. That is gone — see "What changed" at the bottom.

## What it is

One dataset that ships with the app and refreshes from a public URL. It holds **themes,
shows, arcs, and per-show themes** for anthologies that warrant them.

The name is not new. `IWantUrPod/Resources/catalog.json` already ships 315 shows with
their theme mappings. The Catalog is that file, extended.

| | Count | Ships today |
|---|---|---|
| **Themes** — the 30 that drive Explore | 30 | yes, `themes.json` |
| **Shows** — title, artwork, network, its themes | 315 | yes, `catalog.json` |
| **Arcs** — runs of episodes that are one story | 1,583 across 221 shows | **no** |
| **Show themes** — per-show, for anthologies | 14 (Swindled only) | **no** |

## The user's path

1. Opens the app, browses themes → The Catalog gives the 30. *Ships today.*
2. Picks a theme → The Catalog gives every show tagged with it. *Ships today.*
3. Picks a show → The Catalog gives **that show's arcs and its own themes**. *Missing.*
4. Episodes The Catalog doesn't cover → **regex, on the phone**. *Runs, not wired this way.*
5. Nothing left → list the episodes, no arcs shelf. *Ships today.*

Step 3 is the entire gap. Everything else already works.

## The one rule: resolution is per episode

The Catalog is a snapshot keyed by episode guid. Shows publish on their own schedule, so
it is always behind the feed. Therefore:

```
for each episode in the feed:
    guid in The Catalog?  → use its grouping
    guid unknown?         → regex it; if it matches an arc already in
                            The Catalog, it joins that arc
```

Consequences:

- **Regex is not a fallback, it is a permanent complement.** It runs for every show, always,
  covering everything newer than the last export. A new `Part 6` joins the series it belongs
  to instead of floating as an orphan.
- **Staleness degrades smoothly.** A day behind, one episode is regexed. Six months behind,
  most of the show is. Nothing breaks anywhere on that curve.
- **A feed you add yourself is the far end of that curve** — a private or premium URL is never
  in The Catalog, so all of it is regexed. That is the standing reason
  `Packages/PodcastModels/Sources/PodcastModels/EpisodeArcs.swift` has to stay good.

## How it is produced

On this machine, by hand, occasionally:

1. `scripts/fetch-atlas-feeds.py` → the corpus (`curation/feeds/`, gitignored).
2. `curation/arc-bakeoff/approaches.py` (`A8-cascade`) → arcs. Free, exact, no model.
3. `curation/arc-bakeoff/episode-theme-workflow.mjs` → per-show themes, but **only for
   shows regex could not group**. Swindled has themes because it has no arcs; American
   History Tellers never needed them.
4. `curation/arc-bakeoff/build-catalog-index.py` → joins it together on `slugify(title)`.

**Join on `slugify(title)`** (`scripts/build-catalog.py:34`) — not `feedUrl` (8 URLs are
shared by two shows) and not `catalog.id` (a stale positional index; 231 of 315 are wrong).

## Confidence, not sign-off

Nobody is going to review 1,600 arcs, so nothing waits on approval. Everything produced
ships. Confidence exists to tell you which handful is worth a glance.

**For themes** the model reports its own confidence, and the labelling pass runs twice with
different batching — where the two runs disagree, the category boundary is fuzzy.
Swindled: 104 high, 32 medium, 17 low, 76% two-run agreement.

**For arcs** the rule that produced it is the signal. `pipe` and `part` are near-certain —
the counter is in the title. `affix-prefix` and `bare-counter` infer more and are where
junk lives. Arc size is the other tell: anything over ~20 episodes is suspect.

Filter to them in the workbench (`Browse → Detected by`), or read the list below.

## Worth a glance right now

**The Swindled vocabulary has a junk drawer.** 9 of the 17 low-confidence episodes landed in
`swindlers-and-grifters`, and it appears in 4 of the 5 most-disagreed boundaries. Its
definition is "an individual con artist… without a fund, a company, or a religious front" —
defined by what it is not, so everything ambiguous falls in. Fixing that one category is
worth more than re-checking 17 episodes.

Also debatable: **Nikola Motor Company** → *Fabricated Stories & Hoaxes for Fame*. It was
securities fraud — a truck rolled downhill for a promo video to move the stock.

**Oversized arcs**, the shape most likely to be wrong — 8 in the whole corpus:

| Episodes | Show | Arc | Rule |
|---|---|---|---|
| 144 | Fake Diana | Maura Murray | `part` |
| 72 | Zeit Verbrechen | Adventskalender | `hash` |
| 50 | Lore | REMASTERED | `ep` |
| 29 / 27 | We're Alive | We're Alive: Descendants | `part` |
| 22 | 99% Invisible | Mini-Stories | `volume` |
| 20 | You Must Remember This | Erotic 90's | `paren` |
| 20 | Fake Diana | Brianna Maitland | `part` |

## How it ships

```
this machine (private)          public (static)              the app
  build → export  ───────────►  manifest.json  ~80 B    ┌─► bundled at release
                                arcs-v14.json  ~200 KB  └─► refreshed when reachable
```

The app checks `manifest.json` on launch; same version means an 80-byte round trip. A new
version means one download, cached forever because the filename changes on every publish.
Host: **Cloudflare Pages free tier** (GitHub Pages needs a paid plan for private repos).
If the host is unreachable the bundled snapshot stands and the failure is invisible.

Writes never leave this machine. Only the export is public.

## The Catalog is not the show

A show's public RSS is often not its archive, and The Catalog must not assume it is.
**This American Life** publishes a rolling window — 15 items numbered 884–892 against ~892
episodes. **Twenty-six shows are samplers**: a trailer and episode one, the rest behind a
subscription. Wondery ships an item literally titled *"Where to find Episodes 2-6 of The
Shrink Next Door"*.

This is not our truncation — `fetch-atlas-feeds.py` caps at 800, so a feed holding two items
served two. `build-catalog-index.py` labels each: `sampler` 26, `short-series` 5,
`unknown-short` 6, `empty-feed` 3, `windowed` 1.

## Constraints

- Stdlib Python only; no pip, no SDK, no API key. The model is reached through Claude Code
  `Workflow` subagents.
- `curation/feeds/` and `catalog-index.json` stay gitignored.
- Don't join on `feedUrl` or `catalog.id`. See above.

## What changed, and one thing to push back on

Dropped from the previous design, because none of it survives without human curation:
the three-layer merge rule, durable ids matched by episode overlap across re-runs, verdicts
as a stored entity, and the edit log.

**And with those gone, the argument for SQLite goes too.** It was chosen for transactional
edits, an edit history, and stable ids that keep verdicts attached through a detector change.
None of those are needed now. What is left is a build step over files that already exist —
`catalog-index.json` and `episode-themes/<slug>.json` — so this doc assumes files. Say so if
you want the database anyway; it is a small change either way.

## Known corpus defect

Eight "anthology" feeds resolve to the wrong show — `broken-record` is a teenager's music
vlog, `hit-parade` a Spanish radio chart show, `homecoming` a self-help podcast, plus
`animal`, `earshot`, `shift`, `startup`, `gun-machine`. And `making-obama` / `making-oprah`
are byte-identical: one WBEZ umbrella feed resolved twice. Cause:
`scripts/fetch-atlas-feeds.py` matches on title similarity alone, so a same-named podcast
wins. Any taxonomy over those feeds describes the wrong show.
