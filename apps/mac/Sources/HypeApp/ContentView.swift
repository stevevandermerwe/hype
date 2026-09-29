import SwiftUI
import HypeCore
import HypeRender

/// The main window: the slide sidebar, a live preview of the selected slide,
/// and a Markdown editor for it — the Mac app's counterpart to the Qt
/// editor's split preview/source layout (Visual mode only in Phase 1; there
/// is no whole-document Markdown mode or slide overview grid yet). A plain
/// launch shows the start page over this, matching the Qt app.
struct ContentView: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    @EnvironmentObject var ui: AppUI
    @State private var editorText: String = ""

    var body: some View {
        ZStack {
            editor
            if ui.showStartPage {
                StartPageView(
                    onOpen: { if chooseAndOpenPresentation(deck) { ui.showStartPage = false } },
                    onWingIt: { deck.newDeck(); ui.showStartPage = false },
                    onPlanIt: { ui.sheet = .generate("plan") },
                    onMindMap: { ui.sheet = .generate("mindmap") },
                    onChooseRecent: { path in if deck.loadPath(path) { ui.showStartPage = false } },
                    onDismiss: { ui.showStartPage = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.default, value: ui.showStartPage)
        .sheet(item: $ui.sheet) { item in
            switch item {
            case .generate(let mode):
                GenerateSheet(mode: mode) { path, warnings in
                    deck.loadPath(path)
                    ui.showStartPage = false
                    deck.setStatus(warnings.isEmpty ? "Created \(path)"
                        : "Created; \(warnings.count) warning\(warnings.count > 1 ? "s" : ""), run check")
                }
            case .slideAssist(let index):
                SlideAssistSheet(slideIndex: index) { summary, warnings in
                    let note = warnings.isEmpty ? "" : "; \(warnings.count) warning\(warnings.count > 1 ? "s" : ""), see the slide"
                    deck.setStatus(summary + " · Cmd+Z undoes it" + note)
                }
            }
        }
    }

    private var editor: some View {
        NavigationSplitView {
            SlideListView(deck: deck)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                SlidePreviewView(slideSource: deck.slideSource(at: deck.selected), baseDir: deck.baseDir, palette: deck.palette)
                    .padding()
                Divider()
                TextEditor(text: $editorText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
            }
            .toolbar {
                ToolbarItemGroup {
                    Menu {
                        ForEach(BundledTheme.allCases) { theme in
                            Button(theme.rawValue) { deck.chooseTheme(theme.rawValue) }
                        }
                    } label: { Label("Theme", systemImage: "paintpalette") }
                    Button { ui.sheet = .slideAssist(deck.selected) } label: { Label("Ask AI", systemImage: "sparkles") }
                        .keyboardShortcut("j", modifiers: .command)
                    Button { deck.addSlide() } label: { Label("Add Slide", systemImage: "plus.rectangle") }
                    Button { deck.duplicateSlide() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { deck.deleteSlide() } label: { Label("Delete", systemImage: "trash") }
                        .disabled(deck.count <= 1)
                }
            }
        }
        .navigationTitle(deck.title + (deck.dirty ? " •" : ""))
        .safeAreaInset(edge: .bottom) {
            if !deck.status.isEmpty {
                Text(deck.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
            }
        }
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
}
