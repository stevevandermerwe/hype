import XCTest
import HypeCore
@testable import HypeRender

/// `measureSlideText`: the "does this slide hold too much text?" check shared by
/// the editor's warning badges and `hype check`.
@MainActor
final class SlideTextMeasureTests: XCTestCase {
    private let manyBullets = (1...30).map { "- Point number \($0) with a few extra words" }.joined(separator: "\n")

    func testAnOrdinarySlideIsNotFlagged() throws {
        let report = try XCTUnwrap(measureSlideText(source: "# Title\n\n- One\n- Two\n- Three", baseDir: ""))
        XCTAssertFalse(report.isCramped)
        XCTAssertGreaterThanOrEqual(report.readability, 1)
    }

    func testAnOverfullSlideIsFlaggedWithHowSmallItGotToBe() throws {
        let report = try XCTUnwrap(measureSlideText(source: "# Way too much\n\n" + manyBullets, baseDir: ""))
        XCTAssertTrue(report.isCramped)
        XCTAssertLessThan(report.readability, 1)
        XCTAssertGreaterThan(report.readability, 0)
    }

    func testSlidesWithNoTextHaveNothingToMeasure() {
        XCTAssertNil(measureSlideText(source: "", baseDir: ""))
        XCTAssertNil(measureSlideText(source: "![](a.png)", baseDir: ""))
        XCTAssertNil(measureSlideText(source: "<!-- just a note -->", baseDir: ""))
    }

    func testTextBesideAPictureHasLessRoomAndCommentsDoNotCount() throws {
        let text = "# Title\n\n- A fairly long first bullet point in this slide\n- A fairly long second bullet point in this slide\n- A third one that is also fairly long"
        let full = try XCTUnwrap(measureSlideText(source: text, baseDir: ""))
        let split = try XCTUnwrap(measureSlideText(source: text + "\n\n![left](a.png)", baseDir: ""))
        XCTAssertEqual(full.wrappedLines, 0)
        XCTAssertGreaterThan(split.wrappedLines, 0, "half the width, so the long bullets wrap")

        let withNote = try XCTUnwrap(measureSlideText(source: text + "\n<!-- \(manyBullets) -->", baseDir: ""))
        XCTAssertEqual(withNote.fittedBodySize, full.fittedBodySize, accuracy: 0.01)
    }

    func testEveryBuiltInSlideTemplateStartsOutReadable() throws {
        for template in SlideTemplate.allCases {
            let source = template.text(picture: template.needsPicture ? "photo.png" : nil) ?? ""
            let report = try XCTUnwrap(measureSlideText(source: source, baseDir: ""), "\(template)")
            XCTAssertFalse(report.isCramped, "\(template) should not start out with too much text")
        }
    }

    func testTheDecksTextScaleDoesNotHideTheWarning() throws {
        let report = try XCTUnwrap(measureSlideText(source: "# T\n\n" + manyBullets, baseDir: "", textScale: 0.6))
        XCTAssertTrue(report.isCramped)
    }
}
