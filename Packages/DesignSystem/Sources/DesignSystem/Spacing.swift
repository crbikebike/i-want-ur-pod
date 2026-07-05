// Spacing scale. Design source: docs/design/direction.md §4 (4-based ramp).
import CoreGraphics

/// 4-based spacing ramp. Gutter = sp5 = 20 (the page inset). Use tokens, not raw px.
public enum Spacing {
    /// 4 — micro nudge.
    public static let sp1: CGFloat = 4
    /// 8 — icon gaps, chip gaps.
    public static let sp2: CGFloat = 8
    /// 12 — card padding, list-to-list gaps.
    public static let sp3: CGFloat = 12
    /// 16 — block separation.
    public static let sp4: CGFloat = 16
    /// 20 — page gutter (`--sp-5` / `--gutter`).
    public static let sp5: CGFloat = 20
    /// 26 — section top margin.
    public static let sp6: CGFloat = 26
    /// 32 — large-state vertical padding.
    public static let sp7: CGFloat = 32

    /// The page gutter — alias of `sp5` (20).
    public static let gutter: CGFloat = 20
}
