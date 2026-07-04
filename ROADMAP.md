# Roadmap — i want ur pod

An open-source iOS podcast app with a fast, focused, playful feel. Native SwiftUI, local-first, MIT-licensed.

**Status:** M0.5 (Design) complete. **M1 (Foundations) is next.**

---

## Design

The visual system is built as self-contained HTML prototypes (a faithful proxy that gets translated to SwiftUI), and mirrored in a Claude Design project for review.

- **Direction:** "Playful Pulse" — coral (`#FF6A4D`) + mint (`#34E0C4`) accents, rounded type, rewarding micro-motion (pulse-ring Subscribe), on a dark-forward ground. Our own identity, inspired by the spirit of classic Pocket Casts (not a copy).
- **Chrome:** floating **Liquid Glass** tab bar (iOS-26 style; graceful classic fallback on older iOS).
- **Kit:** `design/kit/` — tokens, 12 components, the Discover flow + every state (first-run, typing, loading, results, no-results, error), and a Settings → Sources screen. Light + dark, WCAG AA.
- **Spec for translation:** `docs/design/direction.md` (tokens, type, spacing, motion) and `docs/design/carplay-ia.md` (CarPlay information architecture).

## Milestones

- **M0.5 — Design** ✅ Visual system, Discover flow + states, Settings → Sources, CarPlay IA.
- **M1 — Foundations** ⏭️ *next*
  - XcodeGen scaffold (`project.yml`), seven local Swift packages, thin SwiftUI app target.
  - `PodcastModels` (SwiftData): Podcast / Episode / Chapter / DownloadState / QueueItem.
  - `DirectoryKit`: search via **Apple/iTunes (primary, zero-config)** + **PodcastIndex (opt-in, user-supplied key)**. Multiple sources use **primary + fallback, no merge**. Sources are chosen in **Settings**, not inline.
  - SwiftUI **Discover** screen wired to live results, matching the approved design.
  - **CarPlay seam**: scene delegate + template skeleton + entitlement (goes live at M3).
- **M2 — Subscribe & Library** Feed parsing (`FeedParsingKit`), subscribe flow, Podcasts tab + episode list.
- **M3 — Playback** `PlaybackKit`, background audio, lock-screen Now Playing, mini-player + Now Playing sheet. **CarPlay goes live.**
- **M4 — Downloads** `DownloadKit`, offline playback, background download, relaunch resumption.
- **M5 — Chapters & Queue** `ChapterKit` (Podcasting 2.0 JSON + ID3v2), chapter UI, reorderable Up Next.
- **M6 — Polish** Empty/error states, app icon, accessibility pass, CONTRIBUTING, expanded README.

## Key decisions

- **Platform:** native iOS 17+, SwiftUI, Swift only. No sync in v1 (local-first, designed so sync can be added later).
- **Sources:** Apple primary (no key); PodcastIndex opt-in with your own free API key (kept in Keychain, never committed). Rate-limit-safe by design; a proxy can be added later behind the same interface if needed.
- **CarPlay:** first-class goal; built as a seam in M1, activated at M3.
- **Tooling:** XcodeGen generates the `.xcodeproj` (not committed). RSS parser package is `FeedParsingKit`. No CI yet — builds run on macOS/Xcode.

## Building

```bash
brew install xcodegen
xcodegen generate
open IWantUrPod.xcodeproj   # (available from M1 on)
```

## Before M3

Apply to Apple for the CarPlay Audio entitlement (`com.apple.developer.carplay-audio`) — it's manually approved and can take a while, so start early.
