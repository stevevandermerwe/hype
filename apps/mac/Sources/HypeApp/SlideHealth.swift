import SwiftUI
import HypeCore
import HypeRender

/// Which slides hold too much text to read, kept up to date as the deck is
/// edited. Checking a slide means fitting its text, so this waits for a pause in
/// typing and remembers the answer for each slide's exact text, so only edited
/// slides are re-measured.
@MainActor
final class SlideHealth: ObservableObject {
    /// Slides (by index) whose text had to shrink below a readable size.
    @Published private(set) var cramped: [Int: SlideTextReport] = [:]

    private var cache: [String: SlideTextReport?] = [:]
    private var pending: Task<Void, Never>?
    private static let pause: Duration = .milliseconds(300)

    /// Re-checks the deck after a short pause (each new call restarts the pause).
    func refresh(_ deck: DeckModel) {
        pending?.cancel()
        pending = Task { [weak self, weak deck] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled, let self, let deck else { return }
            self.recompute(deck)
        }
    }

    /// Checks every slide now.
    func recompute(_ deck: DeckModel) {
        var found: [Int: SlideTextReport] = [:]
        for index in 0..<deck.count {
            let source = deck.slideSource(at: index)
            let key = "\(deck.textScale)|\(deck.fontName)|\(source)"
            let report: SlideTextReport?
            if let cached = cache[key] {
                report = cached
            } else {
                report = measureSlideText(source: source, baseDir: deck.baseDir, textScale: deck.textScale, fontName: deck.fontName)
                cache[key] = .some(report)
            }
            if let report, report.isCramped { found[index] = report }
        }
        if found != cramped { cramped = found }
        if cache.count > 500 { cache.removeAll() }
    }

    func report(for index: Int) -> SlideTextReport? { cramped[index] }
}

/// "Too much text" as words, for tooltips and the banner.
func crampedDescription(_ report: SlideTextReport) -> String {
    "Too much text: it shrinks to \(Int((report.readability * 100).rounded()))% of a readable size"
}

/// A small orange warning mark for a slide's corner in the sidebar and light table.
struct CrampedBadge: View {
    let report: SlideTextReport

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white, .orange)
            .padding(4)
            .background(Circle().fill(.orange))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .help(crampedDescription(report) + ". Split the slide or cut words.")
            .accessibilityLabel(crampedDescription(report))
    }
}
