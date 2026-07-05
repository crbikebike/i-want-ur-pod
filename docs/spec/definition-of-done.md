# Definition of Done

**Applies to every story in `ROADMAP.md`.** A story is "done" only when all of the
following hold. This is the checklist the build session runs before calling a story
complete — it is the standing acceptance bar so stories don't each restate it.

---

## 1. It builds

```bash
brew install xcodegen        # once
xcodegen generate
```

The generated `IWantUrPod.xcodeproj` builds for the iOS simulator with no errors and
no new warnings introduced by the story.

## 2. Tests pass

- Every determinate test listed under the story exists as an automated test where the
  layer allows it (model/parsing/queue logic → unit tests in the owning package's
  `Tests/`; UI-only assertions may be exercised via previews/UI tests or documented as
  manual steps).
- `swift test` passes for any package the story touched
  (`Packages/<Kit>/`), and the app test target is green.
- No test was skipped or commented out to make the suite pass.

## 3. Design fidelity

- UI matches the approved system: tokens, type, spacing, and motion from
  `docs/design/direction.md`, and the component behavior in `design/kit/**`.
- `scripts/verify-design-manifest.sh` runs clean — no Swift file cites an
  unregistered or nonexistent kit source (see `design/kit/MANIFEST.md`).
- New components are added to `design/kit/MANIFEST.md` with their kit source, or
  explicitly marked data-only (no design source), matching the existing header-comment
  convention in the model files.

## 4. Data & model hygiene

- No unintended SwiftData schema change. If a story genuinely needs a new field, it is
  called out explicitly (migration impact considered), not slipped in.
- User-owned fields are never clobbered by feed re-parsing (see
  `feed-field-mapping.md`): `isSubscribed`, `dateAdded`, `downloadState`,
  `playbackProgress`.
- New persistent types are registered in `ModelSchema.models`
  (`Packages/PodcastModels/.../ModelSchema.swift`).

## 5. Boundaries respected

- The frozen navigation contract holds (see `navigation-map.md`): shared services
  (search coordinator, playback engine, queue store) are created at app scope and
  injected, never constructed inside `AppShell`'s tab switch.
- Domain logic lives in its package (`FeedParsingKit`, `DownloadKit`, `PlaybackKit`,
  `ChapterKit`), not in the app target. The app target wires and presents.

## 6. Errors are typed, not fatal

- Failure paths surface typed errors and a user-visible state (empty/error), never a
  trap. Parsing, downloading, and playback all degrade gracefully per their spec docs.

---

If a story can't meet an item here, that's a signal to split the story or fix the
gap — not to lower the bar.
