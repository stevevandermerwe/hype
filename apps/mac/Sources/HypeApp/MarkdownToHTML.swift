import Foundation

/// Converts the subset of Markdown used by Hype's bundled help files into HTML
/// for display in a WKWebView. This intentionally handles only the elements
/// present in those files: headings, paragraphs, fenced code blocks, unordered
/// and ordered lists, tables, and inline bold/italic/underline/code/links.
func markdownToHTML(_ markdown: String, title: String) -> String {
    let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    var output: [String] = []
    var index = 0

    var inCodeBlock = false
    var codeFenceLength = 0
    var codeBuffer: [String] = []

    var inList = false
    var listType: Character?
    var listItems: [String] = []

    var inTable = false
    var tableRows: [String] = []

    var paragraphBuffer: [String] = []

    func flushParagraph() {
        guard !paragraphBuffer.isEmpty else { return }
        let text = paragraphBuffer.joined(separator: " ")
        output.append("<p>\(text.htmlInlined)</p>")
        paragraphBuffer.removeAll()
    }

    func flushCodeBlock() {
        guard inCodeBlock else { return }
        let escaped = codeBuffer
            .joined(separator: "\n")
            .htmlEscaped
        output.append("<pre><code>\(escaped)</code></pre>")
        codeBuffer.removeAll()
        inCodeBlock = false
        codeFenceLength = 0
    }

    func flushList() {
        guard inList, let type = listType else { return }
        let tag = type == "-" ? "ul" : "ol"
        let items = listItems.map { "<li>\($0.htmlInlined)</li>" }.joined()
        output.append("<\(tag)>\(items)</\(tag)>")
        listItems.removeAll()
        inList = false
        listType = nil
    }

    func flushTable() {
        guard inTable, !tableRows.isEmpty else { return }
        var html = "<table>"
        let headerCells = parseTableRow(tableRows[0])
        html += "<thead><tr>" + headerCells.map { "<th>\($0.htmlInlined)</th>" }.joined() + "</tr></thead>"
        if tableRows.count >= 3 {
            html += "<tbody>"
            for row in tableRows.dropFirst(2) {
                let cells = parseTableRow(row)
                html += "<tr>" + cells.map { "<td>\($0.htmlInlined)</td>" }.joined() + "</tr>"
            }
            html += "</tbody>"
        }
        html += "</table>"
        output.append(html)
        tableRows.removeAll()
        inTable = false
    }

    while index < lines.count {
        let line = String(lines[index])

        let fenceLength = codeFencePrefixLength(line)
        if fenceLength >= 3 {
            if inCodeBlock {
                if fenceLength >= codeFenceLength {
                    flushCodeBlock()
                    index += 1
                    continue
                }
            } else {
                flushParagraph()
                flushList()
                flushTable()
                inCodeBlock = true
                codeFenceLength = fenceLength
                index += 1
                continue
            }
        }

        if inCodeBlock {
            codeBuffer.append(line)
            index += 1
            continue
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            flushParagraph()
            flushList()
            flushTable()
            index += 1
            continue
        }

        if let heading = parseHeading(line) {
            flushParagraph()
            flushList()
            flushTable()
            output.append(heading)
            index += 1
            continue
        }

        if isTableRow(line) {
            flushParagraph()
            flushList()
            inTable = true
            tableRows.append(line)
            index += 1
            continue
        }

        if let (type, content) = parseListItem(line) {
            flushParagraph()
            flushTable()
            if !inList || listType != type {
                flushList()
                inList = true
                listType = type
            }
            listItems.append(content)
            index += 1
            continue
        }

        flushList()
        flushTable()
        paragraphBuffer.append(line)
        index += 1
    }

    flushCodeBlock()
    flushList()
    flushTable()
    flushParagraph()

    let body = output.joined()
    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="color-scheme" content="light dark">
    <title>\(title.htmlEscaped)</title>
    <style>
      :root { color-scheme: light dark; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        font-size: 14px;
        line-height: 1.6;
        padding: 20px;
        max-width: 760px;
        margin: 0 auto;
        color: #1a1a1a;
        background: #ffffff;
      }
      @media (prefers-color-scheme: dark) {
        body { color: #e6e6e6; background: #1e1e1e; }
      }
      h1, h2, h3 { font-weight: 600; margin-top: 1.4em; margin-bottom: 0.5em; }
      h1 { font-size: 1.8em; border-bottom: 1px solid #ccc; padding-bottom: 0.3em; }
      h2 { font-size: 1.4em; }
      h3 { font-size: 1.15em; }
      code {
        background: rgba(128, 128, 128, 0.15);
        padding: 2px 5px;
        border-radius: 4px;
        font-family: SFMono-Regular, Menlo, monospace;
        font-size: 0.9em;
      }
      pre {
        background: rgba(128, 128, 128, 0.12);
        padding: 12px;
        border-radius: 6px;
        overflow-x: auto;
      }
      pre code { background: transparent; padding: 0; }
      table { border-collapse: collapse; width: 100%; margin: 1em 0; }
      th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
      th { background: rgba(128, 128, 128, 0.12); font-weight: 600; }
      ul, ol { margin: 1em 0; padding-left: 1.5em; }
      li { margin: 0.3em 0; }
      a { color: #0066cc; }
      @media (prefers-color-scheme: dark) {
        a { color: #4da6ff; }
        h1 { border-bottom-color: #555; }
        th, td { border-color: #555; }
      }
    </style>
    </head>
    <body>
    \(body)
    </body>
    </html>
    """
}

private func parseHeading(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("#") else { return nil }
    let level = trimmed.prefix { $0 == "#" }.count
    guard (1...6).contains(level) else { return nil }
    let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
    return "<h\(level)>\(text.htmlInlined)</h\(level)>"
}

private func parseListItem(_ line: String) -> (type: Character, content: String)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("- ") {
        return ("-", String(trimmed.dropFirst(2)))
    }
    let digits = trimmed.prefix(while: \.isNumber)
    guard !digits.isEmpty else { return nil }
    let afterDigits = trimmed.dropFirst(digits.count)
    guard afterDigits.hasPrefix(".") else { return nil }
    let afterPeriod = afterDigits.dropFirst()
    guard afterPeriod.hasPrefix(" ") || afterPeriod.hasPrefix("\t") else { return nil }
    return ("1", afterPeriod.trimmingCharacters(in: .whitespaces))
}

private func codeFencePrefixLength(_ line: String) -> Int {
    line.prefix(while: { $0 == "`" }).count
}

private func isTableRow(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
}

private func parseTableRow(_ line: String) -> [String] {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let inner = trimmed.dropFirst().dropLast()
    return inner.split(separator: "|", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
}

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    var htmlInlined: String {
        var result = htmlEscaped
        // Code spans first so their contents are not further processed.
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\*\\*([^*]+)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\*([^*]+)\\*",
            with: "<em>$1</em>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "_(.+?)_",
            with: "<u>$1</u>",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        return result
    }
}
