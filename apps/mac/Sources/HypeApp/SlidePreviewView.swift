import SwiftUI
import HypeCore

/// Renders one slide's Markdown as a 16:9 picture, scaled to fit the view.
/// The Mac app's counterpart to the Qt editor's live slide preview.
struct SlidePreviewView: View {
    let slideSource: String
    let baseDir: String
    let palette: Palette

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 1920
            context.scaleBy(x: scale, y: scale)
            drawSlide(&context, source: slideSource, baseDir: baseDir, palette: palette)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(Color(hex: palette.background))
        .clipped()
    }
}
