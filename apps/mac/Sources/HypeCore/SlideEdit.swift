import Foundation

/// One AI-assisted change to a single slide: `"text"` rewrites it; `"diagram"`
/// also returns SVG pictures; `"image"` asks an image model for a raster
/// picture. Matches the Qt app's `SlideReply`/`Generator::editSlide`
/// (`generator.h`/`.cpp`).
public struct SlideReply { public var slide = ""; public var images: [String: Data] = [:]; public var error = "" }
public struct SlideFiles { public var slide = ""; public var error = "" }
public struct SlideEditOutcome { public var slide = ""; public var warnings: [String] = []; public var summary = "" }

private let separatorLineRe = try! NSRegularExpression(pattern: "^ {0,3}(`{3,}|~{3,})")

/// True when `text` holds a `---` slide separator outside a fenced code block.
func hasSlideSeparator(_ text: String) -> Bool {
    var fenceChar: Character?
    var fenceLength = 0
    for raw in text.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if let match = separatorLineRe.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let range = Range(match.range(at: 1), in: raw) {
            let run = raw[range]
            if fenceLength == 0 {
                fenceChar = run.first
                fenceLength = run.count
            } else if run.first == fenceChar, run.count >= fenceLength {
                fenceLength = 0
            }
        } else if fenceLength == 0, line == "---" {
            return true
        }
    }
    return false
}

/// Matches `parseSlideReply` (`generator.cpp`).
public func parseSlideReply(_ text: String, withImages: Bool) -> SlideReply {
    var reply = SlideReply()
    var body = ""
    let hasMarkers = text.range(of: "^=== FILE:", options: .regularExpression) != nil
    if withImages || hasMarkers {
        let files = parseGeneratedFiles(text, primary: "slide.md")
        if !files.error.isEmpty { reply.error = files.error; return reply }
        body = files.files["slide.md"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if withImages {
            for (path, data) in files.files where path != "slide.md" { reply.images[path] = data }
        }
    } else {
        body = unfenced(text)
    }
    body = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if body.isEmpty {
        reply.error = "The model returned an empty slide."
    } else if hasSlideSeparator(body) {
        reply.error = "The model returned more than one slide. Try again with a narrower request."
    } else {
        reply.slide = body
    }
    return reply
}

/// The message sent for a per-slide edit: the deck outline (with the target
/// slide marked), the slide's current text, and the request. Matches
/// `slideRequest` (`generator.cpp`).
public func slideRequest(instruction: String, slide: String, outline: String, index: Int) -> String {
    var lines = outline.components(separatedBy: "\n").filter { !$0.isEmpty }
    if index >= 0, index < lines.count { lines[index] += "   <- the slide to change" }
    return "Outline of the deck:\n" + lines.joined(separator: "\n") + "\n\nThe slide to change (slide \(index + 1)):\n"
         + "<slide>\n" + slide.trimmingCharacters(in: .whitespacesAndNewlines) + "\n</slide>\n\nRequest: "
         + instruction.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Matches `imagePrompt` (`generator.cpp`).
public func imagePrompt(instruction: String, slide: String) -> String {
    let title = slideTitle(parseMedia(slide, base: "").text)
    let titled = title.isEmpty ? "" : " titled \"\(title)\""
    return "Create a picture for one presentation slide\(titled). Wide 16:9 composition with a calm area "
         + "that can sit beside text. Do not draw words, letters or logos unless the request asks for them.\n\n"
         + "Request: " + instruction.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// A name not already used in `folder`, inserting `-2`, `-3`, … before the extension.
private func uniqueName(in directory: String, name: String) -> String {
    let ext = (name as NSString).pathExtension
    let base = (name as NSString).deletingPathExtension
    var candidate = name
    var attempt = 2
    let fm = FileManager.default
    while fm.fileExists(atPath: (directory as NSString).appendingPathComponent(candidate)), attempt <= 99 {
        candidate = "\(base)-\(attempt).\(ext)"
        attempt += 1
    }
    return candidate
}

/// Writes a diagram reply's pictures into `<baseDir>/images`, never
/// overwriting an existing file, and renames references in the slide to match
/// any file that had to be renamed. Matches `writeSlidePictures` (`generator.cpp`).
public func writeSlidePictures(baseDir: String, reply: SlideReply) -> SlideFiles {
    var result = SlideFiles(slide: reply.slide, error: "")
    guard !reply.images.isEmpty else { return result }
    let folder = (baseDir as NSString).appendingPathComponent("images")
    do {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    } catch {
        result.error = "Could not create \(folder)"
        return result
    }
    for (path, data) in reply.images {
        let name = (path as NSString).lastPathComponent
        let written = uniqueName(in: folder, name: name)
        let full = (folder as NSString).appendingPathComponent(written)
        do {
            try data.write(to: URL(fileURLWithPath: full), options: .withoutOverwriting)
        } catch {
            result.error = "\(full): \(error.localizedDescription)"
            return result
        }
        if written != name {
            for form in ["(%@)", "(<%@>)", "(images/%@)", "(<images/%@>)"] {
                result.slide = result.slide.replacingOccurrences(of: String(format: form, name), with: String(format: form, written))
            }
        }
    }
    return result
}

/// Writes a raster picture and points the slide at it, beside the text with
/// `![right]` when there is any, or alone otherwise. Matches
/// `addPictureToSlide` (`generator.cpp`).
public func addPictureToSlide(baseDir: String, slide: String, image: ImageReply, hint: String) -> SlideFiles {
    var result = SlideFiles(slide: slide, error: "")
    let folder = (baseDir as NSString).appendingPathComponent("images")
    do {
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    } catch {
        result.error = "Could not create \(folder)"
        return result
    }
    let name = uniqueName(in: folder, name: String(slugify(hint).prefix(40)) + "." + image.fileExtension)
    let full = (folder as NSString).appendingPathComponent(name)
    do {
        try image.bytes.write(to: URL(fileURLWithPath: full), options: .withoutOverwriting)
    } catch {
        result.error = "\(full): \(error.localizedDescription)"
        return result
    }
    let hasText = !parseMedia(slide, base: baseDir).text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    result.slide = withMediaReference(slide, side: hasText ? "right" : "", name: name)
    return result
}

/// Appends an image reference to a slide's Markdown (a fresh AI-added picture
/// never replaces an existing one, since the slide had none to begin with).
private func withMediaReference(_ slide: String, side: String, name: String) -> String {
    let reference = "![\(side)](\(name))"
    let trimmed = slide.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? reference : trimmed + "\n" + reference
}
