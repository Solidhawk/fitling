import SwiftUI

/// The main action: an ink field with a paper label and square corners. Disabled keeps the 2 pt ink
/// outline so the next step stays visible, with a dimmed but readable label.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Spacing.l)
            .foregroundStyle(isEnabled ? Color.paper : Color.ink.opacity(0.55))
            .background(isEnabled ? Color.ink : Color.paper)
            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: Rule.width))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// A secondary action: paper with an ink outline and ink label.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Spacing.l)
            .foregroundStyle(isEnabled ? Color.ink : Color.ink.opacity(0.55))
            .background(configuration.isPressed ? Color.ink.opacity(0.08) : Color.paper)
            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: Rule.width))
    }
}

extension View {
    /// Lists and forms on the paper ground instead of the grey grouped background.
    func paperGround() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.paper)
    }

    /// A bar pinned to the bottom edge: paper with one ink rule on top.
    func ruledBar() -> some View {
        background(Color.paper)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.ink).frame(height: Rule.width)
            }
    }
}
