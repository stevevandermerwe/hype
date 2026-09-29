import XCTest
@testable import HypeCore

/// User-made themes: saved as small JSON files, listed beside the bundled ones,
/// resolvable by name, and baked into a deck when chosen.
@MainActor
final class ThemeStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ThemeStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hype-themes-\(UUID().uuidString)")
        store = ThemeStore(directory: directory)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private let sunset = Palette(background: "#2b1b2e", foreground: "#f6e7d8", accent: "#ff8552", green: "#8fd694",
                                 red: "#ff5c5c", yellow: "#ffd166", magenta: "#e07be0", cyan: "#7fd6e6", darkForeground: "#7d6b7f")

    // MARK: Names

    func testSlugsAreLowercaseHyphenatedAndSafe() {
        XCTAssertEqual(themeSlug("My Sunset Theme"), "my-sunset-theme")
        XCTAssertEqual(themeSlug("  Café  Noir!! "), "cafe-noir")
        XCTAssertEqual(themeSlug("../../etc/passwd"), "etc-passwd")
        XCTAssertEqual(themeSlug("***"), "")
    }

    // MARK: Saving and listing

    func testASavedThemeCanBeListedAndLoadedByItsSlug() throws {
        let saved = try store.save(name: "My Sunset", palette: sunset)
        XCTAssertEqual(saved.slug, "my-sunset")
        XCTAssertEqual(saved.name, "My Sunset")
        XCTAssertEqual(try store.list().map(\.slug), ["my-sunset"])
        XCTAssertEqual(store.palette(named: "my-sunset"), sunset)
        XCTAssertNil(store.palette(named: "nope"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("my-sunset.json").path))
    }

    func testSavingAgainUnderTheSameNameReplacesIt() throws {
        _ = try store.save(name: "Sunset", palette: sunset)
        var changed = sunset
        changed.accent = "#00ff00"
        _ = try store.save(name: "sunset", palette: changed)
        XCTAssertEqual(try store.list().count, 1)
        XCTAssertEqual(store.palette(named: "sunset")?.accent, "#00ff00")
    }

    func testListIsSortedByNameAndSkipsUnreadableFiles() throws {
        _ = try store.save(name: "Zebra", palette: sunset)
        _ = try store.save(name: "apple", palette: sunset)
        try "not json".write(to: directory.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
        try "ignored".write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.list().map(\.name), ["apple", "Zebra"])
    }

    func testBadNamesAndColoursAreRefused() {
        XCTAssertThrowsError(try store.save(name: "   ", palette: sunset)) { XCTAssertEqual($0 as? ThemeStoreError, .invalidName) }
        XCTAssertThrowsError(try store.save(name: "***", palette: sunset)) { XCTAssertEqual($0 as? ThemeStoreError, .invalidName) }
        XCTAssertThrowsError(try store.save(name: "Nord", palette: sunset)) { XCTAssertEqual($0 as? ThemeStoreError, .reservedName("nord")) }
        var bad = sunset
        bad.accent = "orange"
        XCTAssertThrowsError(try store.save(name: "Fine", palette: bad)) { XCTAssertEqual($0 as? ThemeStoreError, .invalidColor("accent")) }
        XCTAssertEqual((try? store.list().count) ?? 0, 0, "nothing is written for a refused theme")
    }

    func testDeletingRemovesTheThemeAndIgnoresMissingOnes() throws {
        _ = try store.save(name: "Sunset", palette: sunset)
        try store.delete(slug: "sunset")
        XCTAssertEqual(try store.list().count, 0)
        XCTAssertNil(store.palette(named: "sunset"))
        XCTAssertNoThrow(try store.delete(slug: "sunset"))
        XCTAssertNoThrow(try store.delete(slug: "../escape"), "a slug can't reach outside the folder")
    }

    func testAMissingFolderMeansNoThemes() throws {
        XCTAssertEqual(try store.list().count, 0)
        XCTAssertNil(store.palette(named: "anything"))
    }

    // MARK: Light or dark

    func testPalettesAreClassifiedLightOrDarkByTheirBackground() {
        XCTAssertFalse(sunset.isLight)
        XCTAssertTrue(BundledTheme.paper.palette.isLight)
        XCTAssertTrue(BundledTheme.catppuccinLatte.palette.isLight)
        XCTAssertFalse(BundledTheme.tokyoNight.palette.isLight)
    }

    // MARK: Choices for menus

    func testChoicesListBundledThemesThenCustomOnesWithoutNameClashes() throws {
        _ = try store.save(name: "Sunset", palette: sunset)
        let choices = themeChoices(store: store)
        XCTAssertEqual(choices.filter { !$0.isCustom }.count, BundledTheme.allCases.count)
        let custom = try XCTUnwrap(choices.first { $0.isCustom })
        XCTAssertEqual(custom.id, "sunset")
        XCTAssertEqual(custom.displayName, "Sunset")
        XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
    }

    // MARK: In a deck

    func testACustomThemeResolvesByNameInADeckAndFallsBackWhenMissing() throws {
        _ = try store.save(name: "Sunset", palette: sunset)
        let deck = DeckModel(source: "---\ntheme: sunset\n---\n\n# A\n", themes: store)
        XCTAssertEqual(deck.palette, sunset)
        let elsewhere = DeckModel(source: "---\ntheme: sunset\n---\n\n# A\n", themes: ThemeStore(directory: directory.appendingPathComponent("none")))
        XCTAssertEqual(elsewhere.palette, BundledTheme.tokyoNight.palette, "an unknown theme falls back to the default")
    }

    func testChoosingACustomThemeBakesItsColoursSoItTravelsWithTheDeck() throws {
        _ = try store.save(name: "Sunset", palette: sunset)
        let deck = DeckModel(themes: store)
        deck.chooseTheme("sunset")
        XCTAssertEqual(deck.themeName, "sunset")
        XCTAssertTrue(deck.source.contains("color_background: \"#2b1b2e\""))
        XCTAssertTrue(deck.source.contains("color_dark_foreground: \"#7d6b7f\""))
        // Opened on a Mac without the theme, the baked colours still apply.
        let elsewhere = DeckModel(source: deck.source, themes: ThemeStore(directory: directory.appendingPathComponent("none")))
        XCTAssertEqual(elsewhere.palette, sunset)
    }

    func testChoosingAnyThemeClearsColoursLeftOverFromAnEarlierOne() throws {
        _ = try store.save(name: "Sunset", palette: sunset)
        let deck = DeckModel(themes: store)
        deck.chooseTheme("sunset")
        deck.chooseTheme("nord")
        XCTAssertFalse(deck.source.contains("color_"), "stale overrides would hide the new theme")
        XCTAssertEqual(deck.palette, BundledTheme.nord.palette)
        deck.undo()
        XCTAssertEqual(deck.palette, sunset)
    }

    func testChoosingAThemeKeepsOtherFrontMatterAndSlides() {
        let deck = DeckModel(source: "---\ntitle: \"T\"\nfont: \"Georgia\"\n---\n\n# One\n", themes: store)
        deck.chooseTheme("dracula")
        XCTAssertEqual(deck.fontName, "Georgia")
        XCTAssertEqual(deck.title, "T")
        XCTAssertEqual(deck.slideText(at: 0), "# One")
    }
}
