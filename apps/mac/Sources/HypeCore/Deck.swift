import Foundation

/// One slide's exact source text and its `[start, end)` UTF-16 range within the
/// whole presentation, matching the Qt app's `Slide` (`deck.h`). Keeping the
/// range lets editing rewrite exactly the bytes that changed.
public struct Slide: Sendable, Equatable {
    public var source: String
    public var start: Int
    public var end: Int
}

/// The result of splitting a presentation's Markdown into front matter and
/// slides, matching the Qt app's `ParsedDeck` (`deck.h`).
public struct ParsedDeck: Sendable, Equatable {
    public var header: String = ""
    public var slides: [Slide] = []
    public var error: String = ""
    /// Where the unfinished front matter or code fence opens, when `error` is set.
    public var errorOffset: Int?
}

/// Splits `source` into front matter and slides, code-fence aware, exactly as
/// the Qt app's `parseDeck` does: a slide boundary is a line holding only
/// `---`, with a `---` inside a fenced code block never splitting a slide.
public func parseDeck(_ source: String) -> ParsedDeck {
    var result = ParsedDeck()
    let utf16 = Array(source.utf16)
    var contentStart = source.hasPrefix("\u{feff}") ? 1 : 0
    let (firstLine, afterFirst) = lineAt(source, utf16, contentStart)
    if firstLine == "---" {
        var offset = afterFirst
        var closed = false
        while offset < utf16.count {
            let (line, next) = lineAt(source, utf16, offset)
            if line == "---" {
                contentStart = next
                closed = true
                break
            }
            offset = next
        }
        if !closed {
            result.error = "Front matter needs a closing ---"
            result.errorOffset = contentStart
            result.slides.append(Slide(source: source, start: 0, end: utf16.count))
            return result
        }
    }
    result.header = substring(source, utf16, 0, contentStart)
    // A top-level --- inside a fenced code block is code, not a slide break.
    // Fence scanning starts after front matter, exactly as the original did.
    let fences = markdownFences(source, from: contentStart)
    var start = contentStart
    var pos = start
    while pos < utf16.count {
        let (line, next) = lineAt(source, utf16, pos)
        if line == "---", !insideFence(fences, pos) {
            result.slides.append(Slide(source: substring(source, utf16, start, pos), start: start, end: pos))
            start = next
        }
        pos = next
    }
    result.slides.append(Slide(source: substring(source, utf16, start, utf16.count), start: start, end: utf16.count))
    if let unclosed = fences.unclosedOffset, result.error.isEmpty {
        result.error = "Unclosed code fence"
        result.errorOffset = unclosed
    }
    return result
}

/// `source[start..<end]`, `start`/`end` given as UTF-16 offsets.
func substring(_ source: String, _ utf16: [UInt16], _ start: Int, _ end: Int) -> String {
    guard let range = Range(NSRange(location: start, length: max(0, end - start)), in: source) else { return "" }
    return String(source[range])
}

private func scalarLineRe(_ key: String) -> NSRegularExpression {
    try! NSRegularExpression(pattern: "^\(NSRegularExpression.escapedPattern(for: key)):\\s*([^\\r\\n]*)$",
                            options: .anchorsMatchLines)
}

/// Reads a `key: value` front-matter line: JSON-decoded when double-quoted,
/// literal (with `''`→`'`) when single-quoted, else the raw trimmed text.
/// Matches the Qt app's `scalar` (`deck.cpp`).
public func scalar(_ header: String, _ key: String, _ fallback: String = "") -> String {
    let re = scalarLineRe(key)
    guard let match = re.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
          let valueRange = Range(match.range(at: 1), in: header) else { return fallback }
    let value = header[valueRange].trimmingCharacters(in: .whitespaces)
    if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2,
       let data = "[\(value)]".data(using: .utf8),
       let array = try? JSONSerialization.jsonObject(with: data) as? [String], let first = array.first {
        return first
    }
    if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
        let inner = value.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "''", with: "'")
    }
    return value
}

/// Removes a `key: value` front-matter line (only that exact key), if present.
public func removeScalar(_ header: String, _ key: String) -> String {
    let escapedKey = NSRegularExpression.escapedPattern(for: key)
    let re = try! NSRegularExpression(pattern: "^" + escapedKey + ":[^\\r\\n]*(?:\\r?\\n)?", options: .anchorsMatchLines)
    return re.stringByReplacingMatches(in: header, range: NSRange(header.startIndex..., in: header), withTemplate: "")
}

/// Replaces or appends a `key: value` front-matter line, JSON-encoding `value`
/// exactly as the Qt app's `setScalar` (`deck.cpp`) does.
public func setScalar(_ header: String, _ key: String, _ value: String) -> String {
    var header = header
    let encoded = (try? JSONSerialization.data(withJSONObject: [value])).flatMap { String(data: $0, encoding: .utf8) }
        ?? "[\"\(value)\"]"
    // Strip the enclosing "[" and "]" that encoding a one-element array added.
    let quoted = String(encoded.dropFirst().dropLast())
    let line = "\(key): \(quoted)"
    let re = try! NSRegularExpression(pattern: "^\(NSRegularExpression.escapedPattern(for: key)):[^\\r\\n]*",
                                      options: .anchorsMatchLines)
    let fullRange = NSRange(header.startIndex..., in: header)
    if let match = re.firstMatch(in: header, range: fullRange), let range = Range(match.range, in: header) {
        header.replaceSubrange(range, with: line)
    } else if header.isEmpty {
        header = "---\n\(line)\n---\n"
    } else if let end = header.range(of: "---", options: .backwards) {
        header.insert(contentsOf: line + "\n", at: end.lowerBound)
    }
    return header
}
