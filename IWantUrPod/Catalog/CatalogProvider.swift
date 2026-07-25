// App-side bundle glue for the offline catalog (curation/catalog/catalog.schema.md).
// Mirrors HomeFeedProvider.loadCuratedEntries's two-line bundle-lookup glue;
// the actual parsing/skip-malformed behavior lives once, in DirectoryKit's
// CatalogLoader — not duplicated here.
//
// NOTE TO MAC BUILD: this file lives under IWantUrPod/Catalog/, a new group.
// SwiftPM auto-includes DirectoryKit's own sources, but the IWantUrPod app
// target is an Xcode project — this file (and the Catalog/ group) must be
// added to the IWantUrPod app target's "Compile Sources" in Xcode, and
// Resources/catalog.json + Resources/themes.json must be in the target's
// "Copy Bundle Resources" build phase.
import Foundation
import DirectoryKit

enum CatalogProvider {

    /// Loads the bundled catalog (`catalog.json`) via DirectoryKit's pure
    /// `CatalogLoader`.
    static func loadEntries(from bundle: Bundle = .main) -> [CatalogEntry] {
        guard
            let url = bundle.url(forResource: "catalog", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            return []
        }
        return CatalogLoader.loadEntries(from: data)
    }

    /// Loads the bundled theme taxonomy (`themes.json`) via DirectoryKit's
    /// pure `CatalogLoader`.
    static func loadThemes(from bundle: Bundle = .main) -> [ThemeArc] {
        guard
            let url = bundle.url(forResource: "themes", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            return []
        }
        return CatalogLoader.loadThemes(from: data)
    }
}
