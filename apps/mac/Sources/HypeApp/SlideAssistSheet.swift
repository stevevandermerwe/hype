import SwiftUI
import HypeCore

/// "Ask AI" for the selected slide: rewrite its text, add a drawn diagram, or
/// add a generated picture. Applies the change as one edit, so Cmd+Z undoes
/// it. Matches the Qt app's `SlideAssistDialog.qml`.
struct SlideAssistSheet: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    @Environment(\.dismiss) private var dismiss
    var onApplied: (String, [String]) -> Void

    @State private var kind = "text"
    @State private var instruction = ""
    @State private var error = ""
    private let slideIndex: Int

    init(slideIndex: Int, onApplied: @escaping (String, [String]) -> Void) {
        self.slideIndex = slideIndex
        self.onApplied = onApplied
    }

    private struct Kind: Identifiable { let id: String; let label: String; let hint: String; let example: String }
    private let kinds: [Kind] = [
        Kind(id: "text", label: "Text", hint: "Rewrites the slide's text.", example: "Make this punchier and cut it to three bullets"),
        Kind(id: "diagram", label: "Diagram", hint: "Rewrites the text and draws an SVG picture beside it.",
            example: "Add a diagram of the request flow"),
        Kind(id: "image", label: "Image", hint: "Adds a picture from the image model. The text stays as it is.",
            example: "A calm sunrise over a data center"),
    ]
    private var current: Kind { kinds.first { $0.id == kind }! }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask AI").font(.title2).bold()
            Text("Changes the selected slide. Undo with Cmd+Z.").font(.callout).foregroundStyle(.secondary)

            Picker("", selection: $kind) {
                ForEach(kinds) { Text($0.label).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .disabled(generator.busy)
            Text(current.hint).font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $instruction)
                .font(.body)
                .frame(height: 90)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .disabled(generator.busy)
                .overlay(alignment: .topLeading) {
                    if instruction.isEmpty {
                        Text(current.example + "…").foregroundStyle(.tertiary).padding(14).allowsHitTesting(false)
                    }
                }

            if kind == "image" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Image model (uses the same API key)").font(.caption).foregroundStyle(.secondary)
                    TextField("", text: $generator.config.imageModel)
                    Text("Image endpoint (leave empty to use the chat endpoint)").font(.caption).foregroundStyle(.secondary)
                    TextField(generator.config.endpoint, text: $generator.config.imageEndpoint)
                }
            }
            if kind != "text", deck.baseDir.isEmpty {
                Text("Save the presentation first (Cmd+S), so the picture has a folder to go in.")
                    .font(.caption).foregroundStyle(.red)
            }
            if generator.keySource == nil {
                Text("No API key found. Set it up under File → Generate with AI… → Endpoint and model.")
                    .font(.caption).foregroundStyle(.red)
            }
            if generator.busy {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(generator.status).font(.callout)
                }
            }
            if !error.isEmpty, !generator.busy {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(generator.busy ? "Stop" : "Close") {
                    if generator.busy { generator.cancel() } else { dismiss() }
                }
                Button("Go") { Task { await start() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || generator.busy)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func start() async {
        error = ""
        generator.saveSettings()
        let outline = deck.slideOutline()
        let slideText = deck.slideText(at: slideIndex)
        switch await generator.editSlide(instruction: instruction, kind: kind, slide: slideText, outline: outline,
                                         index: slideIndex, baseDir: deck.baseDir) {
        case .success(let outcome):
            guard deck.selected == slideIndex else {
                error = "The selected slide changed while waiting, so nothing was applied."
                return
            }
            deck.editSlide(outcome.slide)
            onApplied(outcome.summary, outcome.warnings)
            dismiss()
        case .failure(let failure):
            error = failure.message
        }
    }
}
