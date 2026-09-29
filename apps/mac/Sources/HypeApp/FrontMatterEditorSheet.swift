import SwiftUI
import AppKit
import HypeCore
import HypeRender

/// A visual editor for the deck's YAML front matter. Every supported setting is
/// shown as a control; changing one writes the matching key into the header as
/// its own undoable edit. Values Hype doesn't manage in the UI are kept as-is,
/// and the raw YAML is always available from the source view.
struct FrontMatterEditorSheet: View {
    @ObservedObject var deck: DeckModel
    /// Switches the main window to the source view so the raw YAML can be edited.
    var onEditSource: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private static let colorLabels: [(key: String, label: String)] = [
        ("background", "Background"),
        ("foreground", "Text"),
        ("accent", "Accent"),
        ("green", "Green"),
        ("red", "Red"),
        ("yellow", "Yellow"),
        ("magenta", "Magenta"),
        ("cyan", "Cyan"),
        ("dark_foreground", "Muted"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            WindowHeader(icon: "doc.text.below.ecg", title: "Front Matter",
                         subtitle: "Settings for the whole presentation, stored as YAML at the top of the file. Each change is one undo step.")
                .padding(20)
            Divider()
            ScrollView {
                Form {
                    presentationSection
                    pageNumberSection
                    titleSection
                    colorSection
                }
                .formStyle(.grouped)
                .padding(.horizontal, 8)
            }
            Divider()
            HStack {
                if let onEditSource {
                    Button("Edit as YAML…") { onEditSource(); dismiss() }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 560, height: 680)
    }

    // MARK: Sections

    private var presentationSection: some View {
        Section("Presentation") {
            LabeledContent("Title") {
                TextField("Untitled", text: binding(get: { deck.titleValue }, set: { deck.setTitle($0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }
            Picker("Theme", selection: binding(get: { deck.themeName }, set: { deck.chooseTheme($0) })) {
                ForEach(themeChoices()) { choice in
                    Text(choice.displayName).tag(choice.id)
                }
            }
            Picker("Font", selection: binding(get: { deck.fontName }, set: { deck.setFontName($0) })) {
                Text("System (default)").tag("")
                ForEach(fontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            LabeledContent("Text size") {
                HStack(spacing: 10) {
                    Slider(value: binding(get: { deck.textScale }, set: { deck.setTextScale($0) }),
                           in: TextScale.minimum...TextScale.maximum, step: 0.05)
                        .frame(width: 180)
                    Text("\(Int((deck.textScale * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                    Button("Reset") { deck.setTextScale(1) }
                        .controlSize(.small)
                        .disabled(deck.textScale == 1)
                }
            }
        }
    }

    private var pageNumberSection: some View {
        Section("Page numbers") {
            Toggle("Show page numbers", isOn: binding(get: { deck.showPageNumber }, set: { deck.setShowPageNumber($0) }))
            if deck.showPageNumber {
                Picker("Position", selection: binding(
                    get: { deck.pageNumberPosition },
                    set: { deck.setPageNumberPosition($0) }
                )) {
                    Text("Automatic").tag(SlideHeaderOptions.PagePosition?.none)
                    Text("Top").tag(SlideHeaderOptions.PagePosition?.some(.top))
                    Text("Bottom").tag(SlideHeaderOptions.PagePosition?.some(.bottom))
                }
                overrideColorRow("Color", hex: deck.pageNumberColorHex, defaultHex: deck.palette.darkForeground,
                                 onChange: { deck.setPageNumberColorHex($0) },
                                 onClear: { deck.setPageNumberColorHex("") })
            }
        }
    }

    private var titleSection: some View {
        Section("Presentation title") {
            Toggle("Show title", isOn: binding(get: { deck.showTitle }, set: { deck.setShowTitle($0) }))
            Picker("Position", selection: binding(get: { deck.titlePosition }, set: { deck.setTitlePosition($0) })) {
                Text("Top").tag(SlideHeaderOptions.TitlePosition.top)
                Text("Bottom").tag(SlideHeaderOptions.TitlePosition.bottom)
            }
            overrideColorRow("Color", hex: deck.titleColorHex, defaultHex: deck.palette.darkForeground,
                             onChange: { deck.setTitleColorHex($0) },
                             onClear: { deck.setTitleColorHex("") })
            LabeledContent("Style") {
                HStack(spacing: 12) {
                    styleToggle("Bold", token: "bold")
                    styleToggle("Italic", token: "italic")
                    styleToggle("Uppercase", token: "uppercase")
                    styleToggle("Underline", token: "underline")
                }
            }
        }
    }

    private var colorSection: some View {
        Section {
            ForEach(Self.colorLabels, id: \.key) { entry in
                HStack {
                    ColorPicker(entry.label, selection: binding(
                        get: { Color(hex: deck.colorHex(for: entry.key)) },
                        set: { deck.setColorHex($0.hexString, for: entry.key) }
                    ), supportsOpacity: false)
                    Spacer()
                    if deck.colorOverrides[entry.key] != nil {
                        Button { deck.setColorHex("", for: entry.key) } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Use the theme's color")
                    }
                }
            }
        } header: {
            HStack {
                Text("Theme colors")
                Spacer()
                if !deck.colorOverrides.isEmpty {
                    Button("Reset all") { deck.clearColorOverrides() }
                        .controlSize(.small)
                }
            }
        } footer: {
            Text("Overrides are written as `color_*` keys and take precedence over the theme.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Small pieces

    /// All installed font families, with the deck's font listed first when it
    /// isn't installed here (so the picker still shows what the deck names).
    private var fontFamilies: [String] {
        let families = availableFontFamilies()
        let current = deck.fontName
        if !current.isEmpty, !families.contains(current) { return [current] + families }
        return families
    }

    private func overrideColorRow(_ label: String, hex: String, defaultHex: String,
                                  onChange: @escaping (String) -> Void,
                                  onClear: @escaping () -> Void) -> some View {
        HStack {
            ColorPicker(label, selection: binding(
                get: { Color(hex: hex.isEmpty ? defaultHex : hex) },
                set: { onChange($0.hexString) }
            ), supportsOpacity: false)
            Spacer()
            if !hex.isEmpty {
                Button { onClear() } label: { Image(systemName: "arrow.uturn.backward.circle") }
                    .buttonStyle(.borderless)
                    .help("Use the default color")
            }
        }
    }

    private func styleToggle(_ label: String, token: String) -> some View {
        Toggle(label, isOn: binding(
            get: { deck.titleStyleTokens.contains(token) },
            set: { on in
                var tokens = deck.titleStyleTokens
                if on { tokens.insert(token) } else { tokens.remove(token) }
                deck.setTitleStyleTokens(tokens)
            }
        ))
        .toggleStyle(.checkbox)
    }

    /// Builds a `Binding` whose getter reads from the deck (so the view refreshes
    /// after any edit) and whose setter records an undoable change.
    private func binding<T>(get: @escaping () -> T, set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: set)
    }
}
