// Semantic color roles for both themes. Design source: docs/design/direction.md §1.
// direction.md is authoritative over design/kit/tokens.html (stale on light neutrals);
// §11 (2026-07-04) warmed the light neutrals used below.
import SwiftUI

/// The two shipping themes. Dark is the hero; both ship.
/// Resolve a concrete ``ThemePalette`` from a SwiftUI `ColorScheme`.
public enum Theme: String, CaseIterable, Sendable {
    case dark
    case light

    /// The palette of semantic color roles for this theme.
    public var palette: ThemePalette {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }

    /// Map a SwiftUI `ColorScheme` onto a `Theme`.
    public init(_ colorScheme: ColorScheme) {
        self = (colorScheme == .dark) ? .dark : .light
    }

    /// Resolve the palette directly from the environment color scheme.
    public static func palette(for colorScheme: ColorScheme) -> ThemePalette {
        Theme(colorScheme).palette
    }
}

/// The theme-agnostic brand ramp. Hues never fork per theme (direction.md §1).
public enum Brand {
    public static let coral = Color(hex: 0xFF6A4D)
    public static let coralDeep = Color(hex: 0xCA340F)
    public static let mint = Color(hex: 0x34E0C4)
    public static let mintDeep = Color(hex: 0x046B58)
    public static let grape = Color(hex: 0x7C6BFF)
}

/// One-off decorative kit hues that appear in more than one place in the kit
/// with no matching theme role (direction.md has no §1 entry for these).
/// Named here so they're defined once instead of hand-copied per call site.
public enum KitLiteralColors {
    /// The PodcastIndex icon gradient's blue stop, also reused as one of the
    /// `.a2` artwork-tile gradient stops (`ArtworkTile.swift`).
    static let podcastIndexBlue = Color(hex: 0x2E8BFF)

    /// `.afu-field.bad`'s focus ring (design/kit/screens/add-feed-url.html:273)
    /// — a literal `#FF5A6E` with no light-theme override in the kit, so it's
    /// theme-agnostic like the brand ramp rather than a `ThemePalette` role.
    /// Public (unlike `podcastIndexBlue`, package-internal only) because
    /// `AddFeedSheet` (app target) needs it for the field's error ring.
    public static let errorRing = Color(hex: 0xFF5A6E)
}

/// Every semantic color role, resolved for one theme. Role → value mapping
/// is direction.md §1; brand hues stay constant, roles remap per theme.
public struct ThemePalette: Sendable {
    // Surfaces
    public let bg: Color
    public let groupedBg: Color
    public let surface: Color
    public let surface2: Color

    // Text
    public let text: Color
    public let textDim: Color
    public let textFaint: Color

    // Accents
    public let accent: Color
    public let accent2: Color
    public let onAccent: Color

    /// `.afu-note.error` text/icon color (design/kit/screens/add-feed-url.html:296-297)
    /// — a themed pair (`#FF7A6A` dark / `#D8322B` light) distinct from the
    /// theme-agnostic `KitLiteralColors.errorRing`, so it's a `ThemePalette`
    /// role rather than a `Brand` constant.
    public let errorText: Color

    /// Destructive-action fill (`--danger`, design/kit/screens/up-next.html) —
    /// the swipe-to-remove action background on Up Next queue rows. A themed
    /// pair mirroring iOS system red (`#FF453A` dark / `#FF3B30` light).
    public let danger: Color

    // Lines & fills
    public let hairline: Color
    public let separator: Color
    public let chip: Color
    public let segTrack: Color
    public let segThumb: Color
    public let field: Color

    // Materials / chrome
    public let barMaterial: Color
    public let tabbarGlass: Color
    public let tabbarHairline: Color
    public let tabbarIcon: Color

    // Brand ramp (constant across themes; mirrored here for convenience)
    public let coral = Brand.coral
    public let coralDeep = Brand.coralDeep
    public let mint = Brand.mint
    public let mintDeep = Brand.mintDeep
    public let grape = Brand.grape

    /// Dark (hero) theme — direction.md §1 "Dark (hero)".
    public static let dark = ThemePalette(
        bg: Color(hex: 0x0E0B12),
        groupedBg: Color(hex: 0x0E0B12),
        surface: Color(hex: 0x1C1722),
        surface2: Color(hex: 0x262030),
        text: Color(hex: 0xF8F3EF),
        textDim: Color(hex: 0xABA1B4),
        textFaint: Color(hex: 0x988DA1),
        accent: Color(hex: 0xFF6A4D),      // coral
        accent2: Color(hex: 0x34E0C4),     // mint
        onAccent: Color(hex: 0x2A0E04),
        errorText: Color(hex: 0xFF7A6A),
        danger: Color(hex: 0xFF453A),
        hairline: Color(hex: 0xFFFFFF, alpha: 0.09),
        separator: Color(hex: 0xFFFFFF, alpha: 0.12),
        chip: Color(hex: 0xFFFFFF, alpha: 0.08),
        segTrack: Color(hex: 0x787880, alpha: 0.24),
        segThumb: Color(hex: 0x38313F),
        field: Color(hex: 0x787880, alpha: 0.24),
        barMaterial: Color(hex: 0x14101A, alpha: 0.72),
        tabbarGlass: Color(hex: 0x0E0B12, alpha: 0.94),
        tabbarHairline: Color(hex: 0xFFFFFF, alpha: 0.14),
        tabbarIcon: Color(hex: 0x8B8291)
    )

    /// Light theme — direction.md §1 "Light" with §11 warmed neutrals (2026-07-04).
    public static let light = ThemePalette(
        bg: Color(hex: 0xFBF5EF),
        groupedBg: Color(hex: 0xFBF5EF),
        surface: Color(hex: 0xFFFFFF),
        surface2: Color(hex: 0xFCEFE7),
        text: Color(hex: 0x1A1420),
        textDim: Color(hex: 0x6B6472),
        textFaint: Color(hex: 0x736A78),
        accent: Color(hex: 0xCA340F),      // coral-deep
        accent2: Color(hex: 0x046B58),     // mint-deep
        onAccent: Color(hex: 0xFFFFFF),
        errorText: Color(hex: 0xD8322B),
        danger: Color(hex: 0xFF3B30),
        hairline: Color(hex: 0x281A24, alpha: 0.10),
        separator: Color(hex: 0x3C3C43, alpha: 0.18),
        chip: Color(hex: 0xF1E7DF),
        segTrack: Color(hex: 0xEFE4DB),
        segThumb: Color(hex: 0xFFFFFF),
        field: Color(hex: 0xF3EAE2),
        barMaterial: Color(hex: 0xF8F6FA, alpha: 0.78),
        tabbarGlass: Color(hex: 0xFAF8FC, alpha: 0.96),
        tabbarHairline: Color(hex: 0x3C3C43, alpha: 0.18),
        tabbarIcon: Color(hex: 0x6C6C70)
    )
}

// MARK: - Environment access

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette = .dark
}

public extension EnvironmentValues {
    /// The active palette. Screens read `@Environment(\.palette)`; a host view
    /// keeps it in sync with the system color scheme via `.themedPalette()`.
    var palette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

public extension View {
    /// Inject the palette that matches the current `ColorScheme` into the
    /// environment so descendants can read `@Environment(\.palette)`.
    func themedPalette() -> some View {
        modifier(ThemedPaletteModifier())
    }
}

private struct ThemedPaletteModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.environment(\.palette, Theme.palette(for: colorScheme))
    }
}
