import SwiftUI
import HypeCore
#if canImport(AppKit)
import AppKit
#endif

private let inlineRe = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*|\*(.+?)\*|_(.+?)_"#)

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
               textScale: CGFloat = 1, fontName: String = "") {
    let full = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    context.fill(Path(full), with: .color(Color(hex: palette.background)))
    let media = parseMedia(source, base: baseDir)
    var foreground = Color(hex: palette.foreground)
    let textArea = slideTextArea(for: media)
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
        if !split, media.overlay > 0 {
            context.fill(Path(full), with: .color(.black.opacity(media.overlay)))
            if !trimmedText.isEmpty { foreground = .white }
        }
    }
    if !trimmedText.isEmpty {
        drawSlideText(&context, text: trimmedText, area: textArea, foreground: foreground, palette: palette, textScale: textScale, fontName: fontName)
    }
    if !media.error.isEmpty {
        let banner = CGRect(x: 0, y: 1000, width: 1920, height: 80)
        context.fill(Path(banner), with: .color(Color(hex: "#9b3030")))
        context.draw(Text(media.error).foregroundColor(.white), in: banner.insetBy(dx: 30, dy: 20))
    }
}
