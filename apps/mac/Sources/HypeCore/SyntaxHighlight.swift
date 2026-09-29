import Foundation

public enum TokenKind: String, Sendable {
    case plain, keyword, string, comment, number, type, constant, property, attribute, tag, variable
}

public struct Token: Equatable, Sendable {
    public var kind: TokenKind
    public var text: String
    public init(kind: TokenKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Canonical names of the languages `highlight` understands (the editor's
/// code-block menu offers these). Common aliases (`js`, `py`, `sh`, `yml`, …)
/// are accepted too.
public let supportedHighlightLanguages = [
    "swift", "ruby", "python", "javascript", "typescript", "bash", "json", "yaml", "html", "css",
    "go", "rust", "c", "cpp", "java", "kotlin", "sql", "markdown",
]

/// Splits `code` into one array of tokens per line, tagging keywords, strings,
/// comments, numbers, and so on for `language`. Concatenating a line's token
/// texts gives back the line exactly. An unknown language yields plain lines.
///
/// This is a small scanner, not a parser: good enough to colour a slide, not
/// to understand the language. (The Qt app shells out to `source-highlight`
/// instead, which this app avoids needing installed.)
public func highlight(_ code: String, language: String) -> [[Token]] {
    let normalized = code.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    guard let spec = LanguageSpec.named(language) else {
        return normalized.components(separatedBy: "\n").map { [Token(kind: .plain, text: $0)] }
    }
    var scanner = Scanner(spec: spec, text: normalized)
    scanner.run()
    return splitLines(scanner.tokens)
}

private func splitLines(_ tokens: [Token]) -> [[Token]] {
    var lines: [[Token]] = [[]]
    for token in tokens {
        for (index, part) in token.text.components(separatedBy: "\n").enumerated() {
            if index > 0 { lines.append([]) }
            guard !part.isEmpty else { continue }
            if token.kind == .plain, let last = lines[lines.count - 1].last, last.kind == .plain {
                lines[lines.count - 1][lines[lines.count - 1].count - 1].text += part
            } else {
                lines[lines.count - 1].append(Token(kind: token.kind, text: part))
            }
        }
    }
    return lines
}

// MARK: - Languages

private enum Mode { case code, yaml, html, markdown }

private struct LanguageSpec {
    var mode: Mode = .code
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    var strings: [Character] = ["\"", "'"]
    var tripleStrings: [String] = []
    var multilineBacktick = false
    /// `'` only starts a string when it closes within a few characters, so Rust
    /// lifetimes (`'a`) and similar don't swallow the rest of the line.
    var strictApostrophe = false
    var keywords: Set<String> = []
    var constants: Set<String> = []
    var types: Set<String> = []
    var capitalizedTypes = false
    var caseInsensitive = false
    var atAttributes = false
    var dollarVariables = false
    var hashDirectives = false
    var cssRules = false
    var jsonKeys = false

    static func words(_ list: String) -> Set<String> { Set(list.split(separator: " ").map(String.init)) }

    static let aliases: [String: String] = [
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "ts": "typescript", "tsx": "typescript",
        "py": "python", "python3": "python", "sh": "bash", "zsh": "bash", "shell": "bash", "console": "bash",
        "yml": "yaml", "c++": "cpp", "cc": "cpp", "hpp": "cpp", "h": "c", "rb": "ruby", "md": "markdown",
        "kt": "kotlin", "kts": "kotlin", "rs": "rust", "golang": "go", "htm": "html", "xml": "html", "svg": "html",
        "jsonc": "json",
    ]

    static func named(_ name: String) -> LanguageSpec? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        let canonical = aliases[key] ?? key
        switch canonical {
        case "swift":
            var s = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"))
            s.tripleStrings = ["\"\"\""]; s.strings = ["\""]; s.capitalizedTypes = true; s.atAttributes = true
            s.keywords = words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as await async is self Self super throws try actor some any final lazy mutating override weak unowned convenience required indirect nonisolated")
            s.constants = words("true false nil")
            return s
        case "ruby":
            var s = LanguageSpec(lineComments: ["#"])
            s.capitalizedTypes = true
            s.keywords = words("alias and begin break case class def do else elsif end ensure for if in module next not or redo rescue retry return then undef unless until when while yield puts require require_relative include extend attr_accessor attr_reader attr_writer private public protected lambda proc")
            s.constants = words("true false nil self super")
            return s
        case "python":
            var s = LanguageSpec(lineComments: ["#"])
            s.tripleStrings = ["\"\"\"", "'''"]; s.capitalizedTypes = true; s.atAttributes = true
            s.keywords = words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case")
            s.constants = words("True False None self cls")
            return s
        case "javascript", "typescript":
            var s = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"))
            s.strings = ["\"", "'", "`"]; s.multilineBacktick = true; s.capitalizedTypes = true
            s.keywords = words("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new of return static super switch this throw try typeof var void while with yield async await from as get set")
            s.constants = words("true false null undefined NaN Infinity")
            if canonical == "typescript" {
                s.atAttributes = true
                s.keywords.formUnion(words("interface type enum implements namespace abstract readonly private public protected declare keyof infer satisfies is"))
                s.types = words("string number boolean unknown never any object void symbol bigint")
            }
            return s
        case "bash":
            var s = LanguageSpec(lineComments: ["#"])
            s.dollarVariables = true
            s.keywords = words("if then else elif fi for while until do done case esac in function select time return exit export local readonly declare unset shift break continue source alias echo cd set")
            s.constants = words("true false")
            return s
        case "json":
            var s = LanguageSpec()
            s.strings = ["\""]; s.jsonKeys = true
            s.constants = words("true false null")
            return s
        case "yaml":
            var s = LanguageSpec()
            s.mode = .yaml
            return s
        case "html":
            var s = LanguageSpec()
            s.mode = .html
            return s
        case "markdown":
            var s = LanguageSpec()
            s.mode = .markdown
            return s
        case "css":
            var s = LanguageSpec(blockComment: ("/*", "*/"))
            s.cssRules = true; s.atAttributes = true
            s.constants = words("important inherit initial unset none auto")
            return s
        case "go":
            var s = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"))
            s.strings = ["\"", "'", "`"]; s.multilineBacktick = true; s.strictApostrophe = true
            s.keywords = words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var")
            s.constants = words("true false nil iota")
            s.types = words("string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr bool byte rune float32 float64 complex64 complex128 error any")
            return s
        case "rust":
            var s = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"))
            s.strings = ["\"", "'"]; s.strictApostrophe = true; s.capitalizedTypes = true
            s.keywords = words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return static struct super trait type unsafe use where while")
            s.constants = words("true false self Self")
            s.types = words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str")
            return s
        case "c", "cpp":
            var s = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"))
            s.strictApostrophe = true; s.hashDirectives = true
            s.keywords = words("auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while")
            s.constants = words("NULL true false")
            s.types = words("char double float int long short signed unsigned void bool size_t")
            if canonical == "cpp" {
                s.keywords.formUnion(words("class namespace template typename this new delete public private protected virtual override final using try catch throw constexpr noexcept operator explicit friend mutable static_cast dynamic_cast reinterpret_cast const_cast"))
                s.constants.formUnion(words("nullptr"))
                s.types.formUnion(words("string vector map set"))
            }
            return s
        case "java":
            var s = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"))
            s.strictApostrophe = true; s.capitalizedTypes = true; s.atAttributes = true
            s.keywords = words("abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try volatile while var record")
            s.constants = words("true false null")
            s.types = words("boolean byte char double float int long short void")
            return s
        case "kotlin":
            var s = LanguageSpec(lineComments: ["//"], blockComment: ("/*", "*/"))
            s.tripleStrings = ["\"\"\""]; s.strings = ["\"", "'"]; s.strictApostrophe = true
            s.capitalizedTypes = true; s.atAttributes = true
            s.keywords = words("as break class continue do else for fun if in interface is object package return super this throw try typealias val var when while by catch constructor finally import init abstract annotation companion const data enum inline inner internal lateinit open operator out override private protected public sealed suspend vararg")
            s.constants = words("true false null")
            return s
        case "sql":
            var s = LanguageSpec(lineComments: ["--"], blockComment: ("/*", "*/"))
            s.caseInsensitive = true
            s.keywords = words("select from where and or not insert into values update set delete create table alter drop index join inner left right outer on group by order having limit offset as distinct union all is in like between exists case when then else end primary key foreign references default unique check constraint view begin commit rollback with asc desc count sum avg min max")
            s.constants = words("true false null")
            return s
        default:
            return nil
        }
    }
}

// MARK: - Scanner

private struct Scanner {
    let spec: LanguageSpec
    let chars: [Character]
    var i = 0
    var tokens: [Token] = []
    var braceDepth = 0

    init(spec: LanguageSpec, text: String) {
        self.spec = spec
        self.chars = Array(text)
    }

    mutating func run() {
        switch spec.mode {
        case .code: scanCode()
        case .yaml: scanLines(yamlLine)
        case .markdown: scanLines(markdownLine)
        case .html: scanHTML()
        }
    }

    // MARK: Helpers

    private mutating func emit(_ kind: TokenKind, _ text: String) {
        guard !text.isEmpty else { return }
        if kind == .plain, let last = tokens.last, last.kind == .plain {
            tokens[tokens.count - 1].text += text
        } else {
            tokens.append(Token(kind: kind, text: text))
        }
    }
    private mutating func emit(_ kind: TokenKind, from start: Int, to end: Int) {
        emit(kind, String(chars[start..<min(end, chars.count)]))
    }
    private func starts(_ s: String, at index: Int) -> Bool {
        let pattern = Array(s)
        guard index + pattern.count <= chars.count else { return false }
        for (offset, character) in pattern.enumerated() where chars[index + offset] != character { return false }
        return true
    }
    private func isIdentStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
    private func isIdentPart(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
    private func isLineStart(_ index: Int) -> Bool {
        var j = index - 1
        while j >= 0, chars[j] == " " || chars[j] == "\t" { j -= 1 }
        return j < 0 || chars[j] == "\n"
    }
    private func nextNonSpace(after index: Int) -> Character? {
        var j = index
        while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
        return j < chars.count ? chars[j] : nil
    }
    private func endOfLine(from index: Int) -> Int {
        var j = index
        while j < chars.count, chars[j] != "\n" { j += 1 }
        return j
    }

    // MARK: Code

    private mutating func scanCode() {
        let n = chars.count
        while i < n {
            let c = chars[i]
            if c.isWhitespace {
                let start = i
                while i < n, chars[i].isWhitespace { i += 1 }
                emit(.plain, from: start, to: i)
            } else if spec.hashDirectives, c == "#", isLineStart(i), i + 1 < n, chars[i + 1].isLetter {
                let start = i
                i += 1
                while i < n, chars[i].isLetter { i += 1 }
                emit(.keyword, from: start, to: i)
            } else if spec.lineComments.contains(where: { starts($0, at: i) }) {
                let start = i
                i = endOfLine(from: i)
                emit(.comment, from: start, to: i)
            } else if let block = spec.blockComment, starts(block.open, at: i) {
                let start = i
                i += block.open.count
                while i < n, !starts(block.close, at: i) { i += 1 }
                i = min(n, i + block.close.count)
                emit(.comment, from: start, to: i)
            } else if let triple = spec.tripleStrings.first(where: { starts($0, at: i) }) {
                let start = i
                i += triple.count
                while i < n, !starts(triple, at: i) { i += 1 }
                i = min(n, i + triple.count)
                emit(.string, from: start, to: i)
            } else if spec.strings.contains(c), opensString(at: i) {
                scanString(quote: c)
            } else if c.isASCII, c.isNumber {
                scanNumber()
            } else if c == ".", i + 1 < n, chars[i + 1].isNumber, !spec.cssRules || braceDepth > 0 {
                scanNumber()
            } else if spec.atAttributes, c == "@", i + 1 < n, chars[i + 1].isLetter {
                let start = i
                i += 1
                while i < n, isIdentPart(chars[i]) || chars[i] == "." || chars[i] == "-" { i += 1 }
                emit(spec.cssRules ? .keyword : .attribute, from: start, to: i)
            } else if spec.dollarVariables, c == "$" {
                scanShellVariable()
            } else if spec.cssRules, c == "{" || c == "}" {
                braceDepth = max(0, braceDepth + (c == "{" ? 1 : -1))
                emit(.plain, String(c))
                i += 1
            } else if spec.cssRules, c == "#" || c == ".", i + 1 < n, isIdentStart(chars[i + 1]) || (c == "#" && chars[i + 1].isNumber) {
                let start = i
                i += 1
                while i < n, isIdentPart(chars[i]) || chars[i] == "-" { i += 1 }
                emit(braceDepth > 0 ? .number : .type, from: start, to: i)
            } else if isIdentStart(c) {
                scanIdentifier()
            } else {
                emit(.plain, String(c))
                i += 1
            }
        }
    }

    /// Whether a quote at `index` really starts a string (see `strictApostrophe`).
    private func opensString(at index: Int) -> Bool {
        guard spec.strictApostrophe, chars[index] == "'" else { return true }
        if index + 1 < chars.count, chars[index + 1] == "\\" { return true }
        return index + 2 < chars.count && chars[index + 2] == "'"
    }

    private mutating func scanString(quote: Character) {
        let n = chars.count
        let start = i
        i += 1
        while i < n {
            if chars[i] == "\\" {
                i = min(n, i + 2)
            } else if chars[i] == quote {
                i += 1
                break
            } else if chars[i] == "\n", !(quote == "`" && spec.multilineBacktick) {
                break
            } else {
                i += 1
            }
        }
        let isKey = spec.jsonKeys && nextNonSpace(after: i) == ":"
        emit(isKey ? .property : .string, from: start, to: i)
    }

    private mutating func scanNumber() {
        let n = chars.count
        let start = i
        if chars[i] == "." { i += 1 }
        while i < n {
            let c = chars[i]
            if c.isLetter || c.isNumber || c == "_" || c == "%" {
                i += 1
            } else if c == ".", i + 1 < n, chars[i + 1].isNumber {
                i += 1
            } else {
                break
            }
        }
        emit(.number, from: start, to: i)
    }

    private mutating func scanShellVariable() {
        let n = chars.count
        let start = i
        i += 1
        if i < n, chars[i] == "{" {
            while i < n, chars[i] != "}", chars[i] != "\n" { i += 1 }
            i = min(n, i + 1)
        } else if i < n, isIdentPart(chars[i]) {
            while i < n, isIdentPart(chars[i]) { i += 1 }
        } else if i < n, "@#?$!*".contains(chars[i]) {
            i += 1
        }
        emit(i > start + 1 ? .variable : .plain, from: start, to: i)
    }

    private mutating func scanIdentifier() {
        let n = chars.count
        let start = i
        while i < n, isIdentPart(chars[i]) || (spec.cssRules && chars[i] == "-" && i + 1 < n && isIdentPart(chars[i + 1])) { i += 1 }
        let word = String(chars[start..<i])
        let lookup = spec.caseInsensitive ? word.lowercased() : word
        if spec.cssRules {
            if braceDepth > 0, nextNonSpace(after: i) == ":" {
                emit(.property, from: start, to: i)
            } else {
                emit(spec.constants.contains(lookup) ? .constant : .plain, from: start, to: i)
            }
        } else if spec.keywords.contains(lookup) {
            emit(.keyword, from: start, to: i)
        } else if spec.constants.contains(lookup) {
            emit(.constant, from: start, to: i)
        } else if spec.types.contains(lookup) {
            emit(.type, from: start, to: i)
        } else if spec.capitalizedTypes, let first = word.first, first.isUppercase {
            let allCaps = word.count > 1 && !word.contains(where: { $0.isLowercase })
            emit(allCaps ? .constant : .type, from: start, to: i)
        } else {
            emit(.plain, from: start, to: i)
        }
    }

    // MARK: Line-based modes

    private mutating func scanLines(_ line: (inout Scanner, [Character]) -> Void) {
        var start = 0
        while start <= chars.count {
            let end = endOfLine(from: start)
            line(&self, Array(chars[start..<end]))
            if end < chars.count { emit(.plain, "\n") }
            start = end + 1
        }
    }

    private func yamlLine(_ scanner: inout Scanner, _ line: [Character]) {
        var index = 0
        var emitted = 0 // everything before this has already been output
        func flush(_ upTo: Int) {
            guard upTo > emitted else { return }
            scanner.emit(.plain, String(line[emitted..<upTo]))
            emitted = upTo
        }
        while index < line.count, line[index] == " " || line[index] == "\t" { index += 1 }
        flush(index)
        while index + 1 < line.count, line[index] == "-", line[index + 1] == " " {
            index += 2
            while index < line.count, line[index] == " " { index += 1 }
            flush(index)
        }
        if index < line.count, line[index] == "#" {
            scanner.emit(.comment, String(line[index...]))
            return
        }
        // "key:" — a colon followed by a space or the end of the line.
        var colon: Int?
        var probe = index
        while probe < line.count {
            if line[probe] == "#", probe == index || line[probe - 1] == " " { break }
            if line[probe] == ":", probe + 1 == line.count || line[probe + 1] == " " { colon = probe; break }
            if line[probe] == "\"" || line[probe] == "'" { break }
            probe += 1
        }
        if let colon, colon > index {
            scanner.emit(.property, String(line[index..<colon]))
            emitted = colon
            flush(colon + 1)
        }
        scanner.yamlValue(Array(line[emitted...]))
    }

    private mutating func yamlValue(_ value: [Character]) {
        var index = 0
        while index < value.count {
            let c = value[index]
            if c == "\"" || c == "'" {
                var end = index + 1
                while end < value.count, value[end] != c { end += end < value.count - 1 && value[end] == "\\" ? 2 : 1 }
                end = min(value.count, end + 1)
                emit(.string, String(value[index..<end]))
                index = end
            } else if c == "#", index == 0 || value[index - 1] == " " {
                emit(.comment, String(value[index...]))
                return
            } else if c == " " {
                emit(.plain, " ")
                index += 1
            } else {
                var end = index
                while end < value.count, value[end] != " " { end += 1 }
                let word = String(value[index..<end])
                let isNumber = Double(word) != nil
                let isConstant = ["true", "false", "null", "yes", "no", "on", "off", "~"].contains(word.lowercased())
                let isAnchor = (word.hasPrefix("&") || word.hasPrefix("*")) && word.count > 1
                emit(isNumber ? .number : isConstant ? .constant : isAnchor ? .variable : .plain, word)
                index = end
            }
        }
    }

    private func markdownLine(_ scanner: inout Scanner, _ line: [Character]) {
        let text = String(line)
        if text.hasPrefix("#") {
            scanner.emit(.keyword, text)
            return
        }
        if text.hasPrefix(">") {
            scanner.emit(.comment, text)
            return
        }
        var index = 0
        while index < line.count {
            if line[index] == "`", let close = line[(index + 1)...].firstIndex(of: "`") {
                scanner.emit(.string, String(line[index...close]))
                index = close + 1
            } else {
                var end = index + 1
                while end < line.count, line[end] != "`" { end += 1 }
                scanner.emit(.plain, String(line[index..<end]))
                index = end
            }
        }
    }

    // MARK: HTML

    private mutating func scanHTML() {
        let n = chars.count
        while i < n {
            if starts("<!--", at: i) {
                let start = i
                i += 4
                while i < n, !starts("-->", at: i) { i += 1 }
                i = min(n, i + 3)
                emit(.comment, from: start, to: i)
            } else if chars[i] == "<", i + 1 < n, chars[i + 1].isLetter || "/!?".contains(chars[i + 1]) {
                scanTag()
            } else {
                let start = i
                i += 1
                while i < n, chars[i] != "<" { i += 1 }
                emit(.plain, from: start, to: i)
            }
        }
    }

    private mutating func scanTag() {
        let n = chars.count
        var start = i
        i += 1
        if i < n, "/!?".contains(chars[i]) { i += 1 }
        emit(.plain, from: start, to: i)
        start = i
        while i < n, chars[i].isLetter || chars[i].isNumber || chars[i] == "-" || chars[i] == ":" { i += 1 }
        emit(.tag, from: start, to: i)
        while i < n, chars[i] != ">" {
            let c = chars[i]
            if c == "\"" || c == "'" {
                start = i
                i += 1
                while i < n, chars[i] != c { i += 1 }
                i = min(n, i + 1)
                emit(.string, from: start, to: i)
            } else if c.isLetter {
                start = i
                while i < n, chars[i].isLetter || chars[i].isNumber || chars[i] == "-" || chars[i] == ":" { i += 1 }
                emit(.property, from: start, to: i)
            } else {
                emit(.plain, String(c))
                i += 1
            }
        }
        if i < n { emit(.plain, ">"); i += 1 }
    }
}
