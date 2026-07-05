// Color hex initializers. Design source: docs/design/direction.md §1 (color roles).
import SwiftUI

public extension Color {
    /// Create a Color from a packed hex integer, e.g. `Color(hex: 0xFF6A4D)`.
    /// Supports RGB (0xRRGGBB) and ARGB (0xAARRGGBB) forms.
    init(hex: UInt, alpha: Double? = nil) {
        let hasAlpha = hex > 0xFFFFFF
        let a: Double
        let r: Double
        let g: Double
        let b: Double
        if hasAlpha {
            a = Double((hex >> 24) & 0xFF) / 255.0
            r = Double((hex >> 16) & 0xFF) / 255.0
            g = Double((hex >> 8) & 0xFF) / 255.0
            b = Double(hex & 0xFF) / 255.0
        } else {
            a = 1.0
            r = Double((hex >> 16) & 0xFF) / 255.0
            g = Double((hex >> 8) & 0xFF) / 255.0
            b = Double(hex & 0xFF) / 255.0
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha ?? a)
    }

    /// Create a Color from a hex string. Accepts "#RGB", "#RRGGBB",
    /// "#AARRGGBB" (and the same without the leading "#"). Falls back to
    /// clear on malformed input so the app never crashes on a bad token.
    init(hex string: String, alpha: Double? = nil) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }

        var value: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&value) else {
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 0)
            return
        }

        let r: Double
        let g: Double
        let b: Double
        var a: Double = 1.0

        switch s.count {
        case 3: // RGB (12-bit)
            r = Double((value >> 8) & 0xF) / 15.0
            g = Double((value >> 4) & 0xF) / 15.0
            b = Double(value & 0xF) / 15.0
        case 6: // RRGGBB
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        case 8: // AARRGGBB
            a = Double((value >> 24) & 0xFF) / 255.0
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        default:
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 0)
            return
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha ?? a)
    }
}
