import SwiftUI
import HypeCore
import HypeRender

/// A toolbar button that opens a gallery of every theme — the bundled ones and
/// your own — each shown as the current slide rendered in that theme. Clicking
/// one applies it (undoable) and leaves the gallery open, so themes can be
/// compared. "New theme…" opens the theme editor; right-click one of your own
/// themes to edit or delete it.
struct ThemePickerButton: View {
    @ObservedObject var deck: DeckModel
    @EnvironmentObject var ui: AppUI
    @EnvironmentObject var library: ThemeLibrary
    @State private var isShowing = false

    var body: some View {
        Button { isShowing.toggle() } label: { Label("Theme", systemImage: "paintpalette") }
            .help("Theme")
            .popover(isPresented: $isShowing, arrowEdge: .bottom) {
                ThemeGallery(deck: deck, library: library) { draft in
                    isShowing = false
                    ui.themeDraft = draft
                }
            }
    }
}

private struct ThemeGallery: View {
    @ObservedObject var deck: DeckModel
    @ObservedObject var library: ThemeLibrary
    var openEditor: (ThemeDraft) -> Void
    private let columns = Array(repeating: GridItem(.fixed(168), spacing: 12), count: 3)

    private var bundled: [ThemeChoice] { bundledThemeChoices() }
    private var yours: [ThemeChoice] {
        library.custom.map { ThemeChoice(id: $0.slug, displayName: $0.name, palette: $0.palette, isCustom: true) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Themes").font(.title3.weight(.semibold))
                    Spacer()
                    Button {
                        openEditor(ThemeDraft(name: "", palette: deck.palette, editingSlug: nil))
                    } label: { Label("New theme…", systemImage: "plus") }
                        .controlSize(.small)
                }
                if !yours.isEmpty { section("Yours", yours) }
                section("Dark", bundled.filter { !$0.isLight })
                section("Light", bundled.filter(\.isLight))
            }
            .padding(16)
        }
        .frame(width: 568, height: 540)
    }

    private func section(_ title: String, _ themes: [ThemeChoice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(themes) { theme in
                    ThemeCard(deck: deck, theme: theme, isCurrent: deck.themeName == theme.id)
                        .contextMenu {
                            if theme.isCustom, let saved = library.custom.first(where: { $0.slug == theme.id }) {
                                Button("Edit…") {
                                    openEditor(ThemeDraft(name: saved.name, palette: saved.palette, editingSlug: saved.slug))
                                }
                                Button("Delete", role: .destructive) { library.delete(saved) }
                            } else {
                                Button("Make a copy to edit…") {
                                    openEditor(ThemeDraft(name: theme.displayName + " copy", palette: theme.palette, editingSlug: nil))
                                }
                            }
                        }
                }
            }
        }
    }
}

private struct ThemeCard: View {
    @ObservedObject var deck: DeckModel
    let theme: ThemeChoice
    let isCurrent: Bool
    @State private var isHovered = false

    var body: some View {
        Button { deck.chooseTheme(theme.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                SlidePreviewView(slideSource: deck.slideSource(at: deck.selected), baseDir: deck.baseDir,
                                 palette: theme.palette, textScale: deck.textScale, fontName: deck.fontName)
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
