# Handoff — current state, written 2026-08-05

The entry point for a fresh session. (This file previously held the July Swift-era kit
reconciliation, superseded by the rewrite — see git history if that matters.)
Everything below is committed and pushed; verify claims against the database, not this
file.

## Where the program stands

| phase | state |
|---|---|
| 1 — catalog + graph | closed |
| 2 — admin workbench | closed |
| 3 — deep labelling | **closed 2026-08-05, merged to `main` (`811422e`)** — record in `HANDOFF-phase3.md` |
| 4 — hfab publisher | **deferred by decision** — stub at `specs/phase-4-hfab-publisher.md` |
| 5 — the web app | **starting.** Spec not yet written. See *Phase 5, exactly where it stopped* below |

Branch: `feat/catalog-workbench`, in sync with origin, merged into `main`. Both pushed.

## Phase 5, exactly where it stopped

The user chose to jump Phase 4 and start the webapp. What is already settled:

- **Locked decisions** (PROGRAM.md + memory): Expo, web target first; kit-first — the 18
  signed-off screens in `design/kit/screens/` are the design source of truth;
  `patterns-from-swift.md` informs; gate is the timed cold-start checklist under 3 min.
- **Data dependency**: no R2 publisher exists (Phase 4 deferred), so the app reads a
  **static release export** committed at build time — same shape a release would have, so
  R2 later is a URL swap. Building that exporter is Phase 5's first backend task.
- **Process** (memory: user stories + tight UI cycles): the spec goes in
  `docs/specs/phase-5-web-app.md` as JTBD stories with human-in-the-loop stops; the
  first UI slice is the big checkpoint.

**The open question, mid-conversation when context cleared:** which slice is the first
UI checkpoint. Options tabled: First-run + Explore themes (recommended — the discovery
spine, and the cold-start gate lives there), Home feed, Search, Detail + playback. The
user was about to clarify something about the question when they stopped to ask for this
handoff. **Resume by asking what they wanted to clarify.**

## The catalog, in one paragraph

275 kept shows, 29,215 live episodes, 201 subjects under 33 themes (the newest theme is
**Formats**: `trailer` 924 episodes, `introducing` 171 — format is the label, decided by
the user from inside the review queue). 1,733 arcs. Run `2026-07-relabel-v176` carries
~50k label rows; `agreement` is filled on all 5,195 once-doubtful labels (3-vote
escalation). Depth: 92 shows at 3, 183 at 4. The whole catalog provably rebuilds from
`curation/source/` — `python3 -m catalog.build.verify_rebuild` must say "rebuild proven".

## The review loop (live, in use)

The workbench's third tab (`http://hfab:5173/#labels`, phone over tailnet) serves
doubtful labels worst-first — 285 scatter cases remain. Verdicts write through
`edits.label_episodes` and append to `docs/briefs/corrections.md` (27 lines and growing);
**every labelling brief cites that file** — it is the feedback half of the Phase 3 gate.

## Running services + their traps

- API: `python3 -m admin.api.main` — binds the **tailscale IP** (100.117.245.23:8828),
  never loopback. **No auto-reload: restart it after touching admin/api/** or it serves
  stale shapes (this bit twice).
- Web: `cd admin/web && npm run dev` — vite on :5173, hot-reloads, `allowedHosts` covers
  `hfab`. The `/api` proxy must target the tailscale IP — `hfab` resolves to 127.0.1.1
  locally.
- `pkill -f admin.api.main` kills your own shell too (the pattern matches it); run the
  pkill and the restart as separate commands.
- Headless screenshots: `google-chrome --headless --window-size=390,844 --screenshot=…`
  — phone-size visual verification is the house rule for UI changes.

## Parked, recorded, not lost

Redo pass (5,881 under-read/pre-split episodes, fresh run_id) · arc/vocab/runs review
surfaces · `group` entity kind (CHECK-constraint decision) · 661 re-air duplicates ·
remaining vocabulary gap candidates (modern espionage ~8 reports, Kind World's kindness
gap 5, Bear Grease's whole genre, stalking 4 — all in escalation voter reports and
`HANDOFF-phase3.md`).

## Traps that cost real time (short form; long form in HANDOFF-phase3.md)

Name the run_id in every label query — three runs coexist and an unfiltered query
silently sums eras. Set the subagent model on the launch call. `remaining`/top-level
counts span all slices. Depth is derived — after anything touches confidences, run
`depth.rebuild(conn)` **and commit**, or verify_rebuild reports a phantom mismatch.
pytest's default norecursedirs eats a directory literally named `build`.

## Doc map

`PROGRAM.md` phases + gates · `HANDOFF-phase3.md` the Phase 3 record · `SESSIONS.md`
the two-session protocol (dormant) · `briefs/` labelling briefs + `corrections.md` ·
`specs/` per-phase specs · `patterns-from-swift.md` what the old app got right.
