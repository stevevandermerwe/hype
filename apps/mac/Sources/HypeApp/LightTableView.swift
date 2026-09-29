import SwiftUI
import HypeCore
import HypeRender

/// Every slide at once, as a grid of thumbnails you can drag to rearrange —
/// like a photo light table. Click selects, double-click (or Return) opens
/// the slide in the editor, Delete removes it. Thumbnail size is adjustable
/// (`LightTableSizeSlider`, shown in the window's status bar) and remembered.
struct LightTableView: View {
    @ObservedObject var deck: DeckModel
    var onOpenSlide: (Int) -> Void

    @AppStorage(LightTableSizeSlider.storageKey) private var thumbnailWidth: Double = LightTableSizeSlider.defaultWidth
    @State private var dragging: Int?
    @State private var dropTarget: Int?

    private let spacing: CGFloat = 24

    var body: some View {
        ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailWidth, maximum: thumbnailWidth * 1.4),
                                                 spacing: spacing)],
                              spacing: spacing) {
                        ForEach(deck.parsed.slides.indices, id: \.self) { index in
                            cell(index).id(index)
                        }
                    }
                    .padding(spacing)
                }
                .onAppear { proxy.scrollTo(deck.selected, anchor: .center) }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .focusable()
            .focusEffectDisabled()
            .onDeleteCommand { if deck.count > 1 { deck.deleteSlide() } }
            .onKeyPress(.return) { onOpenSlide(deck.selected); return .handled }
            .onKeyPress(.leftArrow) { step(-1); return .handled }
            .onKeyPress(.rightArrow) { step(1); return .handled }
    }

    private func cell(_ index: Int) -> some View {
        LightTableCell(deck: deck, index: index, isSelected: index == deck.selected,
                       dropEdge: dropEdge(for: index))
            .onTapGesture(count: 2) { onOpenSlide(index) }
            .onTapGesture { deck.select(index) }
            .onDrag {
                dragging = index
                return NSItemProvider(object: String(index) as NSString)
            }
            .onDrop(of: [.plainText], delegate: SlideDropDelegate(
                target: index, dragging: $dragging, dropTarget: $dropTarget,
                move: { from, to in deck.moveSlide(from: from, to: to) }))
            .contextMenu {
                Button("Edit Slide") { onOpenSlide(index) }
                Button("Duplicate") { deck.select(index); deck.duplicateSlide() }
                Divider()
                Button("Delete", role: .destructive) { deck.select(index); deck.deleteSlide() }
                    .disabled(deck.count <= 1)
            }
    }

    /// Where the dragged slide would land relative to `index`: after it when
    /// moving forward, before it when moving back.
    private func dropEdge(for index: Int) -> HorizontalEdge? {
        guard dropTarget == index, let dragging, dragging != index else { return nil }
        return dragging < index ? .trailing : .leading
    }

    private func step(_ delta: Int) {
        deck.select(max(0, min(deck.count - 1, deck.selected + delta)))
    }
}

/// The light table's thumbnail-size control, for the window's status bar.
struct LightTableSizeSlider: View {
    static let storageKey = "lightTableThumbnailWidth"
    static let defaultWidth: Double = 260
    static let widthRange: ClosedRange<Double> = 140...520
    @AppStorage(storageKey) private var thumbnailWidth: Double = defaultWidth

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3")
            Slider(value: $thumbnailWidth, in: Self.widthRange)
                .frame(width: 120)
                .controlSize(.mini)
            Image(systemName: "square.grid.2x2")
        }
        .help("Thumbnail size")
    }
}

private struct LightTableCell: View {
    @ObservedObject var deck: DeckModel
    let index: Int
    let isSelected: Bool
    let dropEdge: HorizontalEdge?
    @EnvironmentObject var health: SlideHealth
    @State private var isHovered = false

    var body: some View {
        let source = deck.slideSource(at: index)
        VStack(alignment: .leading, spacing: 8) {
            SlidePreviewView(slideSource: source, baseDir: deck.baseDir, palette: deck.palette, textScale: deck.textScale, fontName: deck.fontName)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.3 : 0.1),
                                      lineWidth: isSelected ? 3 : 1)
                )
                .shadow(color: .black.opacity(isHovered ? 0.3 : 0.18), radius: isHovered ? 10 : 5, y: isHovered ? 5 : 2)
                .overlay(alignment: .topTrailing) {
                    if let report = health.report(for: index) { CrampedBadge(report: report).padding(8) }
                }
            HStack(spacing: 6) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
                Text(title(source)).font(.callout).lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .overlay(alignment: dropEdge == .leading ? .leading : .trailing) {
            if dropEdge != nil {
                Capsule().fill(Color.accentColor).frame(width: 4)
                    .padding(.vertical, 4)
                    .offset(x: dropEdge == .leading ? -14 : 14)
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
    }

    private func title(_ source: String) -> String {
        let text = slideTitle(parseMedia(source, base: deck.baseDir).text)
        return text.isEmpty ? "Untitled" : text
    }
}

/// Drops a dragged slide onto another slide's cell, moving it to that
/// position. Only slides dragged from this light table are accepted.
private struct SlideDropDelegate: DropDelegate {
    let target: Int
    @Binding var dragging: Int?
    @Binding var dropTarget: Int?
    let move: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropEntered(info: DropInfo) { dropTarget = target }
    func dropExited(info: DropInfo) { if dropTarget == target { dropTarget = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil; dropTarget = nil }
        guard let from = dragging, from != target else { return false }
        withAnimation(.easeInOut(duration: 0.2)) { move(from, target) }
        return true
    }
}
