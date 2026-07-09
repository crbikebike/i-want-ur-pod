// Corner radii. Design source: docs/design/direction.md §5 (radii table).
import CoreGraphics

/// Named corner radii. `rSeg9` is retained-but-unused (§5) for byte-identity
/// with the kit; kept so a future segmented control has its inner corner.
public enum Radius {
    /// 12 — small fills.
    public static let rSm12: CGFloat = 12
    /// 9 — segmented track/thumb (retained, currently unused — §5).
    public static let rSeg9: CGFloat = 9
    /// 11 — search field.
    public static let rField11: CGFloat = 11
    /// 14 — row / skeleton artwork tile.
    public static let rArt14: CGFloat = 14
    /// 16 — card artwork.
    public static let rMd16: CGFloat = 16
    /// 20 — grouped lists, cards.
    public static let rLg20: CGFloat = 20
    /// 999 — pill (buttons, tags, count, subscribe).
    public static let rPill999: CGFloat = 999

    /// 26 — modal sheet top corners (`.afu-sheet`,
    /// design/kit/screens/add-feed-url.html:241). A literal `26px`, distinct
    /// from `rLg20`'s 20 — not in direction.md's §5 table, so named here
    /// rather than mapped to the nearest existing radius.
    public static let rSheet26: CGFloat = 26
    /// 22 — the Add Feed success check badge (`.afu-check`,
    /// design/kit/screens/add-feed-url.html:324). Also a literal not in the
    /// §5 table.
    public static let rCheck22: CGFloat = 22

    /// 13 — Settings' Feeds row icon tile (`.src-ico`,
    /// design/kit/screens/settings.html:301). Distinct from `rArt14`'s 14 —
    /// a literal not in the §5 table, named rather than mapped to the
    /// nearest existing radius.
    public static let rIcon13: CGFloat = 13
}
