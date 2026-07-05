// App entry point. Design/architecture source: ROADMAP.md (M1 "thin SwiftUI app
// target") + docs/design/direction.md §12 (navigation). Builds the one shared
// SwiftData container for the PodcastModels schema and hosts the AppShell.
import SwiftUI
import SwiftData
import DesignSystem
import PodcastModels

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

    init() {
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
        }
        .modelContainer(modelContainer)
    }
}
