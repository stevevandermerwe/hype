import Foundation

/// Layout options for a slide's image or video, written as directives inside
/// the brackets of `![...](file)` (see `format.md`). Non-directive words in
/// the brackets are alt text and are left alone.
public enum ImageLayout: Equatable, Sendable {
    /// Image in the left/right half, text in the other half.
    case left, right
    /// Show the whole image (with any text overlaid) / fill the slide, cropping.
    case fit, span
    case background(ImageBackground)
    /// Darken the picture behind text (`overlay=0.5`).
    case darken
    /// Video options.
    case loop, muted
}

public enum ImageBackground: String, Sendable, CaseIterable {
    case blur, auto, white, black
}

/// The image/video reference in `slide`, ignoring any inside code.
func firstReference(in slide: String) -> NSTextCheckingResult? {
    let masked = outsideCode(slide)
    return mediaRe.firstMatch(in: masked, range: NSRange(location: 0, length: (masked as NSString).length))
}

/// Toggles `layout` on the slide's first image or video and returns the new
/// slide text, or nil if the slide has no image. Layouts that exclude each
/// other (left/right, fit/span, the backgrounds) replace one another; choosing
/// the one already set clears it.
public func applyImageLayout(_ layout: ImageLayout, to slide: String) -> String? {
    guard let match = firstReference(in: slide) else { return nil }
    let ns = slide as NSString
    let altRange = match.range(at: 1)
    var tokens = ns.substring(with: altRange).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)

    func toggle(_ token: String, replacing conflicts: [String] = []) {
        if tokens.contains(token) {
            tokens.removeAll { $0 == token }
        } else {
            tokens.removeAll { conflicts.contains($0) }
            tokens.append(token)
        }
    }
    func toggleKeyed(_ key: String, _ value: String) {
        let already = tokens.contains("\(key)=\(value)")
        tokens.removeAll { $0.hasPrefix("\(key)=") }
        if !already { tokens.append("\(key)=\(value)") }
    }

    switch layout {
    case .left: toggle("left", replacing: ["right"])
    case .right: toggle("right", replacing: ["left"])
    case .fit: toggle("fit", replacing: ["span"])
    case .span: toggle("span", replacing: ["fit"])
    case .background(let kind): toggleKeyed("background", kind.rawValue)
    case .darken: toggleKeyed("overlay", "0.5")
    case .loop: toggle("loop")
    case .muted: toggle("muted")
    }
    return ns.replacingCharacters(in: altRange, with: tokens.joined(separator: " "))
}

/// Points the slide's image at `file`, keeping its directives; or, if the slide
/// has none, appends a reference after the text.
public func setImageFile(_ file: String, in slide: String) -> String {
    let path = file.contains(where: { $0 == " " || $0 == "(" || $0 == ")" }) ? "<\(file)>" : file
    guard let match = firstReference(in: slide) else {
        let body = slide.trimmingCharacters(in: .whitespacesAndNewlines)
        return (body.isEmpty ? "" : body + "\n\n") + "![](\(path))\n"
    }
    let ns = slide as NSString
    let altEnd = match.range(at: 1).location + match.range(at: 1).length
    // Everything between "](" and the closing ")".
    let target = NSRange(location: altEnd + 2, length: match.range.location + match.range.length - 1 - (altEnd + 2))
    return ns.replacingCharacters(in: target, with: path)
}

// MARK: - Importing

public enum MediaImportError: LocalizedError, Equatable {
    case needsSavedDeck
    case unsupported(String)
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .needsSavedDeck: return "Save the presentation first, so its pictures have a folder to go in."
        case .unsupported(let name): return "\(name) isn't a picture or video Hype can show."
        case .copyFailed(let reason): return "Couldn't copy the file: \(reason)"
        }
    }
}

let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg"]

/// Copies a picture or video into the deck's `images/` or `videos/` folder
/// (creating it), never overwriting a file already there, and returns the bare
/// filename to reference from the slide.
public func importMedia(from source: URL, into baseDir: String) throws -> String {
    guard !baseDir.isEmpty else { throw MediaImportError.needsSavedDeck }
    let ext = source.pathExtension.lowercased()
    let isVideo = videoExtensions.contains(ext)
    guard isVideo || imageExtensions.contains(ext) else { throw MediaImportError.unsupported(source.lastPathComponent) }

    let folder = URL(fileURLWithPath: baseDir).appendingPathComponent(isVideo ? "videos" : "images")
    let fileManager = FileManager.default
    do {
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = source.deletingPathExtension().lastPathComponent
        var name = source.lastPathComponent
        var counter = 0
        while fileManager.fileExists(atPath: folder.appendingPathComponent(name).path) {
            counter += 1
            name = "\(stem)-\(counter).\(source.pathExtension)"
        }
        try fileManager.copyItem(at: source, to: folder.appendingPathComponent(name))
        return name
    } catch {
        throw MediaImportError.copyFailed(error.localizedDescription)
    }
}
