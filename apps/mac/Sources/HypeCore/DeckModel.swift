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

    /// Where custom themes are looked up (tests give it a temporary folder).
    public let themes: ThemeStore

    /// Where recovery snapshots of unsaved edits are kept; nil (the default, used
    /// by the CLI and tests) keeps none. The app passes `RecoveryStore.shared`.
    public let recovery: RecoveryStore?
    /// Whether saving over an existing file first keeps a timestamped backup of it.
    public var keepsBackups = true
    /// How long after an edit (and its last neighbour) the recovery snapshot is written.
    public var recoveryDelay: TimeInterval = 2
    private let sessionID = UUID().uuidString
    private var recoveryTicket = 0
    private var snapshotKeysWritten = Set<String>()

    public init(source: String = DeckModel.defaultSource, themes: ThemeStore = .shared, recovery: RecoveryStore? = nil) {
        self.themes = themes
        self.recovery = recovery
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
    public var palette: Palette { HypeCore.palette(forTheme: themeName, header: parsed.header, store: themes) }
    /// Where this deck's `images/`/`videos/` live; empty until it has a path.
    public var baseDir: String { path.map { ($0 as NSString).deletingLastPathComponent } ?? "" }

    /// Every slide's text (padding trimmed), in order.
    public var slideTexts: [String] { (0..<count).map { slideText(at: $0) } }

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
        scheduleRecoverySnapshot()
    }

    // MARK: Recovery

    /// The recovery key for the deck as it is now: its file's, or this session's if unsaved.
    public var recoveryKey: String { path.map(RecoveryStore.key(forPath:)) ?? RecoveryStore.untitledKey(sessionID) }

    private func scheduleRecoverySnapshot() {
        guard recovery != nil else { return }
        recoveryTicket += 1
        let ticket = recoveryTicket
        DispatchQueue.main.asyncAfter(deadline: .now() + recoveryDelay) { [weak self] in
            guard let self, self.recoveryTicket == ticket else { return }
            self.flushRecoverySnapshot()
        }
    }

    /// Writes the recovery snapshot now if the deck has unsaved edits; if it is
    /// back to matching its file (say, after undo), removes the snapshot this
    /// session wrote. (A snapshot from an earlier session is left for the start
    /// page to offer.)
    public func flushRecoverySnapshot() {
        guard let recovery else { return }
        let key = recoveryKey
        if dirty {
            if (try? recovery.snapshot(key: key, source: source, path: path, title: title)) != nil { snapshotKeysWritten.insert(key) }
        } else if snapshotKeysWritten.remove(key) != nil {
            recovery.discard(key: key)
        }
    }

    /// Removes this deck's snapshot (for "Don't Save", or once it is saved).
    public func discardRecoverySnapshot() {
        recovery?.discard(key: recoveryKey)
        snapshotKeysWritten.remove(recoveryKey)
    }

    /// Brings a snapshot back as this deck: its text becomes the unsaved edits to
    /// its file (or to a deck with no file yet), so it can be saved deliberately.
    public func restore(_ snapshot: RecoverySnapshot) {
        path = snapshot.path
        savedSource = snapshot.path.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
        undoStack.removeAll(); redoStack.removeAll()
        apply(snapshot.source, selected: 0, pushUndo: false)
        canUndo = false; canRedo = false
        recovery?.discard(key: snapshot.key)
        if let restoredPath = snapshot.path { RecentPresentations.record(restoredPath) }
        flushRecoverySnapshot()
    }

    public func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append((source, selected))
        source = last.source
        parsed = parseDeck(source)
        selected = last.selected
        canUndo = !undoStack.isEmpty
        canRedo = true
        scheduleRecoverySnapshot()
    }
    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((source, selected))
        source = next.source
        parsed = parseDeck(source)
        selected = next.selected
        canUndo = true
        canRedo = !redoStack.isEmpty
        scheduleRecoverySnapshot()
    }

    /// Validates and applies a new complete Markdown source. Returns `true` when
    /// the source parses cleanly (slide separators and fenced code blocks) and
    /// its front matter is valid YAML. Invalid edits set `status` and leave the
    /// deck unchanged, so the source editor can keep the user's text while
    /// showing the problem.
    @discardableResult
    public func editSource(_ text: String) -> Bool {
        guard text != source else { return true }
        let candidate = parseDeck(text)
        if !candidate.error.isEmpty {
            status = candidate.error
            return false
        }
        if !candidate.header.isEmpty, !isValidYAMLHeader(candidate.header) {
            status = "Front matter is not valid YAML"
            return false
        }
        apply(text)
        status = ""
        return true
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

    /// Replaces every slide's text at once — one undoable edit that keeps the
    /// front matter and (clamped) selection. Used for whole-deck AI changes.
    /// An empty list is ignored.
    public func replaceSlides(_ texts: [String]) {
        guard !texts.isEmpty else { return }
        let last = texts.count - 1
        let padded = texts.enumerated().map { index, text -> String in
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lead = index > 0 || !parsed.header.isEmpty ? "\n" : ""
            return lead + body + (index < last ? "\n\n" : "\n")
        }
        let updated = parsed.header + padded.joined(separator: "---\n")
        guard updated != source else { return }
        apply(updated, selected: min(selected, last))
    }

    /// Adds a slide with `text` after slide `index` (at the end if `index` is past
    /// it) and selects it — one undoable edit.
    public func insertSlide(_ text: String, after index: Int) {
        var texts = slideTexts
        let position = min(max(0, index + 1), texts.count)
        texts.insert(text, at: position)
        replaceSlides(texts)
        select(position)
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

    /// Chooses a theme by name. Colours left in the front matter by an earlier
    /// choice (which would override the new theme) are cleared; for one of your
    /// own themes its colours are written in, so the deck looks the same on a
    /// Mac that doesn't have the theme. One undoable edit.
    public func chooseTheme(_ name: String) {
        var header = parsed.header
        for key in Palette.colorKeys { header = removeScalar(header, "color_\(key)") }
        header = setScalar(header, "theme", name)
        if BundledTheme(rawValue: name) == nil, let palette = themes.palette(named: name) {
            for key in Palette.colorKeys { header = setScalar(header, "color_\(key)", palette[key]) }
        }
        replaceHeader(header)
    }

    /// The deck's `font:` — a font name, or "" for the system font.
    public var fontName: String { scalar(parsed.header, "font") }

    /// Sets the deck's font, or clears it (system font) when `name` is empty —
    /// one undoable edit.
    public func setFontName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != fontName else { return }
        if trimmed.isEmpty {
            replaceHeader(removeScalar(parsed.header, "font"))
        } else {
            setHeaderValue("font", trimmed)
        }
    }

    // MARK: Header & Page Number Front Matter

    /// Whether page numbers are displayed when presenting/rendering.
    public var showPageNumber: Bool {
        let raw = scalar(parsed.header, "show_page_number", scalar(parsed.header, "page_number", scalar(parsed.header, "page_numbers", scalar(parsed.header, "show_page_numbers"))))
        return parseBoolScalar(raw) ?? false
    }

    /// Sets whether page numbers are displayed in front matter.
    public func setShowPageNumber(_ show: Bool) {
        if show {
            setHeaderValue("show_page_number", "true")
        } else {
            var header = parsed.header
            header = removeScalar(header, "show_page_number")
            header = removeScalar(header, "page_number")
            header = removeScalar(header, "page_numbers")
            header = removeScalar(header, "show_page_numbers")
            replaceHeader(header)
        }
    }

    /// Where the presentation title is placed (.top or .bottom).
    public var titlePosition: SlideHeaderOptions.TitlePosition {
        let raw = scalar(parsed.header, "title_position", scalar(parsed.header, "header_position", scalar(parsed.header, "title_location", "top"))).lowercased()
        return raw == "bottom" ? .bottom : .top
    }

    /// Sets title position in front matter.
    public func setTitlePosition(_ position: SlideHeaderOptions.TitlePosition) {
        setHeaderValue("title_position", position.rawValue)
    }

    /// Whether the presentation title is displayed in headers/footers.
    public var showTitle: Bool {
        let raw = scalar(parsed.header, "show_title", scalar(parsed.header, "title_display"))
        if let b = parseBoolScalar(raw) { return b }
        let hasPos = !scalar(parsed.header, "title_position").isEmpty || !scalar(parsed.header, "header_position").isEmpty
        let hasStyle = !scalar(parsed.header, "title_color").isEmpty || !scalar(parsed.header, "title_style").isEmpty || !scalar(parsed.header, "header_color").isEmpty || !scalar(parsed.header, "header_style").isEmpty
        return hasPos || hasStyle
    }

    /// Sets whether the presentation title is displayed in front matter.
    public func setShowTitle(_ show: Bool) {
        setHeaderValue("show_title", show ? "true" : "false")
    }

    /// Custom color hex for presentation title text.
    public var titleColorHex: String {
        scalar(parsed.header, "title_color", scalar(parsed.header, "header_color"))
    }

    /// Sets presentation title color in front matter.
    public func setTitleColorHex(_ hex: String) {
        if hex.trimmingCharacters(in: .whitespaces).isEmpty {
            var header = parsed.header
            header = removeScalar(header, "title_color")
            header = removeScalar(header, "header_color")
            replaceHeader(header)
        } else {
            setHeaderValue("title_color", hex)
        }
    }

    /// Custom style string for presentation title text (e.g., "bold", "italic", "uppercase").
    public var titleStyle: String {
        scalar(parsed.header, "title_style", scalar(parsed.header, "header_style"))
    }

    /// Sets presentation title style in front matter.
    public func setTitleStyle(_ style: String) {
        if style.trimmingCharacters(in: .whitespaces).isEmpty {
            var header = parsed.header
            header = removeScalar(header, "title_style")
            header = removeScalar(header, "header_style")
            replaceHeader(header)
        } else {
            setHeaderValue("title_style", style)
        }
    }

    /// Custom color hex for page number text.
    public var pageNumberColorHex: String {
        scalar(parsed.header, "page_number_color")
    }

    /// Position for page number text (.top or .bottom).
    public var pageNumberPosition: SlideHeaderOptions.PagePosition? {
        let raw = scalar(parsed.header, "page_number_position", scalar(parsed.header, "page_position")).lowercased()
        if raw.contains("top") { return .top }
        if raw.contains("bottom") { return .bottom }
        return nil
    }

    /// Sets the page-number position, or removes it (back to the default) when nil.
    public func setPageNumberPosition(_ position: SlideHeaderOptions.PagePosition?) {
        if let position {
            setHeaderValue("page_number_position", position.rawValue)
        } else {
            var header = parsed.header
            header = removeScalar(header, "page_number_position")
            header = removeScalar(header, "page_position")
            replaceHeader(header)
        }
    }

    /// Sets the page-number color, or clears the override when `hex` is empty.
    public func setPageNumberColorHex(_ hex: String) {
        if hex.trimmingCharacters(in: .whitespaces).isEmpty {
            replaceHeader(removeScalar(parsed.header, "page_number_color"))
        } else {
            setHeaderValue("page_number_color", hex)
        }
    }

    /// The `title:` scalar exactly as written, or "" when absent (unlike `title`,
    /// which falls back to the file name).
    public var titleValue: String { scalar(parsed.header, "title") }

    /// Sets `title:`, or removes it (so the file name is used) when empty.
    public func setTitle(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            replaceHeader(removeScalar(parsed.header, "title"))
        } else {
            setHeaderValue("title", trimmed)
        }
    }

    /// The title styles currently set, as a set of lowercase tokens.
    public var titleStyleTokens: Set<String> {
        Set(titleStyle.lowercased().split(separator: " ").map(String.init))
    }

    /// Replaces `title_style` with the given tokens (bold, italic, uppercase,
    /// underline); an empty set removes the key.
    public func setTitleStyleTokens(_ tokens: Set<String>) {
        setTitleStyle(tokens.sorted().joined(separator: " "))
    }

    // MARK: Per-color overrides (`color_*`)

    /// The `color_*` overrides currently written in the front matter, keyed
    /// without the `color_` prefix.
    public var colorOverrides: [String: String] {
        var result: [String: String] = [:]
        for key in Palette.colorKeys {
            let value = scalar(parsed.header, "color_\(key)")
            if !value.isEmpty { result[key] = value }
        }
        return result
    }

    /// The effective color for a palette key: the `color_*` override when set,
    /// otherwise the theme's own color.
    public func colorHex(for key: String) -> String {
        colorOverrides[key] ?? palette[key]
    }

    /// Sets one `color_*` override, or removes it (back to the theme's color)
    /// when `hex` is empty.
    public func setColorHex(_ hex: String, for key: String) {
        if hex.trimmingCharacters(in: .whitespaces).isEmpty {
            replaceHeader(removeScalar(parsed.header, "color_\(key)"))
        } else {
            setHeaderValue("color_\(key)", hex)
        }
    }

    /// Removes every `color_*` override, returning the deck to its theme.
    public func clearColorOverrides() {
        var header = parsed.header
        for key in Palette.colorKeys { header = removeScalar(header, "color_\(key)") }
        replaceHeader(header)
    }

    /// Full header & footer configuration for rendering.
    public func headerOptions(forIndex index: Int? = nil) -> SlideHeaderOptions {
        SlideHeaderOptions(
            showPageNumber: showPageNumber,
            slideIndex: index,
            slideCount: count,
            presentationTitle: title,
            showTitle: showTitle,
            titlePosition: titlePosition,
            titleColorHex: titleColorHex,
            titleStyle: titleStyle,
            pageNumberColorHex: pageNumberColorHex,
            pageNumberPosition: pageNumberPosition
        )
    }

    /// Swaps in a new front-matter block, leaving every slide's bytes alone.
    private func replaceHeader(_ newHeader: String) {
        guard newHeader != parsed.header else { return }
        var utf16 = Array(source.utf16)
        utf16.replaceSubrange(0..<parsed.header.utf16.count, with: Array(newHeader.utf16))
        apply(String(utf16CodeUnits: utf16, count: utf16.count))
    }

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
        if keepsBackups { Backups.backupBeforeOverwriting(path: filePath, newContent: source) }
        do {
            try source.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch { return false }
        discardRecoverySnapshot()
        path = filePath
        savedSource = source
        discardRecoverySnapshot()
        return true
    }
}
