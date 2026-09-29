import XCTest
import AppKit
import SwiftUI
import HypeCore
@testable import HypeApp

/// The NSTextView glue behind the editor-assist buttons and the Return key,
/// exercised on a real (offscreen) text view: the pure text logic is covered in
/// `MarkdownEditTests`; this checks it is wired to the view correctly.
@MainActor
final class EditorGlueTests: XCTestCase {
    private final class Box { var text = "" }

    /// A text view with `text`, the caret/selection set, wired to a controller and
    /// coordinator the way `MarkdownEditor.makeNSView` does.
    private func makeEditor(_ text: String, selection: NSRange) -> (NSTextView, EditorController, MarkdownEditor.Coordinator, Box) {
        let box = Box()
        box.text = text
        let controller = EditorController()
        let editor = MarkdownEditor(text: Binding(get: { box.text }, set: { box.text = $0 }), controller: controller)
        let coordinator = MarkdownEditor.Coordinator(editor)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.delegate = coordinator
        textView.string = text
        textView.setSelectedRange(selection)
        controller.textView = textView
        return (textView, controller, coordinator, box)
    }

    func testFormatButtonEditsTheViewKeepsTheSelectionAndUpdatesTheBinding() {
        let (textView, controller, _, box) = makeEditor("hello world", selection: NSRange(location: 6, length: 5))
        controller.apply(.bold)
        XCTAssertEqual(textView.string, "hello **world**")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 5))
        XCTAssertEqual(box.text, "hello **world**", "the SwiftUI binding must see the edit")
    }

    func testTransformChangesTheTextAndReportsWhetherItApplied() {
        let (textView, controller, _, box) = makeEditor("![](a.png)", selection: NSRange(location: 0, length: 0))
        XCTAssertTrue(controller.transform { applyImageLayout(.left, to: $0) })
        XCTAssertEqual(textView.string, "![left](a.png)")
        XCTAssertEqual(box.text, "![left](a.png)")
        XCTAssertFalse(controller.transform { _ in nil })
        XCTAssertEqual(textView.string, "![left](a.png)")
    }

    func testReturnAtTheEndOfAListItemContinuesTheList() {
        let (textView, _, coordinator, box) = makeEditor("- one", selection: NSRange(location: 5, length: 0))
        let handled = coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(handled)
        XCTAssertEqual(textView.string, "- one\n- ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 0))
        XCTAssertEqual(box.text, "- one\n- ")
    }

    func testReturnOnAnEmptyItemEndsTheListAndOtherReturnsAreLeftAlone() {
        let (textView, _, coordinator, _) = makeEditor("- one\n- ", selection: NSRange(location: 8, length: 0))
        XCTAssertTrue(coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(textView.string, "- one\n")

        let (plain, _, plainCoordinator, _) = makeEditor("plain", selection: NSRange(location: 5, length: 0))
        XCTAssertFalse(plainCoordinator.textView(plain, doCommandBy: #selector(NSResponder.insertNewline(_:))),
                       "an ordinary Return is left to the text view")
        XCTAssertFalse(plainCoordinator.textView(plain, doCommandBy: #selector(NSResponder.moveDown(_:))))
    }

    func testAnEditWithEmojiKeepsSurrogatePairsIntact() {
        let (textView, controller, _, _) = makeEditor("😀 hi", selection: NSRange(location: 3, length: 2))
        controller.apply(.bold)
        XCTAssertEqual(textView.string, "😀 **hi**")
    }
}
