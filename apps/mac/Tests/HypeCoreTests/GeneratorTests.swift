import XCTest
@testable import HypeCore

/// Exercises `Generator` end-to-end against `FakeURLProtocol` — no real
/// network, no API key — mirroring the Qt app's `tests/test_generate.py`.
@MainActor
final class GeneratorTests: XCTestCase {
    var tempDir: URL!
    var generator: Generator!

    override func setUpWithError() throws {
        FakeURLProtocol.reset(json: [:]) // Clears state left over by a previous test; each test sets its own reply.
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        var config = AIConfig()
        config.endpoint = "https://fake.test/v1/chat/completions"
        config.imageEndpoint = "https://fake.test/v1/chat/completions"
        setenv("HYPE_AI_KEY", "test-key", 1)
        generator = Generator(config: config, session: FakeURLProtocol.session())
    }
    override func tearDownWithError() throws {
        unsetenv("HYPE_AI_KEY")
        try? FileManager.default.removeItem(at: tempDir)
    }

    private static let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1600 900\"><rect width=\"1600\" height=\"900\" fill=\"#123456\"/></svg>"
    private static let deckReply = """
    === FILE: presentation.md ===
    ---
    title: "Small Teams Ship Faster"
    ---

    # Small teams ship faster

    ---

    ![span](hero.svg)

    # Why

    - Less coordination
    - Faster decisions
    === FILE: images/hero.svg ===
    ```svg
    \(svg)
    ```
    === FILE: ../evil.md ===
    should never be written
    === FILE: images/notes.txt ===
    not an svg
    """

    func testGenerateWritesAFolderWithSlidesAndImages() async throws {
        FakeURLProtocol.reset(json: ["choices": [["message": ["content": Self.deckReply], "finish_reason": "stop"]]])
        let target = tempDir.appendingPathComponent("talk").path
        let result = await generator.generate(prompt: "a talk on small teams", theme: "nord", directory: target, mode: nil)
        guard case .success(let written) = result else { return XCTFail("expected success") }
        XCTAssertEqual(written.path, target + "/presentation.md")
        XCTAssertEqual(written.warnings, [])
        let text = try String(contentsOfFile: written.path, encoding: .utf8)
        XCTAssertTrue(text.contains("title: \"Small Teams Ship Faster\""))
        XCTAssertTrue(text.contains("theme: \"nord\"")) // Chosen theme applied. Unlike the Qt app, colors are
        // not baked in as color_* overrides: bundled themes are a fixed set resolved by name at render time,
        // not discovered from disk paths, so there is no portability need for baking them.
        let svgText = try String(contentsOfFile: target + "/images/hero.svg", encoding: .utf8)
        XCTAssertEqual(svgText.trimmingCharacters(in: .whitespacesAndNewlines), Self.svg)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("evil.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target + "/images/notes.txt"))

        let request = FakeURLProtocol.recorded[0]
        XCTAssertEqual(request.request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.bodyJSON["model"] as? String, AIConfig.defaultModel)
        let messages = request.bodyJSON["messages"] as? [[String: String]]
        XCTAssertEqual(messages?[1]["content"], "a talk on small teams")
        XCTAssertTrue(messages?[0]["content"]?.contains("hype check") ?? false)
        XCTAssertFalse(messages?[0]["content"]?.contains("{{format}}") ?? true)
    }

    func testGenerateRefusesANonEmptyFolder() async {
        try? FileManager.default.createDirectory(atPath: tempDir.appendingPathComponent("taken").path, withIntermediateDirectories: true)
        try? "mine".write(toFile: tempDir.appendingPathComponent("taken/keep.txt").path, atomically: true, encoding: .utf8)
        FakeURLProtocol.reset(json: ["choices": [["message": ["content": Self.deckReply]]]])
        let result = await generator.generate(prompt: "x", theme: nil, directory: tempDir.appendingPathComponent("taken").path, mode: nil)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertTrue(error.message.contains("not empty"))
        XCTAssertEqual(try? String(contentsOfFile: tempDir.appendingPathComponent("taken/keep.txt").path, encoding: .utf8), "mine")
    }

    func testGenerateNeedsAKeyForARemoteEndpoint() async {
        unsetenv("HYPE_AI_KEY")
        var config = AIConfig()
        config.endpoint = "https://example.invalid/v1/chat/completions"
        let generator = Generator(config: config, session: FakeURLProtocol.session())
        let result = await generator.generate(prompt: "x", theme: nil, directory: nil, mode: nil)
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertTrue(error.message.contains("OPENROUTER_API_KEY"))
        XCTAssertEqual(FakeURLProtocol.recorded.count, 0)
    }

    func testGenerateReportsEndpointErrorsAndBadReplies() async {
        FakeURLProtocol.reset(status: 401, json: ["error": ["message": "Invalid API key"]])
        var result = await generator.generate(prompt: "x", theme: nil, directory: tempDir.appendingPathComponent("a").path, mode: nil)
        if case .failure(let error) = result { XCTAssertTrue(error.message.contains("HTTP 401: Invalid API key")) } else { XCTFail() }

        FakeURLProtocol.reset(json: ["choices": [["message": ["content": "Sure! Here is a talk."], "finish_reason": "stop"]]])
        result = await generator.generate(prompt: "x", theme: nil, directory: tempDir.appendingPathComponent("b").path, mode: nil)
        if case .failure(let error) = result { XCTAssertTrue(error.message.contains("presentation.md")) } else { XCTFail() }

        FakeURLProtocol.reset(json: ["choices": [["message": ["content": Self.deckReply], "finish_reason": "length"]]])
        result = await generator.generate(prompt: "x", theme: nil, directory: tempDir.appendingPathComponent("c").path, mode: nil)
        if case .failure(let error) = result { XCTAssertTrue(error.message.contains("ran out of output tokens")) } else { XCTFail() }
    }

    func testGenerateWarnsAboutImagesTheModelForgotToWrite() async {
        FakeURLProtocol.reset(json: ["choices": [["message": ["content": "---\ntitle: \"T\"\n---\n\n# One\n\n---\n\n![](missing.svg)\n"],
                                                  "finish_reason": "stop"]]])
        let target = tempDir.appendingPathComponent("t").path
        let result = await generator.generate(prompt: "x", theme: nil, directory: target, mode: nil)
        guard case .success(let written) = result else { return XCTFail("expected success") }
        XCTAssertEqual(written.warnings.count, 1)
        XCTAssertTrue(written.warnings[0].contains("Slide 2"))
    }

    func testMindMapModeAddsTheOutlineRules() async {
        FakeURLProtocol.reset(json: ["choices": [["message": ["content": Self.deckReply], "finish_reason": "stop"]]])
        _ = await generator.generate(prompt: "Talk\n  Why\n    Speed\n", theme: nil,
                                     directory: tempDir.appendingPathComponent("m").path, mode: "mindmap")
        let system = FakeURLProtocol.recorded[0].bodyJSON["messages"] as? [[String: String]]
        XCTAssertTrue(system?[0]["content"]?.contains("The brief is a mind map") ?? false)
        XCTAssertTrue(system?[0]["content"]?.contains("OPML") ?? false)
    }

    // MARK: - editSlide

    private static let deck = "---\ntitle: \"Deck\"\n---\n\n# Alpha\n\n---\n\n# Beta\n\n- one\n- two\n\n---\n\n# Gamma\n"

    func testTextEditRewritesTheSlideAndSendsTheOutline() async {
        FakeURLProtocol.reset(json: ["choices": [["message": ["content": "# Punchy\n\n- Fast\n- Simple"], "finish_reason": "stop"]]])
        let model = DeckModel(source: Self.deck)
        model.select(1)
        let outline = model.slideOutline()
        let result = await generator.editSlide(instruction: "make it punchier", kind: "text", slide: model.slideText(at: 1),
                                               outline: outline, index: 1, baseDir: tempDir.path)
        guard case .success(let outcome) = result else { return XCTFail("expected success") }
        XCTAssertEqual(outcome.slide, "# Punchy\n\n- Fast\n- Simple")
        XCTAssertEqual(outcome.summary, "Rewrote the slide")
        let user = FakeURLProtocol.recorded[0].bodyJSON["messages"] as? [[String: String]]
        XCTAssertTrue(user?[1]["content"]?.contains("2. Beta   <- the slide to change") ?? false)
        XCTAssertTrue(user?[1]["content"]?.contains("1. Alpha") ?? false)
    }

    func testAReplyWithSeveralSlidesIsRefused() async {
        FakeURLProtocol.reset(json: ["choices": [["message": ["content": "# One\n\n---\n\n# Two"], "finish_reason": "stop"]]])
        let result = await generator.editSlide(instruction: "x", kind: "text", slide: "# Beta", outline: "1. Beta", index: 0, baseDir: "")
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertTrue(error.message.contains("more than one slide"))
    }

    func testDiagramWritesAnSVGAndNeverOverwritesOne() async {
        let reply = "=== FILE: slide.md ===\n# Flow\n\n![right](flow.svg)\n=== FILE: images/flow.svg ===\n\(Self.svg)\n"
        FakeURLProtocol.reset(json: ["choices": [["message": ["content": reply], "finish_reason": "stop"]]])
        var result = await generator.editSlide(instruction: "add a diagram", kind: "diagram", slide: "# Flow",
                                               outline: "1. Flow", index: 0, baseDir: tempDir.path)
        guard case .success(let first) = result else { return XCTFail("expected success") }
        XCTAssertEqual(first.slide, "# Flow\n\n![right](flow.svg)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("images/flow.svg").path))

        FakeURLProtocol.reset(json: ["choices": [["message": ["content": reply], "finish_reason": "stop"]]])
        result = await generator.editSlide(instruction: "again", kind: "diagram", slide: "# Flow", outline: "1. Flow",
                                           index: 0, baseDir: tempDir.path)
        guard case .success(let second) = result else { return XCTFail("expected success") }
        XCTAssertTrue(second.slide.contains("flow-2.svg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("images/flow-2.svg").path))
    }

    func testImageAddsAPictureBesideTheText() async {
        let png = Self.tinyPNG()
        let dataURL = "data:image/png;base64,\(png.base64EncodedString())"
        FakeURLProtocol.reset(json: ["choices": [["message": ["images": [["image_url": ["url": dataURL]]]]]]])
        let result = await generator.editSlide(instruction: "A calm sunrise", kind: "image", slide: "# Beta\n\n- one\n- two",
                                               outline: "1. Beta", index: 0, baseDir: tempDir.path)
        guard case .success(let outcome) = result else { return XCTFail("expected success") }
        XCTAssertEqual(outcome.slide, "# Beta\n\n- one\n- two\n![right](a-calm-sunrise.png)")
        let request = FakeURLProtocol.recorded[0].bodyJSON
        XCTAssertEqual(request["model"] as? String, AIConfig.defaultImageModel)
        XCTAssertNotNil(request["modalities"])
    }

    func testArgumentErrorsLeaveNoRequestSent() async {
        var result = await generator.editSlide(instruction: " ", kind: "text", slide: "# A", outline: "1. A", index: 0, baseDir: "")
        if case .failure(let error) = result { XCTAssertTrue(error.message.contains("Say what")) } else { XCTFail() }
        result = await generator.editSlide(instruction: "x", kind: "diagram", slide: "# A", outline: "1. A", index: 0, baseDir: "")
        if case .failure(let error) = result { XCTAssertTrue(error.message.contains("Save the presentation first")) } else { XCTFail() }
        XCTAssertEqual(FakeURLProtocol.recorded.count, 0)
    }

    private static func tinyPNG() -> Data {
        // A minimal valid 1x1 PNG, hand-encoded.
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        return Data(base64Encoded: base64)!
    }
}
