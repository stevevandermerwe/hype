import XCTest
@testable import HypeCore

/// Whole-deck AI rewrite: what is sent, and how the reply is checked before it
/// is allowed to replace the deck's slides.
final class DeckRewriteTests: XCTestCase {
    private let original = [
        "# Welcome\n\nHello team",
        "# Plan\n\n- One\n- Two\n\n![left](chart.png)\n\n<!-- say hi -->",
        "# Thanks",
    ]

    func testTheRequestListsEverySlideInOrderWithTheInstruction() {
        let request = deckRewriteRequest(instruction: "  Translate to Spanish ", slides: original)
        XCTAssertTrue(request.contains("Request: Translate to Spanish"))
        XCTAssertTrue(request.contains("3 slides"))
        let positions = (1...3).compactMap { request.range(of: "=== SLIDE \($0) ===")?.lowerBound }
        XCTAssertEqual(positions.count, 3)
        XCTAssertEqual(positions, positions.sorted())
        XCTAssertTrue(request.contains("- One"))
    }

    func testAWellFormedReplyReplacesEverySlide() throws {
        let reply = """
        === SLIDE 1 ===
        # Bienvenidos

        Hola equipo
        === SLIDE 2 ===
        # Plan

        - Uno
        - Dos

        ![left](chart.png)

        <!-- saluda -->
        === SLIDE 3 ===
        # Gracias
        """
        let result = parseDeckRewriteReply(reply, original: original)
        XCTAssertEqual(result.error, "")
        XCTAssertEqual(result.slides.count, 3)
        XCTAssertEqual(result.slides[0], "# Bienvenidos\n\nHola equipo")
        XCTAssertEqual(result.slides[2], "# Gracias")
        XCTAssertEqual(result.changed, 3)
    }

    func testAWrappingCodeFenceAroundTheWholeReplyIsIgnored() {
        let reply = "```\n=== SLIDE 1 ===\n# A\n=== SLIDE 2 ===\n# B\n=== SLIDE 3 ===\n# C\n```"
        // (Slide 2 had a picture the reply left out, so it is put back.)
        XCTAssertEqual(parseDeckRewriteReply(reply, original: original).slides, ["# A", "# B\n\n![left](chart.png)", "# C"])
    }

    func testTheWrongNumberOfSlidesIsRefusedAndChangesNothing() {
        let reply = "=== SLIDE 1 ===\n# A\n=== SLIDE 2 ===\n# B"
        let result = parseDeckRewriteReply(reply, original: original)
        XCTAssertTrue(result.slides.isEmpty)
        XCTAssertTrue(result.error.contains("2 slides") && result.error.contains("3"), result.error)
    }

    func testOutOfOrderDuplicateOrEmptySlidesAreRefused() {
        XCTAssertFalse(parseDeckRewriteReply("=== SLIDE 2 ===\n# A\n=== SLIDE 1 ===\n# B\n=== SLIDE 3 ===\n# C", original: original).error.isEmpty)
        XCTAssertFalse(parseDeckRewriteReply("=== SLIDE 1 ===\n# A\n=== SLIDE 1 ===\n# B\n=== SLIDE 3 ===\n# C", original: original).error.isEmpty)
        XCTAssertFalse(parseDeckRewriteReply("=== SLIDE 1 ===\n# A\n=== SLIDE 2 ===\n\n=== SLIDE 3 ===\n# C", original: original).error.isEmpty)
        XCTAssertFalse(parseDeckRewriteReply("Sorry, I can't do that.", original: original).error.isEmpty)
    }

    func testASlideWithItsOwnSeparatorIsRefused() {
        let reply = "=== SLIDE 1 ===\n# A\n\n---\n\n# Extra\n=== SLIDE 2 ===\n# B\n=== SLIDE 3 ===\n# C"
        XCTAssertTrue(parseDeckRewriteReply(reply, original: original).error.contains("more than one slide"))
    }

    func testCodeFencesInsideASlideAreKeptIntact() {
        let reply = "=== SLIDE 1 ===\n# A\n\n```swift\nlet x = 1\n---\n```\n=== SLIDE 2 ===\n# B\n=== SLIDE 3 ===\n# C"
        let result = parseDeckRewriteReply(reply, original: original)
        XCTAssertEqual(result.error, "")
        XCTAssertTrue(result.slides[0].contains("let x = 1\n---\n```"))
    }

    // MARK: Pictures are never invented or lost

    func testAPictureTheModelDroppedIsPutBack() {
        let reply = "=== SLIDE 1 ===\n# A\n=== SLIDE 2 ===\n# Plan\n\n- Uno\n=== SLIDE 3 ===\n# C"
        let result = parseDeckRewriteReply(reply, original: original)
        XCTAssertEqual(result.slides[1], "# Plan\n\n- Uno\n\n![left](chart.png)")
    }

    func testAChangedPictureFileIsRestoredKeepingTheNewDirectives() {
        let reply = "=== SLIDE 1 ===\n# A\n=== SLIDE 2 ===\n# Plan\n\n![right](other.png)\n=== SLIDE 3 ===\n# C"
        let result = parseDeckRewriteReply(reply, original: original)
        XCTAssertTrue(result.slides[1].contains("![right](chart.png)"), result.slides[1])
        XCTAssertFalse(result.slides[1].contains("other.png"))
    }

    func testAnInventedPictureIsRemoved() {
        let reply = "=== SLIDE 1 ===\n# A\n\n![](made-up.png)\n=== SLIDE 2 ===\n# B\n=== SLIDE 3 ===\n# C"
        let result = parseDeckRewriteReply(reply, original: original)
        XCTAssertEqual(result.slides[0], "# A")
    }

    func testUnchangedSlidesAreNotCountedAsChanged() {
        let reply = "=== SLIDE 1 ===\n# Welcome\n\nHello team\n=== SLIDE 2 ===\n# Plan\n\n- One\n- Two\n\n![left](chart.png)\n\n<!-- say hi -->\n=== SLIDE 3 ===\n# Danke"
        let result = parseDeckRewriteReply(reply, original: original)
        XCTAssertEqual(result.changed, 1)
    }
}
