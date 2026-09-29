import Foundation

private let fenceMarkerRe = try! NSRegularExpression(pattern: "^(`{3,}|~{3,})(.*)$")
private let listMarkerRe = try! NSRegularExpression(pattern: #"^(>|[-*+]|\d+\.)\s+|\\$"#)

/// The headline, or else the first line of text, or else of code, of a
/// slide's text (media and comments already removed). Matches `slideTitle`
/// (`cli.cpp`).
public func slideTitle(_ text: String) -> String {
    var first = "", code = "", fence = ""
    for raw in text.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        let ns = line as NSString
        let match = fenceMarkerRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        let run = match.map { ns.substring(with: $0.range(at: 1)) } ?? ""
        let info = match.map { ns.substring(with: $0.range(at: 2)) } ?? ""
        if match != nil, fence.isEmpty {
            fence = run
        } else if match != nil, run.first == fence.first, run.count >= fence.count,
                  info.trimmingCharacters(in: .whitespaces).isEmpty {
            fence = ""
        } else if !fence.isEmpty, code.isEmpty {
            code = line
        } else if fence.isEmpty, line.hasPrefix("#") {
            let afterSpace = line.firstIndex(of: " ").map { line.index(after: $0) } ?? line.endIndex
            return String(line[afterSpace...]).trimmingCharacters(in: .whitespaces)
        } else if fence.isEmpty, first.isEmpty {
            let cleaned = listMarkerRe.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length),
                                                                withTemplate: "")
            first = cleaned.trimmingCharacters(in: .whitespaces)
        }
    }
    return first.isEmpty ? code : first
}

extension DeckModel {
    /// One numbered title per slide, for giving an AI the shape of the talk.
    /// Matches `Deck::slideOutline` (`deck.cpp`).
    public func slideOutline() -> String {
        let maxTitleLength = 80
        var lines: [String] = []
        for index in 0..<count {
            var title = slideTitle(parseMedia(slideSource(at: index), base: baseDir).text)
            if title.count > maxTitleLength {
                title = String(title.prefix(maxTitleLength)) + "…"
            }
            lines.append("\(index + 1). \(title.isEmpty ? "(no text)" : title)")
        }
        return lines.joined(separator: "\n")
    }
}
