import SwiftUI
import HypeCore

/// Generate a picture for the current slide right from the editor's format bar,
/// without opening the Ask AI window: describe it, pick a style, and it is drawn
/// by the image model, saved into the deck's `images/` folder, and added to the
/// slide (one undo step).
struct PicturePopover: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    @Binding var isPresented: Bool

    @State private var prompt = ""
    @State private var style = PictureStyle.none
    @State private var error = ""

    enum PictureStyle: String, CaseIterable, Identifiable {
        case none = "Any style", illustration = "Illustration", photo = "Photo", flat = "Flat vector",
             watercolor = "Watercolor", render = "3D render", lineArt = "Minimal line art"
        var id: String { rawValue }
        /// Words added to the prompt for this style ("" for none).
        var phrase: String {
            switch self {
            case .none: return ""
            case .illustration: return "in a clean illustration style"
            case .photo: return "as a realistic photograph"
            case .flat: return "as a flat vector illustration"
            case .watercolor: return "as a soft watercolor painting"
            case .render: return "as a polished 3D render"
            case .lineArt: return "as minimal line art"
            }
        }
    }

    private var slideTitle: String { HypeCore.slideTitle(parseMedia(deck.slideText(at: deck.selected), base: "").text) }
    private var canGo: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !generator.busy && !deck.baseDir.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Generate a picture", systemImage: "wand.and.stars").font(.headline)

            TextField("", text: $prompt,
                      prompt: Text(slideTitle.isEmpty ? "Describe the picture…" : "Describe the picture for “\(slideTitle)”…"),
                      axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .disabled(generator.busy)
                .onSubmit { Task { await start() } }

            HStack {
                Picker("Style", selection: $style) {
                    ForEach(PictureStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                .fixedSize()
                Spacer()
                Text(generator.config.imageModel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .disabled(generator.busy)

            if deck.baseDir.isEmpty {
                Label("Save the presentation first (⌘S), so the picture has a folder to go in.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if generator.keySource == nil { NoKeyNote() }
            RequestStatus(isBusy: generator.busy, status: generator.status, error: error)

            HStack {
                Text("Replaces this slide's picture, if it has one.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(generator.busy ? "Stop" : "Cancel") {
                    if generator.busy { generator.cancel() } else { isPresented = false }
                }
                Button("Generate") { Task { await start() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canGo)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onDisappear { if generator.busy { generator.cancel() } }
    }

    private func start() async {
        guard canGo else { return }
        error = ""
        generator.saveSettings()
        let request = [prompt.trimmingCharacters(in: .whitespacesAndNewlines), style.phrase].filter { !$0.isEmpty }.joined(separator: ", ")
        switch await generator.addPicture(request, to: deck) {
        case .success(let message):
            deck.setStatus(message + " · Cmd+Z undoes it")
            isPresented = false
        case .failure(let failure):
            error = failure.message
        }
    }
}
