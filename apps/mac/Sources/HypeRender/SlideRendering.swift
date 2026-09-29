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

/// What the text fitter decided for one slide, mainly for tests and warnings.
struct TextFit: Equatable {
    var bodySize: CGFloat
    var headlineSize: CGFloat
    /// How many lines had to wrap onto a second line; 0 when every line fits whole.
    var wrappedLines: Int
    /// Height of the drawn text block, in slide units.
    var height: CGFloat
}

/// Body text below this many units (of a 1080-tall slide) is too small to read
/// from a room, so the fitter will always wrap lines rather than go below it.
let readableBodySize: CGFloat = 36
/// Below this, text is legible but small: the fitter still prefers keeping lines
/// whole, unless wrapping them makes the text at least `wrapGain` times bigger.
let comfortableBodySize: CGFloat = 52
let wrapGain: CGFloat = 1.3

/// One slide's text, laid out for `area` (1920×1080 units) and drawn with
/// `context`. The text is sized as large as it can be while every line stays
/// whole and the block fits the area; long lines wrap only when keeping them
/// whole would leave the text unreadably (or needlessly) small. The headline is sized
/// on its own, so a long title shrinks to stay on one line instead of wrapping
/// or dragging the body text down with it.
/// `textScale` (the deck's `text_scale`) above 1 raises the largest size text
/// may be fitted to; below 1 it shrinks the fitted size, so it always shows.
@discardableResult
func drawSlideText(_ context: inout GraphicsContext, text: String, area: CGRect, foreground: Color,
                   textScale: CGFloat = 1) -> TextFit {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return TextFit(bodySize: 0, headlineSize: 0, wrappedLines: 0, height: 0) }
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
    let headlineRatio: CGFloat = 1.7
    let minHeadlineRatio: CGFloat = 1.15

    func headlineText(_ size: CGFloat) -> Text? {
        headline.map { Text(inlineFormatted($0, font: baseFont(size), color: foreground)).bold() }
    }
    /// The largest headline size that still fits `area` on one line. Text width
    /// grows linearly with font size, so measuring once at a reference size is
    /// enough; a small margin absorbs rounding.
    let headlineFitSize: CGFloat = {
        let unbounded = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        guard let reference = headlineText(100) else { return CGFloat.infinity }
        let width = context.resolve(reference).measure(in: unbounded).width
        return width > 0 ? 100 * area.width / width * 0.98 : CGFloat.infinity
    }()
    func headlineSize(forBody body: CGFloat) -> CGFloat {
        headline == nil ? 0 : max(body * minHeadlineRatio, min(body * headlineRatio, headlineFitSize))
    }

    struct Line { var text: Text; var size: CGSize; var wrapped: Bool }
    func layout(bodySize: CGFloat, wrapping: Bool) -> [Line] {
        var texts: [Text] = []
        if let title = headlineText(headlineSize(forBody: bodySize)) { texts.append(title) }
        for line in bodyLines {
            texts.append(Text(inlineFormatted(line, font: baseFont(bodySize), color: foreground)))
        }
        return texts.map { text in
            let resolved = context.resolve(text)
            let whole = resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
            guard wrapping, whole.width > area.width else { return Line(text: text, size: whole, wrapped: false) }
            return Line(text: text, size: resolved.measure(in: CGSize(width: area.width, height: CGFloat.infinity)), wrapped: true)
        }
    }
    func blockHeight(_ lines: [Line]) -> CGFloat {
        guard !lines.isEmpty else { return 0 }
        return lines.reduce(0) { $0 + $1.size.height } + CGFloat(lines.count - 1) * lineSpacing
    }

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

    /// The largest body size in `low...high` whose layout fits; with `wrapping`
    /// off that means every line whole (no line wider than the area).
    func largestFit(wrapping: Bool) -> CGFloat {
        func fits(_ size: CGFloat) -> Bool {
            let lines = layout(bodySize: size, wrapping: wrapping)
            return blockHeight(lines) <= area.height && lines.allSatisfy { $0.size.width <= area.width + 1 }
        }
        if fits(high) { return high }
        var lowBound = low, highBound = high
        for _ in 0..<9 {
            let mid = (lowBound + highBound) / 2
            if fits(mid) { lowBound = mid } else { highBound = mid }
        }
        return lowBound
    }

    var wrapping = false
    var chosen = largestFit(wrapping: false)
    if chosen < comfortableBodySize {
        let wrapped = largestFit(wrapping: true)
        if wrapped > chosen, chosen < readableBodySize || wrapped >= chosen * wrapGain {
            chosen = wrapped
            wrapping = true
        }
    }
    chosen = max(low, chosen * min(1, textScale))

    let final = layout(bodySize: chosen, wrapping: wrapping)
    let height = blockHeight(final)
    var y = area.minY + max(0, (area.height - height) / 2)
    for line in final {
        let x = centered ? area.minX + max(0, (area.width - line.size.width) / 2) : area.minX
        context.draw(context.resolve(line.text), in: CGRect(x: x, y: y, width: line.size.width, height: line.size.height))
        y += line.size.height + lineSpacing
    }
    return TextFit(bodySize: chosen, headlineSize: headlineSize(forBody: chosen),
                   wrappedLines: final.filter(\.wrapped).count, height: height)
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
