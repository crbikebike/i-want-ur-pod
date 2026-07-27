# i want ur pod

Project-specific guidance for Claude Code. Auto-loaded for sessions started in this directory.

## What this is

A discovery app for **story-driven and investigative** podcasts. Less talk show, more
story arc. No host-interviews-guest shows.

Read `docs/PROGRAM.md` first — it holds the phase order, the locked decisions, and each
phase's gate. Specs live in `docs/specs/`, one per phase, written when the phase starts.

## Layout

| Path | What it is |
|---|---|
| `curation/source/` | Read-only inputs. Never edited by hand or by the app. |
| `catalog/` | Schema and the build that compiles source into the shipped `.db`. |
| `detector/` | The A6 regex arc cascade. For **user-added feeds only**, not the catalog. |
| `design/kit/` | Design source of truth. HTML/CSS mocks, signed off before code. |
| `docs/` | `PROGRAM.md`, `specs/`, `patterns-from-swift.md`, `reference/`. |

## The catalog

The SQLite database is the source of truth, with an append-only `edits` table for audit
and undo. The `.db` is a build output — never commit one, always be able to rebuild it
from `curation/source/`.

Every entity has an immutable slug. Incremental releases never renumber.

## Verification

After making UI or code changes, always launch and visually verify the running app (take
a screenshot), not just run build/test.

For catalog changes, show the actual query output. "It returned rows" is not verification
— the rows have to be defensible.

## CSS / Frontend Conventions

For mobile scroll-lock, use `position: fixed` on the body rather than `overflow: hidden`,
which does not block touch scrolling.

Design lives in the kit; code cites the kit. When a tuned constant lands in code, name
where it came from — see `docs/patterns-from-swift.md` for why this matters.

## Remote / SSH Operations

Before starting extraction/copy to remote SSH directories, confirm the exact target
directory path with the user first.

## Debugging

When a fix doesn't render, suspect stale build cache and check for concurrent build/dev
processes before assuming the code is wrong.

## History

The Swift app and the regex-taxonomy pipeline are at tag
`reference/swift-app-2026-07`. `main` holds them too. They are reference, not code to
extend — but `docs/patterns-from-swift.md` records what they got right.
