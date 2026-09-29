import SwiftUI
import WebKit
import HypeCore

/// A Markdown viewer for bundled help topics, rendered as HTML in a WKWebView so
/// tables, code blocks, and headings format correctly. The topic is a plain
/// binding because a window's toolbar does not inherit `.environmentObject`
/// applied to its content view.
struct HelpView: View {
    @Binding var topic: HelpTopic

    var body: some View {
        Group {
            if let markdown = loadHelp(topic) {
                HelpWebView(html: markdownToHTML(markdown, title: topic.title))
            } else {
                Text("Could not load help topic.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 520, idealWidth: 680, maxWidth: .infinity,
               minHeight: 400, idealHeight: 720, maxHeight: .infinity)
    }
}

/// A WKWebView wrapper that loads a generated HTML string.
struct HelpWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

/// A toolbar with a picker that switches the Help window's topic.
struct HelpToolbar: View {
    @Binding var topic: HelpTopic

    var body: some View {
        Picker("Topic", selection: $topic) {
            ForEach(HelpTopic.allCases, id: \.self) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 480)
    }
}
