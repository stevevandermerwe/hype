import Foundation

/// Limits and steps for a deck's `text_scale` (see `DeckModel.textScale`).
/// Text is still fitted to the slide, so a scale above 1 raises the size text
/// may grow to, while one below 1 shrinks it outright.
public enum TextScale {
    public static let minimum = 0.5
    public static let maximum = 2.0
    public static let step = 0.1

    public static func clamped(_ value: Double) -> Double { min(maximum, max(minimum, value)) }
    public static func bigger(_ value: Double) -> Double { clamped(((value + step) * 100).rounded() / 100) }
    public static func smaller(_ value: Double) -> Double { clamped(((value - step) * 100).rounded() / 100) }
}
