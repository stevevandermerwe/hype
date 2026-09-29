import Foundation

/// A slide color palette: the same nine keys the Qt app reads from an Omarchy
/// `colors.toml` (`themecatalog.cpp`), plus per-slide overrides (`color_*` front
/// matter keys).
public struct Palette: Sendable, Equatable {
    public var background: String
    public var foreground: String
    public var accent: String
    public var green: String
    public var red: String
    public var yellow: String
    public var magenta: String
    public var cyan: String
    public var darkForeground: String

    public static let tokyoNight = Palette(background: "#1a1b26", foreground: "#c0caf5", accent: "#7aa2f7",
                                           green: "#9ece6a", red: "#f7768e", yellow: "#e0af68",
                                           magenta: "#bb9af7", cyan: "#7dcfff", darkForeground: "#565f89")
}

/// Bundled themes. The Qt app discovers themes at runtime from
/// `$OMARCHY_PATH/themes/*/colors.toml`; this Mac app instead ships a fixed set
/// (Phase 1 decision — see `../ROADMAP.md`), taken from the same three themes'
/// `colors.toml` files, so a deck using one renders identically.
public enum BundledTheme: String, CaseIterable, Sendable, Identifiable {
    case tokyoNight = "tokyo-night"
    case nord = "nord"
    case gruvbox = "gruvbox"

    public var id: String { rawValue }

    public var palette: Palette {
        switch self {
        case .tokyoNight: return .tokyoNight
        case .nord: return Palette(background: "#2e3440", foreground: "#d8dee9", accent: "#88c0d0",
                                   green: "#a3be8c", red: "#bf616a", yellow: "#ebcb8b",
                                   magenta: "#b48ead", cyan: "#8fbcbb", darkForeground: "#4c566a")
        case .gruvbox: return Palette(background: "#282828", foreground: "#ebdbb2", accent: "#fabd2f",
                                      green: "#b8bb26", red: "#fb4934", yellow: "#fabd2f",
                                      magenta: "#d3869b", cyan: "#83a598", darkForeground: "#928374")
        }
    }
}

/// The palette named by `theme:` in front matter, with any `color_*` keys
/// overriding individual colors — matching `ThemeCatalog::paletteForTheme` plus
/// the override step `Deck::palette()` applies in the Qt app.
public func palette(forTheme name: String, header: String) -> Palette {
    var palette = (BundledTheme(rawValue: name) ?? .tokyoNight).palette
    func override(_ key: String, _ keyPath: WritableKeyPath<Palette, String>) {
        let value = scalar(header, "color_\(key)")
        if !value.isEmpty { palette[keyPath: keyPath] = value }
    }
    override("background", \.background)
    override("foreground", \.foreground)
    override("accent", \.accent)
    override("green", \.green)
    override("red", \.red)
    override("yellow", \.yellow)
    override("magenta", \.magenta)
    override("cyan", \.cyan)
    override("dark_foreground", \.darkForeground)
    return palette
}
