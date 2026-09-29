import Foundation

/// Find and replace across the slides of a deck. Slides are searched as text, so
/// speaker notes and code are included; the filenames inside `![](…)` picture
/// references never match, so replacing a word can't break a picture.

public struct SearchOptions: Equatable, Sendable {
    public var caseSensitive: Bool
    public var wholeWord: Bool
    /// Treat the query as a regular expression (and `$1` etc. in the replacement).
    public var regex: Bool

    public init(caseSensitive: Bool = false, wholeWord: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.regex = regex
    }
}

public enum SearchError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidPattern(String)
    /// The replacement would put a `---` line in a slide, splitting it in two.
    case wouldSplitSlides

    public var description: String {
        switch self {
        case .invalidPattern(let reason): return "That isn't a valid pattern: \(reason)"
        case .wouldSplitSlides: return "That replacement contains a slide separator (---), which would split a slide."
        }
    }
}

public struct SearchMatch: Equatable, Sendable, Identifiable {
    /// 0-based slide index.
    public var slide: Int
    /// UTF-16 range within that slide's text.
    public var range: NSRange
    public var text: String
    /// Text before and after the match on its line, for showing it in context.
    public var before: String
    public var after: String
    public var id: String { "\(slide):\(range.location)" }
}

private func makeRegex(_ query: String, _ options: SearchOptions) -> Result<NSRegularExpression, SearchError> {
    var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
    if options.wholeWord { pattern = "(?<![\\p{L}\\p{N}_])(?:\(pattern))(?![\\p{L}\\p{N}_])" }
    var flags: NSRegularExpression.Options = options.caseSensitive ? [] : [.caseInsensitive]
    if options.regex { flags.insert(.anchorsMatchLines) }
    do {
        return .success(try NSRegularExpression(pattern: pattern, options: flags))
    } catch {
        return .failure(.invalidPattern(error.localizedDescription))
    }
}

/// The picture references in `slide` (outside code), which searching skips.
private func pictureReferenceRanges(in slide: String) -> [NSRange] {
    let masked = outsideCode(slide)
    return mediaRe.matches(in: masked, range: NSRange(location: 0, length: (masked as NSString).length)).map(\.range)
}

private func matches(in slide: String, _ regex: NSRegularExpression) -> [NSTextCheckingResult] {
    let protected = pictureReferenceRanges(in: slide)
    return regex.matches(in: slide, range: NSRange(location: 0, length: (slide as NSString).length)).filter { match in
        match.range.length > 0 && !protected.contains { NSIntersectionRange($0, match.range).length > 0 }
    }
}

private let contextBefore = 30
private let contextAfter = 50

/// `text[range]`, widened so it never cuts an emoji or accented letter in half.
private func snippet(_ text: NSString, _ range: NSRange) -> String {
    guard range.length > 0 else { return "" }
    return text.substring(with: text.rangeOfComposedCharacterSequences(for: range))
}

/// Every match of `query` in `slides`, in order. An empty query matches nothing;
/// an invalid regex is an error.
public func findMatches(in slides: [String], query: String, options: SearchOptions) -> Result<[SearchMatch], SearchError> {
    guard !query.isEmpty else { return .success([]) }
    switch makeRegex(query, options) {
    case .failure(let error): return .failure(error)
    case .success(let regex):
        var found: [SearchMatch] = []
        for (index, slide) in slides.enumerated() {
            let ns = slide as NSString
            for match in matches(in: slide, regex) {
                let line = ns.lineRange(for: match.range)
                let endsWithNewline = line.length > 0 && ns.character(at: line.location + line.length - 1) == 10
                let lineEnd = line.location + line.length - (endsWithNewline ? 1 : 0)
                let matchEnd = match.range.location + match.range.length
                let beforeStart = max(line.location, match.range.location - contextBefore)
                let afterEnd = min(lineEnd, matchEnd + contextAfter)
                found.append(SearchMatch(
                    slide: index, range: match.range, text: ns.substring(with: match.range),
                    before: snippet(ns, NSRange(location: beforeStart, length: match.range.location - beforeStart)),
                    after: snippet(ns, NSRange(location: matchEnd, length: max(0, afterEnd - matchEnd)))))
            }
        }
        return .success(found)
    }
}

/// Replaces every match (or only those in slide `onlySlide`, 0-based) and returns
/// the new slides with how many replacements were made. Without `options.regex`
/// the replacement is literal text; with it, `$1` etc. refer to capture groups.
/// A replacement that would split a slide is refused, changing nothing.
public func replaceMatches(in slides: [String], query: String, replacement: String, options: SearchOptions,
                           onlySlide: Int?) -> Result<(slides: [String], count: Int), SearchError> {
    guard !query.isEmpty else { return .success((slides, 0)) }
    switch makeRegex(query, options) {
    case .failure(let error): return .failure(error)
    case .success(let regex):
        var result = slides
        var count = 0
        for (index, slide) in slides.enumerated() where onlySlide == nil || onlySlide == index {
            let found = matches(in: slide, regex)
            guard !found.isEmpty else { continue }
            var text = slide as NSString
            for match in found.reversed() {
                let new = options.regex ? regex.replacementString(for: match, in: slide, offset: 0, template: replacement) : replacement
                text = text.replacingCharacters(in: match.range, with: new) as NSString
            }
            if hasSlideSeparator(text as String), !hasSlideSeparator(slide) { return .failure(.wouldSplitSlides) }
            result[index] = text as String
            count += found.count
        }
        return .success((result, count))
    }
}
