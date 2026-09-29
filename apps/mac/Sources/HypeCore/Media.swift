import Foundation
// SPM targets, unlike Xcode app targets, don't get CoreGraphics implicitly
// through Foundation: without this, `CGRect(x:y:width:height:)` below resolves
// to some other zero-argument `CGRect` and fails with a confusing
// "argument passed to call that takes no arguments" (seen while building this).
import CoreGraphics

/// One slide's media reference and its directives, matching the Qt app's
/// `Media` (`renderer.h`) and the parsing in `renderer.cpp`'s `readMedia`.
public struct Media: Sendable, Equatable {
    public var file = ""
    public var path = ""
    public var poster = ""
    public var error = ""
    public var background = ""
    /// `"left"`, `"right"`, or empty (under the text, or the whole slide).
    public var side = ""
    public var video = false
    public var span = false
    public var loop = false
    public var muted = false
    public var autoplay = true
    public var overlay: Double = 0
    /// The slide's text with the `![...](...)` reference and `<!-- comments -->` removed.
    public var text = ""
}

let mediaRe = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\((?:<([^>]+)>|([^\s)]+))\)"#)
private let commentRe = try! NSRegularExpression(pattern: "<!--[\\s\\S]*?-->")
private let inlineCodeRe = try! NSRegularExpression(pattern: "(`+)([^`]|`(?!`))*?\\1")
private let tokenRe = try! NSRegularExpression(pattern: #"([a-z]+)(?:=("(?:[^"\\]|\\.)*"|[^\s]+))?"#)
private let bareDirectives: Set<String> = ["fit", "span", "left", "right", "loop", "muted"]
let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv"]

/// `source` with fenced code, 4-space-indented lines, and (optionally) inline
/// `code` spans replaced by spaces of the same length, so a later scan for
/// media references, comments, or headlines never matches inside code.
/// Matches the Qt app's `outsideCode` (`renderer.cpp`).
func outsideCode(_ source: String, maskInline: Bool = true) -> String {
    var utf16 = Array(source.utf16)
    let fences = markdownFences(source)
    var position = 0
    while position < utf16.count {
        let (line, next) = lineAt(source, utf16, position)
        let lineEnd = line.utf16.count + position
        if insideFence(fences, position) || line.hasPrefix("    ") {
            for i in position..<lineEnd { utf16[i] = 0x20 }
        }
        position = next
    }
    var masked = String(utf16CodeUnits: utf16, count: utf16.count)
    if maskInline {
        let nsMasked = masked as NSString
        var ranges: [NSRange] = []
        inlineCodeRe.enumerateMatches(in: masked, range: NSRange(location: 0, length: nsMasked.length)) { match, _, _ in
            if let match { ranges.append(match.range) }
        }
        var codeUnits = Array(masked.utf16)
        for range in ranges {
            for i in range.location..<(range.location + range.length) { codeUnits[i] = 0x20 }
        }
        masked = String(utf16CodeUnits: codeUnits, count: codeUnits.count)
    }
    return masked
}

/// `source` with every `<!-- ... -->` HTML comment removed, ignoring one that
/// appears inside fenced or indented code. Matches `withoutComments` (`renderer.cpp`).
func withoutComments(_ source: String) -> String {
    let masked = outsideCode(source)
    let ns = masked as NSString
    var ranges: [NSRange] = []
    commentRe.enumerateMatches(in: masked, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
        if let match { ranges.append(match.range) }
    }
    var utf16 = Array(source.utf16)
    for range in ranges.sorted(by: { $0.location > $1.location }) {
        utf16.removeSubrange(range.location..<(range.location + range.length))
    }
    return String(utf16CodeUnits: utf16, count: utf16.count)
}

/// Whether the (masked, code-free) text holds a `# Headline` line.
private func hasHeadline(_ source: String) -> Bool {
    let masked = outsideCode(source) as NSString
    let re = try! NSRegularExpression(pattern: "^# ", options: .anchorsMatchLines)
    return re.firstMatch(in: masked as String, range: NSRange(location: 0, length: masked.length)) != nil
}

/// Resolves a bare filename to `images/<file>` or `videos/<file>` under `base`,
/// unless it already names one of those folders or is absolute. Matches
/// `assetPath` (`renderer.cpp`).
func assetPath(base: String, file: String, video: Bool) -> String {
    if file.hasPrefix("/") { return file }
    let relative = file.hasPrefix("images/") || file.hasPrefix("videos/") ? file : (video ? "videos/" : "images/") + file
    return base.isEmpty ? relative : base + "/" + relative
}

private func unescapeQuoted(_ value: String) -> String {
    guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return value }
    let inner = value.dropFirst().dropLast()
    return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
}

/// Parses a slide's Markdown into its text and, if present, its media
/// reference and directives. Matches `readMedia`/`parseMedia` (`renderer.cpp`);
/// unlike the Qt app this is not cached, since Phase 1 has no export worker
/// re-parsing thousands of slides per second.
public func parseMedia(_ slideSource: String, base: String) -> Media {
    var result = Media()
    result.text = withoutComments(slideSource)
    let masked = outsideCode(result.text) as NSString
    guard let match = mediaRe.firstMatch(in: masked as String, range: NSRange(location: 0, length: masked.length))
    else { return result }
    // Groups 2 (`<angle bracket path>`) and 3 (bare path) are alternatives: exactly
    // one matches per reference, and the other's range is NSNotFound, which
    // NSString.substring(with:) would crash on if not guarded.
    func group(_ index: Int) -> String? {
        let groupRange = match.range(at: index)
        guard groupRange.location != NSNotFound else { return nil }
        return masked.substring(with: groupRange)
    }
    let bracket = group(2) ?? group(3) ?? ""
    result.file = bracket
    result.video = videoExtensions.contains((bracket as NSString).pathExtension.lowercased())
    result.path = assetPath(base: base, file: result.file, video: result.video)
    var utf16 = Array(result.text.utf16)
    let range = match.range
    utf16.removeSubrange(range.location..<(range.location + range.length))
    result.text = String(utf16CodeUnits: utf16, count: utf16.count)
    result.span = !result.video && hasHeadline(result.text)

    let flags = masked.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
    let flagsNS = flags as NSString
    let firstMatch = tokenRe.firstMatch(in: flags, range: NSRange(location: 0, length: flagsNS.length))
    let firstIsDirective: Bool = {
        guard let firstMatch, firstMatch.range.location == 0 else { return false }
        let key = flagsNS.substring(with: firstMatch.range(at: 1))
        let hasValue = firstMatch.range(at: 2).location != NSNotFound
        return bareDirectives.contains(key) || hasValue
    }()
    var explicitOverlay = ""
    var fit = false, span = false
    if firstIsDirective {
        var consumed = 0
        var invalid = false
        tokenRe.enumerateMatches(in: flags, range: NSRange(location: 0, length: flagsNS.length)) { tokenMatch, _, _ in
            guard let tokenMatch else { return }
            let between = flagsNS.substring(with: NSRange(location: consumed, length: tokenMatch.range.location - consumed))
            if !between.trimmingCharacters(in: .whitespaces).isEmpty { invalid = true }
            consumed = tokenMatch.range.location + tokenMatch.range.length
            let key = flagsNS.substring(with: tokenMatch.range(at: 1))
            let rawValue = tokenMatch.range(at: 2).location == NSNotFound ? "" : flagsNS.substring(with: tokenMatch.range(at: 2))
            let value = unescapeQuoted(rawValue)
            switch key {
            case "span": result.span = true; span = true
            case "fit": result.span = false; fit = true
            case "left", "right":
                if !result.side.isEmpty, result.side != key { result.error = "Choose either left or right" }
                result.side = key
            case "loop": result.loop = value != "false"
            case "muted": result.muted = value != "false"
            case "autoplay": result.autoplay = value != "false"
            case "overlay": explicitOverlay = value
            case "background":
                result.background = value
                if !["auto", "theme", "blur", "white", "black"].contains(value), !isValidHexColor(value) {
                    result.error = "Invalid background color"
                }
            case "poster": result.poster = assetPath(base: base, file: value, video: false)
            case "alt": break
            default: result.error = "Unknown media directive: \(key)"
            }
        }
        let tail = flagsNS.substring(from: consumed).trimmingCharacters(in: .whitespaces)
        if invalid || !tail.isEmpty { result.error = "Invalid media directive" }
    }
    if fit, span { result.error = "Choose either span or fit" }
    // Beside the text an image fits its half; span then fills that half.
    if !result.side.isEmpty, !span { result.span = false }
    if !result.background.isEmpty, (result.background == "blur" || result.background == "auto"), !span {
        result.span = false
    }
    let hasText = !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    result.overlay = result.side.isEmpty && (!result.video || result.span) && hasText ? 0.25 : 0
    if !explicitOverlay.isEmpty {
        if let opacity = Double(explicitOverlay), opacity >= 0, opacity <= 1 {
            result.overlay = opacity
        } else {
            result.error = "Overlay must be between 0 and 1"
        }
    }
    return result
}

func isValidHexColor(_ value: String) -> Bool {
    guard value.hasPrefix("#"), value.count == 7 else { return false }
    return value.dropFirst().allSatisfy { $0.isHexDigit }
}

/// A half of a split slide (`![left]`/`![right]`): full slide height, half its
/// width, on its side. Matches `splitHalf` (`renderer.cpp`).
///
/// The ternaries below are hoisted into explicitly `CGFloat`-typed locals
/// rather than written inline as `CGRect` arguments: an untyped integer-literal
/// ternary nested inside a labeled initializer call can defeat Swift's
/// type-checker, which then reports a confusing, unrelated-looking diagnostic
/// (seen while building this file) instead of a real type error.
func splitHalf(_ side: String) -> CGRect {
    let x: CGFloat = side == "left" ? 0 : 960
    return CGRect(x: x, y: 0, width: 960, height: 1080)
}
/// The text's area on a split slide, opposite its picture. Matches `splitTextArea`.
public func splitTextArea(_ side: String) -> CGRect {
    let x: CGFloat = side == "left" ? 990 : 130
    return CGRect(x: x, y: 90, width: 800, height: 900)
}

/// Where a slide's media is drawn, in 1920×1080 slide units. Matches `mediaRect` (`renderer.cpp`).
public func mediaRect(_ media: Media) -> CGRect {
    if !media.side.isEmpty {
        if media.span { return splitHalf(media.side) }
        let x: CGFloat = media.side == "left" ? 60 : 980
        return CGRect(x: x, y: 60, width: 880, height: 960)
    }
    if media.span { return CGRect(x: 0, y: 0, width: 1920, height: 1080) }
    let hasText = !media.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if !media.video || !hasText { return CGRect(x: 70, y: 50, width: 1780, height: 980) }
    return CGRect(x: 100, y: 280, width: 1720, height: 730)
}
