import XCTest
@testable import HypeCore

/// The deck-wide AI features end to end against `FakeURLProtocol` (no network):
/// rewriting every slide, drafting speaker notes, and applying either to a deck
/// as one undoable edit.
@MainActor
final class DeckAITests: XCTestCase {
    var generator: Generator!
    private let slides = ["# Welcome\n\nHello team", "# Plan\n\n- One\n- Two", "# Thanks"]

    override func setUpWithError() throws {
        FakeURLProtocol.reset(json: [:])
        var config = AIConfig()
        config.endpoint = "https://fake.test/v1/chat/completions"
        setenv("HYPE_AI_KEY", "test-key", 1)
        generator = Generator(config: config, session: FakeURLProtocol.session(), readKeychain: { nil })
    }
    override func tearDownWithError() throws { unsetenv("HYPE_AI_KEY") }

    private func reply(_ content: String) -> [String: Any] {
        ["choices": [["message": ["content": content], "finish_reason": "stop"]]]
    }
    private func messages() -> [[String: Any]] {
        FakeURLProtocol.recorded.first?.bodyJSON["messages"] as? [[String: Any]] ?? []
    }

    // MARK: Rewrite

    func testRewriteSendsEverySlideAndReturnsTheRewrittenDeck() async {
        FakeURLProtocol.reset(json: reply("=== SLIDE 1 ===\n# Bienvenidos\n=== SLIDE 2 ===\n# Plan\n\n- Uno\n- Dos\n=== SLIDE 3 ===\n# Gracias"))
        guard case .success(let result) = await generator.rewriteDeck(instruction: "Translate to Spanish", slides: slides)
        else { return XCTFail("expected success") }
        XCTAssertEqual(result.slides, ["# Bienvenidos", "# Plan\n\n- Uno\n- Dos", "# Gracias"])
        XCTAssertEqual(result.changed, 3)
        XCTAssertEqual(FakeURLProtocol.recorded.count, 1)
        let sent = messages().compactMap { $0["content"] as? String }
        XCTAssertTrue(sent.contains { $0.contains("Translate to Spanish") && $0.contains("=== SLIDE 3 ===") && $0.contains("- Two") })
        XCTAssertTrue(sent.contains { $0.contains("rewrite") || $0.contains("Rewrite") }, "the system prompt explains the task")
        XCTAssertFalse(generator.busy)
    }

    func testRewriteWithoutAnInstructionOrSlidesNeverCallsTheModel() async {
        guard case .failure = await generator.rewriteDeck(instruction: "  ", slides: slides) else { return XCTFail() }
        guard case .failure = await generator.rewriteDeck(instruction: "shorter", slides: []) else { return XCTFail() }
        XCTAssertTrue(FakeURLProtocol.recorded.isEmpty)
    }

    func testABadRewriteReplyFailsAndSaysNothingChanged() async {
        FakeURLProtocol.reset(json: reply("=== SLIDE 1 ===\n# Only one slide"))
        guard case .failure(let error) = await generator.rewriteDeck(instruction: "shorter", slides: slides)
        else { return XCTFail("expected failure") }
        XCTAssertTrue(error.message.contains("Nothing was changed"), error.message)
    }

    func testRewriteReportsEndpointErrors() async {
        FakeURLProtocol.reset(status: 500, json: ["error": ["message": "boom"]])
        guard case .failure(let error) = await generator.rewriteDeck(instruction: "shorter", slides: slides)
        else { return XCTFail("expected failure") }
        XCTAssertTrue(error.message.contains("500"), error.message)
    }

    // MARK: Speaker notes

    func testSuggestNotesReturnsNotesForTheRequestedSlidesOnly() async {
        FakeURLProtocol.reset(json: reply("=== SLIDE 1 ===\nWelcome everyone.\n=== SLIDE 3 ===\nThank the team."))
        guard case .success(let result) = await generator.suggestNotes(slides: slides, targets: [0, 2], guidance: "brief")
        else { return XCTFail("expected success") }
        XCTAssertEqual(result.notes, [0: "Welcome everyone.", 2: "Thank the team."])
        let sent = messages().compactMap { $0["content"] as? String }
        XCTAssertTrue(sent.contains { $0.contains("Write notes for slides: 1, 3") && $0.contains("Guidance: brief") })
    }

    func testSuggestNotesWithNothingToNoteNeverCallsTheModel() async {
        guard case .failure(let error) = await generator.suggestNotes(slides: slides, targets: [], guidance: "")
        else { return XCTFail("expected failure") }
        XCTAssertTrue(error.message.lowercased().contains("no slides"), error.message)
        XCTAssertTrue(FakeURLProtocol.recorded.isEmpty)
    }

    // MARK: Generating a picture from the editor

    private static let tinyPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    private func savedDeck() throws -> (DeckModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hype-pic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let deck = DeckModel(source: "# One\n\n---\n\n# Two\n")
        XCTAssertTrue(deck.savePath(dir.appendingPathComponent("presentation.md").path))
        return (deck, dir)
    }

    func testAddPictureSavesTheImageEditsTheSelectedSlideAndCanBeUndone() async throws {
        let (deck, dir) = try savedDeck()
        defer { try? FileManager.default.removeItem(at: dir) }
        deck.select(1)
        FakeURLProtocol.reset(json: ["choices": [["message": ["images": [["image_url": ["url": "data:image/png;base64,\(Self.tinyPNG)"]]]]]]])
        guard case .success(let message) = await generator.addPicture("A calm sunrise", to: deck) else { return XCTFail("expected success") }
        XCTAssertTrue(message.contains("Added a picture"), message)
        XCTAssertEqual(deck.slideText(at: 0), "# One", "other slides are untouched")
        XCTAssertTrue(deck.slideText(at: 1).contains("![right](a-calm-sunrise.png)"), deck.slideText(at: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("images/a-calm-sunrise.png").path))
        let request = FakeURLProtocol.recorded[0].bodyJSON
        XCTAssertTrue((request["messages"] as? [[String: Any]])?.contains { ($0["content"] as? String)?.contains("A calm sunrise") == true } ?? false)
        deck.undo()
        XCTAssertEqual(deck.slideText(at: 1), "# Two")
    }

    func testAddPictureNeedsASavedDeckAndADescription() async {
        let unsaved = DeckModel()
        guard case .failure(let error) = await generator.addPicture("A sunrise", to: unsaved) else { return XCTFail() }
        XCTAssertTrue(error.message.contains("Save the presentation first"), error.message)
        guard case .failure = await generator.addPicture("   ", to: unsaved) else { return XCTFail() }
        XCTAssertTrue(FakeURLProtocol.recorded.isEmpty)
    }

    func testAddPictureLeavesTheDeckAloneWhenTheModelReturnsNoPicture() async throws {
        let (deck, dir) = try savedDeck()
        defer { try? FileManager.default.removeItem(at: dir) }
        FakeURLProtocol.reset(json: ["choices": [["message": ["content": "sorry"]]]])
        guard case .failure = await generator.addPicture("A sunrise", to: deck) else { return XCTFail() }
        XCTAssertEqual(deck.slideText(at: 0), "# One")
        XCTAssertFalse(deck.dirty && deck.canUndo, "nothing was edited")
    }

    // MARK: Applying notes

    func testApplyingNotesAddsThemAndReportsWhatWasSkipped() {
        let withNote = ["# A\n\n<!-- mine -->", "# B", "# C"]
        let applied = applyingNotes([0: "new", 1: "note b"], to: withNote, replacing: false)
        XCTAssertEqual(applied.slides, ["# A\n\n<!-- mine -->", "# B\n\n<!-- note b -->", "# C"])
        XCTAssertEqual(applied.added, 1)
        XCTAssertEqual(applied.skipped, 1)
        let replaced = applyingNotes([0: "new"], to: withNote, replacing: true)
        XCTAssertEqual(replaced.slides[0], "# A\n\n<!-- new -->")
        XCTAssertEqual(replaced.added, 1)
    }

    // MARK: Applying to a deck

    func testReplacingSlidesIsOneUndoableEditThatKeepsTheFrontMatter() {
        let deck = DeckModel(source: "---\ntitle: \"T\"\ntheme: nord\n---\n\n# One\n\n---\n\n# Two\n")
        deck.select(1)
        deck.replaceSlides(["# Uno", "# Dos"])
        XCTAssertEqual(deck.slideText(at: 0), "# Uno")
        XCTAssertEqual(deck.slideText(at: 1), "# Dos")
        XCTAssertEqual(deck.themeName, "nord")
        XCTAssertEqual(deck.selected, 1)
        deck.undo()
        XCTAssertEqual(deck.slideText(at: 0), "# One")
        XCTAssertEqual(deck.slideText(at: 1), "# Two")
    }

    func testReplacingWithADifferentNumberOfSlidesClampsTheSelection() {
        let deck = DeckModel(source: "# One\n\n---\n\n# Two\n\n---\n\n# Three\n")
        deck.select(2)
        deck.replaceSlides(["# Only"])
        XCTAssertEqual(deck.count, 1)
        XCTAssertEqual(deck.selected, 0)
        deck.replaceSlides([])
        XCTAssertEqual(deck.count, 1, "an empty replacement is ignored")
    }
}
