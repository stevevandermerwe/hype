import Foundation

/// AI-suggested speaker notes. A note lives in the slide as a hidden
/// `<!-- comment -->`, which the slide never shows (see `format.md`), so adding
/// one can't change how a slide looks or exports.

private let noteCommentRe = try! NSRegularExpression(pattern: "<!--([\\s\\S]*?)-->")

/// The slide's existing speaker note (all its comments, outside code), or nil.
public func speakerNote(in slide: String) -> String? {
    let masked = outsideCode(slide)
    let ns = masked as NSString
    var notes: [String] = []
    noteCommentRe.enumerateMatches(in: masked, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
        guard let match else { return }
        let text = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { notes.append(text) }
    }
    return notes.isEmpty ? nil : notes.joined(separator: "\n\n")
}

/// The message sent to draft notes: the whole deck for context (without its
/// existing notes), which slides need notes, and any style guidance.
public func speakerNotesRequest(slides: [String], targets: [Int], guidance: String) -> String {
    var lines = ["The deck has \(slides.count) slide\(slides.count == 1 ? "" : "s"):", ""]
    for (index, slide) in slides.enumerated() {
        lines.append("=== SLIDE \(index + 1) ===")
        lines.append(withoutComments(slide).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    lines.append("")
    lines.append("Write notes for slides: " + targets.sorted().map { String($0 + 1) }.joined(separator: ", "))
    let style = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
    if !style.isEmpty { lines.append("Guidance: " + style) }
    return lines.joined(separator: "\n")
}

public struct SpeakerNotesResult: Equatable, Sendable {
    /// Note text by 0-based slide index, only for slides that were asked for.
    public var notes: [Int: String] = [:]
    public var error = ""
}

/// Note text with comment markers removed (so a note can't close its own
/// comment and inject slide content), spaces tidied, and blank-line runs collapsed.
func cleanNoteText(_ text: String) -> String {
    let stripped = text.replacingOccurrences(of: "<!--", with: "").replacingOccurrences(of: "-->", with: "")
    let lines = stripped.components(separatedBy: "\n").map { line in
        line.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    return lines.joined(separator: "\n")
        .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Splits a reply of `=== SLIDE n ===` blocks into notes for the `wanted`
/// slides (0-based). Blocks for other slides, and empty ones, are ignored; a
/// reply with no usable note at all is an error.
public func parseSpeakerNotesReply(_ text: String, wanted: [Int]) -> SpeakerNotesResult {
    var result = SpeakerNotesResult()
    var blocks: [(index: Int, lines: [String])] = []
    for line in unfenced(text).components(separatedBy: "\n") {
        let ns = line as NSString
        if let match = slideMarkerRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
           let number = Int(ns.substring(with: match.range(at: 1))) {
            blocks.append((number - 1, []))
        } else if !blocks.isEmpty {
            blocks[blocks.count - 1].lines.append(line)
        }
    }
    for block in blocks where wanted.contains(block.index) && result.notes[block.index] == nil {
        let note = cleanNoteText(block.lines.joined(separator: "\n"))
        if !note.isEmpty { result.notes[block.index] = note }
    }
    if result.notes.isEmpty {
        result.error = "The model didn't return any notes for those slides. Nothing was changed."
    }
    return result
}

/// Writes each note into its slide (see `settingNote`), reporting how many slides
/// got one and how many were skipped because they already have a note.
public func applyingNotes(_ notes: [Int: String], to slides: [String], replacing: Bool)
    -> (slides: [String], added: Int, skipped: Int) {
    var result = slides
    var added = 0, skipped = 0
    for (index, note) in notes.sorted(by: { $0.key < $1.key }) where slides.indices.contains(index) {
        if let updated = settingNote(note, in: slides[index], replacing: replacing) {
            result[index] = updated
            added += 1
        } else {
            skipped += 1
        }
    }
    return (result, added, skipped)
}

/// Puts `note` at the end of `slide` as a hidden comment. A slide that already
/// has a note is left alone (nil) unless `replacing`, which swaps its comments
/// for the new note.
public func settingNote(_ note: String, in slide: String, replacing: Bool) -> String? {
    let clean = cleanNoteText(note)
    guard !clean.isEmpty else { return nil }
    let hasNote = speakerNote(in: slide) != nil
    if hasNote, !replacing { return nil }
    let base = (hasNote ? withoutComments(slide) : slide).trimmingCharacters(in: .whitespacesAndNewlines)
    let comment = clean.contains("\n") ? "<!--\n\(clean)\n-->" : "<!-- \(clean) -->"
    return base.isEmpty ? comment : base + "\n\n" + comment
}
