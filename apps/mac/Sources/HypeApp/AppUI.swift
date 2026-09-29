import SwiftUI

/// What the AI window is doing: whole-deck generation (`"plan"` or
/// `"mindmap"` mode) or the per-slide Ask AI assistant.
enum AITask: Hashable {
    case generate(String)
    case slideAssist(Int)

    var title: String {
        switch self {
        case .generate(let mode): return mode == "mindmap" ? "Mind Map" : "Generate with AI"
        case .slideAssist(let index): return "Ask AI — Slide \(index + 1)"
        }
    }
}

/// Cross-cutting UI state the File menu (`HypeMacApp`) and the main window
/// (`ContentView`) both need to read and write — separate from `DeckModel`,
/// which owns the document, not view routing.
@MainActor
final class AppUI: ObservableObject {
    @Published var showStartPage = true
    @Published var aiTask: AITask?
    /// Bumped on every `openAI` call, so asking again for the same task still
    /// brings an already-open (possibly buried) AI window back to the front.
    @Published private(set) var aiRequest = 0

    func openAI(_ task: AITask) {
        aiTask = task
        aiRequest += 1
    }
}
