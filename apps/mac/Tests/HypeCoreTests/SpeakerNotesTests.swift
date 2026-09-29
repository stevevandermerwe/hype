import XCTest
@testable import HypeCore

/// AI-suggested speaker notes: which slides need them, the request, the reply
/// parsing, and writing a note into a slide as a hidden `<!-- comment -->`.
final class SpeakerNotesTests: XCTestCase {
    private let slides = [
        "# Welcome\n\nHello team",
        "# Plan\n\n- One\n- Two\n\n<!-- Already has a note -->",
        "# Thanks",
    ]

    // MARK: Reading notes

    func testExistingNotesAreReadFromCommentsOutsideCode() {
        XCTAssertEqual(speakerNote(in: slides[1]), "Already has a note")
        XCTAssertNil(speakerNote(in: slides[0]))
        XCTAssertNil(speakerNote(in: "```\n<!-- not a note -->\n```"))
        XCTAssertEqual(speakerNote(in: "<!-- one -->\n# T\n<!--\ntwo\n-->"), "one\n\ntwo")
    }

    // MARK: Request

    func testTheRequestShowsTheWholeDeckAndNamesTheSlidesToNote() {
        let request = speakerNotesRequest(slides: slides, targets: [0, 2], guidance: " keep it to two sentences ")
        XCTAssertTrue(request.contains("=== SLIDE 1 ==="))
        XCTAssertTrue(request.contains("=== SLIDE 3 ==="))
        XCTAssertTrue(request.contains("Write notes for slides: 1, 3"))
        XCTAssertTrue(request.contains("keep it to two sentences"))
        XCTAssertFalse(request.contains("Already has a note"), "existing notes are not sent as slide text")
    }

    func testTheRequestWorksWithoutGuidance() {
        let request = speakerNotesRequest(slides: slides, targets: [1], guidance: "  ")
        XCTAssertTrue(request.contains("Write notes for slides: 2"))
        XCTAssertFalse(request.contains("Guidance:"))
    }

    // MARK: Reply

    func testTheReplyIsSplitIntoNotesBySlideNumber() {
        let reply = "=== SLIDE 1 ===\nOpen warmly. Thank everyone.\n\n=== SLIDE 3 ===\nClose with the next steps."
        let result = parseSpeakerNotesReply(reply, wanted: [0, 2])
        XCTAssertEqual(result.error, "")
        XCTAssertEqual(result.notes, [0: "Open warmly. Thank everyone.", 2: "Close with the next steps."])
    }

    func testNotesForSlidesNobodyAskedForAreIgnoredAndCommentMarkersAreStripped() {
        let reply = "=== SLIDE 1 ===\n<!-- Say hello --> ok\n=== SLIDE 2 ===\nnot wanted\n=== SLIDE 9 ===\nnot a slide"
        let result = parseSpeakerNotesReply(reply, wanted: [0])
        XCTAssertEqual(result.notes, [0: "Say hello ok"])
    }

    func testAReplyWithNoUsableNotesIsAnError() {
        XCTAssertFalse(parseSpeakerNotesReply("I can't help with that.", wanted: [0]).error.isEmpty)
        XCTAssertFalse(parseSpeakerNotesReply("=== SLIDE 2 ===\nx", wanted: [0]).error.isEmpty)
        XCTAssertFalse(parseSpeakerNotesReply("=== SLIDE 1 ===\n   \n", wanted: [0]).error.isEmpty)
    }

    func testAFencedReplyAndBlankLineRunsAreCleaned() {
        let reply = "```\n=== SLIDE 1 ===\nOne\n\n\n\nTwo\n```"
        XCTAssertEqual(parseSpeakerNotesReply(reply, wanted: [0]).notes[0], "One\n\nTwo")
    }

    // MARK: Writing a note into a slide

    func testANoteIsAppendedAsAHiddenComment() {
        XCTAssertEqual(settingNote("Greet everyone.", in: "# Welcome\n\nHello", replacing: false),
                       "# Welcome\n\nHello\n\n<!-- Greet everyone. -->")
    }

    func testMultiLineNotesUseABlockComment() {
        XCTAssertEqual(settingNote("Line one.\nLine two.", in: "# T", replacing: false),
                       "# T\n\n<!--\nLine one.\nLine two.\n-->")
    }

    func testASlideThatAlreadyHasANoteIsSkippedUnlessReplacing() {
        XCTAssertNil(settingNote("New", in: slides[1], replacing: false))
        let replaced = settingNote("New", in: slides[1], replacing: true)
        XCTAssertEqual(replaced, "# Plan\n\n- One\n- Two\n\n<!-- New -->")
    }

    func testANoteCannotBreakOutOfItsComment() {
        let result = settingNote("oops --> # injected", in: "# T", replacing: false) ?? ""
        XCTAssertEqual(result.components(separatedBy: "-->").count, 2, "exactly one closing marker")
        XCTAssertNil(parseMedia(result, base: "").text.range(of: "injected"))
    }

    func testAddingANoteNeverChangesWhatTheSlideShows() {
        let slide = "# Title\n\n- One\n\n![left](a.png)"
        let noted = settingNote("Talk track.", in: slide, replacing: false) ?? ""
        let shown = { (source: String) in parseMedia(source, base: "").text.trimmingCharacters(in: .whitespacesAndNewlines) }
        XCTAssertEqual(shown(noted), shown(slide)) // trailing blank lines don't render
        XCTAssertEqual(parseMedia(noted, base: "").file, "a.png")
    }
}
