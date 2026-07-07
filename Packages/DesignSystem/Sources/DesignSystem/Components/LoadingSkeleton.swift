// Translated from design/kit/screens/search-loading.html (.sk-shelf / .sk-shelf-head /
// .sk-rail / .sk-pod / .sk-pod-art / .sk-pod-line + .shimmer, SHARED KIT EXTRAS).
// A placeholder for the shelf gallery (`ResultShelf`) while a search is in
// flight: shimmering shelf headers over rails of square `.sk-pod-art` blocks,
// each with two shimmer lines — mirroring the real `PodCard`'s shape at the
// same 150pt width. Distinct from `components/loading-skeleton.html`'s flat
// `.sk-row` list, which has no current consumer (see design/kit/MANIFEST.md).
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
/// Sizes come from the frame the parent applies (art tile or a line).
private struct SkeletonBlock: View {
    var cornerRadius: CGFloat

    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(palette.chip)
            .shimmer(cornerRadius: cornerRadius)
    }
}

/// One `.sk-sh-title`/`.sk-sh-count`/`.sk-pod-line`: an 11pt-tall bar filling
/// `fraction` of the available width, pinned leading.
private struct SkeletonLine: View {
    var fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            SkeletonBlock(cornerRadius: 6) // { border-radius: 6px }
                .frame(width: geo.size.width * fraction, height: 11)
        }
        .frame(height: 11)
    }
}

/// One `.sk-pod`: a 138×138 art placeholder + two shimmer lines (w80/w50),
/// matching `PodCard`'s shape at the kit's skeleton width.
private struct SkeletonPod: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {   // .sk-pod { gap: 9px }
            SkeletonBlock(cornerRadius: Radius.rMd16)
                .frame(width: 138, height: 138)   // .sk-pod-art

            SkeletonLine(fraction: 0.80)   // .w80
                .padding(.horizontal, 2)
            SkeletonLine(fraction: 0.50)   // .w50
                .padding(.horizontal, 2)
        }
        .frame(width: 138)
    }
}

/// One `.sk-shelf`: a shimmering title + count header over a `.sk-rail` of
/// three `.sk-pod` placeholders.
private struct SkeletonShelf: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp3) {   // .sk-shelf-head margin-bottom
            HStack {
                SkeletonLine(fraction: 1)
                    .frame(width: 110)
                Spacer(minLength: Spacing.sp3)
                SkeletonLine(fraction: 1)
                    .frame(width: 60)
            }
            .padding(.horizontal, 2)

            HStack(spacing: Spacing.sp3) {   // .sk-rail { gap: --sp-3 }
                SkeletonPod()
                SkeletonPod()
                SkeletonPod()
            }
        }
    }
}

// MARK: - Loading skeleton (public)

/// A stack of shimmering shelf placeholders shown while search results load —
/// mirrors `screens/loading.html`'s shelf/rail skeleton, matching the shape
/// `ResultShelf`/`PodCard` render once results arrive.
public struct LoadingSkeleton: View {
    private let shelves: Int

    /// - Parameter shelves: number of placeholder shelves (defaults to 2, as in the kit).
    public init(shelves: Int = 2) {
        self.shelves = max(0, shelves)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp5) {   // .sk-shelf margin-top
            ForEach(0..<shelves, id: \.self) { _ in
                SkeletonShelf()
            }
        }
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
        ScrollView {
            LoadingSkeleton()
                .padding(Spacing.gutter)
        }
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
