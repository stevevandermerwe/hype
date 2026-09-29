import SwiftUI
import HypeCore
#if canImport(AppKit)
import AppKit
#endif

/// PDF and HTML export — the Mac app's counterpart to the Qt app's
/// `exporter.cpp`/`html.cpp`. Shared by `HypeApp` (the File menu) and
/// `HypeCLI` (`export`). PowerPoint export is not implemented (a stretch goal
/// noted in `../../ROADMAP.md`, not required for Phase 2).
public enum ExportError: LocalizedError {
    case cannotCreateFile(String)
    case noSlides
    public var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let path): return "Could not create \(path)"
        case .noSlides: return "This presentation has no slides"
        }
    }
}

/// The standard 16:9 slide size PowerPoint/Keynote use for PDF pages, in points.
private let pdfPageSize = CGSize(width: 960, height: 540)
/// Raster export resolution for HTML's embedded images (960×540 already reads
/// crisply at typical window sizes; Qt exports at 4K, which this Phase 2 port
/// does not match, to keep exported HTML files smaller).
private let htmlImageSize = CGSize(width: 1920, height: 1080)

@MainActor
public func exportPDF(deck: DeckModel, to url: URL) throws {
    guard deck.count > 0 else { throw ExportError.noSlides }
    var mediaBox = CGRect(origin: .zero, size: pdfPageSize)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw ExportError.cannotCreateFile(url.path)
    }
    for index in 0..<deck.count {
        let view = SlidePreviewView(
            slideSource: deck.slideSource(at: index),
            baseDir: deck.baseDir,
            palette: deck.palette,
            textScale: deck.textScale,
            fontName: deck.fontName,
            headerOptions: deck.headerOptions(forIndex: index)
        )
        .frame(width: pdfPageSize.width, height: pdfPageSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.render { _, drawInContext in
            pdfContext.beginPDFPage(nil)
            pdfContext.saveGState()
            drawInContext(pdfContext)
            pdfContext.restoreGState()
            pdfContext.endPDFPage()
        }
    }
    pdfContext.closePDF()
}

@MainActor
private func renderPNGBase64(source: String, baseDir: String, palette: Palette, textScale: Double, fontName: String, headerOptions: SlideHeaderOptions) -> String? {
    let view = SlidePreviewView(
        slideSource: source,
        baseDir: baseDir,
        palette: palette,
        textScale: textScale,
        fontName: fontName,
        headerOptions: headerOptions
    )
    .frame(width: htmlImageSize.width, height: htmlImageSize.height)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(htmlImageSize)
    #if canImport(AppKit)
    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
    return png.base64EncodedString()
    #else
    return nil
    #endif
}

@MainActor
public func exportHTML(deck: DeckModel, to url: URL) throws {
    guard deck.count > 0 else { throw ExportError.noSlides }
    var images: [String] = []
    for index in 0..<deck.count {
        guard let base64 = renderPNGBase64(
            source: deck.slideSource(at: index),
            baseDir: deck.baseDir,
            palette: deck.palette,
            textScale: deck.textScale,
            fontName: deck.fontName,
            headerOptions: deck.headerOptions(forIndex: index)
        )
        else { throw ExportError.cannotCreateFile(url.path) }
        images.append(base64)
    }
    let html = htmlDocument(title: deck.title, backgroundHex: deck.palette.background, imagesBase64: images)
    guard let data = html.data(using: .utf8) else { throw ExportError.cannotCreateFile(url.path) }
    try data.write(to: url, options: .atomic)
}

/// Renders one slide to a PNG file at `size` (default 4K) — the Mac app's
/// counterpart to the Qt CLI's `hype render`.
@MainActor
public func renderSlidePNG(deck: DeckModel, index: Int, to url: URL, size: CGSize = CGSize(width: 3840, height: 2160)) throws {
    let view = SlidePreviewView(
        slideSource: deck.slideSource(at: index),
        baseDir: deck.baseDir,
        palette: deck.palette,
        textScale: deck.textScale,
        fontName: deck.fontName,
        headerOptions: deck.headerOptions(forIndex: index)
    )
    .frame(width: size.width, height: size.height)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(size)
    #if canImport(AppKit)
    guard let nsImage = renderer.nsImage, let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
        throw ExportError.cannotCreateFile(url.path)
    }
    try png.write(to: url, options: .atomic)
    #else
    throw ExportError.cannotCreateFile(url.path)
    #endif
}

/// A single self-contained HTML file: every slide is a base64 PNG, so it opens
/// in any browser with no network or companion files. Matches the Qt app's
/// documented HTML viewer controls (see `README.md`): arrow keys, Space,
/// Page Up/Down, and Home/End navigate; `F` toggles fullscreen; `G` shows a grid.
private func htmlDocument(title: String, backgroundHex: String, imagesBase64: [String]) -> String {
    let escapedTitle = title.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    let slidesJS = imagesBase64.map { "\"data:image/png;base64,\($0)\"" }.joined(separator: ",\n")
    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <title>\(escapedTitle)</title>
    <style>
      html, body { margin: 0; height: 100%; background: \(backgroundHex); overflow: hidden; }
      #stage { display: flex; align-items: center; justify-content: center; width: 100%; height: 100%; }
      #stage img { max-width: 100%; max-height: 100%; }
      #grid { display: none; flex-wrap: wrap; align-content: flex-start; gap: 12px; padding: 24px; width: 100%; height: 100%;
              box-sizing: border-box; overflow: auto; background: \(backgroundHex); }
      #grid.shown { display: flex; }
      #grid img { width: 220px; cursor: pointer; border: 2px solid transparent; border-radius: 4px; }
      #grid img.current { border-color: #7aa2f7; }
      #stage.hidden { display: none; }
    </style>
    </head>
    <body>
    <div id="stage"><img id="slideImage" src=""></div>
    <div id="grid"></div>
    <script>
      const slides = [
    \(slidesJS)
      ];
      let index = 0;
      const stage = document.getElementById('stage');
      const grid = document.getElementById('grid');
      const image = document.getElementById('slideImage');
      function show(i) {
        index = Math.max(0, Math.min(slides.length - 1, i));
        image.src = slides[index];
      }
      function buildGrid() {
        grid.innerHTML = '';
        slides.forEach((src, i) => {
          const img = document.createElement('img');
          img.src = src;
          img.className = i === index ? 'current' : '';
          img.addEventListener('click', () => { show(i); hideGrid(); });
          grid.appendChild(img);
        });
      }
      function showGrid() { buildGrid(); grid.classList.add('shown'); stage.classList.add('hidden'); }
      function hideGrid() { grid.classList.remove('shown'); stage.classList.remove('hidden'); }
      function toggleGrid() { grid.classList.contains('shown') ? hideGrid() : showGrid(); }
      function toggleFullscreen() {
        if (document.fullscreenElement) document.exitFullscreen();
        else document.documentElement.requestFullscreen();
      }
      document.addEventListener('keydown', (event) => {
        switch (event.key) {
          case 'ArrowRight': case 'ArrowDown': case ' ': case 'PageDown': show(index + 1); break;
          case 'ArrowLeft': case 'ArrowUp': case 'PageUp': show(index - 1); break;
          case 'Home': show(0); break;
          case 'End': show(slides.length - 1); break;
          case 'f': case 'F': toggleFullscreen(); break;
          case 'g': case 'G': toggleGrid(); break;
        }
      });
      show(0);
    </script>
    </body>
    </html>
    """
}
