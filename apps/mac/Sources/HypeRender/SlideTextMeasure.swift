import SwiftUI
import HypeCore

/// How a slide's text came out when fitted, for warning about slides that hold
/// too much. Sizes are in units of a 1080-tall slide.
public struct SlideTextReport: Equatable, Sendable {
    /// The body size that fit the slide's text area (before the deck's `text_scale`).
    public var fittedBodySize: Double
    /// The text had to shrink below a readable size (or overflow): split or cut it.
    public var isCramped: Bool
    /// Lines (or table cells) that had to wrap.
    public var wrappedLines: Int

    /// The fitted size relative to the smallest readable one: 1 or more is
    /// fine, 0.5 means text at half a readable size.
    public var readability: Double { fittedBodySize / Double(readableBodySize) }
}

/// Fits `source`'s text exactly as drawing it would, without loading pictures,
/// and reports the result; nil if the slide has no text. `baseDir` is only
/// needed to resolve the slide's media reference.
@MainActor
public func measureSlideText(source: String, baseDir: String, textScale: Double = 1, fontName: String = "") -> SlideTextReport? {
    let media = parseMedia(source, base: baseDir)
    let text = media.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let area = slideTextArea(for: media)

    // The fitter needs a live GraphicsContext to measure with, which only a
    // Canvas provides. The canvas itself is tiny: only the measurements matter.
    final class Result { var fit: TextFit? }
    let result = Result()
    let canvas = Canvas { context, _ in
        result.fit = drawSlideText(&context, text: text, area: area, foreground: .white, textScale: CGFloat(textScale), fontName: fontName)
    }
    .frame(width: 16, height: 9)
    _ = ImageRenderer(content: canvas).cgImage
    guard let fit = result.fit else { return nil }
    return SlideTextReport(fittedBodySize: Double(fit.fittedBodySize), isCramped: fit.isCramped, wrappedLines: fit.wrappedLines)
}
