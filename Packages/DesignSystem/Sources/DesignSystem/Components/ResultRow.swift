// Translated from design/kit/components/result-row.html (.pod-art / .sk-row / .a1–.a6 + SHARED KIT EXTRAS).
// A horizontal search-result list row (60pt gradient artwork tile + title/author
// meta + a trailing slot, geometry from the kit's `.sk-row`), plus the reusable
// gradient artwork tile (`ArtworkTile`) with a bold white initial glyph.
//
// Structural color/spacing/radius/motion come only from the active ThemePalette
// and the Spacing/Radius/Typography/Elevation tokens. The one exception is the
// `.a1`–`.a6` artwork gradient stops: these are decorative placeholder hues
// defined literally by the kit (§9) with no matching theme role, so their exact
// stops are carried here (brand-ramp tokens are reused where a stop matches).
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
    /// are the kit's literal decorative stops (design/kit/components/result-row.html).
    var stops: [Color] {
        switch self {
        case .a1: return [Color(hex: 0xFF7A4D), Color(hex: 0xFF4D8D)]
        case .a2: return [Brand.mint, Color(hex: 0x2E8BFF)]
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

/// The gradient tile itself: `.pod-art` — a 140° gradient, an inset white
/// highlight ring, top-left highlight + bottom-right shade radials, and a bold
/// white initial glyph. Fills whatever square frame the parent gives it; the
/// glyph scales with the tile so it reads at both 60pt (row) and larger sizes.
private struct GradientArtwork: View {
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
                // .pod-art::after — top-left specular highlight + bottom-right shade.
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

/// A standalone gradient artwork placeholder — the kit's `.pod-art` with a bold
/// white initial. The gradient is chosen from `seed` so the same show always
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

// MARK: - Result row (public)

/// A horizontal search-result row: 60pt gradient artwork, a two-line meta stack
/// (row title + author), and a caller-supplied trailing slot (typically a
/// `SubscribeButton`). Geometry mirrors the kit's `.sk-row` — gap `--sp-3`,
/// padding `--sp-3`/`--sp-4`, artwork radius `--r-art` — and all colors come
/// from the active `ThemePalette`.
public struct ResultRow<Trailing: View>: View {
    private let title: String
    private let author: String
    private let artwork: ArtworkStyle
    private let trailing: () -> Trailing

    @Environment(\.palette) private var palette

    public init(
        title: String,
        author: String,
        artwork: ArtworkStyle,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.author = author
        self.artwork = artwork
        self.trailing = trailing
    }

    /// First character of the title, uppercased — the tile's initial glyph.
    private var initial: String {
        guard let first = title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }

    public var body: some View {
        HStack(spacing: Spacing.sp3) {
            GradientArtwork(style: artwork, initial: initial)
                .frame(width: 60, height: 60)          // fixed 60px art (§4)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.sp1) {
                Text(title)
                    .typeStyle(Typography.rowTitleStyle)  // 1rem / 700
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(author)
                    .typeStyle(Typography.subheadStyle)   // 0.82rem / 500
                    .foregroundStyle(palette.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.vertical, Spacing.sp3)   // .sk-row padding-block --sp-3
        .padding(.horizontal, Spacing.sp4) // .sk-row padding-inline --sp-4
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(author)")
    }
}

// MARK: - Preview

#if DEBUG
private struct ResultRowPreviewHost: View {
    @Environment(\.palette) private var palette

    private struct Item {
        let title: String
        let author: String
        let art: ArtworkStyle
    }

    private let items: [Item] = [
        .init(title: "Acquired", author: "Ben Gilbert & David Rosenthal", art: .a2),
        .init(title: "Behind the Bastards", author: "Cool Zone Media", art: .a3),
        .init(title: "99% Invisible", author: "Roman Mars", art: .a1),
        .init(title: "Darknet Diaries", author: "Jack Rhysider", art: .a4),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp5) {
            // Grouped list of rows — floats on `--surface` with `--elev-list`.
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    ResultRow(title: item.title, author: item.author, artwork: item.art) {
                        // Stand-in trailing slot (the real screen passes a SubscribeButton).
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(palette.onAccent)
                            .frame(width: 34, height: 34)
                            .background(palette.accent, in: Circle())
                    }
                    if index < items.count - 1 {
                        Rectangle()
                            .fill(palette.separator)
                            .frame(height: 0.5)
                            .padding(.leading, Spacing.sp4 + 60 + Spacing.sp3) // kit separator inset
                    }
                }
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
            .elevList(hairline: palette.hairline)

            // Bare artwork tiles, one per gradient.
            HStack(spacing: Spacing.sp3) {
                ForEach(ArtworkStyle.allCases, id: \.self) { style in
                    ArtworkTile(seed: style.rawValue - 1, initial: "\(style.rawValue)")
                        .frame(width: 48, height: 48)
                }
            }
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.groupedBg)
    }
}

#Preview("Result row — light") {
    ResultRowPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Result row — dark") {
    ResultRowPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
