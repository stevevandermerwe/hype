import SwiftUI
import AppKit
import HypeCore
import HypeRender

/// Your own themes: the saved list (shared by the gallery and the editor) and
/// the sheet for making or changing one.
@MainActor
final class ThemeLibrary: ObservableObject {
    @Published private(set) var custom: [CustomTheme] = []
    private let store: ThemeStore

    init(store: ThemeStore = .shared) {
        self.store = store
        reload()
    }

    func reload() { custom = (try? store.list()) ?? [] }

    @discardableResult
    func save(name: String, palette: Palette) throws -> CustomTheme {
        defer { reload() }
        return try store.save(name: name, palette: palette)
    }

    func delete(_ theme: CustomTheme) {
        try? store.delete(slug: theme.slug)
        reload()
    }
}

/// A theme being made or edited. `editingSlug` is set when changing a saved one.
struct ThemeDraft: Identifiable {
    let id = UUID()
    var name: String
    var palette: Palette
    var editingSlug: String?
}

extension Color {
    /// `#rrggbb` in sRGB, the form themes store.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent))
    }
}

/// The theme editor: a name, nine colours, a "start from" menu, and a live
/// preview on the slide you're looking at. Saving also switches the deck to it.
struct ThemeEditorSheet: View {
    @EnvironmentObject var deck: DeckModel
    @EnvironmentObject var library: ThemeLibrary
    @Environment(\.dismiss) private var dismiss
    @State var draft: ThemeDraft
    @State private var error = ""

    private static let fields: [(key: String, label: String, hint: String)] = [
        ("background", "Background", "The slide"),
        ("foreground", "Text", "Headlines and body"),
        ("accent", "Accent", "Links and highlights"),
        ("green", "Green", "Strings in code"),
        ("red", "Red", "Variables in code"),
        ("yellow", "Yellow", "Numbers in code"),
        ("magenta", "Magenta", "Keywords in code"),
        ("cyan", "Cyan", "Types in code"),
        ("dark_foreground", "Muted", "Comments in code"),
    ]

    private func colorBinding(_ key: String) -> Binding<Color> {
        Binding(get: { Color(hex: draft.palette[key]) }, set: { draft.palette[key] = $0.hexString })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                WindowHeader(icon: "paintpalette", title: draft.editingSlug == nil ? "New theme" : "Edit theme",
                             subtitle: "Choose colours for slides and code. Decks keep the colours they were saved with.")
                TextField("Theme name", text: $draft.name).textFieldStyle(.roundedBorder)
                Menu("Start from…") {
                    ForEach(themeChoices()) { choice in
                        Button(choice.displayName) { draft.palette = choice.palette }
                    }
                }
                .fixedSize()
                Form {
                    ForEach(Self.fields, id: \.key) { field in
                        ColorPicker(selection: colorBinding(field.key), supportsOpacity: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(field.label)
                                Text(field.hint).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.columns)
                if !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Save and Use") { save() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .controlSize(.large)
            }
            .frame(width: 300)

            VStack(alignment: .leading, spacing: 10) {
                Text("Preview").font(.headline).foregroundStyle(.secondary)
                SlidePreviewView(slideSource: deck.slideSource(at: deck.selected), baseDir: deck.baseDir,
                                 palette: draft.palette, textScale: deck.textScale, fontName: deck.fontName)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                SlidePreviewView(slideSource: "# Code\n\n```swift\nlet answer = 42 // yes\nprint(\"Hi\")\n```", baseDir: "",
                                 palette: draft.palette)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                Spacer(minLength: 0)
            }
            .frame(width: 380)
        }
        .padding(24)
        .frame(width: 750, height: 560)
    }

    private func save() {
        do {
            let saved = try library.save(name: draft.name, palette: draft.palette)
            deck.chooseTheme(saved.slug)
            deck.setStatus("Theme “\(saved.name)” saved and applied · Cmd+Z undoes the change to this deck")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
