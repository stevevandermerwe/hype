import XCTest
@testable import HypeCore

/// The built-in code highlighter: one array of tokens per line, covering the
/// languages offered by the editor's code-block menu.
final class SyntaxHighlightTests: XCTestCase {
    private func tokens(_ code: String, _ language: String) -> [[Token]] { highlight(code, language: language) }
    private func has(_ line: [Token], _ kind: TokenKind, _ text: String) -> Bool {
        line.contains { $0.kind == kind && $0.text == text }
    }

    func testSwiftKeywordsStringsCommentsAndNumbers() {
        let line = tokens("let x = 42 // answer\nprint(\"hi\")", "swift")
        XCTAssertTrue(has(line[0], .keyword, "let"))
        XCTAssertTrue(has(line[0], .number, "42"))
        XCTAssertTrue(has(line[0], .comment, "// answer"))
        XCTAssertTrue(has(line[1], .string, "\"hi\""))
    }

    func testTypesConstantsAndAttributes() {
        let line = tokens("@State var view: View = nil", "swift")[0]
        XCTAssertTrue(has(line, .attribute, "@State"))
        XCTAssertTrue(has(line, .type, "View"))
        XCTAssertTrue(has(line, .constant, "nil"))
    }

    func testStringEscapesDoNotEndTheString() {
        XCTAssertTrue(has(tokens("s = \"a\\\"b\"", "python")[0], .string, "\"a\\\"b\""))
    }

    func testAnUnterminatedStringEndsAtTheEndOfTheLine() {
        let lines = tokens("x = \"open\ny = 1", "python")
        XCTAssertTrue(has(lines[0], .string, "\"open"))
        XCTAssertTrue(has(lines[1], .number, "1"))
    }

    func testBlockCommentsSpanLines() {
        let lines = tokens("a /* one\ntwo */ b", "javascript")
        XCTAssertTrue(has(lines[0], .comment, "/* one"))
        XCTAssertTrue(has(lines[1], .comment, "two */"))
        XCTAssertFalse(lines[1].contains { $0.kind == .comment && $0.text.contains("b") })
    }

    func testPythonTripleQuotedStringsAndHashComments() {
        let lines = tokens("\"\"\"doc\nmore\"\"\"\nx = True # yes", "python")
        XCTAssertTrue(has(lines[0], .string, "\"\"\"doc"))
        XCTAssertTrue(has(lines[1], .string, "more\"\"\""))
        XCTAssertTrue(has(lines[2], .constant, "True"))
        XCTAssertTrue(has(lines[2], .comment, "# yes"))
    }

    func testJavaScriptTemplateLiteralsAndAliases() {
        XCTAssertTrue(has(tokens("const s = `a ${b}`", "js")[0], .string, "`a ${b}`"))
        XCTAssertTrue(has(tokens("const a = 1", "js")[0], .keyword, "const"))
        XCTAssertTrue(has(tokens("def f(): pass", "py")[0], .keyword, "def"))
        XCTAssertTrue(has(tokens("fn main() {}", "rs")[0], .keyword, "fn"))
    }

    func testJSONKeysAreProperties() {
        let line = tokens("{\"a\": 1, \"b\": true, \"c\": \"x\"}", "json")[0]
        XCTAssertTrue(has(line, .property, "\"a\""))
        XCTAssertTrue(has(line, .number, "1"))
        XCTAssertTrue(has(line, .constant, "true"))
        XCTAssertTrue(has(line, .string, "\"x\""))
    }

    func testYAMLKeysValuesAndComments() {
        let lines = tokens("name: Hype # app\nitems:\n  - a: 1\n  - \"quoted\"", "yaml")
        XCTAssertTrue(has(lines[0], .property, "name"))
        XCTAssertTrue(has(lines[0], .comment, "# app"))
        XCTAssertTrue(has(lines[1], .property, "items"))
        XCTAssertTrue(has(lines[2], .property, "a"))
        XCTAssertTrue(has(lines[2], .number, "1"))
        XCTAssertTrue(has(lines[3], .string, "\"quoted\""))
    }

    func testCSSSelectorsPropertiesAndValues() {
        let line = tokens(".box { color: #fff; margin: 4px; }", "css")[0]
        XCTAssertTrue(has(line, .type, ".box"))
        XCTAssertTrue(has(line, .property, "color"))
        XCTAssertTrue(has(line, .number, "#fff"))
        XCTAssertTrue(has(line, .property, "margin"))
        XCTAssertTrue(has(line, .number, "4px"))
    }

    func testHTMLTagsAttributesStringsAndComments() {
        let line = tokens("<div class=\"a\">x</div><!-- hi -->", "html")[0]
        XCTAssertTrue(has(line, .tag, "div"))
        XCTAssertTrue(has(line, .property, "class"))
        XCTAssertTrue(has(line, .string, "\"a\""))
        XCTAssertTrue(has(line, .comment, "<!-- hi -->"))
        XCTAssertEqual(line.filter { $0.kind == .tag }.count, 2, "opening and closing tag names")
    }

    func testBashVariablesKeywordsAndComments() {
        let line = tokens("if [ -f $HOME ]; then echo \"x\" # done", "bash")[0]
        XCTAssertTrue(has(line, .keyword, "if"))
        XCTAssertTrue(has(line, .keyword, "then"))
        XCTAssertTrue(has(line, .variable, "$HOME"))
        XCTAssertTrue(has(line, .comment, "# done"))
    }

    func testSQLKeywordsAreCaseInsensitive() {
        let line = tokens("select Name FROM users -- all", "sql")[0]
        XCTAssertTrue(has(line, .keyword, "select"))
        XCTAssertTrue(has(line, .keyword, "FROM"))
        XCTAssertTrue(has(line, .comment, "-- all"))
    }

    func testCPreprocessorLinesAreKeywords() {
        XCTAssertTrue(has(tokens("#include <stdio.h>", "c")[0], .keyword, "#include"))
    }

    func testMarkdownHeadingsAndCodeSpans() {
        let lines = tokens("# Title\ntext `code` here", "markdown")
        XCTAssertTrue(has(lines[0], .keyword, "# Title"))
        XCTAssertTrue(has(lines[1], .string, "`code`"))
    }

    func testUnknownOrEmptyLanguagesStayPlain() {
        for language in ["", "klingon"] {
            let lines = tokens("let x = 1\nfoo", language)
            XCTAssertEqual(lines.count, 2)
            XCTAssertTrue(lines.allSatisfy { $0.allSatisfy { $0.kind == .plain } })
        }
    }

    func testEveryLanguageReproducesItsInputExactly() {
        let sample = "  // c\n# h\n\"str\" 'c' `t` 12.5e3 0xFF @at $var {\"k\": [1, true]}\n<a b=\"c\">/* x\n*/</a>\n\té😀 end\r\nlast"
        let normalized = sample.replacingOccurrences(of: "\r\n", with: "\n")
        for language in supportedHighlightLanguages + ["", "unknown"] {
            let lines = tokens(sample, language)
            XCTAssertEqual(lines.map { $0.map(\.text).joined() }, normalized.components(separatedBy: "\n"), language)
        }
    }

    func testTheLanguageListCoversTheEditorMenu() {
        for name in ["swift", "ruby", "python", "javascript", "typescript", "bash", "json", "yaml", "html", "css",
                     "go", "rust", "c", "cpp", "java", "kotlin", "sql", "markdown"] {
            XCTAssertTrue(supportedHighlightLanguages.contains(name), name)
        }
    }
}
