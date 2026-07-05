// Elevation / shadows. Design source: docs/design/direction.md §6 (elevation table).
// CSS shadows carry a negative spread and a 1px hairline that SwiftUI's
// `.shadow` cannot express directly; these modifiers approximate them —
// radius ≈ blur/2, y = CSS offset-y, spread dropped, alpha preserved. The
// leading `0 1px 0 hairline` line in elev-list/card is rendered as a thin
// top border overlay.
import SwiftUI

public extension View {
    /// `--elev-list` — grouped list float. Soft drop + top hairline.
    func elevList(hairline: Color) -> some View {
        modifier(ElevationLine(hairline: hairline,
                               shadow: Color(hex: 0x000000, alpha: 0.5),
                               radius: 12, y: 8))
    }

    /// `--elev-card` — card float. Slightly deeper than list + top hairline.
    func elevCard(hairline: Color) -> some View {
        modifier(ElevationLine(hairline: hairline,
                               shadow: Color(hex: 0x000000, alpha: 0.55),
                               radius: 15, y: 12))
    }

    /// `--elev-sub` — coral glow carried only by the Subscribe pill (§6).
    /// Defaults to the constant coral brand hue; pass the theme accent to
    /// match light-mode coral-deep.
    func elevSub(color: Color = Brand.coral) -> some View {
        shadow(color: color.opacity(0.9), radius: 7, x: 0, y: 6)
    }

    /// `--elev-pop` — popovers / floating surfaces.
    func elevPop() -> some View {
        shadow(color: Color(hex: 0x000000, alpha: 0.6), radius: 25, x: 0, y: 20)
    }
}

/// Soft drop shadow plus the 1px top hairline from the elev-list/card tokens.
private struct ElevationLine: ViewModifier {
    let hairline: Color
    let shadow: Color
    let radius: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(hairline)
                    .frame(height: 1)
            }
            .shadow(color: shadow, radius: radius, x: 0, y: y)
    }
}
