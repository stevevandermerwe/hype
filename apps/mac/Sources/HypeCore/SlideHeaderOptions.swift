import Foundation

/// Configuration for slide headers and footers (page numbers, presentation title position and styling),
/// set via front matter scalars in the presentation header.
public struct SlideHeaderOptions: Sendable, Equatable {
    public var showPageNumber: Bool
    public var slideIndex: Int?
    public var slideCount: Int?
    public var presentationTitle: String
    public var showTitle: Bool
    public var titlePosition: TitlePosition
    public var titleColorHex: String
    public var titleStyle: String
    public var pageNumberColorHex: String
    public var pageNumberPosition: PagePosition?

    public enum TitlePosition: String, Sendable, CaseIterable {
        case top
        case bottom
    }

    public enum PagePosition: String, Sendable, CaseIterable {
        case top
        case bottom
    }

    public init(
        showPageNumber: Bool = false,
        slideIndex: Int? = nil,
        slideCount: Int? = nil,
        presentationTitle: String = "",
        showTitle: Bool = false,
        titlePosition: TitlePosition = .top,
        titleColorHex: String = "",
        titleStyle: String = "",
        pageNumberColorHex: String = "",
        pageNumberPosition: PagePosition? = nil
    ) {
        self.showPageNumber = showPageNumber
        self.slideIndex = slideIndex
        self.slideCount = slideCount
        self.presentationTitle = presentationTitle
        self.showTitle = showTitle
        self.titlePosition = titlePosition
        self.titleColorHex = titleColorHex
        self.titleStyle = titleStyle
        self.pageNumberColorHex = pageNumberColorHex
        self.pageNumberPosition = pageNumberPosition
    }
}

/// Parses standard boolean values from front-matter scalar strings ("true", "yes", "1", "on" vs "false", "no", "0", "off").
public func parseBoolScalar(_ value: String) -> Bool? {
    let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
    if ["true", "yes", "1", "on"].contains(trimmed) { return true }
    if ["false", "no", "0", "off"].contains(trimmed) { return false }
    return nil
}
