import Foundation

/// Shared Markdown scanning, mirroring the Qt app's `markdown.cpp`: the deck
/// parser and the slide renderer's code masking must agree on where fenced code
/// blocks begin and end, so both use this one scanner.
public struct FencedRanges: Sendable {
    /// Each range spans `[lowerBound, upperBound)`: the opening fence line
    /// through the line after the closing fence. Ranges never overlap and
    /// appear in source order.
    public var ranges: [Range<Int>] = []
    /// Offset of the opening fence when a fence never closes; nil otherwise.
    public var unclosedOffset: Int?

    public func contains(_ offset: Int) -> Bool {
        ranges.contains { $0.contains(offset) }
    }
}

private let fenceLineRe = try! NSRegularExpression(pattern: "^ {0,3}(`{3,}|~{3,})(.*)$")

/// One line of `source` starting at UTF-16 offset `offset` (without its
/// trailing `\n` or `\r\n`), plus the offset of the following line. All
/// offsets in this file are UTF-16 offsets, so they line up with `NSString`/
/// `NSRegularExpression` ranges and with `String.Index` via `Range(_:in:)`.
func lineAt(_ source: String, _ utf16: [UInt16], _ offset: Int) -> (line: String, next: Int) {
    var end = offset
    while end < utf16.count, utf16[end] != 0x0A { end += 1 }
    var lineEnd = end
    if lineEnd > offset, utf16[lineEnd - 1] == 0x0D { lineEnd -= 1 }
    let next = end < utf16.count ? end + 1 : utf16.count
    guard let range = Range(NSRange(location: offset, length: lineEnd - offset), in: source) else {
        return ("", next)
    }
    return (String(source[range]), next)
}

/// Scans fenced code blocks (backtick and tilde, length 3 or more). Opening
/// fences may carry an info string; closing fences must not. Fences are only
/// recognized from `from` onward, matching where the deck parser starts
/// scanning after front matter.
public func markdownFences(_ source: String, from: Int = 0) -> FencedRanges {
    let utf16 = Array(source.utf16)
    var result = FencedRanges()
    var pos = max(0, from)
    var fenceChar: Character?
    var fenceLength = 0
    var fenceStart = 0
    while pos < utf16.count {
        let (line, next) = lineAt(source, utf16, pos)
        if let match = fenceLineRe.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let runRange = Range(match.range(at: 1), in: line) {
            let run = String(line[runRange])
            if fenceLength == 0 {
                fenceChar = run.first
                fenceLength = run.count
                fenceStart = pos
            } else if run.first == fenceChar, run.count >= fenceLength,
                      let infoRange = Range(match.range(at: 2), in: line),
                      line[infoRange].trimmingCharacters(in: .whitespaces).isEmpty {
                result.ranges.append(fenceStart..<next)
                fenceLength = 0
            }
        }
        pos = next
    }
    if fenceLength > 0 {
        result.unclosedOffset = fenceStart
        result.ranges.append(fenceStart..<utf16.count)
    }
    return result
}

/// Whether `offset` (a UTF-16 offset into the same source) falls inside one of
/// the fenced ranges (a line of code).
public func insideFence(_ fences: FencedRanges, _ offset: Int) -> Bool {
    fences.contains(offset)
}
