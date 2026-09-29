import SwiftUI
import AppKit
import HypeCore

/// The bridge between the editor-assist buttons/menu items and the text view.
/// SwiftUI's `TextEditor` can't report or set its selection on macOS 14, so the
/// Markdown editor is an `NSTextView`; this controller applies a `FormatAction`
/// (or any other whole-text change) to it as a single edit.
@MainActor
final class EditorController: ObservableObject {
    weak var textView: NSTextView?

    /// Whether an editor is currently on screen (the light table has none).
    var isAvailable: Bool { textView?.window != nil }

    func apply(_ action: FormatAction) {
        guard let textView else { return }
        let result = applyFormat(action, to: textView.string, selection: textView.selectedRange())
        replaceText(with: result.text, selection: result.selection)
    }

    /// Replaces the text with `change(currentText)`, keeping the selection where
    /// it was. Returns false (changing nothing) if `change` returns nil.
    @discardableResult
    func transform(_ change: (String) -> String?) -> Bool {
        guard let textView, let updated = change(textView.string) else { return false }
        replaceText(with: updated, selection: nil)
        return true
    }

    /// Rewrites only the span that differs, through the text view's normal edit
    /// path (so the binding updates and scroll position and undo grouping are
    /// undisturbed), then puts the selection where the caller asked.
    fileprivate func replaceText(with updated: String, selection: NSRange?) {
        guard let textView else { return }
        let old = textView.string as NSString, new = updated as NSString
        let shortest = min(old.length, new.length)
        var prefix = 0
        while prefix < shortest, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        if prefix > 0, UTF16.isLeadSurrogate(old.character(at: prefix - 1)) { prefix -= 1 }
        var suffix = 0
        while suffix < shortest - prefix, old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        if suffix > 0, UTF16.isTrailSurrogate(old.character(at: old.length - suffix)) { suffix -= 1 }

        let oldRange = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        if oldRange.length > 0 || !replacement.isEmpty,
           textView.shouldChangeText(in: oldRange, replacementString: replacement) {
            textView.textStorage?.replaceCharacters(in: oldRange, with: NSAttributedString(string: replacement, attributes: MarkdownEditor.attributes))
            textView.didChangeText()
        }
        if let selection {
            let clamped = NSRange(location: min(selection.location, new.length),
                                  length: min(selection.length, max(0, new.length - selection.location)))
            textView.setSelectedRange(clamped)
            textView.scrollRangeToVisible(clamped)
        }
        textView.window?.makeFirstResponder(textView)
    }
}

/// The per-slide Markdown source editor: a plain-text `NSTextView` with
/// Markdown-friendly settings (no smart quotes or autocorrect, which would
/// corrupt `"` and `--` in source) and list continuation on Return.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: EditorController
    /// Called when picture or video files are dropped on the editor; return true
    /// if handled. (Without it a dropped file would paste its path as text.)
    var onDropFiles: (([URL]) -> Bool)?

    static let attributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        return [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: style]
    }()

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Built by hand (what `NSTextView.scrollableTextView()` does) so the text view can be ours.
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        textView.onDropFiles = onDropFiles
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = false // Undo is the deck's (Edit menu), one history for everything.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.typingAttributes = Self.attributes
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
        controller.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        controller.textView = textView
        (textView as? MarkdownTextView)?.onDropFiles = onDropFiles
        // Only external changes (undo, another slide, AI edit) differ from the view.
        if textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
            let length = (text as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        /// Return inside a list or quote continues it; Return on an empty item ends it.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)),
                  textView.selectedRange().length == 0, !textView.hasMarkedText(),
                  let result = continueList(in: textView.string, caret: textView.selectedRange().location)
            else { return false }
            MainActor.assumeIsolated { parent.controller.replaceText(with: result.text, selection: result.selection) }
            return true
        }
    }
}

/// The editor's text view: picture and video files dropped on it are handed to
/// `onDropFiles` (which adds them to the slide) instead of pasting their paths.
final class MarkdownTextView: NSTextView {
    var onDropFiles: (([URL]) -> Bool)?

    private func mediaURLs(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return mediaFiles(in: urls)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDropFiles != nil && !mediaURLs(sender).isEmpty ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDropFiles != nil && !mediaURLs(sender).isEmpty ? .copy : super.draggingUpdated(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = mediaURLs(sender)
        if !urls.isEmpty, let onDropFiles, onDropFiles(urls) { return true }
        return super.performDragOperation(sender)
    }
}
