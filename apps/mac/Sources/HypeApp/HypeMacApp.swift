import SwiftUI
import HypeCore
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// The app's entry point: one presentation window, plus File/Edit/Slide menu
/// commands. There is no start page, AI generation, presenter mode, or export
/// yet — see `../../ROADMAP.md` for what Phase 1 covers.
@main
struct HypeMacApp: App {
    @StateObject private var deck = DeckModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deck)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Presentation") { deck.newDeck() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { openPresentation() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Save") { savePresentation() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { saveAsPresentation() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { deck.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!deck.canUndo)
                Button("Redo") { deck.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!deck.canRedo)
            }
            CommandMenu("Slide") {
                Button("New Slide") { deck.addSlide() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Duplicate") { deck.duplicateSlide() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Delete") { deck.deleteSlide() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(deck.count <= 1)
            }
        }
    }

    private var markdownType: UTType { UTType(filenameExtension: "md") ?? .plainText }

    private func openPresentation() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [markdownType]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            deck.loadPath(url.path)
        }
        #endif
    }
    private func savePresentation() {
        if deck.path == nil { saveAsPresentation() } else { deck.save() }
    }
    private func saveAsPresentation() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [markdownType]
        panel.nameFieldStringValue = "presentation.md"
        if panel.runModal() == .OK, let url = panel.url {
            deck.savePath(url.path)
        }
        #endif
    }
}
