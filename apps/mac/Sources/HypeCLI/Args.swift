import Foundation

/// A small hand-rolled argument parser: positionals plus `--flag value` /
/// `--flag` (boolean) pairs. No external dependency, matching this port's
/// "no build system beyond SwiftPM" spirit (and the Qt CLI's own
/// `QCommandLineParser` is likewise driven by a fixed, hand-declared option list).
struct Args {
    private(set) var positionals: [String] = []
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    /// `booleanFlags` names options that take no value (e.g. `--json`); any
    /// other `--name` consumes the next argument as its value.
    init(_ arguments: [String], booleanFlags: Set<String> = []) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") || (argument.hasPrefix("-") && argument.count > 1) {
                let name = String(argument.drop(while: { $0 == "-" }))
                if booleanFlags.contains(name) {
                    flags.insert(name)
                } else if index + 1 < arguments.count {
                    values[name] = arguments[index + 1]
                    index += 1
                } else {
                    flags.insert(name) // A value-taking flag with nothing after it; treated as present.
                }
            } else {
                positionals.append(argument)
            }
            index += 1
        }
    }

    func value(_ name: String) -> String? { values[name] }
    func flag(_ name: String) -> Bool { flags.contains(name) }
    func positional(_ index: Int) -> String? { positionals.indices.contains(index) ? positionals[index] : nil }
}
