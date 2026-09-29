import Foundation

func printLine(_ text: String, to stream: FileHandle = .standardOutput) {
    stream.write(Data((text + "\n").utf8))
}
func printErr(_ text: String) { printLine(text, to: .standardError) }

/// Prints `text` to stdout and returns 0; a symmetrical partner to `fail`, so
/// call sites can `return succeed(...)`.
func succeed(_ text: String) -> Int32 { printLine(text); return 0 }
/// Prints `message` to stderr and returns 1, matching the Qt CLI's `fail()`.
func fail(_ message: String) -> Int32 { printErr(message); return 1 }

func printJSON(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
}
