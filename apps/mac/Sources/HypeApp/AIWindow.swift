import SwiftUI
import HypeCore

/// The AI dialogs live in their own ordinary window rather than a sheet, so
/// they can be moved, resized, and closed like any other window, and the
/// editor stays usable behind them. `AppUI.aiTask` says which one to show.
enum AIWindow {
    static let id = "ai"
}

struct AIWindowContent: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    @EnvironmentObject var ui: AppUI
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        content
            .navigationTitle(ui.aiTask?.title ?? "AI")
            .frame(minWidth: 480, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .topLeading)
            .background(.background)
            .onDisappear {
                // Closing the window mid-request abandons the request, rather
                // than letting it land later on a deck the user moved on from.
                if generator.busy { generator.cancel() }
                ui.aiTask = nil
            }
    }

    @ViewBuilder private var content: some View {
        switch ui.aiTask {
        case .generate(let mode):
            GenerateSheet(mode: mode, close: close) { path, warnings in
                // The new presentation is already saved; only opening it would replace unsaved edits.
                guard confirmDiscardChanges(deck) else {
                    deck.setStatus("Created \(path) — not opened, so your current edits are untouched")
                    return
                }
                deck.loadPath(path)
                ui.showStartPage = false
                deck.setStatus(warnings.isEmpty ? "Created \(path)"
                    : "Created; \(warnings.count) warning\(warnings.count > 1 ? "s" : ""), run check")
            }
            .id(ui.aiTask)
        case .slideAssist(let index):
            SlideAssistSheet(slideIndex: index, close: close) { summary, warnings in
                let note = warnings.isEmpty ? "" : "; \(warnings.count) warning\(warnings.count > 1 ? "s" : ""), see the slide"
                deck.setStatus(summary + " · Cmd+Z undoes it" + note)
            }
            .id(ui.aiTask)
        case .rewriteDeck:
            DeckRewriteSheet(close: close) { summary in deck.setStatus(summary + " · Cmd+Z undoes it") }
                .id(ui.aiTask)
        case .speakerNotes:
            SpeakerNotesSheet(close: close) { summary in deck.setStatus(summary + " · Cmd+Z undoes it") }
                .id(ui.aiTask)
        case nil:
            // Reached when macOS restores this window at launch with nothing asked of it.
            ContentUnavailableView {
                Label("Nothing to generate", systemImage: "sparkles")
            } actions: {
                Button("Close", action: close)
            }
        }
    }

    private func close() { dismissWindow(id: AIWindow.id) }
}
