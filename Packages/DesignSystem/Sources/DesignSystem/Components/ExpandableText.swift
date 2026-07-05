// Composed from docs/design/direction.md tokens — no design/kit source (see
// design/kit/MANIFEST.md). Built for E2 (Podcast Detail)'s "long descriptions
// truncate with an expand affordance" requirement — a generic, reusable
// truncate/expand block for any long body copy, not tied to one screen.
import SwiftUI

/// A body-copy block that clamps to `collapsedLineLimit` lines with a
/// trailing "More" / "Less" toggle when the text actually overflows that
/// limit. Uses `--text-dim` body copy and an `--accent` ghost-weight toggle
/// label (direction.md §8 "emphasis in lists" — text weight/color already
/// used for actionable affordances elsewhere in the kit).
public struct ExpandableText: View {
    private let text: String
    private let collapsedLineLimit: Int

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var isTruncated = false

    /// - Parameters:
    ///   - text: The body copy to render.
    ///   - collapsedLineLimit: Lines shown before truncating (defaults to 4).
    public init(_ text: String, collapsedLineLimit: Int = 4) {
        self.text = text
        self.collapsedLineLimit = collapsedLineLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp2) {
            Text(text)
                .typeStyle(Typography.bodyStyle)
                .foregroundStyle(palette.textDim)
                .lineSpacing(4)
                .lineLimit(expanded ? nil : collapsedLineLimit)
                .background(measurement)

            if isTruncated {
                Button(expanded ? "Less" : "More") {
                    withAnimation(Motion.resolve(Motion.easeSoft(), reduceMotion: reduceMotion)) {
                        expanded.toggle()
                    }
                }
                .font(Typography.subhead.weight(.heavy))
                .foregroundStyle(palette.accent)
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Collapses the description" : "Expands the full description")
            }
        }
        .onPreferenceChange(FullHeightKey.self) { fullHeight = $0 }
        .onPreferenceChange(TruncationHeightKey.self) { visibleHeight = $0 }
        .onChange(of: fullHeight) { _, _ in recomputeTruncation() }
        .onChange(of: visibleHeight) { _, _ in recomputeTruncation() }
    }

    // Two hidden measurements — the text's natural (unclamped) height vs. its
    // height when clamped to `collapsedLineLimit` — let us detect overflow
    // without a fragile line-count heuristic that breaks under Dynamic Type.
    @State private var fullHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0

    private var measurement: some View {
        ZStack {
            Text(text)                                    // unclamped
                .typeStyle(Typography.bodyStyle)
                .lineSpacing(4)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: FullHeightKey.self, value: geo.size.height)
                })

            Text(text)                                    // clamped
                .typeStyle(Typography.bodyStyle)
                .lineSpacing(4)
                .lineLimit(collapsedLineLimit)
                .background(GeometryReader { geo in
                    Color.clear.preference(key: TruncationHeightKey.self, value: geo.size.height)
                })
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private func recomputeTruncation() {
        guard fullHeight > 0, visibleHeight > 0 else { return }
        isTruncated = fullHeight > visibleHeight + 1
    }
}

private struct FullHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TruncationHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Preview

#if DEBUG
private struct ExpandableTextPreviewHost: View {
    @Environment(\.palette) private var palette

    private let long = """
    Every week we dig into a story that started small and got out of hand — \
    a scam, a scandal, a disappearance — and follow it as far as the tape \
    recorder will let us. Some weeks that's a courtroom. Some weeks it's a \
    parking lot at 2am. This season we're covering three ongoing investigations \
    end to end, so buckle in.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp5) {
            ExpandableText(long)
            ExpandableText("A short one-liner that never truncates.")
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.groupedBg)
    }
}

#Preview("Expandable text — light") {
    ExpandableTextPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Expandable text — dark") {
    ExpandableTextPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
