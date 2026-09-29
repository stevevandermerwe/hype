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

/// Before unsaved edits would be replaced (opening or creating another deck, or
/// quitting), asks whether to save them. Returns true if it is safe to go ahead:
/// there was nothing to lose, the deck was saved, or "Don't Save" was chosen
/// (which also drops its recovery copy). Returns false on Cancel, or if the save
/// itself was cancelled or failed.
@MainActor
func confirmDiscardChanges(_ deck: DeckModel) -> Bool {
    guard deck.dirty else { return true }
    #if canImport(AppKit)
    let alert = NSAlert()
    alert.messageText = "Do you want to save the changes to “\(deck.title)”?"
    alert.informativeText = "Your changes will be lost if you don't save them."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Don't Save")
    alert.addButton(withTitle: "Cancel")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
        return saveOrSaveAsPresentation(deck)
    case .alertSecondButtonReturn:
        deck.discardRecoverySnapshot()
        return true
    default:
        return false
    }
    #else
    return true
    #endif
}

@MainActor
@discardableResult
func chooseAndOpenPresentation(_ deck: DeckModel) -> Bool {
    #if canImport(AppKit)
    guard confirmDiscardChanges(deck) else { return false }
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
@discardableResult
func saveOrSaveAsPresentation(_ deck: DeckModel) -> Bool {
    deck.path == nil ? chooseAndSaveAsPresentation(deck) : deck.save()
}
