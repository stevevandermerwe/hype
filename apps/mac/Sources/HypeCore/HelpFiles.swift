import Foundation

/// Bundled help topics, shared by the Mac app's Help menu and the CLI's
/// `hype help <topic>` command.
public enum HelpTopic: String, CaseIterable {
    case help = "help"
    case format = "format"
    case keyboardShortcuts = "keyboard-shortcuts"
    case yamlFrontMatter = "yaml-front-matter"

    /// Display title used in menus and window titles.
    public var title: String {
        switch self {
        case .help: return "Hype Help"
        case .format: return "Markdown Format"
        case .keyboardShortcuts: return "Keyboard Shortcuts"
        case .yamlFrontMatter: return "YAML Front Matter"
        }
    }
}

/// Loads a bundled help topic as Markdown text.
public func loadHelp(_ topic: HelpTopic) -> String? {
    guard let url = Bundle.module.url(forResource: topic.rawValue, withExtension: "md", subdirectory: "Resources")
    else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

/// A short usage line listing the available help topics.
public let helpTopicsSummary: String = {
    let topics = HelpTopic.allCases.map { "  \($0.rawValue)" }.joined(separator: "\n")
    return "Help topics:\n" + topics
}()
