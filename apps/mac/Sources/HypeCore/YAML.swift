import Foundation
import Yams

/// YAML front-matter helpers. The existing `scalar`/`setScalar` functions keep
/// handling simple `key: value` lines; these helpers add typed reading for the
/// full YAML syntax that users can now write in the source editor.

/// The YAML content between the first and last `---` delimiter lines, or the
/// whole header if it does not start with `---`. A header that contains only
/// the delimiters yields the empty string.
private func yamlContent(_ header: String) -> String {
    var lines = header.trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .newlines)
    if lines.first == "---" {
        lines.removeFirst()
    }
    if lines.last == "---" {
        lines.removeLast()
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Parses the front-matter block as YAML. Returns `nil` when the header is
/// empty or cannot be parsed.
public func parseYAMLHeader(_ header: String) -> [String: Any]? {
    let content = yamlContent(header)
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
    guard let node = try? Yams.load(yaml: content) else { return nil }
    return node as? [String: Any]
}

/// Whether the front-matter block is valid YAML (empty is valid).
public func isValidYAMLHeader(_ header: String) -> Bool {
    parseYAMLHeader(header) != nil
}

/// Reads a string value from YAML front matter. Numbers and booleans are
/// converted to their string representation so simple keys stay readable.
public func yamlString(_ header: String, key: String) -> String? {
    guard let dict = parseYAMLHeader(header) else { return nil }
    if let value = dict[key] as? String { return value }
    if let value = dict[key] as? Bool { return value ? "true" : "false" }
    if let value = dict[key] as? Double { return String(value) }
    if let value = dict[key] as? Float { return String(value) }
    if let value = dict[key] as? Int { return String(value) }
    return nil
}

/// Reads a boolean value from YAML front matter.
public func yamlBool(_ header: String, key: String) -> Bool? {
    guard let dict = parseYAMLHeader(header) else { return nil }
    if let value = dict[key] as? Bool { return value }
    if let value = dict[key] as? String { return parseBoolScalar(value) }
    return nil
}

/// Reads an array of strings from YAML front matter.
public func yamlArray(_ header: String, key: String) -> [String]? {
    guard let dict = parseYAMLHeader(header) else { return nil }
    if let array = dict[key] as? [String] { return array }
    if let array = dict[key] as? [Any] {
        return array.compactMap { element -> String? in
            if let string = element as? String { return string }
            if let number = element as? NSNumber { return number.stringValue }
            return nil
        }
    }
    return nil
}

/// Reads an integer value from YAML front matter.
public func yamlInt(_ header: String, key: String) -> Int? {
    guard let dict = parseYAMLHeader(header) else { return nil }
    if let value = dict[key] as? Int { return value }
    if let value = dict[key] as? String { return Int(value) }
    return nil
}

/// Reads a double value from YAML front matter.
public func yamlDouble(_ header: String, key: String) -> Double? {
    guard let dict = parseYAMLHeader(header) else { return nil }
    if let value = dict[key] as? Double { return value }
    if let value = dict[key] as? Float { return Double(value) }
    if let value = dict[key] as? Int { return Double(value) }
    if let value = dict[key] as? String { return Double(value) }
    return nil
}
