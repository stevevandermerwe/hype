import XCTest
import SwiftUI
import HypeCore
@testable import HypeRender

/// Custom slide fonts: which are installed, how a deck's `font:` resolves, and
/// that the fitter measures with the chosen font.
@MainActor
final class FontSupportTests: XCTestCase {
    private let area = CGRect(x: 130, y: 90, width: 1660, height: 900)

    private func fit(_ text: String, font: String) -> TextFit {
        final class Box { var value: TextFit? }
        let box = Box()
        let area = self.area
        let view = Canvas { context, _ in
            box.value = drawSlideText(&context, text: text, area: area, foreground: .white, fontName: font)
        }
        .frame(width: 1920, height: 1080)
        _ = ImageRenderer(content: view).cgImage
        return box.value ?? TextFit(bodySize: 0, headlineSize: 0, wrappedLines: 0, height: 0)
    }

    func testInstalledFamiliesAreListedAlphabeticallyWithoutDuplicates() {
        let families = availableFontFamilies()
        XCTAssertGreaterThan(families.count, 10)
        XCTAssertEqual(families, families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        XCTAssertEqual(Set(families).count, families.count)
        XCTAssertTrue(families.contains("Helvetica Neue"))
    }

    func testAFontResolvesByFamilyOrPostScriptNameAndUnknownOnesDoNot() {
        XCTAssertNotNil(resolvedFontName("Helvetica Neue"))
        XCTAssertNotNil(resolvedFontName("Menlo"))
        XCTAssertNotNil(resolvedFontName("Menlo-Regular"))
        XCTAssertNotNil(resolvedFontName("  Menlo  "), "surrounding spaces are ignored")
        XCTAssertNil(resolvedFontName("Definitely Not A Real Font"))
        XCTAssertNil(resolvedFontName(""))
        XCTAssertTrue(isFontAvailable("Menlo"))
        XCTAssertFalse(isFontAvailable("Definitely Not A Real Font"))
    }

    func testTheFitterMeasuresWithTheChosenFont() {
        let text = "# Build a custom Mac slides" // short enough to stay on one line in both fonts
        let system = fit(text, font: "")
        let wide = fit(text, font: "Menlo") // monospaced, so much wider
        XCTAssertLessThan(wide.headlineSize, system.headlineSize, "a wider font must fit at a smaller size")
        XCTAssertEqual(fit(text, font: "Definitely Not A Real Font").headlineSize, system.headlineSize, accuracy: 0.01,
                       "a missing font falls back to the system font")
    }

    func testMeasuringAndDrawingAgreeOnTheFont() throws {
        let source = "# Slides\n\n- This bullet has about forty two chars.\n- Short"
        let system = try XCTUnwrap(measureSlideText(source: source, baseDir: ""))
        let menlo = try XCTUnwrap(measureSlideText(source: source, baseDir: "", fontName: "Menlo"))
        XCTAssertNotEqual(system.fittedBodySize, menlo.fittedBodySize)
    }
}
