import SwiftUI
import HypeCore
import HypeRender
#if canImport(AppKit)
import AppKit
#endif

/// A full-window, fullscreen-able presentation of the current slide — the
/// Mac app's counterpart to the Qt editor's Present mode. Arrow keys and
/// Space move forward, Home/End jump to the ends, and Escape closes the
/// window (matching the Qt app's documented shortcuts; there is no video
/// playback yet, so Space's "play/pause video" role is not implemented in
/// Phase 2).
struct PresenterView: View {
    @EnvironmentObject var deck: DeckModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        GeometryReader { geometry in
            SlidePreviewView(slideSource: deck.slideSource(at: deck.selected), baseDir: deck.baseDir, palette: deck.palette, textScale: deck.textScale, fontName: deck.fontName)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(hex: deck.palette.background))
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { advance(1); return .handled }
        .onKeyPress(.downArrow) { advance(1); return .handled }
        .onKeyPress(.pageDown) { advance(1); return .handled }
        .onKeyPress(.leftArrow) { advance(-1); return .handled }
        .onKeyPress(.upArrow) { advance(-1); return .handled }
        .onKeyPress(.pageUp) { advance(-1); return .handled }
        .onKeyPress(.space) { advance(1); return .handled }
        .onKeyPress(.home) { deck.select(0); return .handled }
        .onKeyPress(.end) { deck.select(deck.count - 1); return .handled }
        .onKeyPress(.escape) { closePresenter(); return .handled }
        .onAppear { enterFullScreen() }
    }

    private func advance(_ delta: Int) {
        deck.select(max(0, min(deck.count - 1, deck.selected + delta)))
    }
    private func closePresenter() {
        #if canImport(AppKit)
        NSApp.keyWindow?.toggleFullScreen(nil)
        #endif
        dismissWindow(id: "presenter")
    }
    private func enterFullScreen() {
        #if canImport(AppKit)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
        #endif
    }
}
