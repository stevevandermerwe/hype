import SwiftUI
import HypeCore
import HypeRender

/// A toolbar button that opens a searchable list of the fonts installed on this
/// Mac, each shown in its own typeface. The choice is saved in the deck's
/// `font:` front matter (one undo step) and used by the editor, presenter, and
/// every export. A deck naming a font that isn't installed here still opens,
/// set in the system font.
struct FontPickerButton: View {
    @ObservedObject var deck: DeckModel
    @State private var isShowing = false

    var body: some View {
        Button { isShowing.toggle() } label: { Label("Font", systemImage: "textformat") }
            .help(deck.fontName.isEmpty ? "Font" : "Font: \(deck.fontName)")
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                FontList(deck: deck) { isShowing = false }
            }
    }
}

private struct FontList: View {
    @ObservedObject var deck: DeckModel
    var done: () -> Void
    @State private var search = ""
    private let families = availableFontFamilies()

    private var shown: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? families : families.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search fonts", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            if !deck.fontName.isEmpty, !isFontAvailable(deck.fontName) {
                Label("“\(deck.fontName)” isn't installed on this Mac, so slides use the system font.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if search.isEmpty {
                        row("System (default)", font: .body, isCurrent: deck.fontName.isEmpty) { deck.setFontName("") }
                    }
                    ForEach(shown, id: \.self) { family in
                        row(family, font: .custom(family, size: 16), isCurrent: deck.fontName.caseInsensitiveCompare(family) == .orderedSame) {
                            deck.setFontName(family)
                        }
                    }
                    if shown.isEmpty { Text("No fonts match").foregroundStyle(.secondary).padding(16) }
                }
            }
        }
        .frame(width: 320, height: 420)
    }

    private func row(_ title: String, font: Font, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            done()
        } label: {
            HStack {
                Text(title).font(font).lineLimit(1)
                Spacer()
                if isCurrent { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}
