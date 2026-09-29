import XCTest
@testable import HypeCore

/// A slide's text broken into the pieces the renderer lays out: a headline,
/// body lines, fenced code, and tables.
final class SlideBlocksTests: XCTestCase {
    func testPlainSlideHasAHeadlineAndLines() {
        let content = parseSlideContent("# Title\n\nHello **there**")
        XCTAssertEqual(content.blocks, [.headline("Title"), .line(""), .line("Hello **there**")])
        XCTAssertEqual(content.kind, .plain)
    }

    func testListItemsGetBulletsAndKeepTheirNumbers() {
        let content = parseSlideContent("# T\n- a\n* b\n2. c\nplain")
        XCTAssertEqual(content.blocks, [.headline("T"), .line("•  a"), .line("•  b"), .line("2. c"), .line("plain")])
        XCTAssertEqual(content.kind, .list)
    }

    func testQuoteStripsMarkersAndDoesNotExtractAHeadline() {
        let content = parseSlideContent("> wise\n>> deeper")
        XCTAssertEqual(content.blocks, [.line("wise"), .line("deeper")])
        XCTAssertEqual(content.kind, .quote)
    }

    func testFencedCodeBecomesACodeBlockWithItsLanguage() {
        let content = parseSlideContent("# Demo\n\n```Swift\nlet x = 1\n\nprint(x)\n```\nAfter")
        XCTAssertEqual(content.blocks, [.headline("Demo"), .line(""),
                                        .code(language: "swift", lines: ["let x = 1", "", "print(x)"]),
                                        .line("After")])
        XCTAssertEqual(content.kind, .code)
    }

    func testCodeFenceVariants() {
        XCTAssertEqual(parseSlideContent("```\na\n```").blocks, [.code(language: "", lines: ["a"])])
        XCTAssertEqual(parseSlideContent("~~~python\nb\n~~~").blocks, [.code(language: "python", lines: ["b"])])
        // A longer fence may contain a shorter one; an unclosed fence runs to the end.
        XCTAssertEqual(parseSlideContent("````\n```\n````").blocks, [.code(language: "", lines: ["```"])])
        XCTAssertEqual(parseSlideContent("```js\nlast").blocks, [.code(language: "js", lines: ["last"])])
    }

    func testHeadlineLikeLinesInsideCodeStayCode() {
        let content = parseSlideContent("```bash\n# a comment\n```")
        XCTAssertEqual(content.blocks, [.code(language: "bash", lines: ["# a comment"])])
    }

    func testTableIsParsedWithAlignmentsAndTrailingText() {
        let content = parseSlideContent("# Data\n\n| A | B |\n| :-- | --: |\n| 1 | 2 |\n| 3 | 4 |\n\nfooter")
        let table = TableData(header: ["A", "B"], rows: [["1", "2"], ["3", "4"]], alignments: [.leading, .trailing])
        XCTAssertEqual(content.blocks, [.headline("Data"), .line(""), .table(table), .line(""), .line("footer")])
        XCTAssertEqual(content.kind, .table)
    }

    func testTableCellsHandleEdgesEscapesAndRaggedRows() {
        let source = "A | B | C\n:-: | --- | ---\nx \\| y | 2\n1 | 2 | 3 | 4"
        guard case .table(let table)? = parseSlideContent(source).blocks.first else { return XCTFail("no table") }
        XCTAssertEqual(table.header, ["A", "B", "C"])
        XCTAssertEqual(table.alignments, [.center, .leading, .leading])
        XCTAssertEqual(table.rows, [["x | y", "2", ""], ["1", "2", "3"]], "short rows are padded, long rows trimmed")
    }

    func testAPipeLineWithoutASeparatorRowIsJustText() {
        let content = parseSlideContent("a | b\nc | d")
        XCTAssertEqual(content.blocks, [.line("a | b"), .line("c | d")])
        XCTAssertEqual(content.kind, .plain)
    }

    func testKindPriorityCodeThenQuoteThenListThenTable() {
        XCTAssertEqual(parseSlideContent("- a\n```\nx\n```\n| a | b |\n| - | - |").kind, .code)
        XCTAssertEqual(parseSlideContent("> q\n- a").kind, .quote)
        XCTAssertEqual(parseSlideContent("- a\n| a | b |\n| - | - |\n| 1 | 2 |").kind, .list)
    }

    func testTablesInsideAListSlideAreStillTables() {
        let content = parseSlideContent("- a\n| a | b |\n| - | - |\n| 1 | 2 |")
        XCTAssertEqual(content.blocks.count, 2)
        if case .table = content.blocks[1] {} else { XCTFail("expected a table") }
    }

    func testEmptyTextHasNoBlocks() {
        XCTAssertTrue(parseSlideContent("  \n ").blocks.isEmpty)
    }
}
