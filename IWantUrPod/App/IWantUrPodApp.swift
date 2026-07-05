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

    /// Tracks scene-phase transitions so backgrounding forces a progress
    /// write per the spec's "on backgrounding" persistence-cadence rule
    /// (docs/spec/playback-state-machine.md).
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let downloadManager = DownloadManager()
        _downloadManager = State(initialValue: downloadManager)
        _playbackEngine = State(initialValue: PlaybackEngine(
            localURLResolver: { episode in downloadManager.localURL(for: episode) }
        ))
        // Register the bundled brand display face (IBM Plex Mono), shipped as a
        // DesignSystem SPM resource in Bundle.module. Because it lives outside the
        // app bundle it cannot be picked up via Info.plist UIAppFonts, so it must
        // be registered with CTFontManager once at launch or every
        // Typography.Font.custom("IBM Plex Mono", …) accessor silently falls back
        // to the system font. See DesignSystem/FontRegistration.swift.
        FontRegistration.registerFonts()

        do {
            modelContainer = try ModelSchema.makeContainer()
        } catch {
            // A schema that cannot open the persistent store is a programmer
            // error, not a recoverable runtime condition.
            fatalError("Failed to create the shared ModelContainer: \(error)")
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
