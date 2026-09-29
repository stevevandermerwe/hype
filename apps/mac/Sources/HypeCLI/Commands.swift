import Foundation
import HypeCore
import HypeRender

/// Headless commands, mirroring the Qt app's `cli.cpp`:
/// `new`/`check`/`slides`/`render`/`export`/`generate`/`revise`/`themes`/`help`.
/// Each subcommand's `Args` holds only the arguments *after* the subcommand
/// name, so `positional(0)` is the first real argument (typically the
/// presentation path), matching how the dispatcher in `Entry.swift` builds it.

let usageSummary = """
Commands:
  new <presentation>              Start a presentation
  check <presentation>            Report every problem, with slide and line
  slides <presentation>           Outline the slides
  render <presentation>           Render one slide or all of them to PNG
  export <presentation> <output>  Export PDF or HTML
  generate <prompt>                Write a whole presentation folder with an AI model
  revise <presentation> <n> <what> Change one slide, or draw its picture, with an AI model
  themes                          List bundled themes
  help                            Show this summary, or `help <command>`
"""

private func lineNumber(_ source: String, utf16Offset: Int) -> Int {
    let utf16 = Array(source.utf16)
    var count = 1
    for i in 0..<min(max(0, utf16Offset), utf16.count) where utf16[i] == 0x0A { count += 1 }
    return count
}

func cmdNew(_ args: Args) -> Int32 {
    guard let path = args.positional(0) else { return fail("Name the Markdown file to create.") }
    if FileManager.default.fileExists(atPath: path) { return fail("\(path) already exists.") }
    let theme = args.value("theme") ?? "tokyo-night"
    let choices = themeChoices()
    guard let chosen = choices.first(where: { $0.id == theme }) else {
        return fail("Theme \(theme) is not installed. Installed: " + choices.map(\.id).joined(separator: ", "))
    }
    let title = args.value("title") ?? (URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
    var header = setScalar("", "title", title)
    header = setScalar(header, "theme", theme)
    if let font = args.value("font"), !font.isEmpty { header = setScalar(header, "font", font) }
    if chosen.isCustom { // Bake a custom theme's colours in, so the deck looks right anywhere.
        for key in Palette.colorKeys { header = setScalar(header, "color_\(key)", chosen.palette[key]) }
    }
    let source = header + "\n# " + title + "\n"
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
    do {
        if !directory.isEmpty { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true) }
        try FileManager.default.createDirectory(atPath: (directory as NSString).appendingPathComponent("images"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: (directory as NSString).appendingPathComponent("videos"), withIntermediateDirectories: true)
        try source.write(toFile: path, atomically: true, encoding: .utf8)
    } catch {
        return fail("\(path): \(error.localizedDescription)")
    }
    if args.flag("json") {
        printJSON(["presentation": URL(fileURLWithPath: path).absoluteURL.path, "title": title, "theme": theme])
    } else {
        printLine("Created \(path)")
    }
    return 0
}

@MainActor
func cmdCheck(_ args: Args) -> Int32 {
    guard let path = args.positional(0) else { return fail("Name a Markdown presentation.") }
    let deck = DeckModel()
    guard deck.loadPath(path) else { return fail("\(path): \(deck.status)") }
    var problems: [(slide: Int, line: Int, severity: String, message: String)] = []
    if !deck.parsed.error.isEmpty {
        problems.append((0, 1, "error", deck.parsed.error))
    }
    if !deck.fontName.isEmpty, !isFontAvailable(deck.fontName) {
        problems.append((0, 1, "warning", "Font \"\(deck.fontName)\" is not installed here; slides use the system font"))
    }
    for index in 0..<deck.count {
        let slide = deck.parsed.slides[index]
        let line = lineNumber(deck.source, utf16Offset: slide.start)
        for message in slideProblems(slide.source, base: deck.baseDir) {
            problems.append((index + 1, line, "error", message))
        }
        if deck.slideText(at: index).isEmpty {
            problems.append((index + 1, line, "warning", "Empty slide"))
        }
        if let report = measureSlideText(source: slide.source, baseDir: deck.baseDir, textScale: deck.textScale, fontName: deck.fontName), report.isCramped {
            let percent = Int((report.readability * 100).rounded())
            problems.append((index + 1, line, "warning",
                             "Too much text: it shrinks to \(percent)% of a readable size. Split the slide or cut words"))
        }
    }
    let errors = problems.filter { $0.severity == "error" }.count
    if args.flag("json") {
        let list = problems.map { p -> [String: Any] in
            ["slide": p.slide == 0 ? NSNull() : p.slide, "line": p.line, "severity": p.severity, "message": p.message]
        }
        printJSON(["ok": errors == 0, "slides": deck.count, "problems": list])
    } else {
        for p in problems {
            let where_ = p.slide == 0 ? "" : "slide \(p.slide) "
            printLine("\(path):\(p.line): \(where_)\(p.severity): \(p.message)")
        }
    }
    return errors == 0 ? 0 : 1
}

func cmdSlides(_ args: Args) -> Int32 {
    guard let path = args.positional(0) else { return fail("Name a Markdown presentation.") }
    let deck = DeckModel()
    guard deck.loadPath(path) else { return fail("\(path): \(deck.status)") }
    if args.flag("json") {
        var list: [[String: Any]] = []
        for index in 0..<deck.count {
            let title = slideTitle(parseMedia(deck.slideSource(at: index), base: deck.baseDir).text)
            list.append(["slide": index + 1, "title": title])
        }
        printJSON(["slides": list])
    } else {
        printLine(deck.slideOutline())
    }
    return 0
}

func cmdThemes(_ args: Args) -> Int32 {
    let choices = themeChoices()
    let names = choices.map(\.id)
    if args.flag("json") {
        printJSON(["themes": names, "custom": choices.filter(\.isCustom).map(\.id)])
    } else {
        for name in names { printLine(name) }
    }
    return 0
}

@MainActor
func cmdRender(_ args: Args) -> Int32 {
    guard let path = args.positional(0) else { return fail("Name a Markdown presentation.") }
    let deck = DeckModel()
    guard deck.loadPath(path) else { return fail("\(path): \(deck.status)") }
    let width = args.value("width").flatMap(Double.init) ?? 3840
    let size = CGSize(width: width, height: (width * 9 / 16).rounded())
    if let slideArgument = args.value("slide") {
        guard let n = Int(slideArgument), n >= 1, n <= deck.count else {
            return fail("Name a slide from 1 to \(deck.count).")
        }
        guard let output = args.value("o") else { return fail("Name an output file with -o.") }
        do {
            try renderSlidePNG(deck: deck, index: n - 1, to: URL(fileURLWithPath: output), size: size)
        } catch { return fail("\(error.localizedDescription)") }
        if args.flag("json") { printJSON(["image": URL(fileURLWithPath: output).absoluteURL.path]) }
        else { printLine("Rendered \(output)") }
        return 0
    }
    guard let outputDirectory = args.value("o") else { return fail("Name an output directory with -o.") }
    do {
        try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        var manifest: [[String: Any]] = []
        for index in 0..<deck.count {
            let name = String(format: "slide-%03d.png", index + 1)
            try renderSlidePNG(deck: deck, index: index, to: URL(fileURLWithPath: (outputDirectory as NSString).appendingPathComponent(name)), size: size)
            manifest.append(["file": name])
        }
        let manifestData = try JSONSerialization.data(withJSONObject: ["slides": manifest])
        try manifestData.write(to: URL(fileURLWithPath: (outputDirectory as NSString).appendingPathComponent("slides.json")))
    } catch { return fail("\(error.localizedDescription)") }
    if args.flag("json") { printJSON(["directory": outputDirectory, "count": deck.count]) }
    else { printLine("Rendered \(deck.count) slides to \(outputDirectory)/") }
    return 0
}

@MainActor
func cmdExport(_ args: Args) -> Int32 {
    guard let path = args.positional(0), let output = args.positional(1) else {
        return fail("Name a presentation and an output file ending in .pdf or .html.")
    }
    let deck = DeckModel()
    guard deck.loadPath(path) else { return fail("\(path): \(deck.status)") }
    let url = URL(fileURLWithPath: output)
    do {
        switch url.pathExtension.lowercased() {
        case "pdf": try exportPDF(deck: deck, to: url)
        case "html", "htm": try exportHTML(deck: deck, to: url)
        default: return fail("Name an output file ending in .pdf or .html.")
        }
    } catch { return fail("\(error.localizedDescription)") }
    if args.flag("json") { printJSON(["output": url.absoluteURL.path]) }
    else { printLine("Exported \(output)") }
    return 0
}

@MainActor
func cmdGenerate(_ args: Args) async -> Int32 {
    var config = AIConfigStore.load()
    if let endpoint = args.value("endpoint") { config.endpoint = endpoint }
    if let model = args.value("model") { config.model = model }
    if args.flag("save") {
        AIConfigStore.save(config)
        printErr("Saved AI settings.")
    }
    if args.flag("print-template") {
        guard let text = promptTemplate(mode: args.flag("mind-map") ? "mindmap" : nil) else {
            return fail("Could not read the prompt template.")
        }
        printLine(text, to: FileHandle.standardOutput)
        return 0
    }
    var prompt = args.positional(0) ?? ""
    if prompt == "-" {
        prompt = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if args.flag("save") { return 0 }
        return fail(args.flag("mind-map") ? "Paste your mind map, or use - to read it from stdin."
                                          : "Describe the presentation, or use - to read the prompt from stdin.")
    }
    let generator = Generator(config: config)
    printErr("Generating with \(config.model)…")
    switch await generator.generate(prompt: prompt, theme: args.value("theme"), directory: args.value("o"),
                                    mode: args.flag("mind-map") ? "mindmap" : nil) {
    case .failure(let error):
        return fail(error.message)
    case .success(let written):
        if args.flag("json") {
            printJSON(["presentation": written.path, "warnings": written.warnings])
        } else {
            printLine("Created \(written.path)")
            for warning in written.warnings { printErr("warning: \(warning)") }
        }
        return 0
    }
}

@MainActor
func cmdRevise(_ args: Args) async -> Int32 {
    guard let path = args.positional(0) else { return fail("Name a Markdown presentation.") }
    guard let numberText = args.positional(1), let number = Int(numberText) else {
        return fail("Name a slide, from 1.")
    }
    guard let instruction = args.positional(2), !instruction.trimmingCharacters(in: .whitespaces).isEmpty else {
        return fail("Say what to change on the slide.")
    }
    if args.flag("diagram"), args.flag("image") { return fail("Choose either --diagram or --image.") }
    let kind = args.flag("diagram") ? "diagram" : args.flag("image") ? "image" : "text"
    var config = AIConfigStore.load()
    if let endpoint = args.value("endpoint") { config.endpoint = endpoint }
    if let model = args.value("model") { config.model = model }
    if let imageEndpoint = args.value("image-endpoint") { config.imageEndpoint = imageEndpoint }
    if let imageModel = args.value("image-model") { config.imageModel = imageModel }
    let deck = DeckModel()
    guard deck.loadPath(path) else { return fail("\(path): \(deck.status)") }
    guard number >= 1, number <= deck.count else { return fail("Name a slide from 1 to \(deck.count).") }
    deck.select(number - 1)
    let generator = Generator(config: config)
    printErr("Asking \(kind == "image" ? config.imageModel : config.model)…")
    let outline = deck.slideOutline()
    let slideText = deck.slideText(at: number - 1)
    switch await generator.editSlide(instruction: instruction, kind: kind, slide: slideText, outline: outline,
                                     index: number - 1, baseDir: deck.baseDir) {
    case .failure(let error):
        return fail(error.message)
    case .success(let outcome):
        deck.editSlide(outcome.slide)
        guard deck.savePath(path) else { return fail(deck.status) }
        if args.flag("json") {
            printJSON(["presentation": path, "slide": number, "summary": outcome.summary, "warnings": outcome.warnings])
        } else {
            printLine("\(outcome.summary) (slide \(number)) in \(path)")
            for warning in outcome.warnings { printErr("warning: \(warning)") }
        }
        return 0
    }
}

func cmdHelp(_ args: Args) -> Int32 {
    printLine("Usage: hype <command> [options]\n\n" + usageSummary)
    return 0
}
