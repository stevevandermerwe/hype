import Foundation

/// Problems worth flagging on one slide: missing/undecodable media, or more
/// than one media reference. Matches (a subset of) the Qt app's
/// `slideProblems` (`renderer.cpp`) — used by export to warn, and by AI
/// generation/revision to report what the model got wrong.
public func slideProblems(_ source: String, base: String) -> [String] {
    var problems: [String] = []
    let media = parseMedia(source, base: base)
    if !media.error.isEmpty { problems.append(media.error) }
    if !media.file.isEmpty {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: media.path, isDirectory: &isDirectory)
        if !exists || isDirectory.boolValue {
            problems.append("Missing media: \(media.file)")
        }
    }
    if !media.poster.isEmpty, !FileManager.default.fileExists(atPath: media.poster) {
        problems.append("Missing poster")
    }
    let visible = outsideCode(withoutComments(source))
    let count = mediaReferenceCount(visible)
    if count > 1 {
        problems.append("Use one media item per slide (combine artwork before importing)")
    }
    return problems
}

private let mediaCountRe = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\((?:<([^>]+)>|([^\s)]+))\)"#)
private func mediaReferenceCount(_ text: String) -> Int {
    let ns = text as NSString
    return mediaCountRe.numberOfMatches(in: text, range: NSRange(location: 0, length: ns.length))
}
