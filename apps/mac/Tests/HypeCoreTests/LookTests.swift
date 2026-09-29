import XCTest
@testable import HypeCore

/// Deck-wide look settings: the `text_scale` front-matter key and the bundled
/// theme catalog.
@MainActor
final class LookTests: XCTestCase {
    func testTextScaleDefaultsToOneWhenAbsentOrUnreadable() {
        XCTAssertEqual(DeckModel().textScale, 1)
        XCTAssertEqual(DeckModel(source: "---\ntext_scale: big\n---\n\n# A\n").textScale, 1)
    }

    func testTextScaleIsReadAndClampedToTheAllowedRange() {
        XCTAssertEqual(DeckModel(source: "---\ntext_scale: 0.8\n---\n\n# A\n").textScale, 0.8, accuracy: 0.0001)
        XCTAssertEqual(DeckModel(source: "---\ntext_scale: 9\n---\n\n# A\n").textScale, TextScale.maximum)
        XCTAssertEqual(DeckModel(source: "---\ntext_scale: 0.01\n---\n\n# A\n").textScale, TextScale.minimum)
    }

    func testSetTextScaleWritesFrontMatterRoundedAndIsUndoable() {
        let deck = DeckModel()
        deck.setTextScale(0.7000001)
        XCTAssertEqual(deck.textScale, 0.7, accuracy: 0.0001)
        XCTAssertTrue(deck.source.contains("text_scale: \"0.7\""))
        XCTAssertTrue(deck.source.hasSuffix("# Your next idea\n"), "slides must be untouched")
        deck.undo()
        XCTAssertEqual(deck.source, DeckModel.defaultSource)
    }

    func testSetTextScaleClampsAndStepsStayInRange() {
        let deck = DeckModel()
        deck.setTextScale(5)
        XCTAssertEqual(deck.textScale, TextScale.maximum)
        XCTAssertEqual(TextScale.bigger(TextScale.maximum), TextScale.maximum)
        XCTAssertEqual(TextScale.smaller(TextScale.minimum), TextScale.minimum)
        XCTAssertEqual(TextScale.bigger(1), 1.1, accuracy: 0.0001)
        XCTAssertEqual(TextScale.smaller(1), 0.9, accuracy: 0.0001)
    }

    func testEveryBundledThemeHasAValidDistinctPalette() {
        XCTAssertGreaterThanOrEqual(BundledTheme.allCases.count, 10)
        let hex = try! NSRegularExpression(pattern: "^#[0-9a-fA-F]{6}$")
        for theme in BundledTheme.allCases {
            let p = theme.palette
            for value in [p.background, p.foreground, p.accent, p.green, p.red, p.yellow, p.magenta, p.cyan, p.darkForeground] {
                XCTAssertNotNil(hex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), "\(theme): \(value)")
            }
            XCTAssertNotEqual(p.background.lowercased(), p.foreground.lowercased(), "\(theme)")
        }
        XCTAssertEqual(Set(BundledTheme.allCases.map(\.palette.background)).count, BundledTheme.allCases.count)
    }

    // MARK: Fonts

    func testFontNameDefaultsToEmptyMeaningTheSystemFont() {
        XCTAssertEqual(DeckModel().fontName, "")
        XCTAssertEqual(DeckModel(source: "---\nfont: \"Georgia\"\n---\n\n# A\n").fontName, "Georgia")
        XCTAssertEqual(DeckModel(source: "---\nfont: 'Helvetica Neue'\n---\n\n# A\n").fontName, "Helvetica Neue")
    }

    func testSettingAndClearingTheFontEditsOnlyTheFrontMatterAndCanBeUndone() {
        let deck = DeckModel()
        deck.setFontName("Avenir Next")
        XCTAssertEqual(deck.fontName, "Avenir Next")
        XCTAssertTrue(deck.source.contains("font: \"Avenir Next\""))
        XCTAssertTrue(deck.source.hasSuffix("# Your next idea\n"))
        deck.setFontName("")
        XCTAssertEqual(deck.fontName, "")
        XCTAssertFalse(deck.source.contains("font:"), "clearing removes the key")
        deck.undo()
        XCTAssertEqual(deck.fontName, "Avenir Next")
    }

    func testRemoveScalarDropsOnlyThatKey() {
        let header = "---\ntitle: \"T\"\nfont: \"X\"\ntheme: nord\n---\n"
        XCTAssertEqual(removeScalar(header, "font"), "---\ntitle: \"T\"\ntheme: nord\n---\n")
        XCTAssertEqual(removeScalar(header, "missing"), header)
        XCTAssertEqual(removeScalar("", "font"), "")
        XCTAssertEqual(removeScalar("---\nfont_size: 3\nfont: 1\n---\n", "font"), "---\nfont_size: 3\n---\n", "a longer key with the same start is kept")
    }

    func testLightThemesAreMarkedLight() {
        XCTAssertTrue(BundledTheme.catppuccinLatte.isLight)
        XCTAssertFalse(BundledTheme.tokyoNight.isLight)
    }
}
