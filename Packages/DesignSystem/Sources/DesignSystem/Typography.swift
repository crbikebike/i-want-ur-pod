// Type scale. Design source: docs/design/direction.md §3 (type scale table).
// Display roles use IBM Plex Mono (brand display face); everything else uses
// Roboto — which is NOT bundled (see FontRegistration.swift), so UI/body roles
// fall back to the system font. rem→pt uses the web root of 16pt (1rem = 16pt).
// Tracking below is precomputed in points (em × size). Weights map:
// 800→.heavy, 700→.bold, 600→.semibold, 500→.medium.
import SwiftUI

/// A resolved type token: font + letter tracking + optional uppercasing.
/// Apply with `.typeStyle(_:)` so tracking and case (which `Font` alone cannot
/// carry) are honored on the rendered `Text`/`View`.
public struct TypeStyle: Sendable {
    public let font: Font
    public let tracking: CGFloat
    public let uppercase: Bool

    public init(font: Font, tracking: CGFloat = 0, uppercase: Bool = false) {
        self.font = font
        self.tracking = tracking
        self.uppercase = uppercase
    }
}

/// Font + type-token helpers matching the direction.md §3 table verbatim.
/// The `Font` accessors are the primary API (named per spec); the matching
/// `*Style` tokens additionally carry tracking/case for `.typeStyle(_:)`.
public enum Typography {

    // MARK: Font family names

    /// Bundled brand display face (IBM Plex Mono, Regular only — see FontRegistration).
    public static let displayFontName = FontRegistration.displayFontName

    private static func display(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        // Only the Regular weight of IBM Plex Mono is bundled; a heavier
        // `weight` is requested for forward-compat but renders Regular until
        // the extra faces ship, then falls back to the system mono/display.
        Font.custom(displayFontName, size: size).weight(weight)
    }

    private static func ui(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        // Roboto is not bundled — use the system font at the target weight.
        Font.system(size: size, weight: weight)
    }

    // MARK: Roles (Font accessors — exact spec names)

    /// Large title — 2.32rem / 800 / -0.02em. Display face.
    public static var displayLargeTitle: Font { display(37.12, .heavy) }
    /// Section (h2) — 1.34rem / 800 / -0.015em. Display face.
    public static var section: Font { display(21.44, .heavy) }
    /// Nav title (inline) — 1.06rem / 800 / -0.01em. Display face.
    public static var navTitle: Font { display(16.96, .heavy) }
    /// Shelf header (result-row.html `.sh-title`) — 1.18rem / 800 / -0.015em.
    /// Display face, per direction.md §3's prose ("shelf headers" use
    /// `--font-display`) — filling a gap the type-scale table itself omitted.
    public static var shelfTitle: Font { display(18.88, .heavy) }
    /// Row title — 1rem / 700 / -0.01em. UI face.
    public static var rowTitle: Font { ui(16, .bold) }
    /// Body / input — 1rem / 500. UI face.
    public static var body: Font { ui(16, .medium) }
    /// Subhead / author — 0.82rem / 500. UI face.
    public static var subhead: Font { ui(13.12, .medium) }
    /// Settings group label — 0.72rem / 800 / 0.06em, uppercase. UI face.
    public static var groupLabel: Font { ui(11.52, .heavy) }
    /// Badge / tag (Primary, Open index) — 0.62rem / 800 / 0.04em, uppercase. UI face.
    public static var badge: Font { ui(9.92, .heavy) }
    /// Eyebrow — 0.72rem / 800 / 0.12em, uppercase. UI face.
    public static var eyebrow: Font { ui(11.52, .heavy) }
    /// Tag — 0.64rem / 800 / 0.02em, uppercase. UI face.
    public static var tag: Font { ui(10.24, .heavy) }
    /// Tab label — 0.62rem / 600 / 0.01em. UI face.
    public static var tabLabel: Font { ui(9.92, .semibold) }

    // MARK: Roles (full TypeStyle tokens — carry tracking + case)

    public static var displayLargeTitleStyle: TypeStyle { .init(font: displayLargeTitle, tracking: -0.742) }
    public static var sectionStyle: TypeStyle { .init(font: section, tracking: -0.322) }
    public static var navTitleStyle: TypeStyle { .init(font: navTitle, tracking: -0.170) }
    public static var shelfTitleStyle: TypeStyle { .init(font: shelfTitle, tracking: -0.283) }
    public static var rowTitleStyle: TypeStyle { .init(font: rowTitle, tracking: -0.160) }
    public static var bodyStyle: TypeStyle { .init(font: body) }
    public static var subheadStyle: TypeStyle { .init(font: subhead) }
    public static var groupLabelStyle: TypeStyle { .init(font: groupLabel, tracking: 0.691, uppercase: true) }
    public static var badgeStyle: TypeStyle { .init(font: badge, tracking: 0.397, uppercase: true) }
    public static var eyebrowStyle: TypeStyle { .init(font: eyebrow, tracking: 1.382, uppercase: true) }
    public static var tagStyle: TypeStyle { .init(font: tag, tracking: 0.205, uppercase: true) }
    public static var tabLabelStyle: TypeStyle { .init(font: tabLabel, tracking: 0.099) }
}

public extension View {
    /// Apply a `TypeStyle` (font + tracking + optional uppercasing).
    func typeStyle(_ style: TypeStyle) -> some View {
        let base = self.font(style.font).tracking(style.tracking)
        return Group {
            if style.uppercase {
                base.textCase(.uppercase)
            } else {
                base
            }
        }
    }
}
