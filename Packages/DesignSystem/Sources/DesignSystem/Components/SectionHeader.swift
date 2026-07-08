// Translated from design/kit/components/section-header.html (.sec-head / .count / .sec-sub).
// The label band that tops a group of content (a settings group, the search
// states, a "Suggestions" list). A display-face title on the leading edge, with
// an optional mint count pill pinned to the trailing edge, or an optional
// one-line subtitle below. This is the simpler, non-shelf header — a Result Row
// shelf uses its own "View all" variant. Colors/sizing come only from the active
// ThemePalette + Spacing/Radius/Typography tokens (direction.md §1/§3/§4/§5).
import SwiftUI

/// A section label band: title + optional mint count pill (or subtitle).
///
/// Mirrors `design/kit/components/section-header.html`:
/// - `.sec-head`: `space-between` row, `--sp-6` top / `--sp-1` bottom margin,
///   a 2pt optical inset so the title aligns with the large-title above it.
/// - `h2`: section role (1.34rem / 800, display face), color `--text`.
/// - `.count`: a pill in `--accent-2` (mint / mint-deep) text on a 15% mint
///   tint, radius `--r-pill`, `4×10` padding.
/// - `.sec-sub`: an optional one-line subtitle in `--text-faint`.
public struct SectionHeader: View {
    private let title: String
    private let count: Int?
    private let subtitle: String?

    @Environment(\.palette) private var palette

    /// Title with an optional trailing mint count pill (the frozen signature).
    /// Pass `nil` (or omit) for the title-only variant.
    public init(title: String, count: Int? = nil) {
        self.title = title
        self.count = count
        self.subtitle = nil
    }

    /// Title with a one-line subtitle beneath it (the `.sec-sub` variant).
    public init(title: String, subtitle: String) {
        self.title = title
        self.count = nil
        self.subtitle = subtitle
    }

    /// Title with BOTH a trailing mint count pill and a `.sec-sub` line beneath
    /// — the Up Next "Queue" header (up-next.html: `.sec-head` count + a
    /// sibling `.sec-sub`). The body already lays out count and subtitle
    /// independently; this init is what lets a caller supply both at once.
    public init(title: String, count: Int, subtitle: String) {
        self.title = title
        self.count = count
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {   // .sec-sub margin-top: 2px
            // .sec-head — space-between title / count row.
            HStack(alignment: .center, spacing: Spacing.sp2) {
                Text(title)                          // h2
                    .typeStyle(Typography.sectionStyle)
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)

                if let count {
                    Spacer(minLength: Spacing.sp2)
                    CountPill(count: count)
                }
            }

            if let subtitle {
                Text(subtitle)                       // .sec-sub — wraps (kit has no nowrap)
                    .typeStyle(Typography.subheadStyle)
                    .foregroundStyle(palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // .sec-head margin: --sp-6 (top) 2px (sides) --sp-1 (bottom); the 2px is
        // the intentional optical inset that aligns the header to the title.
        .padding(.horizontal, 2)
        .padding(.top, Spacing.sp6)
        .padding(.bottom, Spacing.sp1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Count pill (.count)

/// The mint count pill: `--accent-2` text on a 15% mint tint, pill radius.
/// The count font is 0.74rem / 800 (direction.md §3 "Count pill"); there is no
/// dedicated Typography token for it, so it is built from the system heavy face.
private struct CountPill: View {
    let count: Int

    @Environment(\.palette) private var palette

    var body: some View {
        Text(count, format: .number)
            .font(Typography.countBadge)                    // .sec-head .count — 0.74rem / 800
            .foregroundStyle(palette.accent2)
            .padding(.vertical, 4)                          // .count padding: 4px 10px
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous)                 // --r-pill
                    // background: color-mix(--accent-2 15%, transparent)
                    .fill(palette.accent2.opacity(0.15))
            )
            .fixedSize()
    }
}

// MARK: - Preview

#if DEBUG
private struct SectionHeaderPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Search sources")            // title only
            SectionHeader(title: "Trending now",              // title + subtitle
                          subtitle: "Fresh picks pulsing across the network today")
            SectionHeader(title: "Downloads", count: 12)      // title + count
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.sp4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.groupedBg)
    }
}

#Preview("Section header — light") {
    SectionHeaderPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Section header — dark") {
    SectionHeaderPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
