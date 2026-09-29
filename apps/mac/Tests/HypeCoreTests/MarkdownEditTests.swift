import XCTest
@testable import HypeCore

/// The editor-assist buttons: each `FormatAction` turns (text, selection) into
/// new text and a new selection. Positions are UTF-16 offsets, as in NSTextView.
final class MarkdownEditTests: XCTestCase {
    private func apply(_ action: FormatAction, _ text: String, at location: Int, length: Int = 0) -> EditResult {
        applyFormat(action, to: text, selection: NSRange(location: location, length: length))
    }
    private func selected(_ result: EditResult) -> String {
        (result.text as NSString).substring(with: result.selection)
    }

    // MARK: Inline styles

    func testBoldOnAnEmptySelectionInsertsSelectedPlaceholder() {
        let result = apply(.bold, "", at: 0)
        XCTAssertEqual(result.text, "**bold text**")
        XCTAssertEqual(selected(result), "bold text")
    }

    func testBoldWrapsTheSelectionAndKeepsItSelected() {
        let result = apply(.bold, "hello world", at: 6, length: 5)
        XCTAssertEqual(result.text, "hello **world**")
        XCTAssertEqual(selected(result), "world")
    }

    func testBoldTogglesOffWhenTheMarkersSurroundTheSelection() {
        let result = apply(.bold, "hello **world**", at: 8, length: 5)
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(selected(result), "world")
    }

    func testBoldTogglesOffWhenTheMarkersAreInsideTheSelection() {
        let result = apply(.bold, "hello **world**", at: 6, length: 9)
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(selected(result), "world")
    }

    func testItalicInsideBoldAddsItRatherThanRemovingBold() {
        let result = apply(.italic, "**world**", at: 2, length: 5)
        XCTAssertEqual(result.text, "***world***")
    }

    func testItalicTogglesOffAndUnderlineAndCodeAndNoteWork() {
        XCTAssertEqual(apply(.italic, "*hi*", at: 1, length: 2).text, "hi")
        XCTAssertEqual(apply(.underline, "make this loud", at: 5, length: 4).text, "make _this_ loud")
        XCTAssertEqual(apply(.inlineCode, "call run now", at: 5, length: 3).text, "call `run` now")
        let note = apply(.note, "Intro", at: 5)
        XCTAssertEqual(note.text, "Intro<!-- Speaker note -->")
        XCTAssertEqual(selected(note), "Speaker note")
    }

    func testSurroundingWhitespaceStaysOutsideTheMarkers() {
        let result = apply(.bold, "a word here", at: 1, length: 6) // " word "
        XCTAssertEqual(result.text, "a **word** here")
        XCTAssertEqual(selected(result), "word")
    }

    func testAMultiLineSelectionIsWrappedLineByLine() {
        let result = apply(.bold, "one\n\ntwo", at: 0, length: 8)
        XCTAssertEqual(result.text, "**one**\n\n**two**")
    }

    func testInlineStylesSkipTheListHeadingOrQuoteMarkerAtTheStartOfALine() {
        XCTAssertEqual(apply(.bold, "- Big idea", at: 0, length: 10).text, "- **Big idea**")
        XCTAssertEqual(apply(.italic, "1. Big idea", at: 0, length: 11).text, "1. *Big idea*")
        XCTAssertEqual(apply(.bold, "# Title", at: 0, length: 7).text, "# **Title**")
        XCTAssertEqual(apply(.bold, "> wise words", at: 0, length: 12).text, "> **wise words**")
        XCTAssertEqual(apply(.bold, "- one\n- two", at: 0, length: 11).text, "- **one**\n- **two**")
        // Toggling back off works from the whole line too.
        XCTAssertEqual(apply(.bold, "- **Big idea**", at: 0, length: 14).text, "- Big idea")
        // A selection that starts inside the text is untouched by this rule.
        XCTAssertEqual(apply(.bold, "- Big idea", at: 2, length: 3).text, "- **Big** idea")
    }

    func testInlineStylesUseUTF16OffsetsAroundEmoji() {
        // "😀" is two UTF-16 units, so "hi" starts at offset 3.
        let result = apply(.bold, "😀 hi", at: 3, length: 2)
        XCTAssertEqual(result.text, "😀 **hi**")
        XCTAssertEqual(selected(result), "hi")
    }

    // MARK: Line styles

    func testHeadingOnAnEmptyDocumentInsertsAPlaceholder() {
        let result = apply(.heading, "", at: 0)
        XCTAssertEqual(result.text, "# Headline")
        XCTAssertEqual(selected(result), "Headline")
    }

    func testHeadingTogglesAndKeepsTheCaretOnTheSameCharacter() {
        let on = apply(.heading, "hello", at: 3)
        XCTAssertEqual(on.text, "# hello")
        XCTAssertEqual(on.selection, NSRange(location: 5, length: 0))
        let off = apply(.heading, on.text, at: 5)
        XCTAssertEqual(off.text, "hello")
        XCTAssertEqual(off.selection, NSRange(location: 3, length: 0))
    }

    func testHeadingReplacesAnyLevelAndOnlyRemovesWhenEveryLineIsAHeading() {
        XCTAssertEqual(apply(.heading, "## Deep", at: 0).text, "Deep") // all lines already headings: toggles off
        XCTAssertEqual(apply(.heading, "# One\nTwo", at: 0, length: 9).text, "# One\n# Two")
    }

    func testHeadingLeavesBlankLinesAlone() {
        XCTAssertEqual(apply(.heading, "One\n\nTwo", at: 0, length: 8).text, "# One\n\n# Two")
    }

    func testBulletListPrefixesEveryLineAndTogglesOff() {
        let on = apply(.bulletList, "one\ntwo\nthree", at: 0, length: 13)
        XCTAssertEqual(on.text, "- one\n- two\n- three")
        XCTAssertEqual(apply(.bulletList, on.text, at: 0, length: on.text.utf16.count).text, "one\ntwo\nthree")
    }

    func testNumberedListNumbersLinesAndConvertsFromBullets() {
        XCTAssertEqual(apply(.numberedList, "a\nb\nc", at: 0, length: 5).text, "1. a\n2. b\n3. c")
        XCTAssertEqual(apply(.numberedList, "- a\n- b", at: 0, length: 7).text, "1. a\n2. b")
        XCTAssertEqual(apply(.bulletList, "1. a\n2. b", at: 0, length: 9).text, "- a\n- b")
    }

    func testListKeepsIndentation() {
        XCTAssertEqual(apply(.bulletList, "  nested", at: 0).text, "  - nested")
    }

    func testQuoteTogglesAndAnEmptyLineGetsAPlaceholder() {
        XCTAssertEqual(apply(.quote, "wise words", at: 0).text, "> wise words")
        XCTAssertEqual(apply(.quote, "> wise words", at: 0).text, "wise words")
        let empty = apply(.quote, "", at: 0)
        XCTAssertEqual(empty.text, "> Quote")
        XCTAssertEqual(selected(empty), "Quote")
    }

    func testLineStylesOnlyTouchTheSelectedLines() {
        let result = apply(.bulletList, "keep\nchange\nkeep", at: 5, length: 0)
        XCTAssertEqual(result.text, "keep\n- change\nkeep")
    }

    // MARK: Blocks

    func testCodeBlockWrapsTheSelectionInAFenceWithTheLanguage() {
        let result = apply(.codeBlock(language: "swift"), "let x = 1", at: 0, length: 9)
        XCTAssertEqual(result.text, "```swift\nlet x = 1\n```")
        XCTAssertEqual(selected(result), "let x = 1")
    }

    func testCodeBlockOnNothingInsertsAPlaceholderOnItsOwnLines() {
        let result = apply(.codeBlock(language: ""), "Title", at: 5)
        XCTAssertEqual(result.text, "Title\n```\ncode\n```")
        XCTAssertEqual(selected(result), "code")
    }

    func testCodeBlockUsesALongerFenceWhenTheSelectionContainsOne() {
        let result = apply(.codeBlock(language: ""), "```a```", at: 0, length: 7)
        XCTAssertTrue(result.text.hasPrefix("````\n"))
        XCTAssertTrue(result.text.hasSuffix("\n````"))
    }

    func testTableInsertsATemplateSeparatedByBlankLines() {
        let result = apply(.table, "# Data", at: 6)
        XCTAssertEqual(result.text, "# Data\n\n| Column | Column |\n| --- | --- |\n| Cell | Cell |\n")
        XCTAssertEqual(selected(result), "Column")
    }

    // MARK: Return key

    func testReturnAtTheEndOfAListItemStartsTheNextOne() {
        let bullet = continueList(in: "- one", caret: 5)
        XCTAssertEqual(bullet?.text, "- one\n- ")
        XCTAssertEqual(bullet?.selection, NSRange(location: 8, length: 0))
        XCTAssertEqual(continueList(in: "1. one", caret: 6)?.text, "1. one\n2. ")
        XCTAssertEqual(continueList(in: "9) nine", caret: 7)?.text, "9) nine\n10) ")
        XCTAssertEqual(continueList(in: "  - nested", caret: 10)?.text, "  - nested\n  - ")
        XCTAssertEqual(continueList(in: "> wise", caret: 6)?.text, "> wise\n> ")
    }

    func testReturnOnAnEmptyListItemEndsTheList() {
        let result = continueList(in: "- one\n- ", caret: 8)
        XCTAssertEqual(result?.text, "- one\n")
        XCTAssertEqual(result?.selection, NSRange(location: 6, length: 0))
        XCTAssertEqual(continueList(in: "> ", caret: 2)?.text, "")
    }

    func testReturnElsewhereIsLeftToTheTextView() {
        XCTAssertNil(continueList(in: "plain text", caret: 10))
        XCTAssertNil(continueList(in: "- one", caret: 3), "mid-line Return splits the line normally")
        XCTAssertNil(continueList(in: "- one two", caret: 5))
        XCTAssertNil(continueList(in: "*emphasis* text", caret: 15))
    }

    func testSelectionOutOfRangeIsClamped() {
        let result = applyFormat(.bold, to: "hi", selection: NSRange(location: 99, length: 5))
        XCTAssertEqual(result.text, "hi**bold text**")
    }
}
