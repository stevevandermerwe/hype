import SwiftUI
import HypeCore

/// What the text fitter decided for one slide, mainly for tests and warnings.
struct TextFit: Equatable {
    /// Body font size as drawn (after the deck's `text_scale`).
    var bodySize: CGFloat
    var headlineSize: CGFloat
    /// How many lines (or table cells) had to wrap; 0 when everything fits whole.
    var wrappedLines: Int
    /// Height of the drawn text block, in slide units.
    var height: CGFloat
    /// Body size that fit the area, before `text_scale`.
    var fittedBodySize: CGFloat = 0
    /// The slide holds more than fits at a readable size (or overflows outright).
    var isCramped = false
}

/// Body text below this many units (of a 1080-tall slide) is too small to read
/// from a room, so the fitter will always wrap lines rather than go below it,
/// and a slide that still can't reach it is reported as holding too much.
let readableBodySize: CGFloat = 36
/// Below this, text is legible but small: the fitter still prefers keeping lines
/// whole, unless wrapping them makes the text at least `wrapGain` times bigger.
let comfortableBodySize: CGFloat = 52
let wrapGain: CGFloat = 1.3

/// Where a slide's text goes, in 1920×1080 units: the whole slide inset, or the
/// half beside a `left`/`right` picture.
func slideTextArea(for media: Media) -> CGRect {
    if !media.file.isEmpty, !media.side.isEmpty { return splitTextArea(media.side) }
    return CGRect(x: 130, y: 90, width: 1660, height: 900)
}

/// Relative sizes of the other blocks, against the body size.
private let headlineRatio: CGFloat = 1.7
private let minHeadlineRatio: CGFloat = 1.15
private let codeRatio: CGFloat = 0.85
private let tableRatio: CGFloat = 1.0
private let lineSpacing: CGFloat = 6
private let blockSpacing: CGFloat = 16

/// Narrows the widest columns just enough for the total to fit `available`,
/// leaving narrow ones (numbers, short labels) at their natural width, so it is
/// long prose cells that wrap rather than every column being squeezed.
private func shrinkWidest(_ natural: [CGFloat], toFit available: CGFloat) -> [CGFloat] {
    var remaining = available
    var left = natural.count
    var cap = CGFloat.infinity
    for width in natural.sorted() {
        let share = remaining / CGFloat(left)
        if width <= share {
            remaining -= width
            left -= 1
        } else {
            cap = share
            break
        }
    }
    return natural.map { min($0, cap) }
}

private func color(for kind: TokenKind, palette: Palette, foreground: Color) -> Color {
    switch kind {
    case .plain: return foreground
    case .keyword, .tag: return Color(hex: palette.magenta)
    case .string: return Color(hex: palette.green)
    case .comment: return Color(hex: palette.darkForeground)
    case .number, .constant: return Color(hex: palette.yellow)
    case .type, .attribute: return Color(hex: palette.cyan)
    case .property: return Color(hex: palette.accent)
    case .variable: return Color(hex: palette.red)
    }
}

/// One laid-out block: already measured, ready to draw.
private enum Item {
    case text(GraphicsContext.ResolvedText, CGSize, wrapped: Bool)
    case code(CodeBox)
    case table(TableBox)

    var size: CGSize {
        switch self {
        case .text(_, let size, _): return size
        case .code(let box): return box.size
        case .table(let box): return box.size
        }
    }
    var wrappedCount: Int {
        switch self {
        case .text(_, _, let wrapped): return wrapped ? 1 : 0
        case .code: return 0
        case .table(let box): return box.wrappedCells
        }
    }
    var isBox: Bool {
        if case .text = self { return false }
        return true
    }
}

private struct CodeBox {
    var lines: [(text: GraphicsContext.ResolvedText, size: CGSize)]
    var size: CGSize
    var padX: CGFloat
    var padY: CGFloat
    var gap: CGFloat
    var fontSize: CGFloat
}

private struct TableBox {
    var cells: [[(text: GraphicsContext.ResolvedText, size: CGSize)]] // row 0 is the header
    var columnWidths: [CGFloat]
    var rowHeights: [CGFloat]
    var alignments: [TableAlignment]
    var padX: CGFloat
    var wrappedCells: Int
    var fontSize: CGFloat
    var size: CGSize { CGSize(width: columnWidths.reduce(0, +), height: rowHeights.reduce(0, +)) }
}

/// One slide's text, laid out for `area` (1920×1080 units) and drawn with
/// `context`: a headline, body lines, highlighted code panels, and table grids.
///
/// The text is sized as large as it can be while every line stays whole and the
/// block fits the area; long lines wrap only when keeping them whole would leave
/// body text unreadably (or needlessly) small. The headline is sized on its own,
/// so a long title shrinks to stay on one line instead of wrapping or dragging
/// the body text down with it. `textScale` (the deck's `text_scale`) above 1
/// raises the largest size text may be fitted to; below 1 it shrinks the fitted
/// size, so it always shows.
@discardableResult
func drawSlideText(_ context: inout GraphicsContext, text: String, area: CGRect, foreground: Color,
                   palette: Palette = .tokyoNight, textScale: CGFloat = 1, fontName: String = "") -> TextFit {
    let content = parseSlideContent(text)
    guard !content.blocks.isEmpty else { return TextFit(bodySize: 0, headlineSize: 0, wrappedLines: 0, height: 0) }
    let centered = content.kind == .plain
    let font = resolvedFontName(fontName)
    let unbounded = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)

    // Highlighting doesn't depend on size, so tokenize each code block once.
    var highlighted: [Int: [[Token]]] = [:]
    for (index, block) in content.blocks.enumerated() {
        if case .code(let language, let lines) = block {
            highlighted[index] = highlight(lines.joined(separator: "\n"), language: language)
        }
    }

    func headlineText(_ text: String, _ size: CGFloat) -> Text {
        Text(inlineFormatted(text, font: slideFont(font, size: size), color: foreground)).bold()
    }
    let headline: String? = content.blocks.compactMap { block -> String? in
        if case .headline(let text) = block { return text }
        return nil
    }.first
    /// The largest headline size that still fits `area` on one line. Text width
    /// grows linearly with font size, so measuring once at a reference size is
    /// enough; a small margin absorbs rounding.
    let headlineFitSize: CGFloat = {
        guard let headline else { return CGFloat.infinity }
        let width = context.resolve(headlineText(headline, 100)).measure(in: unbounded).width
        return width > 0 ? 100 * area.width / width * 0.98 : CGFloat.infinity
    }()
    func headlineSize(forBody body: CGFloat) -> CGFloat {
        headline == nil ? 0 : max(body * minHeadlineRatio, min(body * headlineRatio, headlineFitSize))
    }

    func textItem(_ text: Text, wrapping: Bool) -> Item {
        let resolved = context.resolve(text)
        let whole = resolved.measure(in: unbounded)
        guard wrapping, whole.width > area.width else { return .text(resolved, whole, wrapped: false) }
        return .text(resolved, resolved.measure(in: CGSize(width: area.width, height: CGFloat.infinity)), wrapped: true)
    }

    func codeItem(_ index: Int, lines: [String], bodySize: CGFloat) -> Item {
        let fontSize = bodySize * codeRatio
        let tokens = highlighted[index] ?? lines.map { [Token(kind: .plain, text: $0)] }
        let resolved = tokens.map { line -> (text: GraphicsContext.ResolvedText, size: CGSize) in
            var attributed = AttributedString()
            for token in line {
                var piece = AttributedString(token.text)
                piece.font = .system(size: fontSize, design: .monospaced)
                piece.foregroundColor = color(for: token.kind, palette: palette, foreground: foreground)
                attributed += piece
            }
            if line.isEmpty { // an empty line still takes a line's height
                attributed = AttributedString(" ")
                attributed.font = .system(size: fontSize, design: .monospaced)
            }
            let text = context.resolve(Text(attributed))
            return (text, text.measure(in: unbounded))
        }
        let padX = fontSize * 0.8, padY = fontSize * 0.6, gap = fontSize * 0.2
        let contentWidth = resolved.map(\.size.width).max() ?? 0
        let contentHeight = resolved.reduce(0) { $0 + $1.size.height } + gap * CGFloat(max(0, resolved.count - 1))
        let natural = contentWidth + 2 * padX
        return .code(CodeBox(lines: resolved,
                             size: CGSize(width: max(natural, area.width * 0.5), height: contentHeight + 2 * padY),
                             padX: padX, padY: padY, gap: gap, fontSize: fontSize))
    }

    func tableItem(_ table: TableData, bodySize: CGFloat, wrapping: Bool) -> Item {
        let fontSize = bodySize * tableRatio
        let padX = fontSize * 0.7, padY = fontSize * 0.4
        let cellFont = slideFont(font, size: fontSize)
        let rowsText = [table.header] + table.rows
        let resolved = rowsText.enumerated().map { rowIndex, row in
            row.map { cell -> GraphicsContext.ResolvedText in
                let styled = inlineFormatted(cell.isEmpty ? " " : cell, font: rowIndex == 0 ? cellFont.bold() : cellFont, color: foreground)
                return context.resolve(Text(styled))
            }
        }
        let natural = resolved.map { $0.map { $0.measure(in: unbounded) } }
        let columns = table.columnCount
        let naturalContent = (0..<columns).map { column in natural.map { $0[column].width }.max() ?? 0 }
        let naturalTotal = naturalContent.reduce(0) { $0 + $1 + 2 * padX }

        var contentWidths = naturalContent
        var wrappedCells = 0
        var sizes = natural
        if wrapping, naturalTotal > area.width {
            contentWidths = shrinkWidest(naturalContent, toFit: max(1, area.width - 2 * padX * CGFloat(columns)))
            for (r, row) in resolved.enumerated() {
                for (c, cell) in row.enumerated() where natural[r][c].width > contentWidths[c] {
                    sizes[r][c] = cell.measure(in: CGSize(width: contentWidths[c], height: CGFloat.infinity))
                    wrappedCells += 1
                }
            }
        }
        let rowHeights = sizes.map { row in (row.map(\.height).max() ?? 0) + 2 * padY }
        let cells = zip(resolved, sizes).map { rowTexts, rowSizes in zip(rowTexts, rowSizes).map { (text: $0, size: $1) } }
        return .table(TableBox(cells: cells, columnWidths: contentWidths.map { $0 + 2 * padX }, rowHeights: rowHeights,
                               alignments: table.alignments, padX: padX, wrappedCells: wrappedCells, fontSize: fontSize))
    }

    func layout(bodySize: CGFloat, wrapping: Bool) -> [Item] {
        content.blocks.enumerated().map { index, block in
            switch block {
            case .headline(let text): return textItem(headlineText(text, headlineSize(forBody: bodySize)), wrapping: wrapping)
            case .line(let text):
                return textItem(Text(inlineFormatted(text, font: slideFont(font, size: bodySize), color: foreground)), wrapping: wrapping)
            case .code(_, let lines): return codeItem(index, lines: lines, bodySize: bodySize)
            case .table(let table): return tableItem(table, bodySize: bodySize, wrapping: wrapping)
            }
        }
    }
    func gap(_ before: Item, _ after: Item) -> CGFloat { before.isBox || after.isBox ? blockSpacing : lineSpacing }
    func blockHeight(_ items: [Item]) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        var total = items[0].size.height
        for index in 1..<items.count { total += gap(items[index - 1], items[index]) + items[index].size.height }
        return total
    }

    let (low, baseHigh): (CGFloat, CGFloat) = {
        switch content.kind {
        case .code: return (8, 68)
        case .quote: return (8, 92)
        case .list: return (8, 72)
        case .table: return (8, 64)
        case .plain:
            // A headline (or several lines) may grow big; a single plain line stays modest.
            return (8, content.blocks.count > 1 || headline != nil ? 128 : 76)
        }
    }()
    let high = baseHigh * max(1, textScale)

    /// The largest body size in `low...high` whose layout fits; with `wrapping`
    /// off that means every line whole (nothing wider than the area).
    func largestFit(wrapping: Bool) -> CGFloat {
        func fits(_ size: CGFloat) -> Bool {
            let items = layout(bodySize: size, wrapping: wrapping)
            return blockHeight(items) <= area.height && items.allSatisfy { $0.size.width <= area.width + 1 }
        }
        if fits(high) { return high }
        var lowBound = low, highBound = high
        for _ in 0..<9 {
            let mid = (lowBound + highBound) / 2
            if fits(mid) { lowBound = mid } else { highBound = mid }
        }
        return lowBound
    }

    var wrapping = false
    var fitted = largestFit(wrapping: false)
    if fitted < comfortableBodySize {
        let wrapped = largestFit(wrapping: true)
        if wrapped > fitted, fitted < readableBodySize || wrapped >= fitted * wrapGain {
            fitted = wrapped
            wrapping = true
        }
    }
    let chosen = max(low, fitted * min(1, textScale))

    let final = layout(bodySize: chosen, wrapping: wrapping)
    let height = blockHeight(final)
    var y = area.minY + max(0, (area.height - height) / 2)
    for (index, item) in final.enumerated() {
        if index > 0 { y += gap(final[index - 1], item) }
        switch item {
        case .text(let resolved, let size, _):
            let x = centered ? area.minX + max(0, (area.width - size.width) / 2) : area.minX
            context.draw(resolved, in: CGRect(x: x, y: y, width: size.width, height: size.height))
        case .code(let box):
            draw(box, in: &context, at: CGPoint(x: area.minX, y: y), foreground: foreground)
        case .table(let box):
            draw(box, in: &context, at: CGPoint(x: area.minX, y: y), foreground: foreground)
        }
        y += item.size.height
    }
    return TextFit(bodySize: chosen, headlineSize: headlineSize(forBody: chosen),
                   wrappedLines: final.reduce(0) { $0 + $1.wrappedCount }, height: height,
                   fittedBodySize: fitted, isCramped: fitted < readableBodySize || height > area.height + 1)
}

// MARK: - Drawing

private func draw(_ box: CodeBox, in context: inout GraphicsContext, at origin: CGPoint, foreground: Color) {
    let panel = CGRect(origin: origin, size: box.size)
    let shape = Path(roundedRect: panel, cornerRadius: box.fontSize * 0.5)
    context.fill(shape, with: .color(foreground.opacity(0.07)))
    context.stroke(shape, with: .color(foreground.opacity(0.16)), lineWidth: 2)
    var y = origin.y + box.padY
    for line in box.lines {
        context.draw(line.text, in: CGRect(x: origin.x + box.padX, y: y, width: line.size.width, height: line.size.height))
        y += line.size.height + box.gap
    }
}

private func draw(_ box: TableBox, in context: inout GraphicsContext, at origin: CGPoint, foreground: Color) {
    let frame = CGRect(origin: origin, size: box.size)
    let outline = Path(roundedRect: frame, cornerRadius: box.fontSize * 0.4)
    // Header tint, clipped to the rounded outline.
    if let headerHeight = box.rowHeights.first {
        context.drawLayer { layer in
            layer.clip(to: outline)
            layer.fill(Path(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: headerHeight)),
                       with: .color(foreground.opacity(0.13)))
        }
    }
    var y = origin.y
    for (rowIndex, row) in box.cells.enumerated() {
        let rowHeight = box.rowHeights[rowIndex]
        if rowIndex > 0 {
            var rule = Path()
            rule.move(to: CGPoint(x: frame.minX, y: y))
            rule.addLine(to: CGPoint(x: frame.maxX, y: y))
            context.stroke(rule, with: .color(foreground.opacity(rowIndex == 1 ? 0.3 : 0.14)), lineWidth: rowIndex == 1 ? 2 : 1)
        }
        var x = origin.x
        for (column, cell) in row.enumerated() {
            let width = box.columnWidths[column]
            let cellX: CGFloat
            switch box.alignments[column] {
            case .leading: cellX = x + box.padX
            case .center: cellX = x + (width - cell.size.width) / 2
            case .trailing: cellX = x + width - box.padX - cell.size.width
            }
            context.draw(cell.text, in: CGRect(x: cellX, y: y + (rowHeight - cell.size.height) / 2,
                                               width: cell.size.width, height: cell.size.height))
            x += width
        }
        y += rowHeight
    }
    context.stroke(outline, with: .color(foreground.opacity(0.28)), lineWidth: 2)
}
