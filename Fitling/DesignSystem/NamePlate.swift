import SwiftUI
import FitlingCore

/// A rounded name plate: heavy lettering on a ribbon colour, edged in white like a sticker.
struct NamePlate: View {
    let title: Text
    let fill: Color
    let foreground: Color
    /// The white sticker rim of the catalog. Nil inside a card, where a white rim is invisible in
    /// light mode and glaring in dark mode.
    let edge: Color?

    init(_ title: LocalizedStringKey, fill: Color, foreground: Color = Color.onRibbon, edge: Color? = Color.white) {
        self.init(text: Text(title), fill: fill, foreground: foreground, edge: edge)
    }

    /// A name the user chose, such as the partner's, shown as typed.
    init(verbatim name: String, fill: Color, foreground: Color = Color.onRibbon, edge: Color? = Color.white) {
        self.init(text: Text(verbatim: name), fill: fill, foreground: foreground, edge: edge)
    }

    private init(text: Text, fill: Color, foreground: Color, edge: Color?) {
        self.title = text
        self.fill = fill
        self.foreground = foreground
        self.edge = edge
    }

    var body: some View {
        title
            .font(.headline.weight(.heavy))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .background(fill, in: Capsule())
            .overlay {
                if let edge {
                    Capsule().strokeBorder(edge, lineWidth: 2)
                }
            }
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
