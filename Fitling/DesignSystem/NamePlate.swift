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

    init(_ title: LocalizedStringResource, fill: Color, foreground: Color = Color.onRibbon, edge: Color? = Color.white) {
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

/// One partner in the welcome catalog: the figure on its pastel ground. VoiceOver reads its name
/// and its line of character.
struct FigureTile: View {
    let species: Species

    var body: some View {
        FigureView(species: species)
            .aspectRatio(1, contentMode: .fit)
            .padding(Spacing.xs)
            .background(species.tint, in: RoundedRectangle(cornerRadius: Radius.card * 0.6, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(species.name))
            .accessibilityHint(Text(species.note))
    }
}
