// App entry point. Design/architecture source: ROADMAP.md (M1 "thin SwiftUI app
// target") + docs/design/direction.md §12 (navigation). Builds the one shared
// SwiftData container for the PodcastModels schema and hosts the AppShell.
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels
import DownloadKit
import PlaybackKit

/// The application root. Owns the single, shared `ModelContainer` for every
/// `PodcastModels` entity and injects it (plus the theme palette) into the view
/// tree. All persistence flows through this one container so every screen sees
/// the same store.
@main
struct IWantUrPodApp: App {

    /// The process-wide SwiftData container, built once from the model layer's
    /// central schema (`ModelSchema.models`).
    private let modelContainer: ModelContainer

    /// The single, shared search-source holder. Discover and Settings both read
    /// this one coordinator so source edits in Settings drive Discover's search
    /// (direction.md §12.3).
    @State private var appSources = AppSources()

    /// The single, shared download manager (E4-S1). Drives every episode's
    /// `downloadState` through DownloadKit's state machine; injected so
    /// PodcastDetailView's Download control (and playback resolving the
    /// local file, below) all read the one instance.
    @State private var downloadManager: DownloadManager

    /// The single, shared playback engine (E4-S2/E4-S3). PlaybackKit doesn't
    /// depend on DownloadKit (see Packages/PlaybackKit/Package.swift), so its
    /// `localURLResolver` seam is wired here to `downloadManager.localURL`
    /// (mirrors how `DownloadManager` itself takes its downloader/store as
    /// injected seams). Injected via `.environment` so PodcastDetailView's
    /// Play control reads the one instance.
    @State private var playbackEngine: PlaybackEngine

    /// The single, shared Up Next queue store (E5). Wraps
    /// `modelContainer.mainContext` — the same context every other screen's
    /// `@Environment(\.modelContext)`/`@Query` resolves — so queue mutations
    /// are immediately consistent with the rest of the store. Injected via
    /// `.environment` so `UpNextScreen` and `PodcastDetailView`'s "Add to Up
    /// Next" control read the one instance.
    @State private var queueStore: QueueStore

    /// The single, shared universal play-intent coordinator (E6). Couples
    /// `playbackEngine`, `downloadManager`, and `queueStore` behind one
    /// `play(_:context:)` call so every "Play" control (Podcast Detail, Up
    /// Next, Home) shares the same not-downloaded → queue-at-front →
    /// preparing → auto-download → auto-play behavior. Injected via
    /// `.environment` (see `AppPlaybackIntent.swift`).
    @State private var playbackIntent: PlaybackIntentCoordinator

    /// Tracks scene-phase transitions so backgrounding forces a progress
    /// write per the spec's "on backgrounding" persistence-cadence rule
    /// (docs/spec/playback-state-machine.md).
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Route all read-path remote loads (AsyncImage artwork, FeedFetcher via
        // URLSession.shared) through a generous persistent cache so artwork and
        // feeds aren't re-downloaded on every appearance / relaunch. See
        // docs/design/data-loading.md (HTTP cache principle).
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,      // 50 MB
            diskCapacity: 500 * 1024 * 1024        // 500 MB
        )

        let downloadManager = DownloadManager()
        _downloadManager = State(initialValue: downloadManager)

        let playbackEngine = PlaybackEngine(
            localURLResolver: { episode in downloadManager.localURL(for: episode) }
        )
        _playbackEngine = State(initialValue: playbackEngine)

        // Register the bundled brand display face (IBM Plex Mono), shipped as a
        // DesignSystem SPM resource in Bundle.module. Because it lives outside the
        // app bundle it cannot be picked up via Info.plist UIAppFonts, so it must
        // be registered with CTFontManager once at launch or every
        // Typography.Font.custom("IBM Plex Mono", …) accessor silently falls back
        // to the system font. See DesignSystem/FontRegistration.swift.
        FontRegistration.registerFonts()

        let container: ModelContainer
        do {
            container = try ModelSchema.makeContainer()
        } catch {
            // A schema that cannot open the persistent store is a programmer
            // error, not a recoverable runtime condition.
            fatalError("Failed to create the shared ModelContainer: \(error)")
        }
        modelContainer = container

        let queueStore = QueueStore(context: container.mainContext)
        _queueStore = State(initialValue: queueStore)

        // Listening-history logging (Wave 1, backend only): each play
        // session PlaybackEngine finalizes gets recorded as a PlayEvent.
        let listeningHistoryRecorder = ListeningHistoryRecorder(context: container.mainContext)

        let playbackIntent = PlaybackIntentCoordinator(
            playbackEngine: playbackEngine,
            downloadManager: downloadManager,
            queueStore: queueStore
        )
        _playbackIntent = State(initialValue: playbackIntent)

        // Auto-advance (E5-S3): couple PlaybackEngine's finished callback to
        // the queue store via QueueAutoAdvanceCoordinator, keeping PlaybackKit
        // itself decoupled from QueueItem/QueueStore-specific logic (see
        // PlaybackEngine.onFinished's doc comment).
        playbackEngine.onFinished = { [weak playbackEngine] finishedEpisode in
            guard let playbackEngine else { return }
            QueueAutoAdvanceCoordinator.handleFinished(
                finishedEpisode,
                queueStore: queueStore,
                playbackEngine: playbackEngine,
                context: container.mainContext
            )
        }

        // Listening-history logging (Wave 1): every finalized play session
        // (user-initiated plays and queue auto-advance alike, since both
        // route through PlaybackEngine.load(episode:context:)) is logged.
        playbackEngine.onDidFinishListening = { episode, startedAt, listenedSeconds in
            listeningHistoryRecorder.record(episode: episode, startedAt: startedAt, listenedSeconds: listenedSeconds)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                // Publish the palette that matches the system color scheme so
                // every DesignSystem component resolves its semantic roles.
                .themedPalette()
                // Share one SearchCoordinator across Discover and Settings.
                .appSources(appSources)
                // Share one DownloadManager across every screen (E4-S1).
                .downloadManager(downloadManager)
                // Share one PlaybackEngine across every screen (E4-S2/S3).
                .playbackEngine(playbackEngine)
                // Share one QueueStore across every screen (E5).
                .queueStore(queueStore)
                // Share one PlaybackIntentCoordinator across every screen (E6).
                .playbackIntent(playbackIntent)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            // Force a progress write on backgrounding, per the spec's
            // persistence-cadence rule (playback-state-machine.md).
            if newPhase == .background {
                playbackEngine.handleAppBackgrounding()
            }
        }
    }
}
