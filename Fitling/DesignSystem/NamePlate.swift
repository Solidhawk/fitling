import SwiftUI

/// A rounded name plate: heavy lettering on a ribbon colour, edged in white like a sticker.
struct NamePlate: View {
    let title: LocalizedStringKey
    let fill: Color
    let foreground: Color

    init(_ title: LocalizedStringKey, fill: Color, foreground: Color = Color.onRibbon) {
        self.title = title
        self.fill = fill
        self.foreground = foreground
    }

    var body: some View {
        Text(title)
            .font(.headline.weight(.heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white, lineWidth: 2))
    }
}

/// A catalog card: the figure on its pastel ground, a name plate and one line of character.
struct FigureCard: View {
    let species: Species

    var body: some View {
        VStack(spacing: Spacing.s) {
            FigureView(species: species)
                .frame(width: 96, height: 96)
            NamePlate(species.nameKey, fill: species.ribbon)
            Text(species.noteKey)
                .font(.footnote)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        // Top-aligned, so the partners in one row stand on one line whatever the length of their note.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(species.tint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
