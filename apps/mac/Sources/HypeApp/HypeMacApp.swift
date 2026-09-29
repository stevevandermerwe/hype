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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var deck = DeckModel(recovery: .shared)
    @StateObject private var generator = Generator()
    @StateObject private var ui = AppUI()
    @StateObject private var editor = EditorController()
    @StateObject private var health = SlideHealth()
    @StateObject private var library = ThemeLibrary()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deck)
                .environmentObject(generator)
                .environmentObject(ui)
                .environmentObject(editor)
                .environmentObject(health)
                .environmentObject(library)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Presentation") { if confirmDiscardChanges(deck) { deck.newDeck(); ui.showStartPage = false } }
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
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find and Replace…") { openWindow(id: "find") }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(ui.showStartPage || deck.count == 0)
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
                Button("Source") { ui.editorMode = .source }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Light Table") { ui.editorMode = .lightTable }
                    .keyboardShortcut("3", modifiers: .command)
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
                Button("New Theme…") { ui.themeDraft = ThemeDraft(name: "", palette: deck.palette, editingSlug: nil) }
                    .disabled(ui.showStartPage)
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
            CommandMenu("AI") {
                Button("Ask AI About This Slide…") { ui.openAI(.slideAssist(deck.selected)) }
                    .keyboardShortcut("j", modifiers: .command)
                Button("Rewrite Whole Deck…") { ui.openAI(.rewriteDeck) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button("Suggest Speaker Notes…") { ui.openAI(.speakerNotes) }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                Button("Generate a Picture…") { ui.requestPicturePopover() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(ui.editorMode != .slide)
                Divider()
                Button("Generate a Presentation…") { ui.openAI(.generate("plan")) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandMenu("Slide") {
                Button("New Slide") { deck.addSlide() }
                    .keyboardShortcut(.return, modifiers: .command)
                Menu("New Slide from Template") { TemplateMenuItems(deck: deck) }
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
            CommandMenu("Help") {
                Button("Hype Help") { ui.helpTopic = .help; openWindow(id: "help") }
                Button("Markdown Format") { ui.helpTopic = .format; openWindow(id: "help") }
                Button("Keyboard Shortcuts") { ui.helpTopic = .keyboardShortcuts; openWindow(id: "help") }
                Button("YAML Front Matter") { ui.helpTopic = .yamlFrontMatter; openWindow(id: "help") }
            }
        }

        Window("Find and Replace", id: "find") {
            FindReplaceView()
                .environmentObject(deck)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 540, height: 560)
        .commandsRemoved()

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

        Window("Help", id: "help") {
            HelpView(topic: $ui.helpTopic)
                .toolbar { ToolbarItem { HelpToolbar(topic: $ui.helpTopic) } }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 800)
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

/// Application-level hooks: keeps unsaved edits from being lost when the app
/// quits, and keeps the recovery copy fresh when you switch away.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The deck being edited; set by the main window.
    nonisolated(unsafe) static weak var deck: DeckModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let deck = Self.deck, deck.dirty else { return .terminateNow }
        return MainActor.assumeIsolated { confirmDiscardChanges(deck) } ? .terminateNow : .terminateCancel
    }

    func applicationDidResignActive(_ notification: Notification) {
        Self.deck?.flushRecoverySnapshot()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.deck?.flushRecoverySnapshot()
    }
}
