import XCTest
@testable import HypeCore

/// The image/video assist buttons: layout directives inside `![...](file)`,
/// swapping the file, and importing a picture into the deck's folders.
final class ImageLayoutTests: XCTestCase {
    func testLeftAndRightToggleAndReplaceEachOther() {
        XCTAssertEqual(applyImageLayout(.left, to: "# T\n\n![](a.png)"), "# T\n\n![left](a.png)")
        XCTAssertEqual(applyImageLayout(.left, to: "![left](a.png)"), "![](a.png)")
        XCTAssertEqual(applyImageLayout(.right, to: "![left](a.png)"), "![right](a.png)")
    }

    func testFitAndSpanReplaceEachOtherAndCombineWithASide() {
        XCTAssertEqual(applyImageLayout(.span, to: "![fit](a.png)"), "![span](a.png)")
        XCTAssertEqual(applyImageLayout(.span, to: "![left](a.png)"), "![left span](a.png)")
    }

    func testBackgroundsReplaceEachOtherAndToggleOff() {
        XCTAssertEqual(applyImageLayout(.background(.blur), to: "![fit](a.png)"), "![fit background=blur](a.png)")
        XCTAssertEqual(applyImageLayout(.background(.auto), to: "![fit background=blur](a.png)"), "![fit background=auto](a.png)")
        XCTAssertEqual(applyImageLayout(.background(.auto), to: "![fit background=auto](a.png)"), "![fit](a.png)")
    }

    func testOverlayTogglesADarkeningLayer() {
        XCTAssertEqual(applyImageLayout(.darken, to: "![](a.png)"), "![overlay=0.5](a.png)")
        XCTAssertEqual(applyImageLayout(.darken, to: "![overlay=0.5](a.png)"), "![](a.png)")
    }

    func testVideoOptionsToggle() {
        XCTAssertEqual(applyImageLayout(.loop, to: "![](d.mp4)"), "![loop](d.mp4)")
        XCTAssertEqual(applyImageLayout(.muted, to: "![loop](d.mp4)"), "![loop muted](d.mp4)")
        XCTAssertEqual(applyImageLayout(.loop, to: "![loop muted](d.mp4)"), "![muted](d.mp4)")
    }

    func testAltTextIsKeptAndOnlyTheFirstImageOutsideCodeIsChanged() {
        XCTAssertEqual(applyImageLayout(.right, to: "![A chart](a.png)"), "![A chart right](a.png)")
        XCTAssertEqual(applyImageLayout(.left, to: "```\n![](in-code.png)\n```\n![](real.png)"),
                       "```\n![](in-code.png)\n```\n![left](real.png)")
    }

    func testSlidesWithoutAnImageReturnNil() {
        XCTAssertNil(applyImageLayout(.left, to: "# Just text"))
        XCTAssertNil(applyImageLayout(.left, to: "```\n![](a.png)\n```"))
    }

    func testSetImageFileReplacesTheFileKeepingDirectives() {
        XCTAssertEqual(setImageFile("b.png", in: "![left](a.png)\n\ntext"), "![left](b.png)\n\ntext")
    }

    func testSetImageFileAppendsAReferenceWhenThereIsNone() {
        XCTAssertEqual(setImageFile("b.png", in: "# Title\n"), "# Title\n\n![](b.png)\n")
        XCTAssertEqual(setImageFile("b.png", in: ""), "![](b.png)\n")
    }

    func testFilenamesWithSpacesUseAngleBrackets() {
        XCTAssertEqual(setImageFile("my pic.png", in: "# T"), "# T\n\n![](<my pic.png>)\n")
    }

    // MARK: Importing

    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hype-media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    func testImportCopiesImagesAndVideosIntoTheirFolders() throws {
        let deck = directory.appendingPathComponent("deck").path
        XCTAssertEqual(try importMedia(from: makeFile("photo.png"), into: deck), "photo.png")
        XCTAssertEqual(try importMedia(from: makeFile("clip.mp4"), into: deck), "clip.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: deck + "/images/photo.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: deck + "/videos/clip.mp4"))
    }

    func testImportNeverOverwritesAnExistingFile() throws {
        let deck = directory.appendingPathComponent("deck").path
        let file = try makeFile("photo.png")
        XCTAssertEqual(try importMedia(from: file, into: deck), "photo.png")
        XCTAssertEqual(try importMedia(from: file, into: deck), "photo-1.png")
        XCTAssertEqual(try importMedia(from: file, into: deck), "photo-2.png")
    }

    func testImportNeedsASavedDeckAndASupportedFile() throws {
        XCTAssertThrowsError(try importMedia(from: makeFile("photo.png"), into: ""))
        XCTAssertThrowsError(try importMedia(from: makeFile("notes.txt"), into: directory.path))
    }
}
