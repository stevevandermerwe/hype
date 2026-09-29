import SwiftUI
import HypeCore

/// A scrollable Markdown viewer for bundled help topics. Tables and code blocks
/// are rendered with AttributedString's full Markdown interpreter. The topic is
/// a plain binding rather than an environment object, because a window's toolbar
/// does not inherit `.environmentObject` applied to its content view.
struct HelpView: View {
    @Binding var topic: HelpTopic

    var body: some View {
        ScrollView {
            Group {
                if let markdown = loadHelp(topic),
                   let attributed = try? AttributedString(
                        markdown: markdown,
                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
                   ) {
                    Text(attributed)
                        .textSelection(.enabled)
                } else {
                    Text("Could not load help topic.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, idealWidth: 680, maxWidth: .infinity,
               minHeight: 400, idealHeight: 720, maxHeight: .infinity)
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
