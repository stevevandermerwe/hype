import Foundation

/// What an editor-assist button does to the Markdown source. The Qt editor
/// (`src/Markdown.js`) offers headline, bold, italic, underline, code, and
/// comment; this adds lists, quotes, inline code, and a table. Hype has a single
/// headline level (`# `), so there is one `heading` action, not H1–H3.
public enum FormatAction: Equatable, Sendable {
    case heading
    case bold, italic, underline, inlineCode
    /// A hidden `<!-- speaker note -->`.
    case note
    case bulletList, numberedList, quote
    /// A fenced block; `language` is what the highlighter is told ("" for none).
    case codeBlock(language: String)
    case table
}

/// The new text and where the selection should be afterwards. Ranges are
/// UTF-16 offsets, as in `NSTextView`/`NSString`.
public struct EditResult: Equatable, Sendable {
    public var text: String
    public var selection: NSRange
}

/// Applies `action` to `text` at `selection`. The result is one complete edit,
/// so it can be applied (and undone) as a single change. Styles toggle: doing
/// the same thing twice puts the text back.
public func applyFormat(_ action: FormatAction, to text: String, selection: NSRange) -> EditResult {
    let length = (text as NSString).length
    let location = min(max(0, selection.location), length)
    let range = NSRange(location: location, length: min(max(0, selection.length), length - location))
    switch action {
    case .bold: return wrapInline(InlineStyle(open: "**", close: "**", placeholder: "bold text"), text, range)
    case .italic: return wrapInline(InlineStyle(open: "*", close: "*", placeholder: "italic text", oddRuns: true), text, range)
    case .underline: return wrapInline(InlineStyle(open: "_", close: "_", placeholder: "underlined text"), text, range)
    case .inlineCode: return wrapInline(InlineStyle(open: "`", close: "`", placeholder: "code"), text, range)
    case .note: return wrapInline(InlineStyle(open: "<!-- ", close: " -->", placeholder: "Speaker note"), text, range)
    case .heading: return editLines(text, range, placeholder: "Headline", plan: headingPlan)
    case .bulletList: return editLines(text, range, placeholder: "Item", plan: bulletPlan)
    case .numberedList: return editLines(text, range, placeholder: "Item", plan: numberedPlan)
    case .quote: return editLines(text, range, placeholder: "Quote", plan: quotePlan)
    case .codeBlock(let language): return insertCodeBlock(language, text, range)
    case .table: return insertTable(text, range)
    }
}

// MARK: - Inline styles

private struct InlineStyle {
    var open: String
    var close: String
    var placeholder: String
    /// Italic's `*` must not be mistaken for half of bold's `**`, so its
    /// markers only count when each side is an odd-length run of asterisks.
    var oddRuns = false

    func isWrapped(_ s: NSString, opening: NSRange, closing: NSRange) -> Bool {
        guard opening.length == open.utf16.count, closing.length == close.utf16.count,
              s.substring(with: opening) == open, s.substring(with: closing) == close else { return false }
        return true
    }
}

private func trailingRun(_ s: NSString, of char: unichar, endingAt end: Int) -> Int {
    var count = 0
    while end - count > 0, s.character(at: end - count - 1) == char { count += 1 }
    return count
}
private func leadingRun(_ s: NSString, of char: unichar, from start: Int) -> Int {
    var count = 0
    while start + count < s.length, s.character(at: start + count) == char { count += 1 }
    return count
}

private func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }

private func wrapInline(_ style: InlineStyle, _ text: String, _ selection: NSRange) -> EditResult {
    let ns = text as NSString
    let selected = ns.substring(with: selection)
    if selected.contains("\n") { return wrapLineByLine(style, ns, selection) }

    // Keep surrounding spaces outside the markers: "**word **" isn't bold.
    var range = selection
    while range.length > 0, isSpace(ns.character(at: range.location)) { range.location += 1; range.length -= 1 }
    while range.length > 0, isSpace(ns.character(at: range.location + range.length - 1)) { range.length -= 1 }
    if range.length == 0, selection.length > 0 { range = NSRange(location: selection.location, length: 0) }
    range = skippingLinePrefix(ns, range)

    let openLen = style.open.utf16.count, closeLen = style.close.utf16.count
    let end = range.location + range.length

    // Markers just outside the selection: remove them.
    if range.location >= openLen, end + closeLen <= ns.length,
       style.isWrapped(ns, opening: NSRange(location: range.location - openLen, length: openLen),
                       closing: NSRange(location: end, length: closeLen)),
       !style.oddRuns || (trailingRun(ns, of: 0x2A, endingAt: range.location) % 2 == 1
                          && leadingRun(ns, of: 0x2A, from: end) % 2 == 1) {
        let outer = NSRange(location: range.location - openLen, length: range.length + openLen + closeLen)
        let inner = ns.substring(with: range)
        return EditResult(text: ns.replacingCharacters(in: outer, with: inner),
                          selection: NSRange(location: outer.location, length: range.length))
    }
    // Markers inside the selection (the whole "**word**" is selected): remove them.
    if range.length >= openLen + closeLen,
       style.isWrapped(ns, opening: NSRange(location: range.location, length: openLen),
                       closing: NSRange(location: end - closeLen, length: closeLen)),
       !style.oddRuns || (leadingRun(ns, of: 0x2A, from: range.location) % 2 == 1
                          && trailingRun(ns, of: 0x2A, endingAt: end) % 2 == 1) {
        let inner = ns.substring(with: NSRange(location: range.location + openLen, length: range.length - openLen - closeLen))
        return EditResult(text: ns.replacingCharacters(in: range, with: inner),
                          selection: NSRange(location: range.location, length: inner.utf16.count))
    }
    let body = range.length == 0 ? style.placeholder : ns.substring(with: range)
    return EditResult(text: ns.replacingCharacters(in: range, with: style.open + body + style.close),
                      selection: NSRange(location: range.location + openLen, length: body.utf16.count))
}

/// Inline Markdown doesn't span lines, so a multi-line selection gets each
/// non-blank line wrapped on its own (or unwrapped, if all already are). A
/// heading, list, or quote marker at the start of a line stays outside.
private func wrapLineByLine(_ style: InlineStyle, _ ns: NSString, _ selection: NSRange) -> EditResult {
    struct Parts { var lead: String; var core: String; var trail: String }
    let parts = ns.substring(with: selection).components(separatedBy: "\n").map { line -> Parts in
        let marker = structuralPrefixLength(line)
        let body = (line as NSString).substring(from: marker)
        let core = body.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return Parts(lead: line, core: "", trail: "") }
        let lead = (line as NSString).substring(to: marker) + String(body.prefix(while: { $0 == " " || $0 == "\t" }))
        return Parts(lead: lead, core: core, trail: String(body.reversed().prefix(while: { $0 == " " || $0 == "\t" })))
    }
    let filled = parts.filter { !$0.core.isEmpty }
    let allWrapped = !filled.isEmpty && filled.allSatisfy {
        $0.core.count >= style.open.count + style.close.count && $0.core.hasPrefix(style.open) && $0.core.hasSuffix(style.close)
    }
    let rewritten = parts.map { part -> String in
        guard !part.core.isEmpty else { return part.lead }
        let core = allWrapped ? String(part.core.dropFirst(style.open.count).dropLast(style.close.count))
                              : style.open + part.core + style.close
        return part.lead + core + part.trail
    }.joined(separator: "\n")
    return EditResult(text: ns.replacingCharacters(in: selection, with: rewritten),
                      selection: NSRange(location: selection.location, length: rewritten.utf16.count))
}

/// Length of a heading, list, or quote marker at the start of `line` (0 if none).
private func structuralPrefixLength(_ line: String) -> Int {
    prefixLength(headingRe, line) ?? listMarker(line)?.length ?? prefixLength(quoteRe, line) ?? 0
}

/// Moves the start of a selection that begins on or inside a line's marker
/// ("- ", "1. ", "# ", "> ") to just after it, so styling covers the text and
/// leaves the marker alone. A caret, or a selection wholly inside the marker,
/// is left as is.
private func skippingLinePrefix(_ ns: NSString, _ range: NSRange) -> NSRange {
    guard range.length > 0 else { return range }
    var lineRange = ns.lineRange(for: NSRange(location: range.location, length: 0))
    if lineRange.length > 0, ns.character(at: lineRange.location + lineRange.length - 1) == 10 { lineRange.length -= 1 }
    let prefix = structuralPrefixLength(ns.substring(with: lineRange))
    let contentStart = lineRange.location + prefix
    let end = range.location + range.length
    guard prefix > 0, range.location < contentStart, end > contentStart else { return range }
    return NSRange(location: contentStart, length: end - contentStart)
}

// MARK: - Line styles

/// Replace `drop` characters at `location` in one line with `insert`.
private struct LineChange {
    var location = 0
    var drop = 0
    var insert = ""
}

private let headingRe = try! NSRegularExpression(pattern: "^#{1,6} ")
private let markerRe = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d+[.)])[ \t]+"#)
private let quoteRe = try! NSRegularExpression(pattern: "^>+ ?")

private func prefixLength(_ re: NSRegularExpression, _ line: String) -> Int? {
    re.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count))?.range.length
}
private func isBlank(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).isEmpty }
private func indentLength(_ line: String) -> Int { line.prefix(while: { $0 == " " || $0 == "\t" }).utf16.count }

/// A list marker at the start of `line`: its indent, total length (indent +
/// marker + spaces), and whether it is a number rather than a bullet.
private func listMarker(_ line: String) -> (indent: Int, length: Int, numbered: Bool)? {
    guard let match = markerRe.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else { return nil }
    let ns = line as NSString
    let marker = ns.substring(with: match.range(at: 2))
    return (match.range(at: 1).length, match.range.length, marker.first?.isNumber == true)
}

private func headingPlan(_ lines: [String]) -> [LineChange] {
    let remove = lines.filter { !isBlank($0) }.allSatisfy { prefixLength(headingRe, $0) != nil }
    return lines.map { line in
        isBlank(line) ? LineChange() : LineChange(location: 0, drop: prefixLength(headingRe, line) ?? 0, insert: remove ? "" : "# ")
    }
}

private func bulletPlan(_ lines: [String]) -> [LineChange] {
    let remove = lines.filter { !isBlank($0) }.allSatisfy { listMarker($0).map { !$0.numbered } ?? false }
    return lines.map { line in
        guard !isBlank(line) else { return LineChange() }
        if let marker = listMarker(line) {
            return LineChange(location: marker.indent, drop: marker.length - marker.indent, insert: remove ? "" : "- ")
        }
        return LineChange(location: indentLength(line), drop: 0, insert: "- ")
    }
}

private func numberedPlan(_ lines: [String]) -> [LineChange] {
    let remove = lines.filter { !isBlank($0) }.allSatisfy { listMarker($0)?.numbered ?? false }
    var number = 0
    return lines.map { line in
        guard !isBlank(line) else { return LineChange() }
        number += 1
        let label = remove ? "" : "\(number). "
        if let marker = listMarker(line) {
            return LineChange(location: marker.indent, drop: marker.length - marker.indent, insert: label)
        }
        return LineChange(location: indentLength(line), drop: 0, insert: label)
    }
}

private func quotePlan(_ lines: [String]) -> [LineChange] {
    let remove = lines.filter { !isBlank($0) }.allSatisfy { $0.hasPrefix(">") }
    return lines.map { line in
        guard !isBlank(line) else { return LineChange() }
        if remove { return LineChange(location: 0, drop: prefixLength(quoteRe, line) ?? 0, insert: "") }
        return line.hasPrefix(">") ? LineChange() : LineChange(location: 0, drop: 0, insert: "> ")
    }
}

/// Applies a per-line plan to every line the selection touches, keeping the
/// selection on the same characters. If all those lines are blank, inserts the
/// styled `placeholder` instead, selected, so there is something to type over.
private func editLines(_ text: String, _ selection: NSRange, placeholder: String,
                       plan: ([String]) -> [LineChange]) -> EditResult {
    let ns = text as NSString
    var last = selection.location + selection.length
    if selection.length > 0, ns.character(at: last - 1) == 10 { last -= 1 }
    var block = ns.lineRange(for: NSRange(location: selection.location, length: last - selection.location))
    if block.length > 0, ns.character(at: block.location + block.length - 1) == 10 { block.length -= 1 }
    let lines = ns.substring(with: block).components(separatedBy: "\n")

    func rewrite(_ line: String, _ change: LineChange) -> String {
        let l = line as NSString
        return l.substring(to: change.location) + change.insert + l.substring(from: change.location + change.drop)
    }

    if lines.allSatisfy(isBlank) {
        let change = plan([placeholder])[0]
        let line = rewrite(placeholder, change)
        return EditResult(text: ns.replacingCharacters(in: block, with: line),
                          selection: NSRange(location: block.location + change.insert.utf16.count, length: placeholder.utf16.count))
    }

    let changes = plan(lines)
    let rewritten = zip(lines, changes).map(rewrite)
    let newBlock = rewritten.joined(separator: "\n")

    func map(_ position: Int) -> Int {
        var oldOffset = block.location, newOffset = block.location
        for (index, line) in lines.enumerated() {
            let oldLength = line.utf16.count
            if position <= oldOffset + oldLength {
                let p = max(0, position - oldOffset), c = changes[index]
                if p < c.location { return newOffset + p }
                if p <= c.location + c.drop { return newOffset + c.location + c.insert.utf16.count }
                return newOffset + p - c.drop + c.insert.utf16.count
            }
            oldOffset += oldLength + 1
            newOffset += rewritten[index].utf16.count + 1
        }
        return position - (block.location + block.length) + block.location + newBlock.utf16.count
    }
    let start = map(selection.location), end = map(selection.location + selection.length)
    return EditResult(text: ns.replacingCharacters(in: block, with: newBlock),
                      selection: NSRange(location: start, length: end - start))
}

// MARK: - Blocks

private func insertCodeBlock(_ language: String, _ text: String, _ selection: NSRange) -> EditResult {
    let ns = text as NSString
    let selected = ns.substring(with: selection)
    let before = ns.substring(to: selection.location)
    let after = ns.substring(from: selection.location + selection.length)
    var fence = "```"
    while selected.contains(fence) { fence += "`" }
    let body = selected.isEmpty ? "code" : selected
    let open = (before.isEmpty || before.hasSuffix("\n") ? "" : "\n") + fence + language + "\n"
    let close = "\n" + fence + (after.isEmpty || after.hasPrefix("\n") ? "" : "\n")
    return EditResult(text: ns.replacingCharacters(in: selection, with: open + body + close),
                      selection: NSRange(location: selection.location + open.utf16.count, length: body.utf16.count))
}

private func insertTable(_ text: String, _ selection: NSRange) -> EditResult {
    let ns = text as NSString
    let insertion = NSRange(location: selection.location + selection.length, length: 0)
    let before = ns.substring(to: insertion.location)
    let after = ns.substring(from: insertion.location)
    let lead = before.isEmpty || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
    let trail = after.isEmpty || after.hasPrefix("\n") ? "" : "\n"
    let table = "| Column | Column |\n| --- | --- |\n| Cell | Cell |\n"
    return EditResult(text: ns.replacingCharacters(in: insertion, with: lead + table + trail),
                      selection: NSRange(location: insertion.location + lead.utf16.count + 2, length: "Column".utf16.count))
}

// MARK: - Return key

/// What pressing Return should do when the caret is at the end of a list item
/// or quote line: start the next item (numbers count up), or, if the item is
/// empty, end the list by clearing the marker. Returns nil for anything else,
/// so the text view inserts an ordinary newline (including mid-line, which
/// should split the line as usual).
public func continueList(in text: String, caret: Int) -> EditResult? {
    let ns = text as NSString
    guard caret >= 0, caret <= ns.length else { return nil }
    let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
    var lineEnd = lineRange.location + lineRange.length
    if lineEnd > lineRange.location, ns.character(at: lineEnd - 1) == 10 { lineEnd -= 1 }
    guard caret == lineEnd else { return nil }

    let line = ns.substring(with: NSRange(location: lineRange.location, length: lineEnd - lineRange.location)) as NSString
    let whole = NSRange(location: 0, length: line.length)
    var content = ""
    var next = ""
    if let match = markerRe.firstMatch(in: line as String, range: whole) {
        let indent = line.substring(with: match.range(at: 1))
        let token = line.substring(with: match.range(at: 2))
        content = line.substring(from: match.range.length)
        if let number = Int(token.dropLast()), let delimiter = token.last {
            next = indent + "\(number + 1)\(delimiter) "
        } else {
            next = indent + token + " "
        }
    } else if line.hasPrefix(">"), let length = prefixLength(quoteRe, line as String) {
        content = line.substring(from: length)
        next = "> "
    } else {
        return nil
    }

    if content.trimmingCharacters(in: .whitespaces).isEmpty {
        let cleared = NSRange(location: lineRange.location, length: lineEnd - lineRange.location)
        return EditResult(text: ns.replacingCharacters(in: cleared, with: ""),
                          selection: NSRange(location: lineRange.location, length: 0))
    }
    let insertion = "\n" + next
    return EditResult(text: ns.replacingCharacters(in: NSRange(location: caret, length: 0), with: insertion),
                      selection: NSRange(location: caret + insertion.utf16.count, length: 0))
}
