import SwiftUI
import HypeCore

/// Find and replace across every slide of the deck. Matches update as you type;
/// click one to jump to its slide. "Replace All" (or "Replace in This Slide") is
/// a single undo step. Shown in its own window so the editor stays usable.
struct FindReplaceView: View {
    @EnvironmentObject var deck: DeckModel

    @State private var query = ""
    @State private var replacement = ""
    @State private var options = SearchOptions()
    @State private var matches: [SearchMatch] = []
    @State private var problem = ""
    @FocusState private var findFocused: Bool

    private static let displayLimit = 300

    private var slideCount: Int { Set(matches.map(\.slide)).count }
    private var matchesInSelectedSlide: Int { matches.filter { $0.slide == deck.selected }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WindowHeader(icon: "magnifyingglass", title: "Find and replace",
                         subtitle: "Searches every slide, including speaker notes and code. Picture filenames are never touched.")

            Form {
                TextField("Find", text: $query).focused($findFocused)
                TextField("Replace with", text: $replacement)
            }
            .formStyle(.columns)

            HStack(spacing: 16) {
                Toggle("Match case", isOn: $options.caseSensitive)
                Toggle("Whole word", isOn: $options.wholeWord)
                Toggle("Regular expression", isOn: $options.regex)
            }
            .toggleStyle(.checkbox)

            summary

            List {
                ForEach(matches.prefix(Self.displayLimit)) { match in
                    MatchRow(match: match, isCurrent: match.slide == deck.selected)
                        .contentShape(Rectangle())
                        .onTapGesture { deck.select(match.slide) }
                }
                if matches.count > Self.displayLimit {
                    Text("…and \(matches.count - Self.displayLimit) more").font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 160)
            .overlay { if matches.isEmpty { emptyState } }

            HStack {
                Spacer()
                Button("Replace in Slide \(deck.selected + 1)") { replace(onlySlide: deck.selected) }
                    .disabled(matchesInSelectedSlide == 0)
                Button("Replace All") { replace(onlySlide: nil) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(matches.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 460)
        .onAppear { findFocused = true; search() }
        .onChange(of: query) { _, _ in search() }
        .onChange(of: options) { _, _ in search() }
        .onChange(of: deck.parsed) { _, _ in search() }
    }

    @ViewBuilder private var summary: some View {
        if !problem.isEmpty {
            Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
        } else if !query.isEmpty {
            Text(matches.isEmpty ? "No matches" : "\(matches.count) match\(matches.count == 1 ? "" : "es") in \(slideCount) slide\(slideCount == 1 ? "" : "s")")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Text(" ").font(.callout)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if query.isEmpty {
            Text("Type something to find").foregroundStyle(.tertiary)
        }
    }

    private func search() {
        switch findMatches(in: deck.slideTexts, query: query, options: options) {
        case .success(let found): matches = found; problem = ""
        case .failure(let error): matches = []; problem = error.description
        }
    }

    private func replace(onlySlide: Int?) {
        switch replaceMatches(in: deck.slideTexts, query: query, replacement: replacement, options: options, onlySlide: onlySlide) {
        case .success(let result):
            guard result.count > 0 else { return }
            deck.replaceSlides(result.slides)
            let slides = onlySlide == nil ? slideCount : 1
            deck.setStatus("Replaced \(result.count) match\(result.count == 1 ? "" : "es") in \(slides) slide\(slides == 1 ? "" : "s") · Cmd+Z undoes it")
            problem = ""
            search()
        case .failure(let error):
            problem = error.description
        }
    }
}

/// One result: the slide number and the match in its line, highlighted.
private struct MatchRow: View {
    let match: SearchMatch
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(match.slide + 1)")
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(isCurrent ? .white : .secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
            Text(context).lineLimit(1).truncationMode(.middle)
        }
    }

    private var context: AttributedString {
        var before = AttributedString(match.before)
        var found = AttributedString(match.text)
        var after = AttributedString(match.after)
        before.foregroundColor = .secondary
        after.foregroundColor = .secondary
        found.font = .body.bold()
        found.backgroundColor = Color.accentColor.opacity(0.25)
        return before + found + after
    }
}
