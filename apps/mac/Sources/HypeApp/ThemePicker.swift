import SwiftUI
import HypeCore
import HypeRender

/// A toolbar button that opens a gallery of every bundled theme, each shown
/// as the current slide rendered in that theme. Clicking one applies it
/// (undoable) and leaves the gallery open, so themes can be compared.
struct ThemePickerButton: View {
    @ObservedObject var deck: DeckModel
    @State private var isShowing = false

    var body: some View {
        Button { isShowing.toggle() } label: { Label("Theme", systemImage: "paintpalette") }
            .help("Theme")
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                ThemeGallery(deck: deck)
            }
    }
}

private struct ThemeGallery: View {
    @ObservedObject var deck: DeckModel
    private let columns = Array(repeating: GridItem(.fixed(168), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Dark", BundledTheme.allCases.filter { !$0.isLight })
                section("Light", BundledTheme.allCases.filter(\.isLight))
            }
            .padding(16)
        }
        .frame(width: 568, height: 520)
    }

    private func section(_ title: String, _ themes: [BundledTheme]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(themes) { theme in
                    ThemeCard(deck: deck, theme: theme, isCurrent: deck.themeName == theme.rawValue)
                }
            }
        }
    }
}

private struct ThemeCard: View {
    @ObservedObject var deck: DeckModel
    let theme: BundledTheme
    let isCurrent: Bool
    @State private var isHovered = false

    var body: some View {
        Button { deck.chooseTheme(theme.rawValue) } label: {
            VStack(alignment: .leading, spacing: 6) {
                SlidePreviewView(slideSource: deck.slideSource(at: deck.selected), baseDir: deck.baseDir,
                                 palette: theme.palette, textScale: deck.textScale)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isCurrent ? Color.accentColor : Color.primary.opacity(isHovered ? 0.35 : 0.12),
                                          lineWidth: isCurrent ? 3 : 1)
                    )
                HStack(spacing: 5) {
                    swatches
                    Text(theme.displayName).font(.callout).lineLimit(1)
                    Spacer(minLength: 0)
                    if isCurrent { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var swatches: some View {
        HStack(spacing: -3) {
            ForEach([theme.palette.accent, theme.palette.magenta, theme.palette.green], id: \.self) { hex in
                Circle().fill(Color(hex: hex)).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 1))
            }
        }
    }
}
