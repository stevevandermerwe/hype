import Foundation

/// Ready-made slide layouts for the "new slide from template" menu. Each is a
/// single slide of ordinary Hype Markdown with placeholder text to type over, so
/// nothing about it is special once inserted.
public enum SlideTemplate: String, CaseIterable, Identifiable, Sendable {
    case title, section, bullets, quote, bigNumber, twoColumns, agenda, code, table, closing
    /// A picture beside the text: the picture is chosen when the slide is added.
    case pictureLeft, pictureRight

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .title: return "Title"
        case .section: return "Section"
        case .bullets: return "Bullets"
        case .quote: return "Quote"
        case .bigNumber: return "Big number"
        case .twoColumns: return "Two columns"
        case .agenda: return "Agenda"
        case .code: return "Code"
        case .table: return "Table"
        case .closing: return "Closing"
        case .pictureLeft: return "Picture on the left"
        case .pictureRight: return "Picture on the right"
        }
    }

    /// An SF Symbol name for menus.
    public var icon: String {
        switch self {
        case .title: return "textformat.size"
        case .section: return "rectangle.split.1x2"
        case .bullets: return "list.bullet"
        case .quote: return "text.quote"
        case .bigNumber: return "number"
        case .twoColumns: return "rectangle.split.2x1"
        case .agenda: return "list.number"
        case .code: return "curlybraces"
        case .table: return "tablecells"
        case .closing: return "hand.wave"
        case .pictureLeft: return "rectangle.lefthalf.inset.filled"
        case .pictureRight: return "rectangle.righthalf.inset.filled"
        }
    }

    public var needsPicture: Bool { self == .pictureLeft || self == .pictureRight }

    /// The slide's Markdown; nil for a picture layout given no `picture` file.
    public func text(picture: String? = nil) -> String? {
        switch self {
        case .title: return "# Your title\n\nA short subtitle"
        case .section: return "# Section name"
        case .bullets: return "# Headline\n\n- First point\n- Second point\n- Third point"
        case .quote: return "> A memorable quote goes here.\n>\n> — Someone wise"
        case .bigNumber: return "# 87%\n\nof teams ship faster with small groups"
        case .twoColumns:
            return "# Two ways to look at it\n\n| Option A | Option B |\n| --- | --- |\n| First point | First point |\n"
                 + "| Second point | Second point |\n| Third point | Third point |"
        case .agenda: return "# Agenda\n\n1. First topic\n2. Second topic\n3. Third topic\n4. Questions"
        case .code: return "# Show the code\n\n```swift\nlet greeting = \"Hello\"\nprint(greeting)\n```"
        case .table: return "# By the numbers\n\n| Item | Value |\n| --- | ---: |\n| One | 10 |\n| Two | 20 |\n| Three | 30 |"
        case .closing: return "# Thank you\n\nQuestions?"
        case .pictureLeft, .pictureRight:
            guard let picture else { return nil }
            let side = self == .pictureLeft ? "left" : "right"
            return "# Headline\n\n- A point beside the picture\n- Another point\n\n![\(side)](\(pictureReference(picture)))"
        }
    }
}
