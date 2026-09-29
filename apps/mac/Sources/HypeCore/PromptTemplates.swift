import Foundation

/// Loads the bundled prompt templates (copied from `../../src/*.md`, the Qt
/// app's own templates — see `Resources/` and `Package.swift`) and builds the
/// system prompts sent to the model. Matches `promptTemplate`/`slideTemplate`
/// (`generator.cpp`).
enum PromptTemplates {
    static func text(_ name: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Resources")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// The whole-deck generation system prompt: the bundled template with
/// `{{format}}` expanded, plus the mind-map rules when `mode == "mindmap"`.
public func promptTemplate(mode: String? = nil) -> String? {
    guard var text = PromptTemplates.text("prompt"), let format = PromptTemplates.text("format") else { return nil }
    text = text.replacingOccurrences(of: "{{format}}", with: format.trimmingCharacters(in: .whitespacesAndNewlines))
    if mode == "mindmap", let mindmap = PromptTemplates.text("mindmap") {
        text += "\n" + mindmap.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
    return text
}

/// The per-slide edit system prompt: `"text"` rewrites the slide; `"diagram"`
/// also draws an SVG. Matches `slideTemplate` (`generator.cpp`).
public func slideTemplate(kind: String) -> String? {
    guard let format = PromptTemplates.text("format") else { return nil }
    let name = kind == "diagram" ? "slide-diagram" : "slide-text"
    guard var text = PromptTemplates.text(name) else { return nil }
    text = text.replacingOccurrences(of: "{{format}}", with: format.trimmingCharacters(in: .whitespacesAndNewlines))
    return text
}
