import XCTest
import SwiftUI
@testable import HypeRender

/// How slide text is fitted: sized as large as it can be while every line stays
/// whole and nothing overflows the text area; lines wrap only when that would
/// make the text smaller than a readable size.
@MainActor
final class TextFitTests: XCTestCase {
    private let area = CGRect(x: 130, y: 90, width: 1660, height: 900)

    /// Runs the fitter for `text` inside a real Canvas (it needs a live
    /// GraphicsContext to measure with) and returns what it decided.
    private func fit(_ text: String, scale: CGFloat = 1) -> TextFit {
        final class Box { var value: TextFit? }
        let box = Box()
        let area = self.area
        let view = Canvas { context, _ in
            box.value = drawSlideText(&context, text: text, area: area, foreground: .white, textScale: scale)
        }
        .frame(width: 1920, height: 1080)
        let renderer = ImageRenderer(content: view)
        _ = renderer.cgImage
        return box.value ?? TextFit(bodySize: 0, headlineSize: 0, wrappedLines: 0, height: 0)
    }

    func testAHeadlineWithBulletsKeepsEveryLineOnOneLine() {
        // The slide from a real deck: a two-word-per-line headline plus bullets.
        let result = fit("# Option D: Journey Instrumentation\n\n**Effort:** Weeks (before Nov 2026)\n\n- Purpose-built MFA funnel tracking\n- Grafana or AppDynamics dashboards\n- **Gap:** UI-only clicks not fully covered")
        XCTAssertEqual(result.wrappedLines, 0, "nothing should wrap when a smaller size avoids it")
        XCTAssertLessThanOrEqual(result.height, area.height)
        XCTAssertGreaterThanOrEqual(result.bodySize, 36, "body text must stay readable")
    }

    func testALongHeadlineShrinksInsteadOfWrappingAndDoesNotDragTheBodyDown() {
        let long = fit("# Choosing a Markup Language for Presentations\n\n- One\n- Two")
        let short = fit("# Markup\n\n- One\n- Two")
        XCTAssertEqual(long.wrappedLines, 0)
        XCTAssertLessThan(long.headlineSize, short.headlineSize, "a longer headline gets a smaller size")
        XCTAssertGreaterThanOrEqual(long.bodySize, short.bodySize * 0.8, "the body shouldn't collapse to make room for the headline")
        XCTAssertGreaterThan(long.headlineSize, long.bodySize, "the headline stays larger than the body")
    }

    func testTextThatCannotFitWholeWrapsAtAReadableSizeAndStaysInsideTheArea() {
        let paragraph = String(repeating: "This is a lot of words for one slide and it just keeps going. ", count: 6)
        let result = fit("# Too much\n\n\(paragraph)")
        XCTAssertGreaterThan(result.wrappedLines, 0)
        XCTAssertLessThanOrEqual(result.height, area.height + 1, "wrapped text must not overflow the slide")
        XCTAssertGreaterThanOrEqual(result.bodySize, 20)
    }

    func testLongLinesWrapToAComfortableSizeRatherThanStayingOneTinyLine() {
        // Kept whole, these lines would force text down to about the minimum size
        // and leave most of the slide empty; wrapping them reads far better.
        let result = fit("# Recommendation: adopt the phased rollout across every business unit before year end\n\n- Phase one covers the pilot teams and the shared platform services\n- Phase two extends to regional teams once the pilot metrics are reviewed and signed off\n- Phase three completes the rollout and retires the legacy reporting path")
        XCTAssertGreaterThan(result.wrappedLines, 0)
        XCTAssertGreaterThanOrEqual(result.bodySize, comfortableBodySize)
        XCTAssertLessThanOrEqual(result.height, area.height + 1)
    }

    func testAShortSlideFillsTheSlideRatherThanStayingSmall() {
        let result = fit("# Hello")
        XCTAssertGreaterThan(result.headlineSize, 150)
    }

    // MARK: Tables, code, and the "too much text" flag

    func testASmallTableFitsWholeAndReadable() {
        let result = fit("# Plans\n\n| Plan | Price |\n| --- | ---: |\n| Starter | $9 |\n| Team | $29 |")
        XCTAssertEqual(result.wrappedLines, 0)
        XCTAssertLessThanOrEqual(result.height, area.height)
        XCTAssertGreaterThanOrEqual(result.bodySize, comfortableBodySize)
        XCTAssertFalse(result.isCramped)
    }

    func testAWideTableWrapsItsLongCellsButStaysInsideTheSlide() {
        let notes = "Strong enterprise demand across the board this quarter"
        let table = "| Region | Q1 | Q2 | Notes |\n| --- | --- | --- | --- |\n| North America | 1 | 2 | \(notes) |\n| Europe | 3 | 4 | \(notes) |"
        let result = fit("# Big table\n\n" + table)
        XCTAssertGreaterThan(result.wrappedLines, 0)
        XCTAssertLessThanOrEqual(result.height, area.height + 1)
        XCTAssertFalse(result.isCramped, "wrapping the prose column keeps the text readable")
    }

    func testCodeBlocksFitAndAreNotCrampedUnlessTheyAreHuge() {
        let short = fit("# Demo\n\n```swift\nlet x = 1\nprint(x)\n```")
        XCTAssertEqual(short.wrappedLines, 0)
        XCTAssertLessThanOrEqual(short.height, area.height)
        XCTAssertFalse(short.isCramped)

        let long = fit("```python\n" + (1...45).map { "value_\($0) = compute(\($0))" }.joined(separator: "\n") + "\n```")
        XCTAssertTrue(long.isCramped, "45 lines of code can't be read from a room")
        XCTAssertLessThanOrEqual(long.height, area.height + 1)
    }

    func testTooMuchTextIsFlaggedAsCrampedAndOrdinarySlidesAreNot() {
        XCTAssertFalse(fit("# Title\n\n- One\n- Two\n- Three").isCramped)
        let bullets = (1...30).map { "- Point number \($0) with a few extra words" }.joined(separator: "\n")
        let result = fit("# Way too much\n\n" + bullets)
        XCTAssertTrue(result.isCramped)
        XCTAssertLessThan(result.fittedBodySize, readableBodySize)
    }

    func testTextScaleDoesNotChangeWhetherASlideIsCramped() {
        let bullets = (1...30).map { "- Point number \($0) with a few extra words" }.joined(separator: "\n")
        let normal = fit("# T\n\n" + bullets)
        let smaller = fit("# T\n\n" + bullets, scale: 0.5)
        XCTAssertEqual(smaller.fittedBodySize, normal.fittedBodySize, accuracy: 0.01)
        XCTAssertEqual(smaller.isCramped, normal.isCramped)
    }

    func testTextScaleBelowOneShrinksAndAboveOneNeverOverflows() {
        let base = fit("# Title\n\n- One\n- Two\n- Three")
        XCTAssertLessThan(fit("# Title\n\n- One\n- Two\n- Three", scale: 0.6).bodySize, base.bodySize)
        let big = fit("# Title\n\n- One\n- Two\n- Three\n- Four\n- Five\n- Six", scale: 2)
        XCTAssertLessThanOrEqual(big.height, area.height + 1)
        XCTAssertEqual(big.wrappedLines, 0)
    }
}
