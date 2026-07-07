// The six gradient artwork placeholders (`.a1`–`.a6`) shared by every kit
// surface that shows podcast art without a remote image: the flat search
// results list (design/kit/screens/{search-typing,search-noresults}.html `.art`), the
// result-card poster grid (design/kit/components/result-card.html `.pcard-art`),
// and the not-yet-built category-shelf gallery (design/kit/components/result-row.html
// `.pod-art`). Extracted here — rather than owned by any one row/card component —
// because all three consume the same six gradients; see design/kit/MANIFEST.md.
//
// Structural color/spacing/radius/motion come only from the active ThemePalette
// and the Spacing/Radius/Typography tokens. The one exception is the `.a1`–`.a6`
// gradient stops themselves: decorative placeholder hues defined literally by
// the kit (§9) with no matching theme role, so their exact stops are carried
// here (brand-ramp tokens are reused where a stop matches).
import SwiftUI

// MARK: - Artwork style (gradient tiles a1…a6)

/// One of the six gradient artwork placeholders from the kit (`.a1`–`.a6`, §9).
/// Decorative only — used behind a bold white initial when a show has no remote
/// artwork. Pick deterministically from an arbitrary seed via `init(seed:)`.
public enum ArtworkStyle: Int, CaseIterable, Sendable, Hashable {
    case a1 = 1, a2, a3, a4, a5, a6

    /// Deterministically map an arbitrary integer seed onto one of the six tiles.
    public init(seed: Int) {
        let count = ArtworkStyle.allCases.count
        let index = ((seed % count) + count) % count // 0..<count, negative-safe
        self = ArtworkStyle.allCases[index]
    }

    /// The two 140°-gradient stops (top-leading → bottom-trailing) for this tile.
    /// Brand-ramp tokens are reused where a stop is an exact brand hue; the rest
    /// are the kit's literal decorative stops (shared `.a1`–`.a6` classes).
    var stops: [Color] {
        switch self {
        case .a1: return [Color(hex: 0xFF7A4D), Color(hex: 0xFF4D8D)]
        case .a2: return [Brand.mint, KitLiteralColors.podcastIndexBlue]
        case .a3: return [Color(hex: 0xFFC24D), Brand.coral]
        case .a4: return [Brand.grape, Brand.mint]
        case .a5: return [Color(hex: 0xFF5E9A), Brand.grape]
        case .a6: return [Color(hex: 0x22C1A6), Color(hex: 0x7ED957)]
        }
    }

    /// The tile's 140°-style linear gradient (top-leading → bottom-trailing),
    /// consumed by poster tiles such as `ResultCard`.
    var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Gradient artwork rendering (shared)

/// The gradient tile itself: `.pod-art`/`.art`/`.pcard-art` — a 140° gradient, an
/// inset white highlight ring, top-left highlight + bottom-right shade radials,
/// and a bold white initial glyph. Fills whatever square frame the parent gives
/// it; the glyph scales with the tile so it reads at both 60pt (row) and larger
/// sizes (poster grid, shelf gallery).
struct GradientArtwork: View {
    let style: ArtworkStyle
    let initial: String
    var cornerRadius: CGFloat = Radius.rArt14

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            shape
                .fill(
                    LinearGradient(
                        colors: style.stops,
                        startPoint: .topLeading,     // ≈ kit's 140° line
                        endPoint: .bottomTrailing
                    )
                )
                // ::after — top-left specular highlight + bottom-right shade.
                .overlay {
                    RadialGradient(
                        colors: [Color(hex: 0xFFFFFF, alpha: 0.42), .clear],
                        center: UnitPoint(x: 0.30, y: 0.26),
                        startRadius: 0,
                        endRadius: side * 0.42
                    )
                }
                .overlay {
                    RadialGradient(
                        colors: [Color(hex: 0x000000, alpha: 0.28), .clear],
                        center: UnitPoint(x: 0.78, y: 0.82),
                        startRadius: 0,
                        endRadius: side * 0.55
                    )
                }
                // Bold white initial glyph.
                .overlay {
                    Text(initial)
                        .font(.system(size: side * 0.42, weight: .black))
                        .foregroundStyle(Color(hex: 0xFFFFFF, alpha: 0.95))
                        .shadow(color: Color(hex: 0x000000, alpha: 0.35), radius: 4, x: 0, y: 2)
                }
                // inset 0 0 0 .5px rgba(255,255,255,.16)
                .overlay {
                    shape.strokeBorder(Color(hex: 0xFFFFFF, alpha: 0.16), lineWidth: 0.5)
                }
                .clipShape(shape)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Artwork tile (public)

/// A standalone gradient artwork placeholder — the kit's `.pod-art`/`.art` with a
/// bold white initial. The gradient is chosen from `seed` so the same show always
/// gets the same tile. Fills its frame square; frame it at the call site
/// (e.g. 60×60 in a row, larger in a poster grid).
public struct ArtworkTile: View {
    private let style: ArtworkStyle
    private let initial: String

    public init(seed: Int, initial: String) {
        self.style = ArtworkStyle(seed: seed)
        self.initial = initial
    }

    public var body: some View {
        GradientArtwork(style: style, initial: initial)
            .accessibilityHidden(true)
    }
}
