import SwiftUI
import HypeCore

/// What the AI window is doing: whole-deck generation (`"plan"` or
/// `"mindmap"` mode) or the per-slide Ask AI assistant.
enum AITask: Hashable {
    case generate(String)
    case slideAssist(Int)
    case rewriteDeck
    case speakerNotes

    var title: String {
        switch self {
        case .generate(let mode): return mode == "mindmap" ? "Mind Map" : "Generate with AI"
        case .slideAssist(let index): return "Ask AI — Slide \(index + 1)"
        case .rewriteDeck: return "Rewrite Deck"
        case .speakerNotes: return "Speaker Notes"
        }
    }
}

/// Cross-cutting UI state the File menu (`HypeMacApp`) and the main window
/// (`ContentView`) both need to read and write — separate from `DeckModel`,
/// which owns the document, not view routing.
/// The main window's layouts: one slide with its Markdown, the whole file
/// as a text editor, or every slide on a light table for arranging the deck.
enum EditorMode: String, Hashable {
    case slide
    case source
    case lightTable
}

@MainActor
final class AppUI: ObservableObject {
    @Published var showStartPage = true
    @Published var editorMode: EditorMode = .slide
    @Published var aiTask: AITask?
    /// The theme being made or edited, shown as a sheet over the main window.
    @Published var themeDraft: ThemeDraft?
    /// The help topic to display in the Help window.
    @Published var helpTopic: HelpTopic = .help
    /// Bumped on every `openAI` call, so asking again for the same task still
    /// brings an already-open (possibly buried) AI window back to the front.
    @Published private(set) var aiRequest = 0

    /// Bumped to ask the format bar to open its "Generate a picture" popover.
    @Published private(set) var pictureRequest = 0
    func requestPicturePopover() { pictureRequest += 1 }

    func openAI(_ task: AITask) {
        aiTask = task
        aiRequest += 1
    }
}
