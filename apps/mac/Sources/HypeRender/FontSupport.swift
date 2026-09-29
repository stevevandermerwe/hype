import SwiftUI
import AppKit

/// Custom slide fonts. A deck's `font:` front-matter key names an installed font
/// (a family such as "Avenir Next", or a specific face like "Avenir-Heavy");
/// slides are set in it, and fall back to the system font if it isn't installed
/// on this Mac. Code always stays monospaced.

/// The installed font families, alphabetical, for a font picker.
public func availableFontFamilies() -> [String] {
    var seen = Set<String>()
    return NSFontManager.shared.availableFontFamilies
        .filter { seen.insert($0).inserted }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

/// The name to hand to `Font.custom` for `requested`, or nil if no such font is
/// installed (or nothing was requested). Accepts a family, a full name, or a
/// PostScript name, ignoring surrounding spaces and letter case of a family.
public func resolvedFontName(_ requested: String) -> String? {
    let name = requested.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return nil }
    if NSFont(name: name, size: 12) != nil { return name }
    return NSFontManager.shared.availableFontFamilies.first { $0.caseInsensitiveCompare(name) == .orderedSame }
}

public func isFontAvailable(_ name: String) -> Bool { resolvedFontName(name) != nil }

/// A SwiftUI font at `size` for a resolved name (see `resolvedFontName`), or the
/// system font when there is none.
func slideFont(_ resolvedName: String?, size: CGFloat) -> Font {
    if let resolvedName { return .custom(resolvedName, fixedSize: size) }
    return .system(size: size)
}
