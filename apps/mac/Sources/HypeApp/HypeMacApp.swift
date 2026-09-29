import SwiftUI
import HypeCore
import HypeRender
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// The app's entry point: one presentation window, plus File/Edit/Slide/Present
/// menu commands, PDF/HTML export, a presenter window, and a separate,
/// resizable AI window (`AIWindow.swift`).

/// Which format `exportPresentation(kind:)` writes.
enum ExportKind { case pdf, html }

@main
struct HypeMacApp: App {
    @StateObject private var deck = DeckModel()
    @StateObject private var generator = Generator()
    @StateObject private var ui = AppUI()
    @StateObject private var editor = EditorController()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deck)
                .environmentObject(generator)
                .environmentObject(ui)
                .environmentObject(editor)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Presentation") { deck.newDeck(); ui.showStartPage = false }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open…") { if chooseAndOpenPresentation(deck) { ui.showStartPage = false } }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Save") { saveOrSaveAsPresentation(deck) }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") { chooseAndSaveAsPresentation(deck) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Generate with AI…") { ui.openAI(.generate("plan")) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Start page") { ui.showStartPage = true }
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
            CommandGroup(before: .toolbar) {
                Button("Slide") { ui.editorMode = .slide }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Light Table") { ui.editorMode = .lightTable }
                    .keyboardShortcut("2", modifiers: .command)
                Divider()
            }
            CommandMenu("Format") {
                Button("Bigger Text") { deck.setTextScale(TextScale.bigger(deck.textScale)) }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(deck.textScale >= TextScale.maximum)
                Button("Smaller Text") { deck.setTextScale(TextScale.smaller(deck.textScale)) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(deck.textScale <= TextScale.minimum)
                Button("Default Text Size") { deck.setTextScale(1) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Group {
                    Button("Heading") { editor.apply(.heading) }
                        .keyboardShortcut("1", modifiers: [.command, .option])
                    Button("Bold") { editor.apply(.bold) }
                        .keyboardShortcut("b", modifiers: .command)
                    Button("Italic") { editor.apply(.italic) }
                        .keyboardShortcut("i", modifiers: .command)
                    Button("Underline") { editor.apply(.underline) }
                        .keyboardShortcut("u", modifiers: .command)
                    Button("Inline Code") { editor.apply(.inlineCode) }
                        .keyboardShortcut("c", modifiers: [.command, .option])
                    Divider()
                    Button("Bulleted List") { editor.apply(.bulletList) }
                        .keyboardShortcut("2", modifiers: [.command, .option])
                    Button("Numbered List") { editor.apply(.numberedList) }
                        .keyboardShortcut("3", modifiers: [.command, .option])
                    Button("Quote") { editor.apply(.quote) }
                        .keyboardShortcut("4", modifiers: [.command, .option])
                    Button("Code Block") { editor.apply(.codeBlock(language: "")) }
                        .keyboardShortcut("5", modifiers: [.command, .option])
                    Button("Table") { editor.apply(.table) }
                        .keyboardShortcut("6", modifiers: [.command, .option])
                    Button("Speaker Note") { editor.apply(.note) }
                        .keyboardShortcut("n", modifiers: [.command, .option])
                    Divider()
                    Button("Insert Picture or Video…") { editor.insertPicture(into: deck) }
                        .keyboardShortcut("m", modifiers: [.command, .shift])
                }
                .disabled(ui.editorMode != .slide || ui.showStartPage)
            }
            CommandMenu("Slide") {
                Button("New Slide") { deck.addSlide() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Duplicate") { deck.duplicateSlide() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Delete") { deck.deleteSlide() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(deck.count <= 1)
                Divider()
                Button("Move Earlier") { deck.moveSlide(from: deck.selected, to: deck.selected - 1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .disabled(deck.selected == 0)
                Button("Move Later") { deck.moveSlide(from: deck.selected, to: deck.selected + 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .disabled(deck.selected >= deck.count - 1)
            }
        }

        Window("AI", id: AIWindow.id) {
            AIWindowContent()
                .environmentObject(deck)
                .environmentObject(generator)
                .environmentObject(ui)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 580, height: 560)
        .defaultPosition(.center)
        .commandsRemoved()

        Window("Presenter", id: "presenter") {
            PresenterView()
                .environmentObject(deck)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 720)
        .commandsRemoved()
    }

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
}
