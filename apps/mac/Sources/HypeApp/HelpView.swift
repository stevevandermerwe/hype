import SwiftUI
import HypeCore

/// A scrollable Markdown viewer for bundled help topics. Tables and code blocks
/// are rendered with AttributedString's full Markdown interpreter.
struct HelpView: View {
    @EnvironmentObject var ui: AppUI

    var body: some View {
        ScrollView {
            Group {
                if let markdown = loadHelp(ui.helpTopic),
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
    @EnvironmentObject var ui: AppUI

    var body: some View {
        Picker("Topic", selection: $ui.helpTopic) {
            ForEach(HelpTopic.allCases, id: \.self) { topic in
                Text(topic.title).tag(topic)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 480)
    }
}
