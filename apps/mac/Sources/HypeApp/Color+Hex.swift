import SwiftUI

extension Color {
    /// A `#rrggbb` (or `#rgb`) hex string, as stored in Hype's theme palettes and
    /// `color_*` front matter. Falls back to black for anything unparsable.
    init(hex: String) {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .black
            return
        }
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                 blue: Double(value & 0xff) / 255)
    }

    /// A readable ink color over `self`, by relative luminance — matches the
    /// Qt renderer's contrast check for an explicit background color.
    static func contrastingInk(over hex: String) -> Color {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .white }
        let r = Double((value >> 16) & 0xff) / 255, g = Double((value >> 8) & 0xff) / 255, b = Double(value & 0xff) / 255
        let luminance = r * 0.2126 + g * 0.7152 + b * 0.0722
        return luminance > 0.55 ? Color(hex: "#161616") : .white
    }
}
