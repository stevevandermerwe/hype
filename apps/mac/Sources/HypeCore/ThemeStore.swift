import Foundation

public enum ThemeStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidName
    /// The name would collide with a bundled theme (its slug is given).
    case reservedName(String)
    /// A colour (named by its palette key) isn't a `#rrggbb` value.
    case invalidColor(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Give the theme a name with at least one letter or number."
        case .reservedName(let slug): return "“\(slug)” is the name of a built-in theme. Choose a different name."
        case .invalidColor(let key): return "The \(key) colour isn't a valid #rrggbb value."
        case .writeFailed(let reason): return "Couldn't save the theme: \(reason)"
        }
    }
}

/// A theme's identifier: the name lowercased with everything but letters and
/// numbers turned into single hyphens ("My Sunset!" → "my-sunset"). It is what
/// goes after `theme:` in a deck, and it is safe to use as a filename.
public func themeSlug(_ name: String) -> String {
    let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en")).lowercased()
    var slug = ""
    for scalar in folded.unicodeScalars {
        let isAlphanumeric = scalar.isASCII && (("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)))
        if isAlphanumeric {
            slug.unicodeScalars.append(scalar)
        } else if !slug.hasSuffix("-"), !slug.isEmpty {
            slug += "-"
        }
    }
    while slug.hasSuffix("-") { slug.removeLast() }
    return slug
}

/// A theme you made: a name and a palette, saved as a small JSON file.
public struct CustomTheme: Codable, Equatable, Identifiable, Sendable {
    public var version = 1
    public var name: String
    public var palette: Palette

    public var slug: String { themeSlug(name) }
    public var id: String { slug }

    public init(name: String, palette: Palette) {
        self.name = name
        self.palette = palette
    }
}

/// Where your own themes live: one `<slug>.json` file per theme in a folder
/// (`~/Library/Application Support/Hype/Themes` by default), read by the app and
/// the `hype` tool alike. Decks name a custom theme by its slug, and the theme's
/// colours are also written into the deck when it is chosen, so the deck still
/// looks right on a Mac that doesn't have the theme.
public final class ThemeStore: @unchecked Sendable {
    public static let shared = ThemeStore(directory: ThemeStore.defaultDirectory)

    /// `~/Library/Application Support/Hype/Themes`, or the folder named by the
    /// `HYPE_THEMES_DIR` environment variable (for tests and scripts).
    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["HYPE_THEMES_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hype/Themes", isDirectory: true)
    }

    public let directory: URL
    private let lock = NSLock()
    private var cache: (stamp: Date?, palettes: [String: Palette])?

    public init(directory: URL) { self.directory = directory }

    private var directoryStamp: Date? {
        (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Every saved theme, sorted by name. Unreadable files are skipped.
    public func list() throws -> [CustomTheme] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder()
        return files.compactMap { file -> CustomTheme? in
            guard let data = try? Data(contentsOf: file), let theme = try? decoder.decode(CustomTheme.self, from: data),
                  !theme.slug.isEmpty, Self.firstInvalidColor(in: theme.palette) == nil else { return nil }
            return theme
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The palette saved under `name` (a slug), or nil. Cached, and refreshed when
    /// the folder changes (including from another process).
    public func palette(named name: String) -> Palette? {
        lock.lock()
        defer { lock.unlock() }
        let stamp = directoryStamp
        if cache == nil || cache?.stamp != stamp {
            let themes = (try? list()) ?? []
            cache = (stamp, Dictionary(themes.map { ($0.slug, $0.palette) }, uniquingKeysWith: { first, _ in first }))
        }
        return cache?.palettes[name]
    }

    /// Saves (or replaces) the theme called `name`. Refuses a name with no letters
    /// or numbers, one that clashes with a bundled theme, or a colour that isn't `#rrggbb`.
    @discardableResult
    public func save(name: String, palette: Palette) throws -> CustomTheme {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = themeSlug(cleanName)
        guard !slug.isEmpty else { throw ThemeStoreError.invalidName }
        guard BundledTheme(rawValue: slug) == nil else { throw ThemeStoreError.reservedName(slug) }
        if let bad = Self.firstInvalidColor(in: palette) { throw ThemeStoreError.invalidColor(bad) }

        var normalized = palette
        for key in Palette.colorKeys { normalized[key] = palette[key].lowercased() }
        let theme = CustomTheme(name: cleanName, palette: normalized)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(theme).write(to: directory.appendingPathComponent("\(slug).json"), options: .atomic)
        } catch {
            throw ThemeStoreError.writeFailed(error.localizedDescription)
        }
        lock.lock(); cache = nil; lock.unlock()
        return theme
    }

    /// Deletes the theme with this slug (nothing happens if there isn't one). The
    /// slug is re-cleaned, so it can't point outside the folder.
    public func delete(slug: String) throws {
        let safe = themeSlug(slug)
        guard !safe.isEmpty else { return }
        let file = directory.appendingPathComponent("\(safe).json")
        if FileManager.default.fileExists(atPath: file.path) {
            do { try FileManager.default.removeItem(at: file) } catch { throw ThemeStoreError.writeFailed(error.localizedDescription) }
        }
        lock.lock(); cache = nil; lock.unlock()
    }

    private static let hexRe = try! NSRegularExpression(pattern: "^#[0-9a-fA-F]{6}$")

    /// The palette key of the first colour that isn't `#rrggbb`, if any.
    static func firstInvalidColor(in palette: Palette) -> String? {
        Palette.colorKeys.first { key in
            let value = palette[key]
            return hexRe.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) == nil
        }
    }
}

/// One entry in a theme menu: a bundled theme or one of yours.
public struct ThemeChoice: Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var palette: Palette
    public var isCustom: Bool
    public var isLight: Bool { palette.isLight }

    public init(id: String, displayName: String, palette: Palette, isCustom: Bool) {
        self.id = id
        self.displayName = displayName
        self.palette = palette
        self.isCustom = isCustom
    }
}

/// Just the bundled themes, in menu order.
public func bundledThemeChoices() -> [ThemeChoice] {
    BundledTheme.allCases.map { ThemeChoice(id: $0.rawValue, displayName: $0.displayName, palette: $0.palette, isCustom: false) }
}

/// The bundled themes followed by your own, for menus and `hype themes`.
public func themeChoices(store: ThemeStore = .shared) -> [ThemeChoice] {
    let custom = ((try? store.list()) ?? []).map {
        ThemeChoice(id: $0.slug, displayName: $0.name, palette: $0.palette, isCustom: true)
    }
    return bundledThemeChoices() + custom
}
