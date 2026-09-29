import SwiftUI
import AppKit
import HypeCore

/// Adds a slide from `template` after the selected slide. Picture layouts first
/// ask for a picture, which is copied into the deck's folder (so the deck must
/// be saved); cancelling the picker adds nothing.
@MainActor
func addSlide(from template: SlideTemplate, deck: DeckModel) {
    var picture: String?
    if template.needsPicture {
        guard !deck.baseDir.isEmpty else {
            deck.setStatus(MediaImportError.needsSavedDeck.errorDescription ?? "Save the presentation first.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the picture for this slide. It is copied into the presentation's folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            picture = try importMedia(from: url, into: deck.baseDir)
        } catch {
            deck.setStatus(error.localizedDescription)
            return
        }
    }
    guard let text = template.text(picture: picture) else { return }
    deck.insertSlide(text, after: deck.selected)
    deck.setStatus("Added a \(template.name.lowercased()) slide · Cmd+Z undoes it")
}

/// The template choices, for the toolbar's Add Slide menu and the Slide menu.
struct TemplateMenuItems: View {
    @ObservedObject var deck: DeckModel

    var body: some View {
        ForEach(SlideTemplate.allCases.filter { !$0.needsPicture }) { template in
            Button { addSlide(from: template, deck: deck) } label: { Label(template.name, systemImage: template.icon) }
        }
        Divider()
        ForEach(SlideTemplate.allCases.filter(\.needsPicture)) { template in
            Button { addSlide(from: template, deck: deck) } label: { Label(template.name + "…", systemImage: template.icon) }
        }
    }
}
