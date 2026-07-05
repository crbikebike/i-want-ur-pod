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
}
