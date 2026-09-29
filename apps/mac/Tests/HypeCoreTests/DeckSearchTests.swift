import XCTest
@testable import HypeCore

/// Find and replace across every slide of a deck.
final class DeckSearchTests: XCTestCase {
    private let slides = [
        "# Welcome to Hype\n\nHype makes slides",
        "# The Cat\n\n- category: cat\n- CAT food",
        "# Photo\n\n![](photo.png)\n\nA nice photo",
        "```swift\nlet cat = 1\n```",
    ]

    private func find(_ query: String, _ options: SearchOptions = SearchOptions()) -> [SearchMatch] {
        guard case .success(let matches) = findMatches(in: slides, query: query, options: options) else { return [] }
        return matches
    }

    // MARK: Finding

    func testFindsEveryMatchAcrossSlidesCaseInsensitivelyByDefault() {
        let matches = find("hype")
        XCTAssertEqual(matches.map(\.slide), [0, 0])
        XCTAssertEqual(matches.map(\.text), ["Hype", "Hype"])
        XCTAssertEqual(find("cat").map(\.slide), [1, 1, 1, 1, 3], "the title, 'category', 'cat', 'CAT', and code")
    }

    func testMatchCaseAndWholeWordNarrowTheResults() {
        XCTAssertEqual(find("cat", SearchOptions(caseSensitive: true)).map(\.text), ["cat", "cat", "cat"])
        XCTAssertEqual(find("cat", SearchOptions(wholeWord: true)).count, 4, "'category' no longer counts")
        XCTAssertEqual(find("cat", SearchOptions(caseSensitive: true, wholeWord: true)).map(\.slide), [1, 3])
    }

    func testTheQueryIsLiteralUnlessRegexIsOn() {
        XCTAssertEqual(find("a.b").count, 0)
        XCTAssertEqual(findMatches(in: ["x a.b y"], query: "a.b", options: SearchOptions()).matchCount, 1)
        XCTAssertEqual(findMatches(in: ["axb a.b"], query: "a.b", options: SearchOptions()).matchCount, 1, "the dot is literal")
        XCTAssertEqual(findMatches(in: ["axb a.b"], query: "a.b", options: SearchOptions(regex: true)).matchCount, 2)
    }

    func testAnInvalidRegexIsReportedNotCrashed() {
        guard case .failure(let error) = findMatches(in: slides, query: "(", options: SearchOptions(regex: true)) else { return XCTFail() }
        XCTAssertFalse(error.description.isEmpty)
    }

    func testAnEmptyQueryFindsNothing() {
        XCTAssertEqual(find("").count, 0)
    }

    func testPictureFilenamesAreNeverMatched() {
        XCTAssertEqual(find("photo").map(\.slide), [2, 2], "the heading and the caption, not photo.png")
        XCTAssertEqual(find("png").count, 0)
    }

    func testMatchesCarryTheirPositionAndSomeContext() throws {
        let match = try XCTUnwrap(find("category").first)
        XCTAssertEqual(match.slide, 1)
        XCTAssertEqual((slides[1] as NSString).substring(with: match.range), "category")
        XCTAssertTrue(match.before.hasSuffix("- "), match.before)
        XCTAssertTrue(match.after.hasPrefix(": cat"), match.after)
    }

    func testPositionsAreCorrectAroundEmoji() throws {
        guard case .success(let matches) = findMatches(in: ["😀 hi 😀 hi"], query: "hi", options: SearchOptions()) else { return XCTFail() }
        XCTAssertEqual(matches.map(\.range.location), [3, 9])
    }

    // MARK: Replacing

    private func replaceAll(_ query: String, with replacement: String, _ options: SearchOptions = SearchOptions(),
                            in slides: [String]? = nil, onlySlide: Int? = nil) -> (slides: [String], count: Int)? {
        guard case .success(let result) = replaceMatches(in: slides ?? self.slides, query: query, replacement: replacement,
                                                         options: options, onlySlide: onlySlide) else { return nil }
        return result
    }

    func testReplaceAllChangesEveryMatchAndCountsThem() throws {
        let result = try XCTUnwrap(replaceAll("Hype", with: "Slidewright"))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.slides[0], "# Welcome to Slidewright\n\nSlidewright makes slides")
        XCTAssertEqual(result.slides[1], slides[1], "other slides are untouched")
    }

    func testReplacingCanBeLimitedToOneSlide() throws {
        let result = try XCTUnwrap(replaceAll("cat", with: "dog", onlySlide: 3))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.slides[3], "```swift\nlet dog = 1\n```")
        XCTAssertEqual(result.slides[1], slides[1])
    }

    func testReplacementTextIsLiteralUnlessRegex() throws {
        XCTAssertEqual(try XCTUnwrap(replaceAll("cost", with: "$1 and \\n", in: ["the cost"])).slides, ["the $1 and \\n"])
        let regex = try XCTUnwrap(replaceAll("(\\w+)@(\\w+)", with: "$2:$1", SearchOptions(regex: true), in: ["me@home"]))
        XCTAssertEqual(regex.slides, ["home:me"])
    }

    func testPicturesSurviveAReplaceOfTheirFilenameText() throws {
        let result = try XCTUnwrap(replaceAll("photo", with: "picture"))
        XCTAssertEqual(result.slides[2], "# picture\n\n![](photo.png)\n\nA nice picture")
    }

    func testReplacingWithNothingDeletesTheMatches() throws {
        XCTAssertEqual(try XCTUnwrap(replaceAll("very ", with: "", in: ["a very good talk"])).slides, ["a good talk"])
    }

    func testAReplacementThatWouldSplitASlideIsRefused() {
        let outcome = replaceMatches(in: ["a b"], query: "b", replacement: "x\n\n---\n\ny", options: SearchOptions(), onlySlide: nil)
        guard case .failure(let error) = outcome else { return XCTFail("expected failure") }
        XCTAssertEqual(error, .wouldSplitSlides)
    }

    func testNothingToReplaceReturnsTheSlidesUnchangedWithZero() throws {
        let result = try XCTUnwrap(replaceAll("zebra", with: "x"))
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(result.slides, slides)
    }
}

private extension Result where Success == [SearchMatch] {
    var matchCount: Int {
        if case .success(let matches) = self { return matches.count }
        return -1
    }
}
