import SwiftUI
import HypeCore

/// "Generate with AI": a prompt (or, in mind-map mode, a pasted outline) goes
/// to the configured endpoint and comes back as a new presentation folder,
/// which is then opened. Matches the Qt app's `GenerateDialog.qml`. Shown in
/// the resizable AI window (`AIWindow.swift`), so the prompt box grows with it.
struct GenerateSheet: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    /// "plan": describe a talk. "mindmap": paste an outline to turn into slides.
    let mode: String
    var close: () -> Void
    var onGenerated: (String, [String]) -> Void

    @State private var prompt = ""
    @State private var theme = "tokyo-night"
    @State private var showSettings = false
    @State private var error = ""
    @State private var keyToStore = ""

    private var isMindMap: Bool { mode == "mindmap" }
    private var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !generator.busy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WindowHeader(
                icon: isMindMap ? "point.topleft.down.curvedto.point.bottomright.up" : "sparkles",
                title: isMindMap ? "Mind map" : "Generate with AI",
                subtitle: isMindMap
                    ? "Paste an indented outline, a Markdown list, or OPML. Each branch becomes slides, in your order and your words."
                    : "Describe the presentation. Hype writes a new folder with the slides and their images, then opens it."
            )

            PromptEditor(
                text: $prompt,
                placeholder: isMindMap ? "- Topic\n  - Point\n  - Point" : "A 10-minute talk introducing our new API to developers…",
                isDisabled: generator.busy
            )
            .frame(minHeight: 120, maxHeight: .infinity)

            HStack {
                Picker("Theme", selection: $theme) {
                    ForEach(BundledTheme.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .fixedSize()
                Spacer()
                keyBadge
            }
            .disabled(generator.busy)

            DisclosureGroup("Endpoint and model", isExpanded: $showSettings) {
                settings.padding(.top, 8)
            }
            .disabled(generator.busy)

            RequestStatus(isBusy: generator.busy, status: generator.status, error: error)

            HStack {
                Spacer()
                Button(generator.busy ? "Stop" : "Cancel") {
                    if generator.busy { generator.cancel() } else { close() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Generate") { Task { await start() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGenerate)
            }
            .controlSize(.large)
        }
        .padding(24)
        .onAppear { theme = deck.themeName.isEmpty ? "tokyo-night" : deck.themeName }
    }

    private var keyBadge: some View {
        let hasKey = generator.keySource != nil
        return Label(hasKey ? "API key ready" : "No API key", systemImage: hasKey ? "checkmark.seal.fill" : "key.slash")
            .font(.caption)
            .foregroundStyle(hasKey ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            .onTapGesture { showSettings = true }
    }

    private var settings: some View {
        Form {
            TextField("Endpoint", text: $generator.config.endpoint, prompt: Text("OpenAI-compatible chat completions URL"))
            TextField("Model", text: $generator.config.model)
            TextField("Key variable", text: $generator.config.keyEnvironmentVariable, prompt: Text("HYPE_AI_KEY"))
            LabeledContent("Keychain") {
                HStack {
                    SecureField("API key", text: $keyToStore, prompt: Text("Paste an API key to save it"))
                        .labelsHidden()
                    Button("Save") {
                        if AIKeychain.save(keyToStore) { keyToStore = "" } else { error = "Could not save to the Keychain." }
                    }
                    .disabled(keyToStore.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            TextField("Save to", text: $generator.config.outputRoot, prompt: Text(defaultOutputRoot()))
            Text(generator.keySource.map { "Using the key from \($0)." }
                 ?? "No API key found. Set the variable before launching Hype, or save one to the Keychain.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.columns)
    }

    private func start() async {
        error = ""
        generator.saveSettings()
        switch await generator.generate(prompt: prompt, theme: theme, directory: nil, mode: mode) {
        case .success(let written):
            onGenerated(written.path, written.warnings)
            close()
        case .failure(let failure):
            error = failure.message
        }
    }
}
