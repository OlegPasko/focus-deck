import SwiftUI

extension Color {
    /// Build a colour from a "RRGGBB" or "AARRGGBB" hex string.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red, green, blue, alpha: Double
        switch cleaned.count {
        case 8:
            alpha = Double((value & 0xFF00_0000) >> 24) / 255
            red = Double((value & 0x00FF_0000) >> 16) / 255
            green = Double((value & 0x0000_FF00) >> 8) / 255
            blue = Double(value & 0x0000_00FF) / 255
        case 6:
            alpha = 1
            red = Double((value & 0xFF0000) >> 16) / 255
            green = Double((value & 0x00FF00) >> 8) / 255
            blue = Double(value & 0x0000FF) / 255
        default:
            red = 1; green = 1; blue = 1; alpha = 1
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// A plain sRGB colour with Double components and the small amount of colour
/// maths the cover renderer needs (mixing, lightening, alpha scaling).
///
/// The kit hands palettes around as hex strings so it stays UI free; this type
/// is the app-side bridge between those strings and SwiftUI.
struct SynthColor: Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = Self.clamp01(r); self.g = Self.clamp01(g)
        self.b = Self.clamp01(b); self.a = Self.clamp01(a)
    }

    /// Parse "RRGGBB" or "AARRGGBB". Bad input falls back to white.
    init(hex: String, alpha: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        var rr = 1.0, gg = 1.0, bb = 1.0, aa = 1.0
        switch cleaned.count {
        case 8:
            aa = Double((value & 0xFF00_0000) >> 24) / 255
            rr = Double((value & 0x00FF_0000) >> 16) / 255
            gg = Double((value & 0x0000_FF00) >> 8) / 255
            bb = Double(value & 0x0000_00FF) / 255
        case 6:
            rr = Double((value & 0xFF0000) >> 16) / 255
            gg = Double((value & 0x00FF00) >> 8) / 255
            bb = Double(value & 0x0000FF) / 255
        default:
            break
        }
        self.init(r: rr, g: gg, b: bb, a: aa * alpha)
    }

    private static func clamp01(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    /// SwiftUI colour for drawing.
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// Same colour with alpha scaled by `factor` (keeps the original alpha).
    func fade(_ factor: Double) -> SynthColor {
        SynthColor(r: r, g: g, b: b, a: a * max(0, factor))
    }

    /// Same colour with an absolute alpha.
    func alpha(_ value: Double) -> SynthColor {
        SynthColor(r: r, g: g, b: b, a: value)
    }

    /// Linear mix toward `other` (0 = self, 1 = other).
    func mixed(with other: SynthColor, _ t: Double) -> SynthColor {
        let k = min(1, max(0, t))
        return SynthColor(r: r + (other.r - r) * k,
                          g: g + (other.g - g) * k,
                          b: b + (other.b - b) * k,
                          a: a + (other.a - a) * k)
    }

    /// Multiply brightness (keeps alpha).
    func scaled(_ factor: Double) -> SynthColor {
        SynthColor(r: r * factor, g: g * factor, b: b * factor, a: a)
    }

    func lightened(_ t: Double) -> SynthColor { mixed(with: SynthColor(r: 1, g: 1, b: 1), t) }

    func darkened(_ t: Double) -> SynthColor { mixed(with: SynthColor(r: 0, g: 0, b: 0, a: a), t) }

    /// Perceived luminance, 0...1.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    var asColor: Color { color }
}
