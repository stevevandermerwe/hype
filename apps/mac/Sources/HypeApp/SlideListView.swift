import SwiftUI
import HypeCore
import HypeRender

/// The sidebar: one small preview per slide, selectable and reorderable —
/// the Mac app's counterpart to the Qt editor's slide thumbnail rail.
struct SlideListView: View {
    @ObservedObject var deck: DeckModel

    var body: some View {
        List(selection: Binding(get: { deck.selected }, set: { if let value = $0 { deck.select(value) } })) {
            ForEach(deck.parsed.slides.indices, id: \.self) { index in
                SlideThumbnail(deck: deck, index: index, isSelected: index == deck.selected)
                    .tag(index)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .contextMenu {
                        Button("Duplicate") { deck.select(index); deck.duplicateSlide() }
                        Button("Delete", role: .destructive) { deck.select(index); deck.deleteSlide() }
                            .disabled(deck.count <= 1)
                    }
            }
            .onMove { indices, destination in
                guard let from = indices.first else { return }
                let to = destination > from ? destination - 1 : destination
                deck.moveSlide(from: from, to: to)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SlideThumbnail: View {
    @ObservedObject var deck: DeckModel
    let index: Int
    let isSelected: Bool

    var body: some View {
        let source = deck.slideSource(at: index)
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1)")
                .font(.caption.weight(.semibold)).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                SlidePreviewView(slideSource: source, baseDir: deck.baseDir, palette: deck.palette, textScale: deck.textScale)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                Text(title(source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private func title(_ source: String) -> String {
        let text = slideTitle(parseMedia(source, base: deck.baseDir).text)
        return text.isEmpty ? "Untitled" : text
    }
}
