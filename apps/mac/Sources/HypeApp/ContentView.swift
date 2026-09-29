import SwiftUI
import HypeCore
import HypeRender

/// The main window: the slide sidebar, a live preview of the selected slide,
/// and a Markdown editor for it — the Mac app's counterpart to the Qt
/// editor's split preview/source layout. The preview and editor sit in a
/// `VSplitView`, so the divider between them can be dragged. The light table
/// mode swaps both (and the sidebar) for a grid of every slide. A plain launch
/// shows the start page over this, matching the Qt app.
struct ContentView: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    @EnvironmentObject var ui: AppUI
    @EnvironmentObject var markdown: EditorController
    @Environment(\.openWindow) private var openWindow
    @State private var editorText: String = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            editor
                // Covered by the start page, so keep VoiceOver (and clicks routed
                // through accessibility) from reaching the editor underneath.
                .accessibilityHidden(ui.showStartPage)
                .allowsHitTesting(!ui.showStartPage)
            if ui.showStartPage {
                StartPageView(
                    onOpen: { if chooseAndOpenPresentation(deck) { ui.showStartPage = false } },
                    onWingIt: { deck.newDeck(); ui.showStartPage = false },
                    onPlanIt: { ui.openAI(.generate("plan")) },
                    onMindMap: { ui.openAI(.generate("mindmap")) },
                    onChooseRecent: { path in if deck.loadPath(path) { ui.showStartPage = false } },
                    onDismiss: { ui.showStartPage = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ui.showStartPage)
        .onChange(of: ui.aiRequest) { _, _ in openWindow(id: AIWindow.id) }
    }

    private var editor: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SlideListView(deck: deck)
                .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 320)
        } detail: {
            Group {
                switch ui.editorMode {
                case .slide:
                    VSplitView {
                        stage
                            .frame(minHeight: 200, idealHeight: 460, maxHeight: .infinity)
                        sourcePane
                            .frame(minHeight: 120, idealHeight: 220, maxHeight: .infinity)
                    }
                case .lightTable:
                    LightTableView(deck: deck) { index in
                        deck.select(index)
                        ui.editorMode = .slide
                    }
                }
            }
            .toolbar { toolbar }
        }
        .onChange(of: ui.editorMode) { _, mode in
            // The light table already shows every slide, so the sidebar would only repeat it.
            withAnimation { columnVisibility = mode == .lightTable ? .detailOnly : .all }
        }
        .navigationTitle(deck.title + (deck.dirty ? " — Edited" : ""))
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .onAppear { editorText = deck.slideText(at: deck.selected) }
        .onChange(of: editorText) { _, newValue in
            if newValue != deck.slideText(at: deck.selected) { deck.editSlide(newValue) }
        }
        .onChange(of: deck.selected) { _, newValue in
            editorText = deck.slideText(at: newValue)
        }
        .onChange(of: deck.parsed) { _, _ in
            let current = deck.slideText(at: deck.selected)
            if current != editorText { editorText = current }
        }
    }

    /// The selected slide, centered on a neutral backdrop with a soft shadow,
    /// so it reads as a slide rather than as part of the window chrome.
    private var stage: some View {
        SlidePreviewView(slideSource: deck.slideSource(at: deck.selected), baseDir: deck.baseDir, palette: deck.palette, textScale: deck.textScale)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var sourcePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    FormatBar(deck: deck, controller: markdown, slideText: editorText)
                        .padding(.horizontal, 10)
                }
                Text("Slide \(deck.selected + 1) of \(deck.count)")
                    .font(.caption.weight(.medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 14)
            }
            .padding(.vertical, 4)
            .background(.bar)
            Divider()
            MarkdownEditor(text: $editorText, controller: markdown)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("View", selection: $ui.editorMode) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis").accessibilityLabel("Slide")
                    .tag(EditorMode.slide)
                Image(systemName: "square.grid.3x2").accessibilityLabel("Light Table")
                    .tag(EditorMode.lightTable)
            }
            .pickerStyle(.segmented)
            .help("Switch between editing one slide and the light table (Cmd+1 / Cmd+2)")
        }
        ToolbarItemGroup {
            Button { deck.addSlide() } label: { Label("Add Slide", systemImage: "plus.rectangle") }
                .help("New slide (Cmd+Return)")
            Button { deck.duplicateSlide() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                .help("Duplicate slide (Cmd+D)")
            Button(role: .destructive) { deck.deleteSlide() } label: { Label("Delete", systemImage: "trash") }
                .disabled(deck.count <= 1)
                .help("Delete slide")
        }
        ToolbarItemGroup {
            ControlGroup {
                Button { deck.setTextScale(TextScale.smaller(deck.textScale)) } label: {
                    Label("Smaller Text", systemImage: "textformat.size.smaller")
                }
                .disabled(deck.textScale <= TextScale.minimum)
                .help("Smaller text (Cmd+-)")
                Button { deck.setTextScale(TextScale.bigger(deck.textScale)) } label: {
                    Label("Bigger Text", systemImage: "textformat.size.larger")
                }
                .disabled(deck.textScale >= TextScale.maximum)
                .help("Bigger text (Cmd++)")
            }
            ThemePickerButton(deck: deck)
            Button { ui.openAI(.slideAssist(deck.selected)) } label: { Label("Ask AI", systemImage: "sparkles") }
                .keyboardShortcut("j", modifiers: .command)
                .help("Ask AI to change this slide (Cmd+J)")
            Button { openWindow(id: "presenter") } label: { Label("Present", systemImage: "play.fill") }
                .disabled(deck.count == 0)
                .help("Present (Cmd+P)")
        }
    }

    @ViewBuilder private var statusBar: some View {
        HStack(spacing: 8) {
            if generator.busy {
                ProgressView().controlSize(.mini)
                Text(generator.status)
            } else if !deck.status.isEmpty {
                Image(systemName: "info.circle")
                Text(deck.status).lineLimit(1).truncationMode(.middle)
            } else if ui.editorMode == .lightTable {
                Text("Drag to rearrange · double-click to edit")
            }
            Spacer()
            if ui.editorMode == .lightTable {
                LightTableSizeSlider()
                Divider().frame(height: 12)
            }
            Text("\(deck.count) slide\(deck.count == 1 ? "" : "s") · Text \(Int((deck.textScale * 100).rounded()))% · \(BundledTheme(rawValue: deck.themeName)?.displayName ?? deck.themeName)")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
