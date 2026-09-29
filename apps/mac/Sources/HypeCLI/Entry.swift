import Foundation
import HypeCore

/// `hype`: headless commands sharing `HypeCore`/`HypeRender` with the app.
/// A separate executable rather than a mode of `HypeApp`, matching the Qt
/// app's `hype` binary, which is both the editor and its own CLI.
@main
@MainActor
struct HypeCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printLine("Usage: hype <command> [options]\n\n" + usageSummary)
            exit(0)
        }
        let rest = Array(arguments.dropFirst())
        let booleanFlags: Set<String> = ["json", "save", "print-template", "mind-map", "diagram", "image"]
        let args = Args(rest, booleanFlags: booleanFlags)

        let code: Int32
        switch command {
        case "new": code = cmdNew(args)
        case "check": code = cmdCheck(args)
        case "slides": code = cmdSlides(args)
        case "themes": code = cmdThemes(args)
        case "render": code = cmdRender(args)
        case "export": code = cmdExport(args)
        case "generate": code = await cmdGenerate(args)
        case "revise": code = await cmdRevise(args)
        case "help", "--help", "-h": code = cmdHelp(args)
        default:
            printErr("Unknown command: \(command)\n")
            code = cmdHelp(args)
        }
        exit(code)
    }
}
