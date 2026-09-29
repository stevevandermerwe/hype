import XCTest
import AppKit
import SwiftUI
import HypeCore
@testable import HypeApp

/// The Help window's views read their topic from a plain binding, not an
/// environment object, and both the content and the toolbar must render when
/// hosted. This guards against a regression to `@EnvironmentObject`, which
/// crashed the window because toolbar content does not inherit the environment
/// applied to the window's content view.
@MainActor
final class HelpViewTests: XCTestCase {
    private func host<V: View>(_ view: V, size: NSSize) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func testHelpViewRendersEveryTopic() {
        for topic in HelpTopic.allCases {
            host(HelpView(topic: .constant(topic)), size: NSSize(width: 600, height: 400))
        }
    }

    func testHelpToolbarRenders() {
        host(HelpToolbar(topic: .constant(.yamlFrontMatter)), size: NSSize(width: 480, height: 40))
    }
}
