import Foundation

public enum TableAlignment: Sendable, Equatable { case leading, center, trailing }

/// A Markdown table: a header row, body rows, and a per-column alignment from
/// the separator row (`:--` leading, `:-:` center, `--:` trailing). Every row
/// has exactly `header.count` cells.
public struct TableData: Sendable, Equatable {
    public var header: [String]
    public var rows: [[String]]
    public var alignments: [TableAlignment]
    public var columnCount: Int { header.count }

    public init(header: [String], rows: [[String]], alignments: [TableAlignment]) {
        self.header = header
        self.rows = rows
        self.alignments = alignments
    }
}

/// One piece of a slide, in reading order.
public enum SlideBlock: Sendable, Equatable {
    /// The `# Headline` (the first one on the slide).
    case headline(String)
    /// One line of body text, with list markers already applied. Blank lines are kept.
    case line(String)
    /// Fenced code. `language` is the lowercased first word after the fence ("" if none).
    case code(language: String, lines: [String])
    case table(TableData)
}

/// How a slide's text is classified for layout, matching the Qt renderer's
/// `code`/`quote`/`list`/`table` booleans (`renderer.cpp`'s `paintSlide`): it
/// decides text alignment and the largest size the text may grow to.
public enum SlideKind: Sendable, Equatable { case code, quote, list, table, plain }

public struct SlideContent: Sendable, Equatable {
    public var blocks: [SlideBlock]
    public var kind: SlideKind
}

private let fenceOpenRe = try! NSRegularExpression(pattern: "^ {0,3}(`{3,}|~{3,})(.*)$")
private let listItemRe = try! NSRegularExpression(pattern: #"^\s*(?:([-*+])\s+|(\d+)([.)])\s+)"#)
private let separatorCellRe = try! NSRegularExpression(pattern: "^:?-+:?$")

private enum Segment {
    case text(String)
    case code(String, [String])
    case table(TableData)
}

/// Splits a slide's text (with any media reference and comments already
/// removed) into blocks. See `SlideBlock` and `SlideKind`.
public func parseSlideContent(_ text: String) -> SlideContent {
    let trimmed = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return SlideContent(blocks: [], kind: .plain) }
    let segments = segment(trimmed.components(separatedBy: "\n"))

    let textLines = segments.compactMap { segment -> String? in
        if case .text(let line) = segment { return line }
        return nil
    }
    let hasCode = segments.contains { if case .code = $0 { return true } else { return false } }
    let hasTable = segments.contains { if case .table = $0 { return true } else { return false } }
    let kind: SlideKind
    if hasCode { kind = .code }
    else if trimmed.hasPrefix(">") { kind = .quote }
    else if textLines.contains(where: { matches(listItemRe, $0) }) { kind = .list }
    else if hasTable { kind = .table }
    else { kind = .plain }

    var headlineTaken = false
    var blocks: [SlideBlock] = []
    for segment in segments {
        switch segment {
        case .code(let language, let lines):
            blocks.append(.code(language: language, lines: lines))
        case .table(let table):
            blocks.append(.table(table))
        case .text(let line):
            blocks.append(textBlock(line, kind: kind, headlineTaken: &headlineTaken))
        }
    }
    return SlideContent(blocks: blocks, kind: kind)
}

private func matches(_ re: NSRegularExpression, _ line: String) -> Bool {
    re.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) != nil
}

/// The block for one line of body text, given the slide's kind.
private func textBlock(_ line: String, kind: SlideKind, headlineTaken: inout Bool) -> SlideBlock {
    switch kind {
    case .quote:
        var stripped = Substring(line)
        while stripped.hasPrefix(">") { stripped = stripped.dropFirst() }
        return .line(stripped.trimmingCharacters(in: .whitespaces))
    case .list:
        let ns = line as NSString
        if let match = listItemRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            let rest = ns.substring(from: match.range.location + match.range.length)
            if match.range(at: 2).location != NSNotFound {
                return .line(ns.substring(with: match.range(at: 2)) + ns.substring(with: match.range(at: 3)) + " " + rest)
            }
            return .line("•  " + rest)
        }
    default:
        break
    }
    if !headlineTaken, line.hasPrefix("# ") {
        headlineTaken = true
        return .headline(String(line.dropFirst(2)))
    }
    return .line(line)
}

/// Groups lines into text, fenced code, and tables.
private func segment(_ lines: [String]) -> [Segment] {
    var result: [Segment] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        if let fence = openingFence(line) {
            var code: [String] = []
            index += 1
            while index < lines.count, !closes(lines[index], fence: fence) {
                code.append(lines[index])
                index += 1
            }
            index += 1 // the closing fence, if there was one
            result.append(.code(fence.language, code))
        } else if let (table, next) = table(startingAt: index, in: lines) {
            result.append(.table(table))
            index = next
        } else {
            result.append(.text(line))
            index += 1
        }
    }
    return result
}

private struct Fence { var character: Character; var length: Int; var language: String }

private func openingFence(_ line: String) -> Fence? {
    let ns = line as NSString
    guard let match = fenceOpenRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
    let run = ns.substring(with: match.range(at: 1))
    let info = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
    let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "{" }).first.map { String($0).lowercased() } ?? ""
    return Fence(character: run.first!, length: run.count, language: language)
}

private func closes(_ line: String, fence: Fence) -> Bool {
    let stripped = line.trimmingCharacters(in: .whitespaces)
    return stripped.count >= fence.length && stripped.allSatisfy { $0 == fence.character }
}

// MARK: - Tables

/// Splits a table row on unescaped `|`, ignoring one leading and trailing pipe.
private func splitRow(_ line: String) -> [String] {
    var body = line.trimmingCharacters(in: .whitespaces)
    if body.hasPrefix("|") { body.removeFirst() }
    if body.hasSuffix("|"), !body.hasSuffix("\\|") { body.removeLast() }
    var cells: [String] = []
    var current = ""
    var characters = body.makeIterator()
    var pending = characters.next()
    while let character = pending {
        pending = characters.next()
        if character == "\\", pending == "|" {
            current.append("|")
            pending = characters.next()
        } else if character == "|" {
            cells.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }
    cells.append(current)
    return cells.map { $0.trimmingCharacters(in: .whitespaces) }
}

private func alignments(fromSeparator line: String) -> [TableAlignment]? {
    guard line.contains("-") else { return nil }
    let cells = splitRow(line)
    guard !cells.isEmpty, cells.allSatisfy({ matches(separatorCellRe, $0) }) else { return nil }
    return cells.map { cell in
        switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
        case (true, true): return .center
        case (false, true): return .trailing
        default: return .leading
        }
    }
}

/// A table starting at `index`: a header row containing `|`, then a separator
/// row with the same number of columns, then body rows until a line with no `|`.
private func table(startingAt index: Int, in lines: [String]) -> (TableData, Int)? {
    guard lines[index].contains("|"), index + 1 < lines.count,
          let alignments = alignments(fromSeparator: lines[index + 1]) else { return nil }
    let header = splitRow(lines[index])
    guard header.count == alignments.count else { return nil }
    var rows: [[String]] = []
    var next = index + 2
    while next < lines.count, lines[next].contains("|"), !lines[next].trimmingCharacters(in: .whitespaces).isEmpty {
        var cells = splitRow(lines[next])
        if cells.count < header.count { cells += Array(repeating: "", count: header.count - cells.count) }
        rows.append(Array(cells.prefix(header.count)))
        next += 1
    }
    return (TableData(header: header, rows: rows, alignments: alignments), next)
}
