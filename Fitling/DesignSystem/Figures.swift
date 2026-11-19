import SwiftUI

/// The four species from PRODUCT.md. In phase 1 they make up the catalog on the welcome screen;
/// choosing and naming one is part of phase 3.
enum Species: CaseIterable, Identifiable {
    case sprout, ember, pip, pebble

    var id: Self { self }

    /// The saturated colour of the species: its body, its name plate and later its own ribbon.
    var ribbon: Color {
        switch self {
        case .sprout: Color.sprout
        case .ember: Color.ember
        case .pip: Color.pip
        case .pebble: Color.pebble
        }
    }

    /// The pastel ground of the species' catalog card.
    var tint: Color {
        switch self {
        case .sprout: Color.sproutTint
        case .ember: Color.emberTint
        case .pip: Color.pipTint
        case .pebble: Color.pebbleTint
        }
    }

    var nameKey: LocalizedStringKey {
        switch self {
        case .sprout: "creature.sprout.name"
        case .ember: "creature.ember.name"
        case .pip: "creature.pip.name"
        case .pebble: "creature.pebble.name"
        }
    }

    /// One line of character for the catalog card.
    var noteKey: LocalizedStringKey {
        switch self {
        case .sprout: "creature.sprout.note"
        case .ember: "creature.ember.note"
        case .pip: "creature.pip.note"
        case .pebble: "creature.pebble.note"
        }
    }
}

/// One flat part of a figure, drawn in a 100 × 100 space. The parts marked `keyline` together form
/// the silhouette that gets the white sticker edge.
struct FigurePart {
    enum Paint: Equatable {
        case fill
        case stroke(CGFloat)
        case fillAndStroke(CGFloat)
    }

    enum Role: Equatable {
        case silhouette
        case body
        case shading
        case detail
    }

    /// Every silhouette ends here, so the figures in the catalog stand on one line.
    static let baseline: CGFloat = 92
    static let keylineWidth: CGFloat = 7
    static let groundShadow = CGRect(x: 20, y: 89.3, width: 60, height: 6.4)

    let path: Path
    let color: Color
    var paint: Paint = .fill
    var keyline = false
    var role: Role = .detail
}

/// A figure as a flat sticker: a white keyline round the silhouette, one flat colour per part.
struct FigureView: View {
    let species: Species

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: side / 100, y: side / 100)
            let parts = species.parts
            for part in parts where part.keyline {
                context.stroke(
                    part.path,
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: FigurePart.keylineWidth, lineCap: .round, lineJoin: .round)
                )
            }
            for part in parts {
                switch part.paint {
                case .fill:
                    context.fill(part.path, with: .color(part.color))
                case let .stroke(width):
                    context.stroke(part.path, with: .color(part.color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                case let .fillAndStroke(width):
                    context.fill(part.path, with: .color(part.color))
                    context.stroke(part.path, with: .color(part.color), style: StrokeStyle(lineWidth: width, lineJoin: .round))
                }
            }
        }
        .shadow(color: Color.cardShadow, radius: 3, y: 2)
        .accessibilityHidden(true)
    }
}

/// Artwork colours that are not ribbons. A figure looks the same in light and dark mode, like a
/// printed sticker.
private enum Artwork {
    static let sproutLeaf = Color(artwork: 0x3E9E57)
    static let sproutBlush = Color(artwork: 0xFF9AA2)
    static let emberGlow = Color(artwork: 0xFFC93C)
    static let emberBlush = Color(artwork: 0xE8503A)
    static let pipWing = Color(artwork: 0xF0B000)
    static let pipBeak = Color(artwork: 0xFF8A3D)
    static let pipBlush = Color(artwork: 0xFF9E80)
    static let pebbleSpeckle = Color(artwork: 0x73839D)
    static let pebbleBlush = Color(artwork: 0xFFA8B0)
}

private extension Color {
    /// An sRGB colour from a 0xRRGGBB value.
    init(artwork hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

extension Species {
    /// The figure's parts, back to front.
    var parts: [FigurePart] {
        switch self {
        case .sprout: [
            FigurePart(path: Path { p in
                p.move(to: pt(48, 36))
                p.addLine(to: pt(48, 22))
                p.addCurve(to: pt(52, 22), control1: pt(48, 20.5), control2: pt(52, 20.5))
                p.addLine(to: pt(52, 36))
                p.closeSubpath()
            }, color: Artwork.sproutLeaf, keyline: true),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 24))
                p.addCurve(to: pt(21, 15), control1: pt(42, 12), control2: pt(28, 10))
                p.addCurve(to: pt(50, 24), control1: pt(26, 26), control2: pt(40, 30))
                p.closeSubpath()
            }, color: Artwork.sproutLeaf, keyline: true),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 22))
                p.addCurve(to: pt(80, 9), control1: pt(56, 8), control2: pt(72, 4))
                p.addCurve(to: pt(50, 22), control1: pt(76, 22), control2: pt(62, 28))
                p.closeSubpath()
            }, color: Artwork.sproutLeaf, keyline: true),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 34))
                p.addCurve(to: pt(84, 68), control1: pt(70, 34), control2: pt(84, 48))
                p.addCurve(to: pt(50, 92), control1: pt(84, 84), control2: pt(70, 92))
                p.addCurve(to: pt(16, 68), control1: pt(30, 92), control2: pt(16, 84))
                p.addCurve(to: pt(50, 34), control1: pt(16, 48), control2: pt(30, 34))
                p.closeSubpath()
            }, color: Color.sprout, keyline: true),
            FigurePart(path: Path(ellipseIn: CGRect(x: 26, y: 69.8, width: 10, height: 6.4)), color: Artwork.sproutBlush),
            FigurePart(path: Path(ellipseIn: CGRect(x: 64, y: 69.8, width: 10, height: 6.4)), color: Artwork.sproutBlush),
            FigurePart(path: Path(ellipseIn: CGRect(x: 35.4, y: 57.4, width: 9.2, height: 11.2)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 55.4, y: 57.4, width: 9.2, height: 11.2)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 39.9, y: 59.3, width: 3.4, height: 3.4)), color: Color.white),
            FigurePart(path: Path(ellipseIn: CGRect(x: 59.9, y: 59.3, width: 3.4, height: 3.4)), color: Color.white),
            FigurePart(path: Path { p in
                p.move(to: pt(45, 74))
                p.addQuadCurve(to: pt(55, 74), control: pt(50, 78.5))
            }, color: Color.onRibbon, paint: .stroke(2.6)),
        ]
        case .ember: [
            FigurePart(path: Path { p in
                p.move(to: pt(50, 8))
                p.addCurve(to: pt(80, 50), control1: pt(57, 22), control2: pt(74, 32))
                p.addCurve(to: pt(50, 92), control1: pt(87, 70), control2: pt(74, 92))
                p.addCurve(to: pt(18, 57), control1: pt(27, 92), control2: pt(13, 76))
                p.addCurve(to: pt(33, 31), control1: pt(21, 46), control2: pt(29, 41))
                p.addCurve(to: pt(45, 45), control1: pt(38, 40), control2: pt(41, 44))
                p.addCurve(to: pt(50, 8), control1: pt(42, 31), control2: pt(44, 19))
                p.closeSubpath()
            }, color: Color.ember, keyline: true),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 70))
                p.addCurve(to: pt(62, 84), control1: pt(57, 74), control2: pt(62, 78.5))
                p.addCurve(to: pt(50, 90), control1: pt(62, 88.5), control2: pt(57, 90))
                p.addCurve(to: pt(38, 84), control1: pt(43, 90), control2: pt(38, 88.5))
                p.addCurve(to: pt(50, 70), control1: pt(38, 78.5), control2: pt(43, 74))
                p.closeSubpath()
            }, color: Artwork.emberGlow),
            FigurePart(path: Path(ellipseIn: CGRect(x: 26, y: 62.8, width: 10, height: 6.4)), color: Artwork.emberBlush),
            FigurePart(path: Path(ellipseIn: CGRect(x: 64, y: 62.8, width: 10, height: 6.4)), color: Artwork.emberBlush),
            FigurePart(path: Path(ellipseIn: CGRect(x: 35.4, y: 52.4, width: 9.2, height: 11.2)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 55.4, y: 52.4, width: 9.2, height: 11.2)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 39.9, y: 54.3, width: 3.4, height: 3.4)), color: Color.white),
            FigurePart(path: Path(ellipseIn: CGRect(x: 59.9, y: 54.3, width: 3.4, height: 3.4)), color: Color.white),
            FigurePart(path: Path { p in
                p.move(to: pt(45.5, 67))
                p.addQuadCurve(to: pt(54.5, 67), control: pt(50, 71))
            }, color: Color.onRibbon, paint: .stroke(2.6)),
        ]
        case .pip: [
            FigurePart(path: Path { p in
                p.move(to: pt(47, 29))
                p.addCurve(to: pt(52, 13), control1: pt(44, 19), control2: pt(47, 12))
                p.addCurve(to: pt(52, 28), control1: pt(50, 17), control2: pt(50, 22))
                p.closeSubpath()
            }, color: Color.pip, keyline: true),
            FigurePart(path: Path { p in
                p.move(to: pt(52, 28))
                p.addCurve(to: pt(65, 17), control1: pt(54, 19), control2: pt(60, 14))
                p.addCurve(to: pt(55, 29), control1: pt(60, 20), control2: pt(57, 24))
                p.closeSubpath()
            }, color: Color.pip, keyline: true),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 26))
                p.addCurve(to: pt(86, 62), control1: pt(72, 26), control2: pt(86, 42))
                p.addCurve(to: pt(50, 92), control1: pt(86, 80), control2: pt(70, 92))
                p.addCurve(to: pt(14, 62), control1: pt(30, 92), control2: pt(14, 80))
                p.addCurve(to: pt(50, 26), control1: pt(14, 42), control2: pt(28, 26))
                p.closeSubpath()
            }, color: Color.pip, keyline: true),
            FigurePart(path: Path { p in
                p.move(to: pt(71, 66))
                p.addCurve(to: pt(83, 74), control1: pt(79, 61), control2: pt(86, 66))
                p.addCurve(to: pt(71, 66), control1: pt(79, 79), control2: pt(72, 76))
                p.closeSubpath()
            }, color: Artwork.pipWing),
            FigurePart(path: Path { p in
                p.move(to: pt(17, 66))
                p.addCurve(to: pt(29, 70), control1: pt(21, 61), control2: pt(28, 64))
                p.addCurve(to: pt(17, 66), control1: pt(26, 76), control2: pt(19, 75))
                p.closeSubpath()
            }, color: Artwork.pipWing),
            FigurePart(path: Path(ellipseIn: CGRect(x: 24, y: 62.8, width: 10, height: 6.4)), color: Artwork.pipBlush),
            FigurePart(path: Path(ellipseIn: CGRect(x: 66, y: 62.8, width: 10, height: 6.4)), color: Artwork.pipBlush),
            FigurePart(path: Path(ellipseIn: CGRect(x: 34.4, y: 49.4, width: 9.2, height: 11.2)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 56.4, y: 49.4, width: 9.2, height: 11.2)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 38.9, y: 51.3, width: 3.4, height: 3.4)), color: Color.white),
            FigurePart(path: Path(ellipseIn: CGRect(x: 60.9, y: 51.3, width: 3.4, height: 3.4)), color: Color.white),
            FigurePart(path: Path { p in
                p.move(to: pt(44.5, 63))
                p.addLine(to: pt(55.5, 63))
                p.addLine(to: pt(50, 70))
                p.closeSubpath()
            }, color: Artwork.pipBeak, paint: .fillAndStroke(2)),
        ]
        case .pebble: [
            FigurePart(path: Path { p in
                p.move(to: pt(50, 38))
                p.addCurve(to: pt(92, 69), control1: pt(76, 38), control2: pt(92, 51))
                p.addCurve(to: pt(50, 92), control1: pt(92, 84), control2: pt(75, 92))
                p.addCurve(to: pt(8, 69), control1: pt(25, 92), control2: pt(8, 84))
                p.addCurve(to: pt(50, 38), control1: pt(8, 51), control2: pt(24, 38))
                p.closeSubpath()
            }, color: Color.pebble, keyline: true),
            FigurePart(path: Path(ellipseIn: CGRect(x: 22.4, y: 52.4, width: 5.2, height: 5.2)), color: Artwork.pebbleSpeckle),
            FigurePart(path: Path(ellipseIn: CGRect(x: 71, y: 46, width: 4, height: 4)), color: Artwork.pebbleSpeckle),
            FigurePart(path: Path(ellipseIn: CGRect(x: 78, y: 71, width: 6, height: 6)), color: Artwork.pebbleSpeckle),
            FigurePart(path: Path(ellipseIn: CGRect(x: 16, y: 75, width: 4, height: 4)), color: Artwork.pebbleSpeckle),
            FigurePart(path: Path(ellipseIn: CGRect(x: 27, y: 69.8, width: 10, height: 6.4)), color: Artwork.pebbleBlush),
            FigurePart(path: Path(ellipseIn: CGRect(x: 63, y: 69.8, width: 10, height: 6.4)), color: Artwork.pebbleBlush),
            FigurePart(path: Path { p in
                p.move(to: pt(34.5, 65))
                p.addQuadCurve(to: pt(45.5, 65), control: pt(40, 70))
            }, color: Color.onRibbon, paint: .stroke(2.8)),
            FigurePart(path: Path { p in
                p.move(to: pt(54.5, 65))
                p.addQuadCurve(to: pt(65.5, 65), control: pt(60, 70))
            }, color: Color.onRibbon, paint: .stroke(2.8)),
            FigurePart(path: Path { p in
                p.move(to: pt(47, 76))
                p.addQuadCurve(to: pt(53, 76), control: pt(50, 78.5))
            }, color: Color.onRibbon, paint: .stroke(2.4)),
        ]
        }
    }
}
