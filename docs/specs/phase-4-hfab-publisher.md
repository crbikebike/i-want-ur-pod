# Phase 4 — hfab Publisher (stub)

**Status: deferred, 2026-08-05.** Phase 5 (the web app) starts first, by decision. This
stub records the scope so deferral is a bookmark, not a loss.

## Scope, from PROGRAM.md

Always-on agent on hfab: comb feeds, label new episodes, publish incremental releases to
R2. Auto-publishes labels. Alerts on anomalies — new theme appearing, show going silent,
confidence dropping. Holds arcs and vocabulary changes for approval.

## What already exists for it

| piece | where | state |
|---|---|---|
| Feed comb | `admin/api/comb.py` | run in anger twice; writes through the edits door |
| Labelling loop | `docs/briefs/lab-*.md` + `admin/api/label.py` | proven at 46k labels; briefs cite `corrections.md` |
| Doubt escalation | `admin/api/escalate.py` | 3-vote machinery, reusable per comb cycle |
| Release identity | `releases` table + `catalog/build/fingerprint.py` | content hash proves reproducibility |
| Rebuildability | `catalog/build/verify_rebuild.py` | all seven layers proven from `curation/source/` |
| Anomaly raw signal | `agreement`, `confidence`, `runs` table | `runs.recent()` exists, still unread |

## What Phase 5 needs from it before it exists

The app was meant to download R2 release artifacts. Until the publisher ships, the app
reads a **static export committed at build time** — same shape a release would have, so
swapping in R2 later is a URL change, not a rewrite. The exporter for that artifact is
Phase 5's first backend task and becomes this phase's `publish` step later.

## Decisions to make when this phase starts

- Cadence (nightly? on-demand?), and what "incremental" means for a `.db` artifact.
- Alert channel (the workbench? push?), and the anomaly thresholds.
- Whether the escalation 3-vote pass runs on every comb or only on confidence dips.
- The parked catalog work that fits naturally here: the redo pass (5,881 episodes,
  fresh run_id), 661 re-air duplicates, the `group` entity kind.
