import XCTest
@testable import HypeCore

/// Ready-made slide layouts you can insert from a menu.
@MainActor
final class SlideTemplatesTests: XCTestCase {
    private func text(_ template: SlideTemplate) -> String {
        template.text(picture: template.needsPicture ? "photo.png" : nil) ?? ""
    }

    func testEveryTemplateIsExactlyOneNonEmptySlide() {
        for template in SlideTemplate.allCases {
            let source = text(template)
            XCTAssertFalse(source.isEmpty, "\(template)")
            XCTAssertFalse(hasSlideSeparator(source), "\(template) must not contain a slide separator")
            XCTAssertEqual(parseDeck(source).slides.count, 1, "\(template)")
            XCTAssertTrue(parseDeck(source).error.isEmpty, "\(template)")
        }
    }

    func testTemplatesHaveDistinctNamesAndIcons() {
        let names = SlideTemplate.allCases.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(SlideTemplate.allCases.allSatisfy { !$0.icon.isEmpty })
    }

    func testTheLayoutsYouAskedForAreThere() {
        let names = Set(SlideTemplate.allCases.map(\.name))
        for expected in ["Title", "Two columns", "Quote", "Big number"] { XCTAssertTrue(names.contains(expected), expected) }
    }

    func testEachTemplateParsesAsTheKindOfSlideItIsMeantToBe() {
        XCTAssertEqual(parseSlideContent(text(.title)).blocks.first, .headline("Your title"))
        XCTAssertEqual(parseSlideContent(text(.quote)).kind, .quote)
        XCTAssertEqual(parseSlideContent(text(.bigNumber)).kind, .plain)
        XCTAssertEqual(parseSlideContent(text(.bullets)).kind, .list)
        XCTAssertEqual(parseSlideContent(text(.agenda)).kind, .list)
        XCTAssertEqual(parseSlideContent(text(.code)).kind, .code)
        for table in [SlideTemplate.twoColumns, .table] {
            guard case .table(let data)? = parseSlideContent(text(table)).blocks.last else { return XCTFail("\(table) needs a table") }
            XCTAssertGreaterThanOrEqual(data.columnCount, 2)
            XCTAssertGreaterThanOrEqual(data.rows.count, 2)
        }
    }

    func testPictureTemplatesNeedAPictureAndPlaceItBesideTheText() {
        XCTAssertTrue(SlideTemplate.pictureLeft.needsPicture)
        XCTAssertNil(SlideTemplate.pictureLeft.text(picture: nil))
        let left = SlideTemplate.pictureLeft.text(picture: "photo.png") ?? ""
        XCTAssertEqual(parseMedia(left, base: "").side, "left")
        XCTAssertEqual(parseMedia(left, base: "").file, "photo.png")
        XCTAssertEqual(parseMedia(SlideTemplate.pictureRight.text(picture: "a b.png") ?? "", base: "").side, "right")
        XCTAssertEqual(parseMedia(SlideTemplate.pictureRight.text(picture: "a b.png") ?? "", base: "").file, "a b.png", "names with spaces work")
        XCTAssertFalse(SlideTemplate.allCases.filter { !$0.needsPicture }.contains { $0.text(picture: nil) == nil })
    }

    // MARK: Inserting

    func testInsertingAddsTheSlideAfterTheSelectedOneSelectsItAndCanBeUndone() {
        let deck = DeckModel(source: "---\ntitle: \"T\"\n---\n\n# One\n\n---\n\n# Two\n")
        deck.select(0)
        deck.insertSlide(text(.quote), after: 0)
        XCTAssertEqual(deck.count, 3)
        XCTAssertEqual(deck.slideTexts, ["# One", text(.quote), "# Two"])
        XCTAssertEqual(deck.selected, 1)
        deck.undo()
        XCTAssertEqual(deck.slideTexts, ["# One", "# Two"])
    }

    func testInsertingAtTheEndAndOutOfRangeAppends() {
        let deck = DeckModel(source: "# One\n")
        deck.insertSlide("# Two", after: 0)
        deck.insertSlide("# Three", after: 99)
        XCTAssertEqual(deck.slideTexts, ["# One", "# Two", "# Three"])
        XCTAssertEqual(deck.selected, 2)
    }
}
