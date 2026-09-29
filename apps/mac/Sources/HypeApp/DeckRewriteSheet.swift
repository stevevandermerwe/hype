import SwiftUI
import HypeCore

/// "Rewrite the whole deck": one instruction ("make this more concise",
/// "translate to Spanish") applied to every slide at once, as a single undoable
/// edit. Shown in the resizable AI window (`AIWindow.swift`).
struct DeckRewriteSheet: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    var close: () -> Void
    var onApplied: (String) -> Void

    @State private var instruction = ""
    @State private var error = ""

    private static let suggestions = [
        "Make it more concise", "Simplify the language", "Make it more persuasive", "Fix spelling and grammar",
        "Make the tone friendlier", "Make it more formal", "Translate to Spanish", "Translate to French",
    ]
    private var canGo: Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !generator.busy && deck.count > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WindowHeader(icon: "wand.and.stars", title: "Rewrite the whole deck",
                         subtitle: "Applies one instruction to all \(deck.count) slide\(deck.count == 1 ? "" : "s"). "
                                 + "Pictures and layout stay as they are, and it's a single undo (⌘Z).")

            SuggestionChips(items: Self.suggestions) { instruction = $0 }
                .disabled(generator.busy)

            PromptEditor(text: $instruction, placeholder: "What should change? For example: Translate everything to German",
                         isDisabled: generator.busy)
                .frame(minHeight: 100, maxHeight: .infinity)

            AIDestinationNote(config: generator.config, what: "All \(deck.count) slides")
            if generator.keySource == nil { NoKeyNote() }
            RequestStatus(isBusy: generator.busy, status: generator.status, error: error)

            HStack {
                Spacer()
                Button(generator.busy ? "Stop" : "Cancel") {
                    if generator.busy { generator.cancel() } else { close() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Rewrite Deck") { Task { await start() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGo)
            }
            .controlSize(.large)
        }
        .padding(24)
    }

    private func start() async {
        error = ""
        generator.saveSettings()
        let snapshot = deck.slideTexts
        switch await generator.rewriteDeck(instruction: instruction, slides: snapshot) {
        case .success(let result):
            // This window doesn't block the editor, so the deck may have changed meanwhile.
            guard deck.slideTexts == snapshot else {
                error = "The deck changed while waiting, so nothing was applied."
                return
            }
            deck.replaceSlides(result.slides)
            onApplied("Rewrote \(result.changed) of \(result.slides.count) slide\(result.slides.count == 1 ? "" : "s")")
            close()
        case .failure(let failure):
            error = failure.message
        }
    }
}
