# Playback State Machine

**Single source of truth for Epic E4 (Playback, download-first).** Defines the
player states, transitions, progress persistence, and lock-screen mapping so E4 can
be built without per-story hand-holding.

Home package: `PlaybackKit` (`Packages/PlaybackKit/`). Progress persists onto
`Episode.playbackProgress` (`Packages/PodcastModels/.../Episode.swift`).

---

## Core rule: download-first

**An episode plays only from a completed local file.** There is no streaming in v1.
Concretely: `PlaybackKit` accepts a local file URL, not a remote one. The Play
affordance is offered **only** when `episode.downloadState.isDownloaded == true`
(see `DownloadState.swift`). This removes every buffering/seek-over-network edge
case from v1.

---

## Player states

| State | Meaning |
|---|---|
| `idle` | No episode loaded. Mini-player hidden (see `navigation-map.md`). |
| `loading` | A downloaded file is being prepared for the AVPlayer. |
| `playing` | Audio advancing; progress ticking. |
| `paused` | Loaded, position held, not advancing. |
| `finished` | Reached end-of-item; triggers queue auto-advance (see `queue-semantics.md`). |
| `failed(message)` | The local asset couldn't be played (missing/corrupt file). |

### Transitions

```
idle --load(downloaded episode)--> loading
loading --ready--> playing            loading --error--> failed
playing <--pause / play--> paused
playing --reach end--> finished
finished --auto-advance (queue non-empty)--> loading(next)
finished --queue empty--> idle
failed --load(other episode)--> loading
any --load(new episode)--> loading    (replaces current)
```

**Guard:** attempting to `load` an episode whose `downloadState` is not `.downloaded`
is a programmer error the UI must prevent (Play not offered). If reached, go to
`failed("not downloaded")` rather than trap.

---

## Progress & `isPlayed`

- **Source of truth:** `Episode.playbackProgress` (fractional `0...1`, clamped by the
  model).
- **Persistence cadence:** write progress **at least every 5s while `playing`**, and
  **on every pause, on `finished`, and on backgrounding**. This bounds loss to ~5s if
  the app is killed.
- **`isPlayed`:** the model computes `playbackProgress >= 0.98` (`Episode.isPlayed`).
  Do **not** duplicate the threshold — read the model's computed property. Reaching
  `finished` implies progress was set to `1.0`.
- **`remainingTime`:** the model derives it from `duration` + progress
  (`Episode.remainingTime`); the detail row and Now Playing read it directly.
- **Resume:** loading an episode with `0 < playbackProgress < 0.98` seeks to that
  fraction before entering `playing`/`paused`.

---

## Background audio & session

- Configure `AVAudioSession` for playback so audio continues when the app is
  backgrounded and mixes/duck per iOS norms.
- Register **remote commands** (play, pause, skip forward/back, scrub) via
  `MPRemoteCommandCenter` so lock-screen and CarPlay (parked, but seam-compatible)
  controls work.

### `MPNowPlayingInfoCenter` field mapping

| Now Playing key | Source |
|---|---|
| `MPMediaItemPropertyTitle` | `Episode.title` |
| `MPMediaItemPropertyArtist` | owning `Podcast.title` (the show) |
| `MPMediaItemPropertyArtwork` | `Episode.remoteArtworkURL` ?? `Podcast.artworkURL` (fetched/cached to a `UIImage`) |
| `MPMediaItemPropertyPlaybackDuration` | `Episode.duration` |
| `MPNowPlayingInfoPropertyElapsedPlaybackTime` | `duration * playbackProgress` |
| `MPNowPlayingInfoPropertyPlaybackRate` | `1.0` when `playing`, `0.0` when `paused` |

Update the Now Playing info on every state change and on each progress write.

---

## Determinate behaviors (map to E4 tests)

- Play is offered **iff** `.downloaded`; otherwise only Download is offered.
- With the file present, playback in **airplane mode** proves no network dependency.
- Backgrounding keeps audio going and shows a lock-screen entry with title + artwork.
- Playing to end sets progress `1.0` → `Episode.isPlayed == true`.
- Scrubbing to 50% persists `playbackProgress ≈ 0.5` across an app relaunch.
- Reaching `finished` with a non-empty queue auto-advances (see `queue-semantics.md`).
