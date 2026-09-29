import SwiftUI
import HypeCore

/// The sidebar: one small preview per slide, selectable and reorderable —
/// the Mac app's counterpart to the Qt editor's slide thumbnail rail.
struct SlideListView: View {
    @ObservedObject var deck: DeckModel

    var body: some View {
        List(selection: Binding(get: { deck.selected }, set: { if let value = $0 { deck.select(value) } })) {
            ForEach(deck.parsed.slides.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    SlidePreviewView(slideSource: deck.slideSource(at: index), baseDir: deck.baseDir, palette: deck.palette)
                        .frame(height: 90)
                        .cornerRadius(4)
                    Text("Slide \(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(index)
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
