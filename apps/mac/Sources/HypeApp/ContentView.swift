import SwiftUI
import HypeCore
import HypeRender

/// The main window: the slide sidebar, a live preview of the selected slide,
/// and a Markdown editor for it — the Mac app's counterpart to the Qt
/// editor's split preview/source layout. The preview and editor sit in a
/// `VSplitView`, so the divider between them can be dragged. A plain launch
/// shows the start page over this, matching the Qt app.
struct ContentView: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var generator: Generator
    @EnvironmentObject var ui: AppUI
    @Environment(\.openWindow) private var openWindow
    @State private var editorText: String = ""

    var body: some View {
        ZStack {
            editor
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
        NavigationSplitView {
            SlideListView(deck: deck)
                .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 320)
        } detail: {
            VSplitView {
                stage
                    .frame(minHeight: 200, idealHeight: 460, maxHeight: .infinity)
                sourcePane
                    .frame(minHeight: 120, idealHeight: 220, maxHeight: .infinity)
            }
            .toolbar { toolbar }
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
        SlidePreviewView(slideSource: deck.slideSource(at: deck.selected), baseDir: deck.baseDir, palette: deck.palette)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var sourcePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text("Markdown")
                Spacer()
                Text("Slide \(deck.selected + 1) of \(deck.count)").monospacedDigit()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.bar)
            Divider()
            TextEditor(text: $editorText)
                .font(.system(size: 13, design: .monospaced))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
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
            Menu {
                Picker("Theme", selection: Binding(get: { deck.themeName }, set: { deck.chooseTheme($0) })) {
                    ForEach(BundledTheme.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
            } label: { Label("Theme", systemImage: "paintpalette") }
                .help("Theme")
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
            }
            Spacer()
            Text("\(deck.count) slide\(deck.count == 1 ? "" : "s") · \(deck.themeName)")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
