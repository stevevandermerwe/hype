import SwiftUI
import HypeCore

/// "Generate with AI": a prompt (or, in mind-map mode, a pasted outline) goes
/// to the configured endpoint and comes back as a new presentation folder,
/// which is then opened. Matches the Qt app's `GenerateDialog.qml`.
struct GenerateSheet: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    @Environment(\.dismiss) private var dismiss
    /// "plan": describe a talk. "mindmap": paste an outline to turn into slides.
    let mode: String
    var onGenerated: (String, [String]) -> Void

    @State private var prompt = ""
    @State private var theme = "tokyo-night"
    @State private var showSettings = false
    @State private var error = ""
    @State private var keyToStore = ""

    private var isMindMap: Bool { mode == "mindmap" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isMindMap ? "Mind map" : "Generate with AI").font(.title2).bold()
            Text(isMindMap
                 ? "Paste your mind map: an indented outline, a Markdown list, or OPML exported from a mind-map tool. Each branch becomes slides, in your order and your words."
                 : "Describe the presentation. Hype writes a new folder with the slides and their images, then opens it.")
                .font(.callout).foregroundStyle(.secondary)

            TextEditor(text: $prompt)
                .font(.body)
                .frame(height: isMindMap ? 220 : 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                .disabled(generator.busy)

            HStack {
                Text("Theme").foregroundStyle(.secondary)
                Picker("", selection: $theme) {
                    ForEach(BundledTheme.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .labelsHidden()
                .disabled(generator.busy)
            }

            DisclosureGroup("Endpoint and model", isExpanded: $showSettings) {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledField("Endpoint (any OpenAI-compatible chat completions URL)", text: $generator.config.endpoint)
                    LabeledField("Model", text: $generator.config.model)
                    LabeledField("Environment variable holding the API key", text: $generator.config.keyEnvironmentVariable)
                    Text(generator.keySource != nil ? "Using the key from \(generator.keySource!)."
                        : "No API key found. Set that variable before launching Hype, or save one to the Keychain below.")
                        .font(.caption).foregroundStyle(generator.keySource != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    HStack {
                        SecureField("Paste an API key to save it to the Keychain", text: $keyToStore)
                        Button("Save key") {
                            if AIKeychain.save(keyToStore) { keyToStore = "" } else { error = "Could not save to the Keychain." }
                        }.disabled(keyToStore.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    LabeledField("New presentations are created in", text: $generator.config.outputRoot,
                                placeholder: defaultOutputRoot())
                }
                .padding(.top, 6)
            }
            .disabled(generator.busy)

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
                Button("Generate") { Task { await start() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || generator.busy)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { theme = deck.themeName == "" ? "tokyo-night" : deck.themeName }
    }

    private func start() async {
        error = ""
        generator.saveSettings()
        switch await generator.generate(prompt: prompt, theme: theme, directory: nil, mode: mode) {
        case .success(let written):
            onGenerated(written.path, written.warnings)
            dismiss()
        case .failure(let failure):
            error = failure.message
        }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    init(_ label: String, text: Binding<String>, placeholder: String = "") {
        self.label = label; self._text = text; self.placeholder = placeholder
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
        }
    }
}
