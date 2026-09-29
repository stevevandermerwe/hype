import XCTest
@testable import HypeCore

/// The front-matter read/write helpers behind the visual front-matter editor.
final class FrontMatterTests: XCTestCase {
    func testSetTitleAddsAndRemovesTheKey() {
        let deck = DeckModel(source: "---\ntheme: tokyo-night\n---\n\n# One\n")
        XCTAssertEqual(deck.titleValue, "")
        deck.setTitle("My Talk")
        XCTAssertEqual(deck.titleValue, "My Talk")
        XCTAssertTrue(deck.source.contains("title:"))
        deck.setTitle("")
        XCTAssertEqual(deck.titleValue, "")
        XCTAssertFalse(deck.source.contains("title:"))
    }

    func testPageNumberPositionAndColorRoundTrip() {
        let deck = DeckModel()
        XCTAssertNil(deck.pageNumberPosition)
        deck.setPageNumberPosition(.bottom)
        XCTAssertEqual(deck.pageNumberPosition, .bottom)
        deck.setPageNumberPosition(nil)
        XCTAssertNil(deck.pageNumberPosition)

        deck.setPageNumberColorHex("#123456")
        XCTAssertEqual(deck.pageNumberColorHex, "#123456")
        deck.setPageNumberColorHex("")
        XCTAssertEqual(deck.pageNumberColorHex, "")
    }

    func testTitleStyleTokens() {
        let deck = DeckModel()
        XCTAssertEqual(deck.titleStyleTokens, [])
        deck.setTitleStyleTokens(["bold", "uppercase"])
        XCTAssertEqual(deck.titleStyleTokens, ["bold", "uppercase"])
        XCTAssertEqual(deck.titleStyle, "bold uppercase")
        deck.setTitleStyleTokens([])
        XCTAssertEqual(deck.titleStyle, "")
    }

    func testColorOverridesReadWriteAndClear() {
        let deck = DeckModel()
        XCTAssertTrue(deck.colorOverrides.isEmpty)
        XCTAssertEqual(deck.colorHex(for: "accent"), BundledTheme.tokyoNight.palette.accent)

        deck.setColorHex("#ff0000", for: "accent")
        XCTAssertEqual(deck.colorOverrides["accent"], "#ff0000")
        XCTAssertEqual(deck.colorHex(for: "accent"), "#ff0000")
        XCTAssertEqual(deck.palette.accent, "#ff0000")

        deck.clearColorOverrides()
        XCTAssertTrue(deck.colorOverrides.isEmpty)
        XCTAssertEqual(deck.colorHex(for: "accent"), BundledTheme.tokyoNight.palette.accent)
        XCTAssertEqual(deck.palette.accent, BundledTheme.tokyoNight.palette.accent)
    }

    func testFrontMatterEditsAreUndoableAndKeepSlides() {
        let deck = DeckModel(source: "---\ntitle: A\n---\n\n# One\n\n---\n\n# Two\n")
        deck.setShowPageNumber(true)
        deck.setTitlePosition(.bottom)
        XCTAssertTrue(deck.showPageNumber)
        XCTAssertEqual(deck.titlePosition, .bottom)
        XCTAssertEqual(deck.count, 2)
        XCTAssertTrue(deck.canUndo)
        deck.undo() // Reverts the title-position edit.
        XCTAssertEqual(deck.titlePosition, .top)
        XCTAssertTrue(deck.showPageNumber)
        deck.undo() // Reverts the show-page-number edit.
        XCTAssertFalse(deck.showPageNumber)
        XCTAssertEqual(deck.count, 2)
    }
}
