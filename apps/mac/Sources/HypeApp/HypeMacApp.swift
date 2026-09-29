import SwiftUI
import HypeCore
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// The app's entry point: one presentation window, plus File/Edit/Slide/Present
/// menu commands, PDF/HTML export, and a presenter window. There is no start
/// page, AI generation, or CLI yet — see `../../ROADMAP.md` for phase status.
/// Which format `exportPresentation(kind:)` writes.
enum ExportKind { case pdf, html }

@main
struct HypeMacApp: App {
    @StateObject private var deck = DeckModel()
    @Environment(\.openWindow) private var openWindow

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
                Divider()
                Button("Export as PDF…") { exportPresentation(kind: .pdf) }
                    .keyboardShortcut("e", modifiers: .command)
                Button("Export as HTML…") { exportPresentation(kind: .html) }
            }
            CommandMenu("Present") {
                Button("Present") { openWindow(id: "presenter") }
                    .keyboardShortcut("p", modifiers: .command)
                    .disabled(deck.count == 0)
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

        Window("Presenter", id: "presenter") {
            PresenterView()
                .environmentObject(deck)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 720)
        .commandsRemoved()
    }

    private var markdownType: UTType { UTType(filenameExtension: "md") ?? .plainText }
    private var pdfType: UTType { .pdf }
    private var htmlType: UTType { .html }

    private func exportPresentation(kind: ExportKind) {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        switch kind {
        case .pdf:
            panel.allowedContentTypes = [pdfType]
            panel.nameFieldStringValue = "presentation.pdf"
        case .html:
            panel.allowedContentTypes = [htmlType]
            panel.nameFieldStringValue = "presentation.html"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch kind {
            case .pdf: try exportPDF(deck: deck, to: url)
            case .html: try exportHTML(deck: deck, to: url)
            }
            deck.setStatus("Exported \(url.lastPathComponent)")
        } catch {
            deck.setStatus(error.localizedDescription)
        }
        #endif
    }

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
