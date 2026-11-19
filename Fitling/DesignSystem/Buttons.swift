import SwiftUI

/// The main action: an ink capsule with the label in the card colour. Disabled turns to the track
/// colour with a readable soft-ink label, so the next step stays visible.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? Color.card : Color.inkSoft)
            .padding(.horizontal, Spacing.l)
            .frame(maxWidth: .infinity, minHeight: ButtonMetrics.height)
            .background(isEnabled ? Color.ink : Color.track, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A secondary action: a card-coloured capsule lifted off the ground by a soft shadow.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? Color.ink : Color.inkSoft)
            .padding(.horizontal, Spacing.l)
            .frame(maxWidth: .infinity, minHeight: ButtonMetrics.height)
            .background {
                Capsule()
                    .fill(Color.card)
                    .shadow(color: Color.cardShadow, radius: 6, y: 2)
            }
            // In dark mode the shadow disappears and the card colour sits close to the ground;
            // the edge keeps the capsule recognisable as a button.
            .overlay(Capsule().strokeBorder(Color.track, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The primary action of a form, with a spinner while the request runs. The form disables it
/// while working, so the spinner sits on the track colour.
struct SubmitButton: View {
    let title: LocalizedStringKey
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Text(title)
                if isWorking {
                    ProgressView()
                        .tint(Color.inkSoft)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

extension View {
    /// Explanations under a list section. The system grey reaches only about 2.8:1 on the pastel
    /// ground; soft ink stays above 4.5:1 in light and dark.
    func footerStyle() -> some View {
        foregroundStyle(Color.inkSoft)
    }

    /// Lists and forms on the pastel ground instead of the system grouped background.
    func groundBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.ground)
    }

    /// A full-width capsule button as the only content of a form row.
    func buttonRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}
