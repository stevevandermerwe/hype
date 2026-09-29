import XCTest
@testable import HypeCore

final class YAMLTests: XCTestCase {
    func testParseYAMLHeaderReadsScalars() {
        let header = """
        ---
        title: "My Talk"
        theme: tokyo-night
        show_page_number: true
        text_scale: 1.2
        ---
        """
        let yaml = parseYAMLHeader(header)
        XCTAssertNotNil(yaml)
        XCTAssertEqual(yaml?["title"] as? String, "My Talk")
        XCTAssertEqual(yaml?["theme"] as? String, "tokyo-night")
        XCTAssertEqual(yaml?["show_page_number"] as? Bool, true)
        XCTAssertEqual(yaml?["text_scale"] as? Double, 1.2)
    }

    func testYAMLStringFallsBackToStringifiedValues() {
        let header = """
        ---
        title: Plain
        count: 42
        enabled: true
        ---
        """
        XCTAssertEqual(yamlString(header, key: "title"), "Plain")
        XCTAssertEqual(yamlString(header, key: "count"), "42")
        XCTAssertEqual(yamlString(header, key: "enabled"), "true")
        XCTAssertNil(yamlString(header, key: "missing"))
    }

    func testYAMLBoolReadsBooleansAndStrings() {
        let header = """
        ---
        a: true
        b: false
        c: "yes"
        d: "no"
        e: 1
        ---
        """
        XCTAssertEqual(yamlBool(header, key: "a"), true)
        XCTAssertEqual(yamlBool(header, key: "b"), false)
        XCTAssertEqual(yamlBool(header, key: "c"), true)
        XCTAssertEqual(yamlBool(header, key: "d"), false)
        XCTAssertNil(yamlBool(header, key: "e"))
        XCTAssertNil(yamlBool(header, key: "missing"))
    }

    func testYAMLArrayReadsListSyntax() {
        let header = """
        ---
        tags:
          - swift
          - macos
          - "hype"
        ---
        """
        XCTAssertEqual(yamlArray(header, key: "tags"), ["swift", "macos", "hype"])
        XCTAssertNil(yamlArray(header, key: "missing"))
    }

    func testYAMLArrayReadsInlineLists() {
        let header = """
        ---
        tags: [one, two, three]
        mixed: [1, two, 3]
        ---
        """
        XCTAssertEqual(yamlArray(header, key: "tags"), ["one", "two", "three"])
        XCTAssertEqual(yamlArray(header, key: "mixed"), ["1", "two", "3"])
    }

    func testYAMLIntAndDouble() {
        let header = """
        ---
        count: 42
        scale: 1.5
        ---
        """
        XCTAssertEqual(yamlInt(header, key: "count"), 42)
        XCTAssertEqual(yamlDouble(header, key: "scale"), 1.5)
        XCTAssertEqual(yamlDouble(header, key: "count"), 42.0)
    }

    func testEmptyHeaderIsValid() {
        XCTAssertTrue(isValidYAMLHeader("---\n---\n"))
        XCTAssertTrue(isValidYAMLHeader(""))
    }

    func testInvalidYAMLHeaderIsRejected() {
        let header = """
        ---
        title: "unclosed
        ---
        """
        XCTAssertFalse(isValidYAMLHeader(header))
    }

    func testDeckEditSourceAppliesValidMarkdown() {
        let deck = DeckModel(source: "---\ntitle: A\n---\n\n# One\n")
        XCTAssertTrue(deck.editSource("---\ntitle: B\n---\n\n# One\n\n---\n\n# Two\n"))
        XCTAssertEqual(deck.title, "B")
        XCTAssertEqual(deck.count, 2)
        XCTAssertTrue(deck.canUndo)
    }

    func testDeckEditSourceRejectsInvalidFrontMatter() {
        let deck = DeckModel(source: "---\ntitle: A\n---\n\n# One\n")
        let original = deck.source
        XCTAssertFalse(deck.editSource("---\ntitle: \"unclosed\n---\n\n# One\n"))
        XCTAssertEqual(deck.source, original)
        XCTAssertFalse(deck.canUndo)
    }

    func testDeckEditSourceRejectsUnclosedFence() {
        let deck = DeckModel(source: "---\ntitle: A\n---\n\n# One\n")
        let original = deck.source
        XCTAssertFalse(deck.editSource("---\ntitle: A\n---\n\n```\ncode\n"))
        XCTAssertEqual(deck.source, original)
    }

    func testDeckEditSourceAcceptsYAMLArrays() {
        let source = """
        ---
        title: Tags
        tags:
          - swift
          - macos
        ---

        # One
        """
        let deck = DeckModel()
        XCTAssertTrue(deck.editSource(source))
        XCTAssertEqual(deck.title, "Tags")
        XCTAssertEqual(yamlArray(deck.parsed.header, key: "tags"), ["swift", "macos"])
    }
}
