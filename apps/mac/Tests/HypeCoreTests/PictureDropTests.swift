import XCTest
@testable import HypeCore

/// Dropping picture or video files onto a slide: they are copied into the deck's
/// folders and added to the slide, as a single undoable edit.
@MainActor
final class PictureDropTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hype-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent("incoming").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: url)
        return url
    }
    private func savedDeck(_ source: String = "# One\n\n---\n\n# Two\n\n- point\n") -> DeckModel {
        try? FileManager.default.createDirectory(at: directory.appendingPathComponent("deck"), withIntermediateDirectories: true)
        let deck = DeckModel(source: source)
        XCTAssertTrue(deck.savePath(directory.appendingPathComponent("deck/presentation.md").path))
        return deck
    }
    private var images: URL { directory.appendingPathComponent("deck/images") }

    func testADroppedPictureIsCopiedAndAddedToTheTargetSlide() throws {
        let deck = savedDeck()
        let result = dropPictures([try makeFile("photo.png")], onto: 1, in: deck)
        guard case .success(let message) = result else { return XCTFail("expected success") }
        XCTAssertTrue(message.contains("photo.png"), message)
        XCTAssertEqual(deck.slideText(at: 1), "# Two\n\n- point\n\n![](photo.png)")
        XCTAssertEqual(deck.slideText(at: 0), "# One")
        XCTAssertTrue(FileManager.default.fileExists(atPath: images.appendingPathComponent("photo.png").path))
        XCTAssertEqual(deck.selected, 1)
    }

    func testDroppingOntoASlideThatHasAPictureSwapsItKeepingItsLayout() throws {
        let deck = savedDeck("# One\n\n![left](old.png)\n")
        guard case .success = dropPictures([try makeFile("new.jpg")], onto: 0, in: deck) else { return XCTFail() }
        XCTAssertEqual(deck.slideText(at: 0), "# One\n\n![left](new.jpg)")
    }

    func testVideosGoToTheVideosFolder() throws {
        let deck = savedDeck()
        guard case .success = dropPictures([try makeFile("clip.mp4")], onto: 0, in: deck) else { return XCTFail() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("deck/videos/clip.mp4").path))
        XCTAssertTrue(deck.slideText(at: 0).contains("![](clip.mp4)"))
    }

    func testSeveralFilesFillTheTargetSlideThenBecomeNewSlidesAfterIt() throws {
        let deck = savedDeck()
        let files = [try makeFile("a.png"), try makeFile("b.png"), try makeFile("c.png")]
        guard case .success(let message) = dropPictures(files, onto: 0, in: deck) else { return XCTFail() }
        XCTAssertEqual(deck.count, 4)
        XCTAssertEqual(deck.slideTexts, ["# One\n\n![](a.png)", "![](b.png)", "![](c.png)", "# Two\n\n- point"])
        XCTAssertTrue(message.contains("2 more"), message)
        deck.undo()
        XCTAssertEqual(deck.count, 2, "one undo takes back the whole drop")
        XCTAssertEqual(deck.slideText(at: 0), "# One")
    }

    func testFilesThatAreNotPicturesAreIgnoredAndAllUnsupportedIsAnError() throws {
        let deck = savedDeck()
        guard case .success = dropPictures([try makeFile("notes.txt"), try makeFile("ok.png")], onto: 0, in: deck) else { return XCTFail() }
        XCTAssertEqual(deck.slideText(at: 0), "# One\n\n![](ok.png)")
        let before = deck.slideTexts
        guard case .failure(let error) = dropPictures([try makeFile("notes.txt")], onto: 0, in: deck) else { return XCTFail() }
        XCTAssertTrue(error.localizedDescription.contains("notes.txt"))
        XCTAssertEqual(deck.slideTexts, before)
    }

    func testAnUnsavedDeckOrABadTargetChangesNothing() throws {
        let unsaved = DeckModel(source: "# One\n")
        guard case .failure(let error) = dropPictures([try makeFile("a.png")], onto: 0, in: unsaved) else { return XCTFail() }
        XCTAssertEqual(error, .needsSavedDeck)
        let deck = savedDeck()
        guard case .failure = dropPictures([try makeFile("b.png")], onto: 9, in: deck) else { return XCTFail() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: images.appendingPathComponent("b.png").path), "nothing is copied for a bad target")
    }

    func testTheSameFileDroppedTwiceIsKeptAsTwoFilesWithoutOverwriting() throws {
        let deck = savedDeck()
        let file = try makeFile("photo.png")
        _ = dropPictures([file], onto: 0, in: deck)
        _ = dropPictures([file], onto: 1, in: deck)
        XCTAssertTrue(deck.slideText(at: 1).contains("photo-1.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: images.appendingPathComponent("photo.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: images.appendingPathComponent("photo-1.png").path))
    }

    func testMediaFileFilteringIsCaseInsensitive() {
        XCTAssertEqual(mediaFiles(in: [URL(fileURLWithPath: "/x/A.PNG"), URL(fileURLWithPath: "/x/b.txt"),
                                       URL(fileURLWithPath: "/x/c.MOV")]).map(\.lastPathComponent), ["A.PNG", "c.MOV"])
    }
}
