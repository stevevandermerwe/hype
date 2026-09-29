import Foundation

/// The whole presentation, plus editing operations and undo/redo. Rewrites
/// exact source text rather than rebuilding it from a document tree, matching
/// the Qt app's `Deck` (`deck.cpp`) — so, as there, an edit changes only the
/// bytes it needs to and everything else in the file is left untouched.
///
/// No AppKit/SwiftUI dependency: this type is meant to be reused by the CLI
/// target in Phase 4, the same way `HypeCore` is shared today.
public final class DeckModel: ObservableObject {
    public static let defaultSource = "---\ntitle: Untitled\ntheme: tokyo-night\n---\n\n# Your next idea\n"

    @Published public private(set) var source: String
    @Published public private(set) var parsed: ParsedDeck
    @Published public var selected: Int = 0 {
        didSet {
            let clamped = min(max(0, selected), max(0, count - 1))
            if clamped != selected { selected = clamped }
        }
    }
    @Published public private(set) var path: String?
    @Published public private(set) var savedSource: String
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false
    /// A short status message for the UI to show (export progress/errors,
    /// AI generation progress) — matches the Qt app's `Deck::status()`.
    @Published public var status = ""
    public func setStatus(_ text: String) { status = text }

    private var undoStack: [(source: String, selected: Int)] = []
    private var redoStack: [(source: String, selected: Int)] = []

    public init(source: String = DeckModel.defaultSource) {
        self.source = source
        self.savedSource = source
        self.parsed = parseDeck(source)
    }

    public var count: Int { parsed.slides.count }
    public var dirty: Bool { source != savedSource }
    public var title: String {
        let fallback = path.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? "Untitled"
        return scalar(parsed.header, "title", fallback)
    }
    public var themeName: String { scalar(parsed.header, "theme", "tokyo-night") }
    public var palette: Palette { HypeCore.palette(forTheme: themeName, header: parsed.header) }
    /// Where this deck's `images/`/`videos/` live; empty until it has a path.
    public var baseDir: String { path.map { ($0 as NSString).deletingLastPathComponent } ?? "" }

    public func slideSource(at index: Int) -> String {
        guard parsed.slides.indices.contains(index) else { return "" }
        return parsed.slides[index].source
    }
    /// The selected slide's text with its surrounding blank-line padding
    /// trimmed, for editing. `editSlide` restores the right padding on save.
    public func slideText(at index: Int) -> String {
        slideSource(at: index).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func apply(_ newSource: String, selected newSelected: Int? = nil, pushUndo: Bool = true) {
        if pushUndo {
            undoStack.append((source, selected))
            redoStack.removeAll()
        }
        source = newSource
        parsed = parseDeck(newSource)
        selected = max(0, min(newSelected ?? selected, count - 1))
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    public func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append((source, selected))
        source = last.source
        parsed = parseDeck(source)
        selected = last.selected
        canUndo = !undoStack.isEmpty
        canRedo = true
    }
    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((source, selected))
        source = next.source
        parsed = parseDeck(source)
        selected = next.selected
        canUndo = true
        canRedo = !redoStack.isEmpty
    }

    /// Replaces the selected slide's text, rewriting only that slide's bytes.
    /// Matches the Qt app's `editSlide` (`deck.cpp`): a no-op edit (the same
    /// text typed back) creates no undo step.
    public func editSlide(_ text: String) {
        guard parsed.slides.indices.contains(selected) else { return }
        let range = parsed.slides[selected]
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            if range.start > 0 { body = "\n" + body }
            body += selected < count - 1 ? "\n\n" : "\n"
        } else {
            body = "\n"
        }
        var utf16 = Array(source.utf16)
        utf16.replaceSubrange(range.start..<range.end, with: Array(body.utf16))
        let edited = String(utf16CodeUnits: utf16, count: utf16.count)
        if edited == source { return }
        apply(edited)
    }

    private var rawSlides: [String] { parsed.slides.map(\.source) }
    /// Rebuilds the whole source from a new list of slides' raw (padded) text,
    /// keeping the front matter.
    private func rebuild(slides: [String], selected newSelected: Int) {
        apply(parsed.header + slides.joined(separator: "---\n"), selected: newSelected)
    }

    public func select(_ index: Int) { selected = index }

    public func addSlide() {
        var slides = rawSlides
        let insertAt = min(selected + 1, slides.count)
        slides.insert("\n\n", at: insertAt)
        rebuild(slides: slides, selected: insertAt)
    }
    public func duplicateSlide() {
        guard parsed.slides.indices.contains(selected) else { return }
        var slides = rawSlides
        slides.insert(slides[selected], at: selected + 1)
        rebuild(slides: slides, selected: selected + 1)
    }
    public func deleteSlide() {
        guard parsed.slides.indices.contains(selected), count > 1 else { return }
        var slides = rawSlides
        slides.remove(at: selected)
        rebuild(slides: slides, selected: min(selected, slides.count - 1))
    }
    public func moveSlide(from: Int, to: Int) {
        guard rawSlides.indices.contains(from), (0..<count).contains(to) else { return }
        var slides = rawSlides
        let moving = slides.remove(at: from)
        slides.insert(moving, at: to)
        rebuild(slides: slides, selected: to)
    }

    public func chooseTheme(_ name: String) { setHeaderValue("theme", name) }

    /// How much bigger or smaller than fitted size every slide's text renders,
    /// from the `text_scale` front-matter key (1 when absent or unreadable).
    public var textScale: Double {
        guard let value = Double(scalar(parsed.header, "text_scale")) else { return 1 }
        return TextScale.clamped(value)
    }

    /// Records a new text scale in the front matter, as one undoable edit.
    public func setTextScale(_ value: Double) {
        let rounded = TextScale.clamped((value * 100).rounded() / 100)
        guard rounded != textScale || scalar(parsed.header, "text_scale").isEmpty else { return }
        setHeaderValue("text_scale", String(format: "%g", rounded))
    }

    /// Splices a new header (with `key` set to `value`) back into the full
    /// source, replacing only the original header's bytes.
    private func setHeaderValue(_ key: String, _ value: String) {
        let newHeader = setScalar(parsed.header, key, value)
        var utf16 = Array(source.utf16)
        utf16.replaceSubrange(0..<parsed.header.utf16.count, with: Array(newHeader.utf16))
        apply(String(utf16CodeUnits: utf16, count: utf16.count))
    }

    public func newDeck() {
        path = nil
        savedSource = DeckModel.defaultSource
        undoStack.removeAll(); redoStack.removeAll()
        apply(DeckModel.defaultSource, selected: 0, pushUndo: false)
        canUndo = false; canRedo = false
    }

    @discardableResult
    public func loadPath(_ filePath: String) -> Bool {
        guard let text = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            status = "Could not read \(filePath)"
            return false
        }
        path = filePath
        savedSource = text
        undoStack.removeAll(); redoStack.removeAll()
        apply(text, selected: 0, pushUndo: false)
        canUndo = false; canRedo = false
        RecentPresentations.record(filePath)
        return true
    }

    @discardableResult
    public func save() -> Bool {
        guard let path else { return false }
        return savePath(path)
    }
    @discardableResult
    public func savePath(_ filePath: String) -> Bool {
        do {
            try source.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch { return false }
        path = filePath
        savedSource = source
        return true
    }
}
