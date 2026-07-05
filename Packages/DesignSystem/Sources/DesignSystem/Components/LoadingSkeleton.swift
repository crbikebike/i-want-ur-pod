// Translated from design/kit/components/loading-skeleton.html (.sk-list / .sk-row / .sk-art / .sk-line / .sk-pill + .shimmer, SHARED KIT EXTRAS).
// A placeholder for the results list while a search is in flight: a grouped
// inset list (`--surface` + `--elev-list` + `--r-lg`) of shimmer rows, each
// mirroring `.sk-row` geometry — a 60pt art tile, a three-line meta stack
// (70% / 45% / 30% widths), and a trailing 74×30 subscribe-pill placeholder.
//
// All fills come from the active ThemePalette (`--chip` base, a swept `--text`
// highlight for the shimmer band) and the Spacing/Radius/Elevation/Motion
// tokens — no hardcoded hex. The shimmer sweep collapses under reduce-motion.
import SwiftUI

// MARK: - Shimmer fill (public modifier)

public extension View {
    /// The kit's `.shimmer` sweep: a moving highlight band travelling across a
    /// `--chip`-filled shape (`shimmer 1.4s var(--ease-soft) infinite`). The
    /// band is `--text` at low opacity, matching the CSS `color-mix(text 12%,
    /// chip)` mid-stop. Collapses to a static fill under reduce-motion.
    func shimmer(cornerRadius: CGFloat) -> some View {
        modifier(ShimmerModifier(cornerRadius: cornerRadius))
    }
}

private struct ShimmerModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay {
                GeometryReader { geo in
                    // Band ≈ 1.6× the element width so the highlight fully clears
                    // both edges as `phase` sweeps from −1 (offscreen left) to
                    // +1 (offscreen right).
                    let bandWidth = geo.size.width * 1.6
                    LinearGradient(
                        colors: [.clear, palette.text.opacity(0.12), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .offset(x: phase * geo.size.width)
                }
            }
            .clipShape(shape)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    Motion.easeSoft(duration: 1.4).repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

// MARK: - Skeleton primitives

/// A single shimmer block: a `--chip`-filled rounded rect with the sweep on top.
/// Sizes come from the frame the parent applies (art tile, pill, or a line).
private struct SkeletonBlock: View {
    var cornerRadius: CGFloat

    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(palette.chip)
            .shimmer(cornerRadius: cornerRadius)
    }
}

/// One `.sk-line`: an 11pt-tall bar filling `fraction` of the available width
/// (the kit's `.w70` / `.w45` / `.w30`), pinned leading.
private struct SkeletonLine: View {
    var fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            SkeletonBlock(cornerRadius: 6) // .sk-line { border-radius: 6px }
                .frame(width: geo.size.width * fraction, height: 11)
        }
        .frame(height: 11) // .sk-line { height: 11px }
    }
}

/// One `.sk-row`: 60pt art tile · three-line meta · 74×30 pill placeholder.
private struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Spacing.sp3) { // .sk-row { gap: --sp-3 }
            SkeletonBlock(cornerRadius: Radius.rArt14)
                .frame(width: 60, height: 60) // .sk-art

            VStack(alignment: .leading, spacing: Spacing.sp2) { // .sk-meta { gap: 8px }
                SkeletonLine(fraction: 0.70) // .w70
                SkeletonLine(fraction: 0.45) // .w45
                SkeletonLine(fraction: 0.30) // .w30
            }
            .frame(maxWidth: .infinity, alignment: .leading) // .sk-meta { flex: 1 }

            SkeletonBlock(cornerRadius: Radius.rPill999)
                .frame(width: 74, height: 30) // .sk-pill
        }
        .padding(.vertical, Spacing.sp3)   // .sk-row padding-block --sp-3
        .padding(.horizontal, Spacing.sp4) // .sk-row padding-inline --sp-4
    }
}

// MARK: - Loading skeleton (public)

/// A grouped inset list of shimmer rows shown while search results load.
/// Mirrors the kit's `.sk-list`: floats on `--surface` with `--r-lg` corners,
/// `--elev-list` elevation, and hairline separators inset past the art tile.
public struct LoadingSkeleton: View {
    private let rows: Int

    @Environment(\.palette) private var palette

    /// - Parameter rows: number of placeholder rows (defaults to 4, as in the kit).
    public init(rows: Int = 4) {
        self.rows = max(0, rows)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                SkeletonRow()
                if index < rows - 1 {
                    // .sk-row::after — inset hairline past the 60pt art + gap.
                    Rectangle()
                        .fill(palette.separator)
                        .frame(height: 0.5)
                        .padding(.leading, Spacing.sp4 + 60 + Spacing.sp3)
                }
            }
        }
        .background(
            palette.surface,
            in: RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .elevList(hairline: palette.hairline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading results")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Preview

#if DEBUG
private struct LoadingSkeletonPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Spacing.sp5) {
            LoadingSkeleton()          // default 4 rows
            LoadingSkeleton(rows: 2)   // shorter placeholder
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.groupedBg)
    }
}

#Preview("Loading skeleton — light") {
    LoadingSkeletonPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Loading skeleton — dark") {
    LoadingSkeletonPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
