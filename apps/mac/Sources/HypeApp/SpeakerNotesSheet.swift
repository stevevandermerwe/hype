import SwiftUI
import HypeCore

/// "Suggest speaker notes": the model drafts what to say for each slide, and
/// each note is added to its slide as a hidden `<!-- comment -->`. Shown in the
/// resizable AI window (`AIWindow.swift`).
struct SpeakerNotesSheet: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    var close: () -> Void
    var onApplied: (String) -> Void

    private enum Scope: Hashable { case all, current }
    @State private var scope: Scope = .all
    @State private var replaceExisting = false
    @State private var guidance = ""
    @State private var error = ""

    private static let styles = ["Short and punchy", "Detailed", "Casual tone", "Include timing hints", "Add a story or example"]

    /// The slides that would get a note (0-based), given the scope and whether existing notes are replaced.
    private var targets: [Int] {
        let candidates = scope == .all ? Array(0..<deck.count) : [deck.selected]
        return candidates.filter { replaceExisting || speakerNote(in: deck.slideSource(at: $0)) == nil }
    }
    private var alreadyNoted: Int {
        (scope == .all ? Array(0..<deck.count) : [deck.selected]).filter { speakerNote(in: deck.slideSource(at: $0)) != nil }.count
    }
    private var canGo: Bool { !targets.isEmpty && !generator.busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WindowHeader(icon: "text.bubble", title: "Suggest speaker notes",
                         subtitle: "Drafts what to say for each slide. Notes are hidden comments in the slide, "
                                 + "so they never show on screen or in exports. One undo (⌘Z) removes them all.")

            Picker("For", selection: $scope) {
                Text("All slides").tag(Scope.all)
                Text("Slide \(deck.selected + 1) only").tag(Scope.current)
            }
            .pickerStyle(.segmented)
            .disabled(generator.busy)

            Toggle("Replace notes that slides already have", isOn: $replaceExisting)
                .disabled(generator.busy)

            Text(summary).font(.callout).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Style (optional)").font(.callout.weight(.medium))
                SuggestionChips(items: Self.styles) { guidance = $0 }
                TextField("", text: $guidance, prompt: Text("e.g. two sentences each, in a warm tone"))
                    .textFieldStyle(.roundedBorder)
            }
            .disabled(generator.busy)

            Spacer(minLength: 0)
            AIDestinationNote(config: generator.config, what: "The whole deck (for context)")
            if generator.keySource == nil { NoKeyNote() }
            RequestStatus(isBusy: generator.busy, status: generator.status, error: error)

            HStack {
                Spacer()
                Button(generator.busy ? "Stop" : "Cancel") {
                    if generator.busy { generator.cancel() } else { close() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Write Notes") { Task { await start() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGo)
            }
            .controlSize(.large)
        }
        .padding(24)
    }

    private var summary: String {
        if targets.isEmpty { return "Every slide here already has a note. Turn on “Replace” to write new ones." }
        var text = "Will write notes for \(targets.count) slide\(targets.count == 1 ? "" : "s")."
        if !replaceExisting, alreadyNoted > 0 { text += " \(alreadyNoted) already \(alreadyNoted == 1 ? "has" : "have") a note and stay\(alreadyNoted == 1 ? "s" : "") as is." }
        return text
    }

    private func start() async {
        error = ""
        generator.saveSettings()
        let snapshot = deck.slideTexts
        let wanted = targets
        switch await generator.suggestNotes(slides: snapshot, targets: wanted, guidance: guidance) {
        case .success(let result):
            guard deck.slideTexts == snapshot else {
                error = "The deck changed while waiting, so nothing was applied."
                return
            }
            let applied = applyingNotes(result.notes, to: snapshot, replacing: replaceExisting)
            deck.replaceSlides(applied.slides)
            let missing = wanted.count - result.notes.count
            var summary = "Added notes to \(applied.added) slide\(applied.added == 1 ? "" : "s")"
            if missing > 0 { summary += "; the model skipped \(missing)" }
            onApplied(summary)
            close()
        case .failure(let failure):
            error = failure.message
        }
    }
}
