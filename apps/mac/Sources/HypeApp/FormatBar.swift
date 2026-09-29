import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HypeCore

/// A strip of editor-assist buttons above the Markdown source: click one to
/// write the syntax instead of typing it. Styles toggle, and work on the
/// selected text (or insert a placeholder to type over). Every action is also
/// in the Format menu with a keyboard shortcut.
struct FormatBar: View {
    @ObservedObject var deck: DeckModel
    @ObservedObject var controller: EditorController
    /// The slide's current Markdown, for showing which layout options are on.
    let slideText: String

    private static let languages = [
        "swift", "ruby", "python", "javascript", "typescript", "bash", "json", "yaml",
        "html", "css", "go", "rust", "c", "cpp", "java", "kotlin", "sql", "markdown",
    ]

    var body: some View {
        HStack(spacing: 2) {
            group {
                button("Heading", "textformat.size", "⌥⌘1", .heading)
                button("Bold", "bold", "⌘B", .bold)
                button("Italic", "italic", "⌘I", .italic)
                button("Underline", "underline", "⌘U", .underline)
                button("Inline code", "chevron.left.forwardslash.chevron.right", "⌥⌘C", .inlineCode)
            }
            divider
            group {
                button("Bulleted list", "list.bullet", "⌥⌘2", .bulletList)
                button("Numbered list", "list.number", "⌥⌘3", .numberedList)
                button("Quote", "text.quote", "⌥⌘4", .quote)
                codeBlockMenu
                button("Table", "tablecells", "⌥⌘6", .table)
                button("Speaker note (hidden from the slide)", "note.text", "⌥⌘N", .note)
            }
            divider
            group {
                IconButton(label: "Insert a picture or video…", icon: "photo.badge.plus", shortcut: "⇧⌘M") {
                    controller.insertPicture(into: deck)
                }
                layoutMenu
            }
        }
    }

    // MARK: Pieces

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2, content: content)
    }
    private var divider: some View { Divider().frame(height: 16).padding(.horizontal, 4) }

    private func button(_ label: String, _ icon: String, _ shortcut: String, _ action: FormatAction) -> some View {
        IconButton(label: label, icon: icon, shortcut: shortcut) { controller.apply(action) }
    }

    private var codeBlockMenu: some View {
        Menu {
            Button("Plain") { controller.apply(.codeBlock(language: "")) }
            Divider()
            ForEach(Self.languages, id: \.self) { language in
                Button(language) { controller.apply(.codeBlock(language: language)) }
            }
        } label: {
            Image(systemName: "curlybraces").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 24)
                .accessibilityLabel("Code block")
        } primaryAction: {
            controller.apply(.codeBlock(language: ""))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Code block (⌥⌘5) — pick a language for highlighting")
        .accessibilityLabel("Code block")
    }

    /// Picture layout options for the slide's image or video. The checkmarks
    /// show what the slide already has; choosing a checked one turns it off.
    private var layoutMenu: some View {
        let media = parseMedia(slideText, base: deck.baseDir)
        func option(_ title: String, _ isOn: Bool, _ layout: ImageLayout) -> some View {
            Toggle(title, isOn: Binding(get: { isOn }, set: { _ in apply(layout) }))
        }
        return Menu {
            Section("Position") {
                option("Picture on the left", media.side == "left", .left)
                option("Picture on the right", media.side == "right", .right)
                option("Fit (show the whole picture)", false, .fit)
                option("Fill the slide (crop)", media.span, .span)
            }
            Section("Behind the picture") {
                option("Blurred backdrop", media.background == "blur", .background(.blur))
                option("Match the picture's edge colour", media.background == "auto", .background(.auto))
                option("White backdrop", media.background == "white", .background(.white))
                option("Black backdrop", media.background == "black", .background(.black))
                option("Darken behind text", media.overlay > 0, .darken)
            }
            if media.video {
                Section("Video") {
                    option("Loop", media.loop, .loop)
                    option("Mute", media.muted, .muted)
                }
            }
        } label: {
            Image(systemName: "rectangle.split.2x1").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 24)
                .accessibilityLabel("Picture layout")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .disabled(media.file.isEmpty)
        .help(media.file.isEmpty ? "Layout — add a picture to this slide first" : "Picture layout")
        .accessibilityLabel("Picture layout")
    }

    private func apply(_ layout: ImageLayout) {
        if !controller.transform({ applyImageLayout(layout, to: $0) }) {
            deck.setStatus("This slide has no picture to lay out.")
        }
    }
}

/// One toolbar-style icon button with a hover highlight and a tooltip that
/// names the action and its shortcut.
private struct IconButton: View {
    let label: String
    let icon: String
    let shortcut: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(label) (\(shortcut))")
        .accessibilityLabel(label)
    }
}

extension EditorController {
    /// Asks for a picture or video, copies it into the deck's folder, and points
    /// the current slide at it (replacing the slide's existing picture).
    func insertPicture(into deck: DeckModel) {
        guard !deck.baseDir.isEmpty else {
            deck.setStatus(MediaImportError.needsSavedDeck.errorDescription ?? "Save the presentation first.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture or video for this slide. It is copied into the presentation's folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = try importMedia(from: url, into: deck.baseDir)
            transform { setImageFile(name, in: $0) }
            deck.setStatus("Added \(name)")
        } catch {
            deck.setStatus(error.localizedDescription)
        }
    }
}
