import SwiftUI
import HypeCore
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// Open/Save panel helpers shared by the File menu (`HypeMacApp`) and the
/// start page (`StartPageView`, via `ContentView`), so both trigger the same
/// code path.
private var markdownType: UTType { UTType(filenameExtension: "md") ?? .plainText }

@MainActor
@discardableResult
func chooseAndOpenPresentation(_ deck: DeckModel) -> Bool {
    #if canImport(AppKit)
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [markdownType]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return false }
    return deck.loadPath(url.path)
    #else
    return false
    #endif
}

@MainActor
@discardableResult
func chooseAndSaveAsPresentation(_ deck: DeckModel) -> Bool {
    #if canImport(AppKit)
    let panel = NSSavePanel()
    panel.allowedContentTypes = [markdownType]
    panel.nameFieldStringValue = "presentation.md"
    guard panel.runModal() == .OK, let url = panel.url else { return false }
    return deck.savePath(url.path)
    #else
    return false
    #endif
}

@MainActor
func saveOrSaveAsPresentation(_ deck: DeckModel) {
    if deck.path == nil {
        chooseAndSaveAsPresentation(deck)
    } else {
        deck.save()
    }
}
