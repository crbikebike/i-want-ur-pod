// PlaybackKit — download-first audio playback engine (E4-S2, E4-S3).
// Architecture source: docs/spec/playback-state-machine.md.
//
// This file used to be the M1 namespace stub; the real API now lives across:
//   - PlaybackState.swift    — the state machine's cases.
//   - AudioPlaying.swift     — the testable player seam.
//   - AVPlayerAudioPlaying.swift — the live AVPlayer conformer.
//   - PlaybackEngine.swift   — the app-scoped @Observable service.
//   - AudioSessionConfigurator.swift, NowPlayingCenter.swift — the iOS-only
//     background-audio / lock-screen integration.
public enum PlaybackKit {}
