// ModelSchema — central schema + container factories for the model layer.
// Model layer for "i want ur pod"; no design source (data type only).
import Foundation
import SwiftData

/// Central registry of the persistent models shipped by `PodcastModels`.
///
/// Use ``models`` when constructing a `Schema` or `ModelContainer` so every
/// call site sees the same entity set, and use the factory helpers to spin up
/// containers for the app, previews, or tests.
public enum ModelSchema {
    /// All persistent model types managed by this package.
    public static var models: [any PersistentModel.Type] {
        [
            Podcast.self,
            Episode.self,
            Chapter.self,
            QueueItem.self,
            PlayEvent.self
        ]
    }

    /// A `Schema` describing every model in the package.
    public static var schema: Schema {
        Schema(models)
    }

    /// Builds a `ModelContainer` for the package's schema.
    ///
    /// - Parameter inMemory: When `true`, storage is ephemeral (ideal for
    ///   previews and tests); when `false`, the container persists to disk.
    /// - Returns: A configured `ModelContainer`.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An ephemeral in-memory container for SwiftUI previews and unit tests.
    ///
    /// Traps on failure — acceptable in preview/test contexts where a broken
    /// schema is a programmer error.
    @MainActor
    public static func previewContainer() -> ModelContainer {
        do {
            return try makeContainer(inMemory: true)
        } catch {
            fatalError("Failed to build in-memory ModelContainer: \(error)")
        }
    }
}
