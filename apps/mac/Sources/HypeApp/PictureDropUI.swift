import SwiftUI
import AppKit
import HypeCore

/// Handles picture/video files dropped onto slide `index` (the preview, a sidebar
/// thumbnail, or the Markdown editor). Returns whether the drop held any
/// pictures — if so it was consumed, and the status bar says what happened.
@MainActor
func acceptPictureDrop(_ urls: [URL], onto index: Int, deck: DeckModel) -> Bool {
    guard !mediaFiles(in: urls).isEmpty else { return false }
    switch dropPictures(urls, onto: index, in: deck) {
    case .success(let message): deck.setStatus(message + " · Cmd+Z undoes it")
    case .failure(let error): deck.setStatus(error.localizedDescription)
    }
    return true
}

/// A soft highlight with a hint, shown over a view while pictures are dragged onto it.
struct DropHint: View {
    var text = "Drop to add the picture"

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.accentColor.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6])))
            .overlay(Label(text, systemImage: "photo.badge.plus").font(.headline).foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule()))
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}
