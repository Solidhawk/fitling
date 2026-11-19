import SwiftUI

/// The four species of partner from PRODUCT.md. In phase 1 they make up the catalog on the welcome
/// screen; choosing and naming one is part of phase 3.
enum Species: CaseIterable, Identifiable {
    case sprout, ember, pip, pebble

    var id: Self { self }

    /// The main colour of the species: its body, its name plate and later its own ribbon.
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

/// One flat part of a partner, drawn in a 100 × 100 space.
struct FigurePart {
    enum Paint: Equatable {
        case fill
        case stroke(CGFloat)
        case fillAndStroke(CGFloat)
    }

    enum Role: Equatable {
        /// Feet, arms, leaves, crest: the outline next to the body.
        case silhouette
        /// The one body shape. Shading is clipped to it.
        case body
        /// Light on top or shadow underneath: flat tones instead of a gradient, only inside the body.
        case shading
        /// Eyes, mouth, beak, speckles.
        case detail
    }

    /// Every partner's feet end here, so the figures in the catalog stand on one line.
    static let baseline: CGFloat = 92
    /// The soft shadow the partner stands on.
    static let groundShadow = CGRect(x: 20, y: 89.3, width: 60, height: 6.4)

    let path: Path
    let color: Color
    var paint: Paint = .fill
    var role: Role = .detail

    func draw(in context: inout GraphicsContext) {
        switch paint {
        case .fill:
            context.fill(path, with: .color(color))
        case let .stroke(width):
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        case let .fillAndStroke(width):
            context.fill(path, with: .color(color))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineJoin: .round))
        }
    }
}

/// A partner: a chunky body in flat tones, light from the upper left, standing on its own shadow.
struct FigureView: View {
    let species: Species

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: side / 100, y: side / 100)
            context.fill(Path(ellipseIn: FigurePart.groundShadow), with: .color(Color.cardShadow))
            let parts = species.parts
            let bodyShape = parts.first { $0.role == .body }?.path
            for part in parts {
                if part.role == .shading, let bodyShape {
                    context.drawLayer { layer in
                        layer.clip(to: bodyShape)
                        part.draw(in: &layer)
                    }
                } else {
                    part.draw(in: &context)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Artwork colours next to the species' main colour. A partner looks the same in light and dark
/// mode.
private enum Artwork {
    static let sproutShadow = Color(artwork: 0x57AE45)
    static let sproutGloss = Color(artwork: 0xC2F08A)
    static let sproutLeaf = Color(artwork: 0x6CC24A)
    static let sproutLeafDark = Color(artwork: 0x3E8E36)
    static let emberShadow = Color(artwork: 0xE8603A)
    static let emberGloss = Color(artwork: 0xFFC56B)
    static let emberFlame = Color(artwork: 0xFF6A2B)
    static let emberFlameCore = Color(artwork: 0xFFD54F)
    static let pipShadow = Color(artwork: 0xF0A500)
    static let pipGloss = Color(artwork: 0xFFEC9A)
    static let pipBeak = Color(artwork: 0xFF8A3D)
    static let pebbleShadow = Color(artwork: 0x74839E)
    static let pebbleGloss = Color(artwork: 0xC5CEDF)
    static let moss = Color(artwork: 0x6CC24A)
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
    /// The partner's parts, back to front.
    var parts: [FigurePart] {
        switch self {
        case .sprout: [
            FigurePart(path: Path { p in
                p.move(to: pt(49, 31))
                p.addLine(to: pt(49, 22))
                p.addCurve(to: pt(51, 22), control1: pt(49, 20.5), control2: pt(51, 20.5))
                p.addLine(to: pt(51, 31))
                p.closeSubpath()
            }, color: Artwork.sproutLeafDark, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 23))
                p.addCurve(to: pt(27, 18), control1: pt(44, 14), control2: pt(33, 13))
                p.addCurve(to: pt(50, 23), control1: pt(31, 26), control2: pt(42, 28))
                p.closeSubpath()
            }, color: Artwork.sproutLeaf, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 23))
                p.addCurve(to: pt(27, 18), control1: pt(42, 28), control2: pt(31, 26))
                p.addCurve(to: pt(50, 23), control1: pt(36, 22), control2: pt(44, 23))
                p.closeSubpath()
            }, color: Artwork.sproutLeafDark),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 22))
                p.addCurve(to: pt(75, 13), control1: pt(55, 11), control2: pt(68, 8))
                p.addCurve(to: pt(50, 22), control1: pt(71, 23), control2: pt(59, 27))
                p.closeSubpath()
            }, color: Artwork.sproutLeaf, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 22))
                p.addCurve(to: pt(75, 13), control1: pt(59, 27), control2: pt(71, 23))
                p.addCurve(to: pt(50, 22), control1: pt(67, 19), control2: pt(58, 21))
                p.closeSubpath()
            }, color: Artwork.sproutLeafDark),
            FigurePart(path: Path(ellipseIn: CGRect(x: 30.5, y: 85, width: 15, height: 7)), color: Artwork.sproutShadow, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 54.5, y: 85, width: 15, height: 7)), color: Artwork.sproutShadow, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 30))
                p.addCurve(to: pt(82, 61), control1: pt(69, 30), control2: pt(82, 43))
                p.addCurve(to: pt(50, 87), control1: pt(82, 77), control2: pt(72, 87))
                p.addCurve(to: pt(18, 61), control1: pt(28, 87), control2: pt(18, 77))
                p.addCurve(to: pt(50, 30), control1: pt(18, 43), control2: pt(31, 30))
                p.closeSubpath()
            }, color: Color.sprout, role: .body),
            FigurePart(path: Path(ellipseIn: CGRect(x: 12, y: 79, width: 84, height: 38)), color: Artwork.sproutShadow, role: .shading),
            FigurePart(path: Path(ellipseIn: CGRect(x: 26, y: 38.5, width: 18, height: 11)), color: Artwork.sproutGloss, role: .shading),
            FigurePart(path: Path(ellipseIn: CGRect(x: 14.9, y: 60.5, width: 7.2, height: 11)), color: Artwork.sproutShadow, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 77.9, y: 60.5, width: 7.2, height: 11)), color: Artwork.sproutShadow, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 36.2, y: 50.7, width: 6.6, height: 8.6)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 57.2, y: 50.7, width: 6.6, height: 8.6)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 39.4, y: 52.3, width: 2.2, height: 2.2)), color: Color.white),
            FigurePart(path: Path(ellipseIn: CGRect(x: 60.4, y: 52.3, width: 2.2, height: 2.2)), color: Color.white),
            FigurePart(path: Path { p in
                p.move(to: pt(46, 63))
                p.addQuadCurve(to: pt(54, 63), control: pt(50, 66.5))
            }, color: Color.onRibbon, paint: .stroke(2.2)),
        ]
        case .ember: [
            FigurePart(path: Path { p in
                p.move(to: pt(50, 6))
                p.addCurve(to: pt(65, 33), control1: pt(57, 15), control2: pt(66, 21))
                p.addCurve(to: pt(35, 33), control1: pt(65, 38), control2: pt(35, 38))
                p.addCurve(to: pt(42, 14), control1: pt(34, 24), control2: pt(40, 20))
                p.addCurve(to: pt(48, 24), control1: pt(45, 19), control2: pt(46, 22))
                p.addCurve(to: pt(50, 6), control1: pt(46, 17), control2: pt(47, 11))
                p.closeSubpath()
            }, color: Artwork.emberFlame, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 16))
                p.addCurve(to: pt(58, 33), control1: pt(54, 22), control2: pt(59, 26))
                p.addLine(to: pt(42, 33))
                p.addCurve(to: pt(47, 21), control1: pt(42, 28), control2: pt(45, 24))
                p.addCurve(to: pt(50, 26), control1: pt(48, 24), control2: pt(49, 25))
                p.addCurve(to: pt(50, 16), control1: pt(49, 22), control2: pt(49, 19))
                p.closeSubpath()
            }, color: Artwork.emberFlameCore),
            FigurePart(path: Path(ellipseIn: CGRect(x: 30.5, y: 85, width: 15, height: 7)), color: Artwork.emberShadow, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 54.5, y: 85, width: 15, height: 7)), color: Artwork.emberShadow, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 30))
                p.addCurve(to: pt(82, 61), control1: pt(69, 30), control2: pt(82, 43))
                p.addCurve(to: pt(50, 87), control1: pt(82, 77), control2: pt(72, 87))
                p.addCurve(to: pt(18, 61), control1: pt(28, 87), control2: pt(18, 77))
                p.addCurve(to: pt(50, 30), control1: pt(18, 43), control2: pt(31, 30))
                p.closeSubpath()
            }, color: Color.ember, role: .body),
            FigurePart(path: Path(ellipseIn: CGRect(x: 12, y: 79, width: 84, height: 38)), color: Artwork.emberShadow, role: .shading),
            FigurePart(path: Path(ellipseIn: CGRect(x: 26, y: 38.5, width: 18, height: 11)), color: Artwork.emberGloss, role: .shading),
            FigurePart(path: Path(ellipseIn: CGRect(x: 14.9, y: 60.5, width: 7.2, height: 11)), color: Artwork.emberShadow, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 77.9, y: 60.5, width: 7.2, height: 11)), color: Artwork.emberShadow, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 36.2, y: 50.7, width: 6.6, height: 8.6)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 57.2, y: 50.7, width: 6.6, height: 8.6)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 39.4, y: 52.3, width: 2.2, height: 2.2)), color: Color.white),
            FigurePart(path: Path(ellipseIn: CGRect(x: 60.4, y: 52.3, width: 2.2, height: 2.2)), color: Color.white),
            FigurePart(path: Path { p in
                p.move(to: pt(46, 63))
                p.addQuadCurve(to: pt(54, 63), control: pt(50, 66.5))
            }, color: Color.onRibbon, paint: .stroke(2.2)),
        ]
        case .pip: [
            FigurePart(path: Path { p in
                p.move(to: pt(47, 32))
                p.addCurve(to: pt(52, 17), control1: pt(44, 22), control2: pt(47, 16))
                p.addCurve(to: pt(52, 31), control1: pt(50, 21), control2: pt(50, 26))
                p.closeSubpath()
            }, color: Color.pip, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(52, 31))
                p.addCurve(to: pt(65, 21), control1: pt(54, 22), control2: pt(60, 18))
                p.addCurve(to: pt(55, 32), control1: pt(60, 24), control2: pt(57, 27))
                p.closeSubpath()
            }, color: Color.pip, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 30.5, y: 85, width: 15, height: 7)), color: Artwork.pipBeak, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 54.5, y: 85, width: 15, height: 7)), color: Artwork.pipBeak, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 30))
                p.addCurve(to: pt(82, 61), control1: pt(69, 30), control2: pt(82, 43))
                p.addCurve(to: pt(50, 87), control1: pt(82, 77), control2: pt(72, 87))
                p.addCurve(to: pt(18, 61), control1: pt(28, 87), control2: pt(18, 77))
                p.addCurve(to: pt(50, 30), control1: pt(18, 43), control2: pt(31, 30))
                p.closeSubpath()
            }, color: Color.pip, role: .body),
            FigurePart(path: Path(ellipseIn: CGRect(x: 12, y: 79, width: 84, height: 38)), color: Artwork.pipShadow, role: .shading),
            FigurePart(path: Path(ellipseIn: CGRect(x: 26, y: 38.5, width: 18, height: 11)), color: Artwork.pipGloss, role: .shading),
            FigurePart(path: Path { p in
                p.move(to: pt(24, 60))
                p.addCurve(to: pt(20, 74), control1: pt(16, 58), control2: pt(13, 68))
                p.addCurve(to: pt(24, 60), control1: pt(23, 70), control2: pt(25, 65))
                p.closeSubpath()
            }, color: Artwork.pipShadow, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(76, 60))
                p.addCurve(to: pt(80, 74), control1: pt(84, 58), control2: pt(87, 68))
                p.addCurve(to: pt(76, 60), control1: pt(77, 70), control2: pt(75, 65))
                p.closeSubpath()
            }, color: Artwork.pipShadow, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 36.2, y: 50.7, width: 6.6, height: 8.6)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 57.2, y: 50.7, width: 6.6, height: 8.6)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 39.4, y: 52.3, width: 2.2, height: 2.2)), color: Color.white),
            FigurePart(path: Path(ellipseIn: CGRect(x: 60.4, y: 52.3, width: 2.2, height: 2.2)), color: Color.white),
            FigurePart(path: Path { p in
                p.move(to: pt(46, 61))
                p.addLine(to: pt(54, 61))
                p.addLine(to: pt(50, 66.5))
                p.closeSubpath()
            }, color: Artwork.pipBeak, paint: .fillAndStroke(2)),
        ]
        case .pebble: [
            FigurePart(path: Path(ellipseIn: CGRect(x: 30.5, y: 85, width: 15, height: 7)), color: Artwork.pebbleShadow, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 54.5, y: 85, width: 15, height: 7)), color: Artwork.pebbleShadow, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(50, 40))
                p.addCurve(to: pt(88, 66), control1: pt(73, 40), control2: pt(88, 51))
                p.addCurve(to: pt(50, 87), control1: pt(88, 80), control2: pt(75, 87))
                p.addCurve(to: pt(12, 66), control1: pt(25, 87), control2: pt(12, 80))
                p.addCurve(to: pt(50, 40), control1: pt(12, 51), control2: pt(27, 40))
                p.closeSubpath()
            }, color: Color.pebble, role: .body),
            FigurePart(path: Path(ellipseIn: CGRect(x: 12, y: 79, width: 84, height: 38)), color: Artwork.pebbleShadow, role: .shading),
            FigurePart(path: Path(ellipseIn: CGRect(x: 26, y: 38.5, width: 18, height: 11)), color: Artwork.pebbleGloss, role: .shading),
            FigurePart(path: Path(ellipseIn: CGRect(x: 8.9, y: 64.5, width: 7.2, height: 11)), color: Artwork.pebbleShadow, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 83.9, y: 64.5, width: 7.2, height: 11)), color: Artwork.pebbleShadow, role: .silhouette),
            FigurePart(path: Path { p in
                p.move(to: pt(38, 42))
                p.addCurve(to: pt(50, 37), control1: pt(40, 35), control2: pt(47, 33))
                p.addCurve(to: pt(62, 41), control1: pt(53, 32), control2: pt(61, 34))
                p.addCurve(to: pt(38, 42), control1: pt(55, 39), control2: pt(45, 39))
                p.closeSubpath()
            }, color: Artwork.moss, role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 25, y: 56, width: 4, height: 4)), color: Artwork.pebbleShadow),
            FigurePart(path: Path(ellipseIn: CGRect(x: 72.4, y: 52.4, width: 3.2, height: 3.2)), color: Artwork.pebbleShadow),
            FigurePart(path: Path(ellipseIn: CGRect(x: 76.6, y: 70.6, width: 4.8, height: 4.8)), color: Artwork.pebbleShadow),
            FigurePart(path: Path(ellipseIn: CGRect(x: 35.7, y: 56.7, width: 6.6, height: 8.6)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 57.7, y: 56.7, width: 6.6, height: 8.6)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: 38.9, y: 58.3, width: 2.2, height: 2.2)), color: Color.white),
            FigurePart(path: Path(ellipseIn: CGRect(x: 60.9, y: 58.3, width: 2.2, height: 2.2)), color: Color.white),
            FigurePart(path: Path { p in
                p.move(to: pt(46, 69))
                p.addQuadCurve(to: pt(54, 69), control: pt(50, 72.5))
            }, color: Color.onRibbon, paint: .stroke(2.2)),
        ]
        }
    }
}
