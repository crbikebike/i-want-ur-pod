// Translated from design/kit/screens/home.html `.tag` / `.tag.hot`
// ("standalone chip, same look as the results-row .tag, usable anywhere",
// lines ~547-630).
import SwiftUI

/// The two `.tag` looks from the kit.
public enum TagChipStyle: Sendable {
    /// `.tag` — `--chip` background, `--text-dim` text.
    case neutral
    /// `.tag.hot` — `--accent` background, `--on-accent` text.
    case hot
}

/// A small uppercase pill chip (`.tag` / `.tag.hot`). Uppercases its own
/// text (`Typography.tagChipStyle` carries tracking only, not the case
/// transform) so non-chip callers of the shared type token aren't forced
/// into uppercase.
public struct TagChip: View {
    private let title: String
    private let style: TagChipStyle

    @Environment(\.palette) private var palette

    public init(_ title: String, style: TagChipStyle = .neutral) {
        self.title = title
        self.style = style
    }

    public var body: some View {
        Text(title)
            .typeStyle(Typography.tagChipStyle)
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.rPill999, style: .continuous)
                    .fill(background)
            )
    }

    private var foreground: Color {
        switch style {
        case .neutral: return palette.textDim
        case .hot:     return palette.onAccent
        }
    }

    private var background: Color {
        switch style {
        case .neutral: return palette.chip
        case .hot:     return palette.accent
        }
    }
}

// MARK: - Preview

#if DEBUG
private struct TagChipPreviewHost: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sp5) {
            Text("Styles").typeStyle(Typography.groupLabelStyle).foregroundStyle(palette.textFaint)
            HStack(spacing: Spacing.sp3) {
                TagChip("New")
                TagChip("Trending", style: .hot)
            }
        }
        .padding(Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.groupedBg)
    }
}

#Preview("Tag chip — light") {
    TagChipPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .light)
}

#Preview("Tag chip — dark") {
    TagChipPreviewHost()
        .themedPalette()
        .environment(\.colorScheme, .dark)
}
#endif
