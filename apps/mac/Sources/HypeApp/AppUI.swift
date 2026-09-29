import SwiftUI

/// Which sheet is presented over the main window: whole-deck generation
/// (`"plan"` or `"mindmap"` mode) or the per-slide Ask AI assistant.
enum ActiveSheet: Identifiable, Equatable {
    case generate(String)
    case slideAssist(Int)
    var id: String {
        switch self {
        case .generate(let mode): return "generate-\(mode)"
        case .slideAssist(let index): return "assist-\(index)"
        }
    }
}

/// Cross-cutting UI state the File menu (`HypeMacApp`) and the main window
/// (`ContentView`) both need to read and write — separate from `DeckModel`,
/// which owns the document, not view routing.
@MainActor
final class AppUI: ObservableObject {
    @Published var showStartPage = true
    @Published var sheet: ActiveSheet?
}
