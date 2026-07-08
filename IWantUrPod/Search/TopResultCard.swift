// Translated from design/kit/screens/search-results.html (.topresult hero + pill .sub).
// The featured "top result" — the strongest search match — shown above the
// "More shows" list: 76pt artwork, title/author, and a full pill Subscribe
// control (idle/subscribing/subscribed). Card chrome mirrors `.topresult`
// (surface, --r-lg, --elev-list); the pill mirrors the kit's base `.sub`
// (pill radius, accent→accent-2 gradient, 34pt min-height) — NOT the
// circular `.reslist .sub` override that `SubscribeButton` renders.
import SwiftUI
import DesignSystem
import DirectoryKit

/// The hero card for the single strongest search match. The parent owns
/// `subscribeState` (idle → subscribing → subscribed) and persistence,
/// exactly like `ShelvesList`/`SearchResultRow` call sites do today —
/// this view only renders the state and fires `onSubscribe` on tap.
public struct TopResultCard: View {
    private let result: SearchResult
    private let subscribeState: SubscribeState
    private let onSubscribe: () -> Void
    private let onTap: () -> Void

    @Environment(\.palette) private var palette

    public init(
        result: SearchResult,
        subscribeState: SubscribeState,
        onSubscribe: @escaping () -> Void,
        onTap: @escaping () -> Void = {}
    ) {
        self.result = result
        self.subscribeState = subscribeState
        self.onSubscribe = onSubscribe
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Art + title/author — one tappable region (kit: the whole
            // `.topresult` row minus the `.sub` button fires the same tap).
            Button(action: onTap) {
                HStack(alignment: .top, spacing: Spacing.sp3) {
                    RemoteArtwork(url: result.artworkURL, seed: seed, initial: initial, cornerRadius: Radius.rMd16)
                        .frame(width: artSize, height: artSize)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title)                    // .tr-title
                            .typeStyle(Typography.heroTitleStyle)
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(result.author)                   // .tr-author
                            .typeStyle(Typography.heroAuthorStyle)
                            .foregroundStyle(palette.textDim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(result.title), \(result.author)")
            .accessibilityAddTraits(.isButton)

            // Pill Subscribe — a sibling of the tap button above (not
            // nested inside it) so its own tap wins the hit, indented to
            // align under the title/author text (kit: nested in `.tr-body`,
            // `margin-top: var(--sp-2); align-self: flex-start`).
            pill
                .padding(.leading, artSize + Spacing.sp3)
                .padding(.top, Spacing.sp2)
        }
        .padding(Spacing.sp3)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.rLg20, style: .continuous))
        .elevList(hairline: palette.hairline)
    }

    // MARK: - Pill subscribe control (kit base `.sub`, not the circle)

    private var pill: some View {
        Button(action: onSubscribe) {
            HStack(spacing: Spacing.sp1) {
                switch subscribeState {
                case .idle:
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))   // .sub .ico svg — kit 15×15
                case .subscribing:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(palette.onAccent)
                        .scaleEffect(0.7)
                case .subscribed:
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))   // .sub .ico svg — kit 15×15
                }

                Text(pillTitle)                               // .sub pill label .8rem/800/.01em
                    .typeStyle(Typography.pillButtonLabelStyle)
            }
            .foregroundStyle(pillForeground)
            .padding(.horizontal, Spacing.sp3)
            .frame(minHeight: 34)
            .background(pillBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.rPill999, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(subscribeState == .subscribing)
        .modifier(PillGlow(active: subscribeState != .subscribed, accent: palette.accent))
        .accessibilityLabel(pillTitle)
        .accessibilityAddTraits(subscribeState == .subscribed ? [.isButton, .isSelected] : .isButton)
    }

    private var pillTitle: String {
        switch subscribeState {
        case .idle, .subscribing: return "Subscribe"
        case .subscribed:         return "Subscribed"
        }
    }

    @ViewBuilder private var pillBackground: some View {
        if subscribeState == .subscribed {
            // kit `.sub.done` — flat `--chip` fill.
            RoundedRectangle(cornerRadius: Radius.rPill999, style: .continuous)
                .fill(palette.chip)
        } else {
            // kit `.sub` — 135° accent → accent-2 gradient.
            RoundedRectangle(cornerRadius: Radius.rPill999, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [palette.accent, palette.accent2],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var pillForeground: Color {
        subscribeState == .subscribed ? palette.text : palette.onAccent
    }

    // MARK: - Artwork fallback idiom (mirrors SearchResultRow/ShelvesList)

    private let artSize: CGFloat = 76

    private var seed: Int {
        result.title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }

    private var initial: String {
        guard let first = result.title.first(where: { !$0.isWhitespace }) else { return "?" }
        return String(first).uppercased()
    }
}

/// `--elev-sub` coral glow (kit `.sub` box-shadow), dropped once the pill
/// reaches `.done` (kit: `box-shadow: none`).
private struct PillGlow: ViewModifier {
    let active: Bool
    let accent: Color

    func body(content: Content) -> some View {
        if active {
            content.elevSub(color: accent)
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct TopResultCardPreviewHost: View {
    @Environment(\.palette) private var palette

    private let sample = DiscoverViewModel.sampleResults[4] // "The Rest Is History"

    var body: some View {
        VStack(spacing: Spacing.sp4) {
            TopResultCard(result: sample, subscribeState: .idle, onSubscribe: {})
            TopResultCard(result: sample, subscribeState: .subscribing, onSubscribe: {})
            TopResultCard(result: sample, subscribeState: .subscribed, onSubscribe: {})
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.groupedBg)
    }
}

#Preview("Top result card — light") {
    TopResultCardPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Top result card — dark") {
    TopResultCardPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
