// Composed from docs/design/direction.md tokens — no design/kit source (see
// design/kit/MANIFEST.md). E2 (Podcast Detail) is the first screen to show
// artwork loaded from a real feed URL rather than a synthetic seed, so the
// kit's gradient placeholders (`ArtworkTile.swift`) need a remote-image
// counterpart that still falls back to the same gradient tile whenever the
// URL is `nil` or the load hasn't resolved to an image (loading/failure).
import SwiftUI

/// Renders `url` via `AsyncImage` when present, falling back to the kit's
/// `ArtworkTile` gradient placeholder when `url` is `nil` or the image hasn't
/// successfully loaded (in flight or failed).
///
/// Fills whatever square frame the parent gives it, matching `ArtworkTile`'s
/// sizing contract so call sites can swap between the two freely.
public struct RemoteArtwork: View {
    private let url: URL?
    private let seed: Int
    private let initial: String
    private let cornerRadius: CGFloat

    /// - Parameters:
    ///   - url: The remote artwork URL, if any.
    ///   - seed: Deterministic seed for the gradient fallback (`ArtworkTile`).
    ///   - initial: The glyph shown on the gradient fallback.
    ///   - cornerRadius: Corner radius applied to the loaded remote image so
    ///     it matches the placeholder's shape. Defaults to the kit's row/tile
    ///     radius (`--r-art`, 14).
    public init(url: URL?, seed: Int, initial: String, cornerRadius: CGFloat = Radius.rArt14) {
        self.url = url
        self.seed = seed
        self.initial = initial
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    default:
                        // `GradientArtwork` (internal to this module) is used directly
                        // rather than the public `ArtworkTile` wrapper so the fallback
                        // honors the same `cornerRadius` the caller asked for — `ArtworkTile`
                        // fixes its radius to `--r-art` (14), which doesn't match every
                        // remote-artwork call site (e.g. Detail's 132pt/16px header tile).
                        GradientArtwork(style: ArtworkStyle(seed: seed), initial: initial, cornerRadius: cornerRadius)
                    }
                }
            } else {
                GradientArtwork(style: ArtworkStyle(seed: seed), initial: initial, cornerRadius: cornerRadius)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Preview

#if DEBUG
private struct RemoteArtworkPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: Spacing.sp4) {
            RemoteArtwork(url: nil, seed: 1, initial: "A")
                .frame(width: 96, height: 96)
            RemoteArtwork(url: URL(string: "https://example.com/missing.jpg"), seed: 2, initial: "B")
                .frame(width: 96, height: 96)
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.groupedBg)
    }
}

#Preview("Remote artwork — light") {
    RemoteArtworkPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Remote artwork — dark") {
    RemoteArtworkPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
