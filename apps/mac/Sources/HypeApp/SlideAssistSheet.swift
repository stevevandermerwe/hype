import SwiftUI
import HypeCore

/// "Ask AI" for the selected slide: rewrite its text, add a drawn diagram, or
/// add a generated picture. Applies the change as one edit, so Cmd+Z undoes
/// it. Matches the Qt app's `SlideAssistDialog.qml`. Shown in the resizable
/// AI window (`AIWindow.swift`).
struct SlideAssistSheet: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    var close: () -> Void
    var onApplied: (String, [String]) -> Void

    @State private var kind = "text"
    @State private var instruction = ""
    @State private var error = ""
    private let slideIndex: Int

    init(slideIndex: Int, close: @escaping () -> Void, onApplied: @escaping (String, [String]) -> Void) {
        self.slideIndex = slideIndex
        self.close = close
        self.onApplied = onApplied
    }

    private struct Kind: Identifiable { let id: String; let label: String; let icon: String; let hint: String; let example: String }
    private let kinds: [Kind] = [
        Kind(id: "text", label: "Text", icon: "text.alignleft", hint: "Rewrites the slide's text.",
             example: "Make this punchier and cut it to three bullets"),
        Kind(id: "diagram", label: "Diagram", icon: "flowchart", hint: "Rewrites the text and draws an SVG picture beside it.",
             example: "Add a diagram of the request flow"),
        Kind(id: "image", label: "Image", icon: "photo", hint: "Adds a picture from the image model. The text stays as it is.",
             example: "A calm sunrise over a data center"),
    ]
    private var current: Kind { kinds.first { $0.id == kind } ?? kinds[0] }
    private var canGo: Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !generator.busy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WindowHeader(icon: "sparkles", title: "Ask AI",
                         subtitle: "Changes slide \(slideIndex + 1). Undo with Cmd+Z.")

            Picker("", selection: $kind) {
                ForEach(kinds) { Label($0.label, systemImage: $0.icon).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(generator.busy)
            Text(current.hint).font(.callout).foregroundStyle(.secondary)

            PromptEditor(text: $instruction, placeholder: current.example + "…", isDisabled: generator.busy)
                .frame(minHeight: 100, maxHeight: .infinity)

            if kind == "image" {
                Form {
                    TextField("Image model", text: $generator.config.imageModel)
                    TextField("Image endpoint", text: $generator.config.imageEndpoint,
                              prompt: Text(generator.config.endpoint))
                }
                .formStyle(.columns)
            }
            warnings
            RequestStatus(isBusy: generator.busy, status: generator.status, error: error)

            HStack {
                Spacer()
                Button(generator.busy ? "Stop" : "Cancel") {
                    if generator.busy { generator.cancel() } else { close() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Apply") { Task { await start() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGo)
            }
            .controlSize(.large)
        }
        .padding(24)
    }

    @ViewBuilder private var warnings: some View {
        if kind != "text", deck.baseDir.isEmpty {
            Label("Save the presentation first (Cmd+S), so the picture has a folder to go in.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
        if generator.keySource == nil {
            Label("No API key found. Set it up under File → Generate with AI… → Endpoint and model.", systemImage: "key.slash")
                .font(.caption).foregroundStyle(.red)
        }
    }

    private func start() async {
        error = ""
        generator.saveSettings()
        let outline = deck.slideOutline()
        let slideText = deck.slideText(at: slideIndex)
        switch await generator.editSlide(instruction: instruction, kind: kind, slide: slideText, outline: outline,
                                         index: slideIndex, baseDir: deck.baseDir) {
        case .success(let outcome):
            // This window doesn't block the editor, so the slide can change under it.
            guard deck.selected == slideIndex, slideIndex < deck.count else {
                error = "The selected slide changed while waiting, so nothing was applied."
                return
            }
            deck.editSlide(outcome.slide)
            onApplied(outcome.summary, outcome.warnings)
            close()
        case .failure(let failure):
            error = failure.message
        }
    }
}
