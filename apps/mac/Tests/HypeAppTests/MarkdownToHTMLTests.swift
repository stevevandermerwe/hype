import XCTest
@testable import HypeApp

final class MarkdownToHTMLTests: XCTestCase {
    func testHeadings() {
        let html = markdownToHTML("# Title\n## Subtitle", title: "T")
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<h2>Subtitle</h2>"))
    }

    func testParagraphLinesAreJoined() {
        let html = markdownToHTML("First line\nsecond line.", title: "T")
        XCTAssertTrue(html.contains("<p>First line second line.</p>"))
    }

    func testBlankLinesSeparateParagraphs() {
        let html = markdownToHTML("One.\n\nTwo.", title: "T")
        let paragraphs = html.components(separatedBy: "<p>")
            .filter { $0.contains("</p>") }
        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertTrue(html.contains("<p>One.</p>"))
        XCTAssertTrue(html.contains("<p>Two.</p>"))
    }

    func testCodeBlockEscapesHTML() {
        let html = markdownToHTML("```\n<a>\n```", title: "T")
        XCTAssertTrue(html.contains("<pre><code>&lt;a&gt;</code></pre>"))
    }

    func testUnorderedList() {
        let html = markdownToHTML("- one\n- two", title: "T")
        XCTAssertTrue(html.contains("<ul><li>one</li><li>two</li></ul>"))
    }

    func testOrderedList() {
        let html = markdownToHTML("1. one\n2. two", title: "T")
        XCTAssertTrue(html.contains("<ol><li>one</li><li>two</li></ol>"))
    }

    func testTable() {
        let html = markdownToHTML("| A | B |\n| --- | --- |\n| 1 | 2 |", title: "T")
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<thead><tr><th>A</th><th>B</th></tr></thead>"))
        XCTAssertTrue(html.contains("<tbody><tr><td>1</td><td>2</td></tr></tbody>"))
    }

    func testInlineFormatting() {
        let html = markdownToHTML("**bold** *italic* _under_ `code` [link](http://x)", title: "T")
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<em>italic</em>"))
        XCTAssertTrue(html.contains("<u>under</u>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
        XCTAssertTrue(html.contains("<a href=\"http://x\">link</a>"))
    }

    func testHelpFilesConvertWithoutTablesBeingEatenByParagraphs() {
        // A regression guard: a table that immediately follows a paragraph must
        // close the paragraph before the table, and a paragraph after the table
        // must start fresh.
        let markdown = "Intro text.\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nOutro text."
        let html = markdownToHTML(markdown, title: "T")
        XCTAssertTrue(html.contains("<p>Intro text.</p>"))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<p>Outro text.</p>"))
    }

    func testNestedCodeFencesWithDifferentLengths() {
        // A 4-backtick fence can contain a 3-backtick fence without closing.
        let markdown = "````markdown\n```ruby\nputs 'hi'\n```\n````"
        let html = markdownToHTML(markdown, title: "T")
        XCTAssertTrue(html.contains("<pre><code>```ruby\nputs 'hi'\n```</code></pre>"))
    }
}
