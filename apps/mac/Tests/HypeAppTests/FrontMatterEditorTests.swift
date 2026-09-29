import XCTest
import AppKit
import SwiftUI
import HypeCore
@testable import HypeApp

/// The front-matter editor must render as a plain sheet with no environment
/// objects (it reads everything from the `DeckModel` it is given), so hosting it
/// directly catches accidental reliance on an injected environment.
@MainActor
final class FrontMatterEditorTests: XCTestCase {
    func testSheetRendersWithoutEnvironmentObjects() {
        let deck = DeckModel()
        let hosting = NSHostingView(rootView: FrontMatterEditorSheet(deck: deck, onEditSource: {}))
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 680)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
    }
}
