// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Hype",
    // .v14 for the two-parameter onChange(of:) { old, new in } closure form used
    // in ContentView.swift; this machine runs a much newer macOS regardless.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HypeApp", targets: ["HypeApp"]),
        .executable(name: "hype", targets: ["HypeCLI"]),
        .library(name: "HypeCore", targets: ["HypeCore"]),
    ],
    targets: [
        // The file format, deck model, theming and media parsing: no UI, so it is
        // testable headlessly and shared with both HypeApp and HypeCLI (Phase 4).
        // Resources/*.md are copied verbatim from ../../src/*.md (the Qt app's
        // prompt templates and format guide) so both apps send the same prompts;
        // keep them in sync by hand if either file changes.
        .target(name: "HypeCore", resources: [.copy("Resources")]),
        // SwiftUI-based slide rendering and PDF/HTML/PNG export — a separate
        // library so HypeCLI can render and export without linking HypeApp's
        // windows/menus/sheets.
        .target(name: "HypeRender", dependencies: ["HypeCore"]),
        .executableTarget(name: "HypeApp", dependencies: ["HypeCore", "HypeRender"]),
        // Headless commands (new/check/slides/render/export/generate/revise/themes),
        // mirroring the Qt app's cli.cpp. Manual argument parsing, no dependencies,
        // matching the rest of this port's "no build system beyond SwiftPM" spirit.
        .executableTarget(name: "HypeCLI", dependencies: ["HypeCore", "HypeRender"]),
        .testTarget(name: "HypeCoreTests", dependencies: ["HypeCore"]),
        // Runs the real text fitter inside a SwiftUI Canvas, so fit/wrap behavior is
        // measured with real fonts rather than assumed.
        .testTarget(name: "HypeRenderTests", dependencies: ["HypeRender", "HypeCore"]),
        // The editor glue (NSTextView wiring for the assist buttons and Return key) needs
        // a real text view, so it is tested against the app module itself.
        .testTarget(name: "HypeAppTests", dependencies: ["HypeApp", "HypeCore"]),
    ]
)
