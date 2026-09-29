import SwiftUI

/// Small shared pieces of the app's look: a rounded "card" surface, a text
/// area with a placeholder, and a section header. Kept here so the start
/// page, editor, and AI windows stay visually consistent.

struct CardBackground: ViewModifier {
    var isHighlighted = false
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHighlighted ? AnyShapeStyle(.tint.opacity(0.10)) : AnyShapeStyle(.background.secondary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isHighlighted ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.separator), lineWidth: 1)
            )
    }
}

extension View {
    func card(highlighted: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        modifier(CardBackground(isHighlighted: highlighted, cornerRadius: cornerRadius))
    }
}

/// A multi-line text box with a grey placeholder, used by both AI windows.
struct PromptEditor: View {
    @Binding var text: String
    var placeholder: String
    var isDisabled = false

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(10)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15).padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .card(cornerRadius: 8)
            .disabled(isDisabled)
    }
}

/// The icon-plus-title header at the top of each AI window.
struct WindowHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A status line shown while a request is running, or its error afterwards.
struct RequestStatus: View {
    let isBusy: Bool
    let status: String
    let error: String

    var body: some View {
        if isBusy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
        } else if !error.isEmpty {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
