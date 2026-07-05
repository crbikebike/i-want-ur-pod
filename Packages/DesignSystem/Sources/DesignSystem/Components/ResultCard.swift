// Translated from design/kit/components/result-card.html (.cardgrid / .pcard + SHARED KIT EXTRAS).
// A 2-up "poster" tile for the Discover grid: full-bleed square gradient artwork
// (radius --r-md) with a bold letter glyph, then a two-line title and a single
// dimmed author line. Display-only — the frozen `ResultCard(title:author:artwork:)`
// signature carries no action, so the interactive subscribe affordance from the
// kit lives in `SubscribeButton`, not here. Colors/sizing come only from the
// active ThemePalette + Spacing/Radius/Typography tokens.
//
// `ArtworkStyle` (the .a1–.a6 gradient placeholder) is owned by the result-row
// component per DesignSystemAPI.swift; this file consumes its `gradient` and its
// `init(seed:)` (the same members `ArtworkTile` relies on) and does not redefine it.
import SwiftUI

/// A poster-style result tile for the Discover grid.
///
/// Mirrors `design/kit/components/result-card.html`:
/// - `.pcard-art`: 1:1 gradient square, radius `--r-md` (16), a soft top-left
///   white highlight + bottom-right shade, an inner white hairline, and a drop
///   shadow. A heavy letter `glyph` (derived from `title`) sits centered.
/// - `.pcard-meta`: two-line `--text` title (`.pcard-title`) over a single
///   ellipsized `--text-dim` author (`.pcard-author`).
public struct ResultCard: View {
    private let title: String
    private let author: String
    private let artwork: ArtworkStyle

    @Environment(\.palette) private var palette

    public init(title: String, author: String, artwork: ArtworkStyle) {
        self.title = title
        self.author = author
        self.artwork = artwork
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp2) {   // .pcard gap ~9
            PosterArt(gradient: artwork.gradient, glyph: glyph)

            // .pcard-meta — padding: 0 2px
            VStack(alignment: .leading, spacing: 3) {
                Text(title)                                   // .pcard-title
                    .typeStyle(Typography.rowTitleStyle)
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(author)                                  // .pcard-author
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(author)")
    }

    /// The `.glyph` letter: first letter/number of the title (matches the kit,
    /// e.g. "9" for "99% Invisible"), uppercased.
    private var glyph: String {
        guard let c = title.first(where: { $0.isLetter || $0.isNumber }) else { return "•" }
        return String(c).uppercased()
    }
}

// MARK: - Poster artwork tile (.pcard-art)

/// The full-width square gradient tile with corner sheen, letter glyph, inner
/// hairline, and drop shadow — the `.pcard-art` half of a `ResultCard`.
private struct PosterArt: View {
    let gradient: LinearGradient
    let glyph: String

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.rMd16, style: .continuous)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(gradient)

            // .pcard-art::after — top-left white highlight + bottom-right shade.
            // endRadius scales with the tile so the sheen holds across sizes.
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack {
                    RadialGradient(
                        gradient: Gradient(colors: [Color.white.opacity(0.42), .clear]),
                        center: UnitPoint(x: 0.30, y: 0.26),
                        startRadius: 0,
                        endRadius: s * 0.42
                    )
                    RadialGradient(
                        gradient: Gradient(colors: [Color.black.opacity(0.28), .clear]),
                        center: UnitPoint(x: 0.78, y: 0.82),
                        startRadius: 0,
                        endRadius: s * 0.55
                    )
                }
            }

            // .glyph — bold white letter, size ≈ 2.6rem at a 2-up width.
            Text(glyph)
                .font(.system(size: 42, weight: .black))
                .foregroundStyle(Color.white.opacity(0.95))
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(shape)
        // inset 0 0 0 .5px rgba(255,255,255,.16)
        .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        // 0 8px 20px -12px rgba(0,0,0,.55)
        .shadow(color: Color.black.opacity(0.55), radius: 10, x: 0, y: 8)
    }
}

// MARK: - Preview

#if DEBUG
private struct ResultCardPreviewHost: View {
    @Environment(\.palette) private var palette

    private let samples: [(String, String)] = [
        ("Acquired", "Ben Gilbert & David Rosenthal"),
        ("99% Invisible", "Roman Mars"),
        ("Behind the Bastards", "Cool Zone Media"),
        ("Bone Valley", "Lava for Good")
    ]

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.sp3),
        GridItem(.flexible(), spacing: Spacing.sp3)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.sp4) {   // .cardgrid gaps
            ForEach(Array(samples.enumerated()), id: \.offset) { i, s in
                ResultCard(title: s.0, author: s.1, artwork: ArtworkStyle(seed: i + 1))
            }
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.groupedBg)
    }
}

#Preview("Result card — light") {
    ResultCardPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Result card — dark") {
    ResultCardPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
