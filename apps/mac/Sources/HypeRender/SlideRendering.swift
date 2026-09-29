import SwiftUI
import HypeCore
#if canImport(AppKit)
import AppKit
#endif

/// How a slide's text is classified for layout, matching the Qt renderer's
/// `code`/`quote`/`list`/`table` booleans (`renderer.cpp`'s `paintSlide`).
///
/// Phase 1 note: the Qt app fits one font size per slide by measuring a whole
/// `QTextDocument` built from a richer internal Markdown-to-richtext pass this
/// port does not have access to; this reimplementation approximates the same
/// visual result (a headline line rendered larger than the body, one fitted
/// body size, the same left/center default per kind) rather than reproducing
/// that algorithm exactly. Code fences render in a fixed monospace size with
/// no syntax highlighting (the Qt app shells out to `source-highlight`), and
/// tables render as preformatted text rather than a true grid — both called
/// out in `../ROADMAP.md` as things to revisit.
enum SlideTextKind { case code, quote, list, table, plain }

private let fenceStartRe = try! NSRegularExpression(pattern: "^ {0,3}(`{3,}|~{3,})")
private let listItemRe = try! NSRegularExpression(pattern: #"^\s*(?:([-*+])\s+|(\d+)([.)])\s+)"#)
private let tableRowRe = try! NSRegularExpression(pattern: #"\|[ :|-]+\|"#)
private let inlineRe = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*|\*(.+?)\*|_(.+?)_"#)

func classify(_ text: String) -> SlideTextKind {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let ns = text as NSString
    if lines.contains(where: { fenceStartRe.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }) {
        return .code
    }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(">") { return .quote }
    if lines.contains(where: { listItemRe.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }) {
        return .list
    }
    if tableRowRe.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil { return .table }
    return .plain
}

/// `**bold**`, `*italic*`, and `_underline_` — matches Hype's Markdown dialect
/// (see `format.md`). Not nested, matching a single-pass reading of the source.
/// Sets font/color directly on each piece as it is built, rather than
/// building a plain string and re-applying attributes by range afterward,
/// since `AttributedString` ranges are not guaranteed portable across a copy.
func inlineFormatted(_ line: String, font: Font, color: Color) -> AttributedString {
    var result = AttributedString()
    let ns = line as NSString
    var consumed = 0
    func append(_ text: String, font pieceFont: Font) {
        guard !text.isEmpty else { return }
        var piece = AttributedString(text)
        piece.font = pieceFont
        piece.foregroundColor = color
        result += piece
    }
    inlineRe.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
        guard let match else { return }
        if match.range.location > consumed {
            append(ns.substring(with: NSRange(location: consumed, length: match.range.location - consumed)), font: font)
        }
        if match.range(at: 1).location != NSNotFound {
            append(ns.substring(with: match.range(at: 1)), font: font.bold())
        } else if match.range(at: 2).location != NSNotFound {
            append(ns.substring(with: match.range(at: 2)), font: font.italic())
        } else if match.range(at: 3).location != NSNotFound {
            var piece = AttributedString(ns.substring(with: match.range(at: 3)))
            piece.font = font
            piece.foregroundColor = color
            piece.underlineStyle = .single
            result += piece
        }
        consumed = match.range.location + match.range.length
    }
    if consumed < ns.length {
        append(ns.substring(from: consumed), font: font)
    }
    return result
}

/// One slide's text, laid out for `area` (1920×1080 units) and drawn with
/// `context`. Returns the fitted body font size, mainly for tests.
/// `textScale` (the deck's `text_scale`) above 1 raises the largest size text
/// may be fitted to; below 1 it shrinks the fitted size, so it always shows.
@discardableResult
func drawSlideText(_ context: inout GraphicsContext, text: String, area: CGRect, foreground: Color,
                   textScale: CGFloat = 1) -> CGFloat {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return 0 }
    let kind = classify(trimmed)
    let centered = kind == .plain
    let rawLines = trimmed.components(separatedBy: "\n")
    var headline: String?
    var bodyLines: [String] = []
    var monospace = false
    for line in rawLines {
        switch kind {
        case .code:
            monospace = true
            if fenceStartRe.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil { bodyLines.append(line) }
        case .quote:
            var stripped = line
            while stripped.hasPrefix(">") { stripped.removeFirst() }
            bodyLines.append(stripped.trimmingCharacters(in: .whitespaces))
        case .list:
            let ns = line as NSString
            if let match = listItemRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let rest = ns.substring(from: match.range.location + match.range.length)
                let marker = match.range(at: 2).location != NSNotFound
                    ? ns.substring(with: match.range(at: 2)) + ns.substring(with: match.range(at: 3)) + " " : "•  "
                bodyLines.append(marker + rest)
            } else if headline == nil, line.hasPrefix("# ") {
                headline = String(line.dropFirst(2))
            } else {
                bodyLines.append(line)
            }
        default:
            if headline == nil, line.hasPrefix("# ") {
                headline = String(line.dropFirst(2))
            } else {
                bodyLines.append(line)
            }
        }
    }
    let baseFont: (CGFloat) -> Font = monospace ? { .system(size: $0, design: .monospaced) } : { .system(size: $0) }

    // Each display line is measured and drawn as its own `Text`, rather than one
    // big multi-line `Text`: `Text.multilineTextAlignment` is a generic `View`
    // modifier returning `some View`, not `Text`, so it cannot feed
    // `GraphicsContext.resolve(_ text: Text)` — and laying lines out by hand
    // here gives real left/center alignment directly, without that detour.
    let lineSpacing: CGFloat = 6
    func displayLines(bodySize: CGFloat) -> [Text] {
        var result: [Text] = []
        if let headline {
            result.append(Text(inlineFormatted(headline, font: baseFont(bodySize * 1.7), color: foreground)).bold())
        }
        for line in bodyLines {
            result.append(Text(inlineFormatted(line, font: baseFont(bodySize), color: foreground)))
        }
        return result
    }
    func measuredLines(bodySize: CGFloat) -> [(text: Text, size: CGSize)] {
        displayLines(bodySize: bodySize).map { line in
            (line, context.resolve(line).measure(in: CGSize(width: area.width, height: .infinity)))
        }
    }
    func blockHeight(_ measured: [(text: Text, size: CGSize)]) -> CGFloat {
        guard !measured.isEmpty else { return 0 }
        return measured.reduce(0) { $0 + $1.size.height } + CGFloat(measured.count - 1) * lineSpacing
    }
    func blockWidth(_ measured: [(text: Text, size: CGSize)]) -> CGFloat { measured.map(\.size.width).max() ?? 0 }

    let (low, baseHigh): (CGFloat, CGFloat) = {
        switch kind {
        case .code: return (8, 56)
        case .quote: return (8, 64)
        case .list: return (8, 72)
        case .table: return (8, 60)
        case .plain: return (8, bodyLines.count > 1 || headline != nil ? 128 : 76)
        }
    }()
    let high = baseHigh * max(1, textScale)
    func fits(_ size: CGFloat) -> Bool {
        let measured = measuredLines(bodySize: size)
        return blockHeight(measured) <= area.height && blockWidth(measured) <= area.width + 1
    }
    var chosen = low
    if fits(high) {
        chosen = high
    } else {
        var lowBound = low, highBound = high
        for _ in 0..<9 {
            let mid = (lowBound + highBound) / 2
            if fits(mid) { lowBound = mid } else { highBound = mid }
        }
        chosen = lowBound
    }
    chosen = max(low, chosen * min(1, textScale))
    let final = measuredLines(bodySize: chosen)
    var y = area.minY + max(0, (area.height - blockHeight(final)) / 2)
    for (text, size) in final {
        let x = centered ? area.minX + max(0, (area.width - size.width) / 2) : area.minX
        context.draw(context.resolve(text), in: CGRect(x: x, y: y, width: size.width, height: size.height))
        y += size.height + lineSpacing
    }
    return chosen
}

/// Fit- or span-scaled size of `imageSize` within `bounds`, matching Qt's
/// `KeepAspectRatio` (fit) and `KeepAspectRatioByExpanding` (span, cropped).
func aspectScaled(_ imageSize: CGSize, into bounds: CGSize, expanding: Bool) -> CGSize {
    guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
    let scale = expanding ? max(bounds.width / imageSize.width, bounds.height / imageSize.height)
                         : min(bounds.width / imageSize.width, bounds.height / imageSize.height)
    return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
}

/// Draws one slide (its Markdown source) into `context` in 1920×1080 units —
/// the Mac app's counterpart to the Qt renderer's `paintSlide`.
func drawSlide(_ context: inout GraphicsContext, source: String, baseDir: String, palette: Palette,
               textScale: CGFloat = 1) {
    let full = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    context.fill(Path(full), with: .color(Color(hex: palette.background)))
    let media = parseMedia(source, base: baseDir)
    var foreground = Color(hex: palette.foreground)
    var textArea = CGRect(x: 130, y: 90, width: 1660, height: 900)
    let trimmedText = media.text.trimmingCharacters(in: .whitespacesAndNewlines)

    if !media.file.isEmpty {
        let rect = mediaRect(media)
        let split = !media.side.isEmpty
        let backdropArea = split ? CGRect(origin: rect.origin, size: CGSize(width: 960, height: 1080)) : full
        #if canImport(AppKit)
        let nsImage = NSImage(contentsOfFile: media.path)
        #else
        let nsImage: NSImage? = nil
        #endif
        if !split, !media.background.isEmpty, !media.span,
           media.background != "theme", media.background != "auto", media.background != "blur" {
            let fillHex = media.background == "white" ? "#ffffff" : media.background == "black" ? "#000000" : media.background
            context.fill(Path(backdropArea), with: .color(Color(hex: fillHex)))
            foreground = Color.contrastingInk(over: fillHex)
        }
        if let nsImage {
            let imageSize = nsImage.size
            let scaled = aspectScaled(imageSize, into: rect.size, expanding: media.span)
            let dest = CGRect(x: rect.midX - scaled.width / 2, y: rect.midY - scaled.height / 2,
                              width: scaled.width, height: scaled.height)
            context.drawLayer { layer in
                layer.clip(to: Path(rect))
                layer.draw(Image(nsImage: nsImage), in: dest)
            }
        } else {
            context.draw(Text("Missing media\n\(media.file)").foregroundColor(Color(hex: palette.accent)), in: rect)
        }
        if split {
            if !trimmedText.isEmpty { textArea = splitTextArea(media.side) }
        } else if media.overlay > 0 {
            context.fill(Path(full), with: .color(.black.opacity(media.overlay)))
            if !trimmedText.isEmpty { foreground = .white }
        }
    }
    if !trimmedText.isEmpty {
        drawSlideText(&context, text: trimmedText, area: textArea, foreground: foreground, textScale: textScale)
    }
    if !media.error.isEmpty {
        let banner = CGRect(x: 0, y: 1000, width: 1920, height: 80)
        context.fill(Path(banner), with: .color(Color(hex: "#9b3030")))
        context.draw(Text(media.error).foregroundColor(.white), in: banner.insetBy(dx: 30, dy: 20))
    }
}
