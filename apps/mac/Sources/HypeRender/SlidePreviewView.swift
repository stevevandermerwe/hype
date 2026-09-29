import SwiftUI
import HypeCore

/// Renders one slide's Markdown as a 16:9 picture, scaled to fit the view.
/// The Mac app's counterpart to the Qt editor's live slide preview. Shared by
/// `HypeApp` (the live editor/presenter) and `HypeCLI` (`render`/`export`),
/// so both draw a slide exactly the same way.
public struct SlidePreviewView: View {
    let slideSource: String
    let baseDir: String
    let palette: Palette
    let textScale: Double
    let fontName: String
    let headerOptions: SlideHeaderOptions

    public init(
        slideSource: String,
        baseDir: String,
        palette: Palette,
        textScale: Double = 1,
        fontName: String = "",
        headerOptions: SlideHeaderOptions = SlideHeaderOptions()
    ) {
        self.slideSource = slideSource
        self.baseDir = baseDir
        self.palette = palette
        self.textScale = textScale
        self.fontName = fontName
        self.headerOptions = headerOptions
    }

    public var body: some View {
        Canvas { context, size in
            let scale = size.width / 1920
            context.scaleBy(x: scale, y: scale)
            drawSlide(&context, source: slideSource, baseDir: baseDir, palette: palette, textScale: textScale, fontName: fontName, headerOptions: headerOptions)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(Color(hex: palette.background))
        .clipped()
    }
}
