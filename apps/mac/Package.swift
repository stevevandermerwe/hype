// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Hype",
    // .v14 for the two-parameter onChange(of:) { old, new in } closure form used
    // in ContentView.swift; this machine runs a much newer macOS regardless.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HypeApp", targets: ["HypeApp"]),
        .library(name: "HypeCore", targets: ["HypeCore"]),
    ],
    targets: [
        // The file format, deck model, theming and media parsing: no UI, so it is
        // testable headlessly and shared later with the CLI target (Phase 4).
        // Resources/*.md are copied verbatim from ../../src/*.md (the Qt app's
        // prompt templates and format guide) so both apps send the same prompts;
        // keep them in sync by hand if either file changes.
        .target(name: "HypeCore", resources: [.copy("Resources")]),
        .executableTarget(name: "HypeApp", dependencies: ["HypeCore"]),
        .testTarget(name: "HypeCoreTests", dependencies: ["HypeCore"]),
    ]
)
