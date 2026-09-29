import Foundation

public struct WrittenPresentation { public var path = ""; public var warnings: [String] = []; public var error = "" }

private let maxFolderAttempts = 99

/// Writes a generated deck's files into a folder: into `directory` when given
/// (it must be new or empty), otherwise a new folder named after the title
/// under `outputRoot`. Applies `theme` (via the same `DeckModel.chooseTheme`
/// the editor uses) and reports any `slideProblems` (e.g. an image the model
/// referenced but never wrote) as warnings. Matches `writePresentation`
/// (`generator.cpp`).
public func writePresentation(_ generated: GeneratedFiles, directory: String?, outputRoot: String, theme: String?) -> WrittenPresentation {
    var result = WrittenPresentation()
    guard let mainData = generated.files["presentation.md"], let mainText = String(data: mainData, encoding: .utf8) else {
        result.error = "Nothing to write: no presentation.md."
        return result
    }
    let fm = FileManager.default
    let title = scalar(parseDeck(mainText).header, "title", "presentation")
    var target: String
    if let directory, !directory.isEmpty {
        target = (directory as NSString).standardizingPath
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: target, isDirectory: &isDirectory) {
            let contents = (try? fm.contentsOfDirectory(atPath: target)) ?? []
            if !contents.isEmpty {
                result.error = "\(target) already exists and is not empty."
                return result
            }
        }
    } else {
        let base = (outputRoot as NSString).appendingPathComponent(slugify(title))
        target = base
        var attempt = 2
        while fm.fileExists(atPath: target), attempt <= maxFolderAttempts {
            target = base + "-\(attempt)"
            attempt += 1
        }
        if fm.fileExists(atPath: target) {
            result.error = "Could not find a free folder name beside \(base)"
            return result
        }
    }
    do {
        try fm.createDirectory(atPath: (target as NSString).appendingPathComponent("images"), withIntermediateDirectories: true)
        try fm.createDirectory(atPath: (target as NSString).appendingPathComponent("videos"), withIntermediateDirectories: true)
    } catch {
        result.error = "Could not create \(target)"
        return result
    }
    for (path, data) in generated.files {
        let full = (target as NSString).appendingPathComponent(path)
        do {
            try fm.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: full), options: .atomic)
        } catch {
            result.error = "\(full): \(error.localizedDescription)"
            return result
        }
    }
    let presentationPath = (target as NSString).appendingPathComponent("presentation.md")
    result.path = presentationPath

    let model = DeckModel()
    guard model.loadPath(presentationPath) else {
        result.warnings.append("Could not read the generated presentation: \(model.status)")
        return result
    }
    if let theme, !theme.isEmpty {
        if BundledTheme(rawValue: theme) != nil {
            model.chooseTheme(theme)
        } else {
            result.warnings.append("Theme \(theme) is not installed; kept the default.")
        }
    } else {
        model.chooseTheme(model.themeName) // Records the theme's colors, as `hype new` does.
    }
    model.savePath(presentationPath)
    for index in 0..<model.count {
        for problem in slideProblems(model.slideSource(at: index), base: target) {
            result.warnings.append("Slide \(index + 1): \(problem)")
        }
    }
    return result
}
