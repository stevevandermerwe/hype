import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Requests

/// A chat-completions request body for an OpenAI-compatible endpoint.
/// Matches `buildChatRequest` (`generator.cpp`).
public func buildChatRequestBody(model: String, system: String, user: String) -> Data {
    let body: [String: Any] = [
        "model": model,
        "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
    ]
    return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
}

/// An image-generation request: OpenAI's `/images/generations` takes a bare
/// prompt; a chat endpoint (OpenRouter) asks for image output via
/// `modalities`. Matches `buildImageRequest` (`generator.cpp`).
public func buildImageRequestBody(endpoint: URL, model: String, prompt: String) -> Data {
    var body: [String: Any] = ["model": model]
    if endpoint.path.hasSuffix("/images/generations") {
        body["prompt"] = prompt
        body["n"] = 1
    } else {
        body["messages"] = [["role": "user", "content": prompt]]
        body["modalities"] = ["image", "text"]
    }
    return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
}

// MARK: - Chat reply

public struct ChatReply { public var content = ""; public var error = "" }

private func errorMessage(_ value: Any?) -> String {
    if let string = value as? String { return string }
    if let dict = value as? [String: Any], let message = dict["message"] as? String { return message }
    return ""
}

/// Matches `parseChatReply` (`generator.cpp`).
public func parseChatReply(_ data: Data) -> ChatReply {
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ChatReply(content: "", error: "The endpoint did not return JSON. Check the endpoint URL.")
    }
    if let error = json["error"] {
        let message = errorMessage(error)
        return ChatReply(content: "", error: message.isEmpty ? "The endpoint returned an error." : message)
    }
    guard let choices = json["choices"] as? [[String: Any]], let first = choices.first,
          let message = first["message"] as? [String: Any] else {
        return ChatReply(content: "", error: "The model returned no content.")
    }
    var text = ""
    if let content = message["content"] as? String {
        text = content
    } else if let parts = message["content"] as? [[String: Any]] {
        for part in parts { text += (part["text"] as? String) ?? "" } // Some providers return content parts.
    }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return ChatReply(content: "", error: "The model returned no content.")
    }
    if (first["finish_reason"] as? String) == "length" {
        return ChatReply(content: "", error: "The model ran out of output tokens before finishing. "
                         + "Ask for fewer slides or use a model with a larger output limit.")
    }
    return ChatReply(content: text, error: "")
}

// MARK: - Image reply

public struct ImageReply { public var bytes = Data(); public var fileExtension = "png"; public var error = "" }

private func isDecodableImage(_ data: Data) -> Bool {
    #if canImport(AppKit)
    return NSImage(data: data) != nil
    #else
    return true
    #endif
}

/// Matches `parseImageReply` (`generator.cpp`).
public func parseImageReply(_ data: Data) -> ImageReply {
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ImageReply(bytes: Data(), fileExtension: "png", error: "The endpoint did not return JSON. Check the image endpoint URL.")
    }
    if let error = json["error"] {
        let message = errorMessage(error)
        return ImageReply(bytes: Data(), fileExtension: "png", error: message.isEmpty ? "The endpoint returned an error." : message)
    }
    var mime = "image/png"
    var encoded = ""
    if let choices = json["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any],
       let images = message["images"] as? [[String: Any]], let first = images.first,
       let imageURL = first["image_url"] as? [String: Any], let url = imageURL["url"] as? String,
       url.hasPrefix("data:"), let comma = url.firstIndex(of: ",") {
        let header = url[url.index(url.startIndex, offsetBy: 5)..<comma] // after "data:"
        mime = String(header.split(separator: ";").first ?? "image/png")
        encoded = String(url[url.index(after: comma)...])
    } else if let items = json["data"] as? [[String: Any]], let first = items.first, let b64 = first["b64_json"] as? String {
        encoded = b64
    }
    guard !encoded.isEmpty, let bytes = Data(base64Encoded: encoded), !bytes.isEmpty else {
        return ImageReply(bytes: Data(), fileExtension: "png", error: "The image model returned no picture. Check that the image model can draw pictures.")
    }
    guard isDecodableImage(bytes) else {
        return ImageReply(bytes: Data(), fileExtension: "png", error: "The image model returned data that is not a picture.")
    }
    let ext = mime == "image/jpeg" ? "jpg" : mime == "image/webp" ? "webp" : "png"
    return ImageReply(bytes: bytes, fileExtension: ext, error: "")
}

// MARK: - Generated files (=== FILE: path === replies)

public struct GeneratedFiles { public var files: [String: Data] = [:]; public var error = "" }

private let fileMarkerRe = try! NSRegularExpression(pattern: "^=== FILE: (.+?) ===$")
private let svgPathRe = try! NSRegularExpression(pattern: "^images/[A-Za-z0-9][A-Za-z0-9._-]*\\.svg$",
                                                 options: .caseInsensitive)
private let openingFenceRe = try! NSRegularExpression(pattern: "^```[A-Za-z0-9_-]*[ \\t]*$")

/// Strips one wrapping ``` fence around a whole file, if a model added one.
func unfenced(_ text: String) -> String {
    let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lines = body.components(separatedBy: "\n")
    guard let first = lines.first, body.hasSuffix("```"),
          openingFenceRe.firstMatch(in: first, range: NSRange(first.startIndex..., in: first)) != nil
    else { return text }
    let inner = lines.dropFirst().joined(separator: "\n")
    guard inner.hasSuffix("```") else { return text }
    return String(inner.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
}

private func acceptedPath(_ path: String, primary: String) -> Bool {
    if path == primary { return true }
    return svgPathRe.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
}

private let maxGeneratedFiles = 40
private let maxGeneratedFileBytes = 2 * 1024 * 1024

/// The model answers with "=== FILE: path ===" sections; matches
/// `parseGeneratedFiles` (`generator.cpp`). Only `primary` and
/// `images/<name>.svg` are accepted, so a reply can never write outside its
/// folder.
public func parseGeneratedFiles(_ text: String, primary: String = "presentation.md") -> GeneratedFiles {
    var result = GeneratedFiles()
    var path: String?
    var body = ""
    var sawMarker = false
    func flush() {
        guard let path, acceptedPath(path, primary: primary), result.files.count < maxGeneratedFiles else { return }
        let bytes = Data((unfenced(body).trimmingCharacters(in: .whitespacesAndNewlines) + "\n").utf8)
        if bytes.count <= maxGeneratedFileBytes { result.files[path] = bytes }
    }
    for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let match = fileMarkerRe.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed) {
            flush()
            path = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
            body = ""
            sawMarker = true
        } else if path != nil {
            body += line + "\n"
        }
    }
    flush()
    if !sawMarker {
        // No markers: accept a bare Markdown deck rather than throw the reply away.
        let bare = unfenced(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if bare.contains("\n---"), bare.contains("# ") {
            result.files[primary] = Data((bare + "\n").utf8)
        }
    }
    if result.files[primary] == nil {
        result.error = "The reply did not contain a \(primary). Try again, or use a more capable model."
    }
    return result
}

/// Matches `slugify` (`generator.cpp`): a folder-safe name from a title.
public func slugify(_ title: String) -> String {
    let folded = title.lowercased().folding(options: .diacriticInsensitive, locale: .current)
    var result = ""
    var lastWasDash = false
    for scalar in folded.unicodeScalars {
        if ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)) {
            result.unicodeScalars.append(scalar)
            lastWasDash = false
        } else if !lastWasDash, !result.isEmpty {
            result.append("-")
            lastWasDash = true
        }
    }
    while result.hasSuffix("-") { result.removeLast() }
    if result.isEmpty { return "presentation" }
    return String(result.prefix(60))
}
