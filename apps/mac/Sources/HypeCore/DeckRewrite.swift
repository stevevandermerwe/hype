import Foundation

/// A whole-deck AI rewrite ("make it more concise", "translate to Spanish"): the
/// request sent to the model, and the checks a reply must pass before it may
/// replace the deck's slides. A reply that doesn't pass is refused outright, so
/// a bad answer changes nothing.
public struct DeckRewriteResult: Equatable, Sendable {
    /// The rewritten slides, one per original slide; empty when `error` is set.
    public var slides: [String] = []
    /// How many of them differ from the original.
    public var changed = 0
    public var error = ""
}

private func plural(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }

/// The message sent for a deck rewrite: every slide in order, each under a
/// `=== SLIDE n ===` line, then the request.
public func deckRewriteRequest(instruction: String, slides: [String]) -> String {
    var lines = ["The deck has \(plural(slides.count, "slide")). Rewrite it as requested and return every slide, in the same order, "
                 + "each under its own marker line.", ""]
    for (index, slide) in slides.enumerated() {
        lines.append("=== SLIDE \(index + 1) ===")
        lines.append(slide.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    lines.append("")
    lines.append("Request: " + instruction.trimmingCharacters(in: .whitespacesAndNewlines))
    return lines.joined(separator: "\n")
}

let slideMarkerRe = try! NSRegularExpression(pattern: #"^=== SLIDE (\d+) ===\s*$"#)

/// Parses and validates a rewrite reply against the `original` slides: it must
/// hold exactly one non-empty, single slide per original, numbered in order.
/// Pictures are reconciled with the originals: one the model dropped is put
/// back, a changed file is restored (keeping the new layout options), and one
/// the model invented is removed.
public func parseDeckRewriteReply(_ text: String, original: [String]) -> DeckRewriteResult {
    var result = DeckRewriteResult()
    var blocks: [(number: Int, lines: [String])] = []
    for line in unfenced(text).components(separatedBy: "\n") {
        let ns = line as NSString
        if let match = slideMarkerRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
           let number = Int(ns.substring(with: match.range(at: 1))) {
            blocks.append((number, []))
        } else if !blocks.isEmpty {
            blocks[blocks.count - 1].lines.append(line) // anything before the first marker is chatter
        }
    }
    guard !blocks.isEmpty else {
        result.error = "The model's reply had no slides in it. Nothing was changed."
        return result
    }
    guard blocks.count == original.count else {
        result.error = "The model returned \(plural(blocks.count, "slide")) but the deck has \(original.count). "
                     + "Nothing was changed; try a narrower request."
        return result
    }
    guard blocks.enumerated().allSatisfy({ $0.element.number == $0.offset + 1 }) else {
        result.error = "The model returned the slides out of order or repeated one. Nothing was changed."
        return result
    }
    var slides: [String] = []
    for (index, block) in blocks.enumerated() {
        let slide = block.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if slide.isEmpty {
            result.error = "The model returned an empty slide \(index + 1). Nothing was changed."
            return result
        }
        if hasSlideSeparator(slide) {
            result.error = "The model returned more than one slide in slide \(index + 1). Try again with a narrower request."
            return result
        }
        slides.append(reconcilePicture(original: original[index], rewritten: slide))
    }
    result.slides = slides
    result.changed = zip(slides, original).filter { $0 != $1.trimmingCharacters(in: .whitespacesAndNewlines) }.count
    return result
}

/// Makes the rewritten slide's picture the original's (see `parseDeckRewriteReply`).
private func reconcilePicture(original: String, rewritten: String) -> String {
    let originalMedia = parseMedia(original, base: "")
    let newMedia = parseMedia(rewritten, base: "")
    switch (originalMedia.file.isEmpty, newMedia.file.isEmpty) {
    case (true, true):
        return rewritten
    case (true, false):
        guard let match = firstReference(in: rewritten) else { return rewritten }
        let removed = (rewritten as NSString).replacingCharacters(in: match.range, with: "")
        return tidy(removed)
    case (false, true):
        guard let match = firstReference(in: original) else { return rewritten }
        return rewritten.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + (original as NSString).substring(with: match.range)
    case (false, false):
        return originalMedia.file == newMedia.file ? rewritten : setImageFile(originalMedia.file, in: rewritten).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Trims and collapses runs of blank lines left behind by removing something.
private func tidy(_ text: String) -> String {
    text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
