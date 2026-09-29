import XCTest
@testable import HypeCore

/// Mirrors a slice of the Qt app's `tests/tests.cpp` for the ported logic:
/// front matter, slide splitting (fence-aware), scalar read/write, media
/// directive parsing, and the deck model's editing operations.
final class HypeCoreTests: XCTestCase {
    func testParseDeckSplitsFrontMatterAndSlides() {
        let source = "---\ntitle: \"A\"\n---\n\n# One\n\n---\n\n# Two\n"
        let parsed = parseDeck(source)
        XCTAssertTrue(parsed.error.isEmpty)
        XCTAssertEqual(parsed.slides.count, 2)
        XCTAssertTrue(parsed.slides[0].source.contains("# One"))
        XCTAssertTrue(parsed.slides[1].source.contains("# Two"))
    }

    func testASeparatorInsideAFencedCodeBlockDoesNotSplit() {
        let source = "# Code\n\n```ruby\na = 1\n---\nb = 2\n```\n"
        let parsed = parseDeck(source)
        XCTAssertTrue(parsed.error.isEmpty)
        XCTAssertEqual(parsed.slides.count, 1)
    }

    func testUnclosedFrontMatterAndFenceAreReportedAsErrors() {
        XCTAssertEqual(parseDeck("---\ntitle: x\n").error, "Front matter needs a closing ---")
        XCTAssertEqual(parseDeck("# One\n\n```\ncode\n").error, "Unclosed code fence")
    }

    func testScalarReadsQuotedSingleQuotedAndBareValues() {
        let header = "---\ntitle: \"A \\\"big\\\" idea\"\ntheme: tokyo-night\nfont: 'Steve''s Font'\n---\n"
        XCTAssertEqual(scalar(header, "title"), "A \"big\" idea")
        XCTAssertEqual(scalar(header, "theme"), "tokyo-night")
        XCTAssertEqual(scalar(header, "font"), "Steve's Font")
        XCTAssertEqual(scalar(header, "missing", "fallback"), "fallback")
    }

    func testSetScalarReplacesOrAppendsAndRoundTrips() {
        let header = "---\ntitle: Untitled\n---\n"
        let updated = setScalar(header, "title", "A \"big\" idea")
        XCTAssertTrue(updated.contains("title: \"A \\\"big\\\" idea\""))
        XCTAssertEqual(scalar(updated, "title"), "A \"big\" idea")
        let withTheme = setScalar(updated, "theme", "nord")
        XCTAssertTrue(withTheme.contains("theme: \"nord\""))
        XCTAssertTrue(withTheme.hasSuffix("---\n"))
    }

    func testMediaDefaultsAndDirectives() {
        var media = parseMedia("![](city.png)\n\n# Hello", base: "/tmp/deck")
        XCTAssertEqual(media.path, "/tmp/deck/images/city.png")
        XCTAssertTrue(media.span) // A headline defaults a fitted image to span.
        XCTAssertEqual(media.overlay, 0.25)

        media = parseMedia("![fit](images/chart.png)\n\n# Chart", base: "/tmp/deck")
        XCTAssertFalse(media.span)

        media = parseMedia("![span loop muted poster=\"demo still.jpg\"](demo.MP4)", base: "/tmp/deck")
        XCTAssertTrue(media.video && media.span && media.loop && media.muted)
        XCTAssertEqual(media.poster, "/tmp/deck/images/demo still.jpg")

        media = parseMedia("![autoplay=false](demo.mp4)", base: "/tmp/deck")
        XCTAssertFalse(media.autoplay)

        XCTAssertFalse(parseMedia("![span fit](photo.jpg)", base: "/tmp/deck").error.isEmpty)

        media = parseMedia("![left](photo.jpg)\n\n# Text", base: "/tmp/deck")
        XCTAssertTrue(media.error.isEmpty)
        XCTAssertEqual(media.side, "left")
        XCTAssertFalse(media.span) // Split layout, not a spanning background.
        XCTAssertEqual(media.overlay, 0)

        XCTAssertTrue(parseMedia("![alt=\"left\"](photo.jpg)", base: "/tmp/deck").side.isEmpty)
    }

    func testSplitLayoutPutsTheTextInTheOppositeHalf() {
        let media = parseMedia("![right](photo.jpg)\n\n# Text", base: "/tmp/deck")
        XCTAssertEqual(mediaRect(media), CGRect(x: 980, y: 60, width: 880, height: 960))
        let spanned = parseMedia("![right span](photo.jpg)", base: "/tmp/deck")
        XCTAssertEqual(mediaRect(spanned), CGRect(x: 960, y: 0, width: 960, height: 1080))
    }

    func testDeckModelEditingIsStringPreservingAndUndoable() {
        let deck = DeckModel(source: "---\ntitle: Untitled\n---\n\n# One\n\n---\n\n# Two\n")
        deck.select(1)
        deck.editSlide("# Two changed")
        XCTAssertTrue(deck.source.contains("# Two changed"))
        XCTAssertTrue(deck.source.contains("# One")) // The other slide is untouched.
        XCTAssertEqual(deck.count, 2)
        XCTAssertTrue(deck.canUndo)
        deck.undo()
        XCTAssertTrue(deck.source.contains("# Two\n"))
        XCTAssertFalse(deck.canUndo)
        XCTAssertTrue(deck.canRedo)

        deck.select(0)
        deck.duplicateSlide()
        XCTAssertEqual(deck.count, 3)
        deck.deleteSlide()
        XCTAssertEqual(deck.count, 2)
    }

    func testChooseThemeUpdatesFrontMatterAndPalette() {
        let deck = DeckModel()
        XCTAssertEqual(deck.themeName, "tokyo-night")
        deck.chooseTheme("nord")
        XCTAssertEqual(deck.themeName, "nord")
        XCTAssertEqual(deck.palette.accent, "#88c0d0")
    }
}
