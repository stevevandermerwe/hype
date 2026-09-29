import Foundation

/// A slide color palette: the same nine keys the Qt app reads from an Omarchy
/// `colors.toml` (`themecatalog.cpp`), plus per-slide overrides (`color_*` front
/// matter keys).
public struct Palette: Sendable, Equatable, Codable {
    public var background: String
    public var foreground: String
    public var accent: String
    public var green: String
    public var red: String
    public var yellow: String
    public var magenta: String
    public var cyan: String
    public var darkForeground: String

    /// The nine colour keys, as used after `color_` in front matter.
    public static let colorKeys = ["background", "foreground", "accent", "green", "red", "yellow", "magenta", "cyan", "dark_foreground"]

    /// The colour for one of `colorKeys`.
    public subscript(key: String) -> String {
        get {
            switch key {
            case "background": return background
            case "foreground": return foreground
            case "accent": return accent
            case "green": return green
            case "red": return red
            case "yellow": return yellow
            case "magenta": return magenta
            case "cyan": return cyan
            default: return darkForeground
            }
        }
        set {
            switch key {
            case "background": background = newValue
            case "foreground": foreground = newValue
            case "accent": accent = newValue
            case "green": green = newValue
            case "red": red = newValue
            case "yellow": yellow = newValue
            case "magenta": magenta = newValue
            case "cyan": cyan = newValue
            default: darkForeground = newValue
            }
        }
    }

    /// Whether the background is light (its perceived brightness is above the middle).
    public var isLight: Bool {
        let hex = background.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return false }
        let red = Double((value >> 16) & 0xFF), green = Double((value >> 8) & 0xFF), blue = Double(value & 0xFF)
        return (0.299 * red + 0.587 * green + 0.114 * blue) / 255 > 0.5
    }

    public static let tokyoNight = Palette(background: "#1a1b26", foreground: "#c0caf5", accent: "#7aa2f7",
                                           green: "#9ece6a", red: "#f7768e", yellow: "#e0af68",
                                           magenta: "#bb9af7", cyan: "#7dcfff", darkForeground: "#565f89")
}

/// Bundled themes. The Qt app discovers themes at runtime from
/// `$OMARCHY_PATH/themes/*/colors.toml`; this Mac app instead ships a fixed set
/// (Phase 1 decision — see `../ROADMAP.md`). The first three come from those
/// themes' `colors.toml` files, so a deck using one renders identically; the
/// rest use each theme's published upstream palette, keeping Omarchy's theme
/// names where Omarchy has the theme so decks stay portable.
public enum BundledTheme: String, CaseIterable, Sendable, Identifiable {
    // Dark
    case tokyoNight = "tokyo-night"
    case nord = "nord"
    case gruvbox = "gruvbox"
    case catppuccin = "catppuccin"
    case rosePine = "rose-pine"
    case everforest = "everforest"
    case kanagawa = "kanagawa"
    case dracula = "dracula"
    case midnight = "midnight"
    // Light
    case catppuccinLatte = "catppuccin-latte"
    case rosePineDawn = "rose-pine-dawn"
    case solarizedLight = "solarized-light"
    case paper = "paper"

    public var id: String { rawValue }

    /// "tokyo-night" → "Tokyo Night", for menus.
    public var displayName: String {
        rawValue.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    public var isLight: Bool {
        switch self {
        case .catppuccinLatte, .rosePineDawn, .solarizedLight, .paper: return true
        default: return false
        }
    }

    public var palette: Palette {
        switch self {
        case .tokyoNight: return .tokyoNight
        case .nord: return Palette(background: "#2e3440", foreground: "#d8dee9", accent: "#88c0d0",
                                   green: "#a3be8c", red: "#bf616a", yellow: "#ebcb8b",
                                   magenta: "#b48ead", cyan: "#8fbcbb", darkForeground: "#4c566a")
        case .gruvbox: return Palette(background: "#282828", foreground: "#ebdbb2", accent: "#fabd2f",
                                      green: "#b8bb26", red: "#fb4934", yellow: "#fabd2f",
                                      magenta: "#d3869b", cyan: "#83a598", darkForeground: "#928374")
        case .catppuccin: return Palette(background: "#1e1e2e", foreground: "#cdd6f4", accent: "#89b4fa",
                                         green: "#a6e3a1", red: "#f38ba8", yellow: "#f9e2af",
                                         magenta: "#cba6f7", cyan: "#94e2d5", darkForeground: "#6c7086")
        case .rosePine: return Palette(background: "#191724", foreground: "#e0def4", accent: "#ebbcba",
                                       green: "#31748f", red: "#eb6f92", yellow: "#f6c177",
                                       magenta: "#c4a7e7", cyan: "#9ccfd8", darkForeground: "#6e6a86")
        case .everforest: return Palette(background: "#2d353b", foreground: "#d3c6aa", accent: "#a7c080",
                                         green: "#a7c080", red: "#e67e80", yellow: "#dbbc7f",
                                         magenta: "#d699b6", cyan: "#83c092", darkForeground: "#859289")
        case .kanagawa: return Palette(background: "#1f1f28", foreground: "#dcd7ba", accent: "#7e9cd8",
                                       green: "#98bb6c", red: "#c34043", yellow: "#e6c384",
                                       magenta: "#957fb8", cyan: "#7fb4ca", darkForeground: "#727169")
        case .dracula: return Palette(background: "#282a36", foreground: "#f8f8f2", accent: "#bd93f9",
                                      green: "#50fa7b", red: "#ff5555", yellow: "#f1fa8c",
                                      magenta: "#ff79c6", cyan: "#8be9fd", darkForeground: "#6272a4")
        case .midnight: return Palette(background: "#0b0d12", foreground: "#f2f4f8", accent: "#ff9e3d",
                                       green: "#7bd88f", red: "#fc618d", yellow: "#fce566",
                                       magenta: "#948ae3", cyan: "#5ad4e6", darkForeground: "#69676c")
        case .catppuccinLatte: return Palette(background: "#eff1f5", foreground: "#4c4f69", accent: "#1e66f5",
                                              green: "#40a02b", red: "#d20f39", yellow: "#df8e1d",
                                              magenta: "#8839ef", cyan: "#179299", darkForeground: "#9ca0b0")
        case .rosePineDawn: return Palette(background: "#faf4ed", foreground: "#575279", accent: "#d7827e",
                                           green: "#286983", red: "#b4637a", yellow: "#ea9d34",
                                           magenta: "#907aa9", cyan: "#56949f", darkForeground: "#9893a5")
        case .solarizedLight: return Palette(background: "#fdf6e3", foreground: "#586e75", accent: "#268bd2",
                                             green: "#859900", red: "#dc322f", yellow: "#b58900",
                                             magenta: "#d33682", cyan: "#2aa198", darkForeground: "#93a1a1")
        case .paper: return Palette(background: "#ffffff", foreground: "#1f2328", accent: "#0969da",
                                    green: "#1a7f37", red: "#cf222e", yellow: "#9a6700",
                                    magenta: "#8250df", cyan: "#1b7c83", darkForeground: "#6e7781")
        }
    }
}

/// The palette named by `theme:` in front matter, with any `color_*` keys
/// overriding individual colors — matching `ThemeCatalog::paletteForTheme` plus
/// the override step `Deck::palette()` applies in the Qt app.
public func palette(forTheme name: String, header: String, store: ThemeStore = .shared) -> Palette {
    var palette = BundledTheme(rawValue: name)?.palette ?? store.palette(named: name) ?? BundledTheme.tokyoNight.palette
    for key in Palette.colorKeys {
        let value = scalar(header, "color_\(key)")
        if !value.isEmpty { palette[key] = value }
    }
    return palette
}
