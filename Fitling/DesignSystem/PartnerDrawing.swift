import SwiftUI
import FitlingCore

/// Everything that changes how a partner looks. The values come from `CreatureSnapshot` and the
/// accessories the user put on; the catalog uses one fixed look.
struct PartnerLook: Equatable {
    var colorIndex = 0
    var mood: CreatureMood = .content
    /// 0 is lean, 1 is round (`CreatureSnapshot.bodyShape`).
    var bodyShape = CreatureEngine.startShape
    /// 0...4 (`CreatureSnapshot.growthStage`).
    var growthStage = 2
    var trainedRecently = false
    var items: [CreatureItem] = []

    /// The welcome catalog: the partners as they look once they have grown a little.
    static let catalog = PartnerLook()

    init(
        colorIndex: Int = 0, mood: CreatureMood = .content, bodyShape: Double = CreatureEngine.startShape,
        growthStage: Int = 2, trainedRecently: Bool = false, items: [CreatureItem] = []
    ) {
        self.colorIndex = colorIndex
        self.mood = mood
        self.bodyShape = bodyShape
        self.growthStage = growthStage
        self.trainedRecently = trainedRecently
        self.items = items
    }

    init(snapshot: CreatureSnapshot, items: [CreatureItem]) {
        self.init(
            colorIndex: snapshot.colorIndex, mood: snapshot.mood, bodyShape: snapshot.bodyShape,
            growthStage: snapshot.growthStage, trainedRecently: snapshot.trainedRecently, items: items
        )
    }

    /// Body width against the start shape: about 92 % when lean, 120 % when round.
    var width: CGFloat {
        1
    }

    /// Widens the body, its outline and what is worn on it around the middle of the drawing.
    /// The face and what sits on the head keep their size.
    var widening: CGAffineTransform {
        CGAffineTransform(translationX: 50, y: 0).scaledBy(x: width, y: 1).translatedBy(x: -50, y: 0)
    }
}

/// The three tones of one body colour: the colour itself, its shadow and its light.
struct PartnerPalette: Equatable {
    let body: Color
    let shadow: Color
    let gloss: Color
}

extension Species {
    /// Colours a partner can have: the base colours first, then the ones unlocked at higher levels
    /// (`CreatureEngine.unlockedColorCount`). Colour 0 is the species' own ribbon colour.
    var palettes: [PartnerPalette] {
        switch self {
        case .sprout: [
            PartnerPalette(body: Color.sprout, shadow: Artwork.color(0x57AE45), gloss: Artwork.color(0xC2F08A)),
            PartnerPalette(body: Artwork.color(0x5FD3A8), shadow: Artwork.color(0x3AAE84), gloss: Artwork.color(0xA8F0D3)),
            PartnerPalette(body: Artwork.color(0xC3DC4E), shadow: Artwork.color(0x9AB532), gloss: Artwork.color(0xE6F59A)),
            PartnerPalette(body: Artwork.color(0xF59AC0), shadow: Artwork.color(0xD8709C), gloss: Artwork.color(0xFFD0E3)),
            PartnerPalette(body: Artwork.color(0xB49AF0), shadow: Artwork.color(0x8E73D3), gloss: Artwork.color(0xDCCDFF)),
        ]
        case .ember: [
            PartnerPalette(body: Color.ember, shadow: Artwork.color(0xE8603A), gloss: Artwork.color(0xFFC56B)),
            PartnerPalette(body: Artwork.color(0xFF7A6B), shadow: Artwork.color(0xE0524A), gloss: Artwork.color(0xFFB3A6)),
            PartnerPalette(body: Artwork.color(0xFFB938), shadow: Artwork.color(0xE8902A), gloss: Artwork.color(0xFFE08A)),
            PartnerPalette(body: Artwork.color(0xFF6FA3), shadow: Artwork.color(0xDE4C82), gloss: Artwork.color(0xFFB0CC)),
            PartnerPalette(body: Artwork.color(0x7CC4FF), shadow: Artwork.color(0x4F9BE0), gloss: Artwork.color(0xC2E4FF)),
        ]
        case .pip: [
            PartnerPalette(body: Color.pip, shadow: Artwork.color(0xF0A500), gloss: Artwork.color(0xFFEC9A)),
            PartnerPalette(body: Artwork.color(0xFFB27A), shadow: Artwork.color(0xEE8C55), gloss: Artwork.color(0xFFD9B8)),
            PartnerPalette(body: Artwork.color(0x8FD0F5), shadow: Artwork.color(0x5FAEDD), gloss: Artwork.color(0xCDEBFC)),
            PartnerPalette(body: Artwork.color(0x8EE3B5), shadow: Artwork.color(0x5EC48E), gloss: Artwork.color(0xCFF6DF)),
            PartnerPalette(body: Artwork.color(0xD2A8F5), shadow: Artwork.color(0xAE80DD), gloss: Artwork.color(0xECD7FF)),
        ]
        case .pebble: [
            PartnerPalette(body: Color.pebble, shadow: Artwork.color(0x74839E), gloss: Artwork.color(0xC5CEDF)),
            PartnerPalette(body: Artwork.color(0xCDB79A), shadow: Artwork.color(0xA99273), gloss: Artwork.color(0xE8DAC6)),
            PartnerPalette(body: Artwork.color(0x9DBBA3), shadow: Artwork.color(0x789A7F), gloss: Artwork.color(0xCADFCD)),
            PartnerPalette(body: Artwork.color(0xE3A9B6), shadow: Artwork.color(0xC2818F), gloss: Artwork.color(0xF4D2DA)),
            PartnerPalette(body: Artwork.color(0xA894C9), shadow: Artwork.color(0x8370A8), gloss: Artwork.color(0xD0C3E6)),
        ]
        }
    }

    func palette(_ index: Int) -> PartnerPalette {
        let palettes = palettes
        return palettes[min(max(index, 0), palettes.count - 1)]
    }

    /// The partner's parts in one look, back to front.
    func parts(for look: PartnerLook) -> [FigurePart] {
        let palette = palette(look.colorIndex)
        let face = FaceAnchor(for: self)
        let widen = look.widening
        let items = Set(look.items)
        var parts: [FigurePart] = []

        if items.contains(.backpack) {
            parts += Accessory.backpack(face).map { $0.widened(by: widen) }
        }
        parts += headBehind(look: look, palette: palette)
        parts += [
            FigurePart(path: Path(ellipseIn: CGRect(x: 30.5, y: 85, width: 15, height: 7)), color: feetColor(palette), role: .silhouette),
            FigurePart(path: Path(ellipseIn: CGRect(x: 54.5, y: 85, width: 15, height: 7)), color: feetColor(palette), role: .silhouette),
        ].map { $0.widened(by: widen) }
        parts.append(FigurePart(path: bodyPath, color: palette.body, role: .body).widened(by: widen))
        parts += [
            FigurePart(path: Path(ellipseIn: CGRect(x: 12, y: 79, width: 84, height: 38)), color: palette.shadow, role: .shading),
            FigurePart(path: Path(ellipseIn: CGRect(x: 26, y: 38.5, width: 18, height: 11)), color: palette.gloss, role: .shading),
        ].map { $0.widened(by: widen) }
        if self == .pip, look.growthStage >= 4 {
            let xs: [CGFloat] = [44, 50, 56]
            parts += xs.map { x in
                FigurePart(
                    path: Path(ellipseIn: CGRect(x: x - 3, y: x == 50 ? 75.5 : 73.5, width: 6, height: 5)),
                    color: palette.gloss, role: .shading
                ).widened(by: widen)
            }
        }
        if look.trainedRecently, self == .pip || self == .pebble {
            parts += Accessory.sweatband(face)
        }
        if items.contains(.scarf) {
            parts += Accessory.scarfBand(face)
        }
        if items.contains(.backpack) {
            parts += Accessory.backpackStraps(face).map { $0.widened(by: widen) }
        }
        parts += arms(palette).map { $0.widened(by: widen) }
        if self == .pebble {
            parts += [
                CGRect(x: 25, y: 56, width: 4, height: 4),
                CGRect(x: 72.4, y: 52.4, width: 3.2, height: 3.2),
                CGRect(x: 76.6, y: 70.6, width: 4.8, height: 4.8),
            ].map { FigurePart(path: Path(ellipseIn: $0), color: palette.shadow).widened(by: widen) }
        }
        parts += headFront(look: look)
        parts += Face.parts(.content, anchor: face, beak: self == .pip, palette: palette)
        if items.contains(.glasses) {
            parts += Accessory.glasses(face)
        }
        if items.contains(.scarf) {
            parts += Accessory.scarfTail(face).map { $0.widened(by: widen) }
        }
        if items.contains(.bow) {
            parts += Accessory.bow(face)
        }
        if items.contains(.cap) {
            parts += Accessory.cap(face)
        }
        if items.contains(.crown) {
            parts += Accessory.crown(face)
        }
        if look.trainedRecently, self == .sprout {
            parts += Accessory.handFlower().map { $0.widened(by: widen) }
        }
        if look.mood == .asleep {
            parts += Face.sleepingZs()
        }
        return parts
    }

    private var bodyPath: Path {
        if self == .pebble {
            return Path { p in
                p.move(to: pt(50, 40))
                p.addCurve(to: pt(88, 66), control1: pt(73, 40), control2: pt(88, 51))
                p.addCurve(to: pt(50, 87), control1: pt(88, 80), control2: pt(75, 87))
                p.addCurve(to: pt(12, 66), control1: pt(25, 87), control2: pt(12, 80))
                p.addCurve(to: pt(50, 40), control1: pt(12, 51), control2: pt(27, 40))
                p.closeSubpath()
            }
        }
        return Path { p in
            p.move(to: pt(50, 30))
            p.addCurve(to: pt(82, 61), control1: pt(69, 30), control2: pt(82, 43))
            p.addCurve(to: pt(50, 87), control1: pt(82, 77), control2: pt(72, 87))
            p.addCurve(to: pt(18, 61), control1: pt(28, 87), control2: pt(18, 77))
            p.addCurve(to: pt(50, 30), control1: pt(18, 43), control2: pt(31, 30))
            p.closeSubpath()
        }
    }

    private func feetColor(_ palette: PartnerPalette) -> Color {
        self == .pip ? Artwork.pipBeak : palette.shadow
    }

    private func arms(_ palette: PartnerPalette) -> [FigurePart] {
        switch self {
        case .sprout, .ember:
            [
                FigurePart(path: Path(ellipseIn: CGRect(x: 14.9, y: 60.5, width: 7.2, height: 11)), color: palette.shadow, role: .silhouette),
                FigurePart(path: Path(ellipseIn: CGRect(x: 77.9, y: 60.5, width: 7.2, height: 11)), color: palette.shadow, role: .silhouette),
            ]
        case .pip:
            [
                FigurePart(path: Path { p in
                    p.move(to: pt(24, 60))
                    p.addCurve(to: pt(20, 74), control1: pt(16, 58), control2: pt(13, 68))
                    p.addCurve(to: pt(24, 60), control1: pt(23, 70), control2: pt(25, 65))
                    p.closeSubpath()
                }, color: palette.shadow, role: .silhouette),
                FigurePart(path: Path { p in
                    p.move(to: pt(76, 60))
                    p.addCurve(to: pt(80, 74), control1: pt(84, 58), control2: pt(87, 68))
                    p.addCurve(to: pt(76, 60), control1: pt(77, 70), control2: pt(75, 65))
                    p.closeSubpath()
                }, color: palette.shadow, role: .silhouette),
            ]
        case .pebble:
            [
                FigurePart(path: Path(ellipseIn: CGRect(x: 8.9, y: 64.5, width: 7.2, height: 11)), color: palette.shadow, role: .silhouette),
                FigurePart(path: Path(ellipseIn: CGRect(x: 83.9, y: 64.5, width: 7.2, height: 11)), color: palette.shadow, role: .silhouette),
            ]
        }
    }

    /// What grows on top of the head behind the body: Sprout's leaves, Ember's flame, Pip's crest.
    private func headBehind(look: PartnerLook, palette: PartnerPalette) -> [FigurePart] {
        let stage = min(max(look.growthStage, 0), 4)
        switch self {
        case .sprout:
            let leafScale: CGFloat = [0.55, 0.8, 1, 1, 1.05][stage]
            let base = pt(50, 23)
            var parts = [
                FigurePart(path: Path { p in
                    p.move(to: pt(49, 31))
                    p.addLine(to: pt(49, 22))
                    p.addCurve(to: pt(51, 22), control1: pt(49, 20.5), control2: pt(51, 20.5))
                    p.addLine(to: pt(51, 31))
                    p.closeSubpath()
                }, color: Artwork.sproutLeafDark, role: .silhouette),
            ]
            if stage >= 3 {
                parts.append(FigurePart(path: Path { p in
                    p.move(to: pt(50, 22))
                    p.addLine(to: pt(50, 14))
                }, color: Artwork.sproutLeafDark, paint: .stroke(2), role: .silhouette))
            }
            parts += [
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
            ].map { $0.scaled(by: leafScale, around: base) }
            if stage == 3 {
                parts.append(FigurePart(path: Path(ellipseIn: CGRect(x: 47.25, y: 8.5, width: 5.5, height: 7)), color: Artwork.blossom, role: .silhouette))
            } else if stage == 4 {
                parts += Flower.parts(center: pt(50, 12), petal: 6, spread: 3.6)
            }
            return parts
        case .ember:
            let flameScale: CGFloat = [0.6, 0.8, 1, 1.1, 1.18][stage]
            let coreScale = flameScale * (look.trainedRecently ? 1.25 : 1)
            let base = pt(50, 34)
            var parts = [
                FigurePart(path: Path { p in
                    p.move(to: pt(50, 6))
                    p.addCurve(to: pt(65, 33), control1: pt(57, 15), control2: pt(66, 21))
                    p.addCurve(to: pt(35, 33), control1: pt(65, 38), control2: pt(35, 38))
                    p.addCurve(to: pt(42, 14), control1: pt(34, 24), control2: pt(40, 20))
                    p.addCurve(to: pt(48, 24), control1: pt(45, 19), control2: pt(46, 22))
                    p.addCurve(to: pt(50, 6), control1: pt(46, 17), control2: pt(47, 11))
                    p.closeSubpath()
                }, color: Artwork.emberFlame, role: .silhouette).scaled(by: flameScale, around: base),
                FigurePart(path: Path { p in
                    p.move(to: pt(50, 16))
                    p.addCurve(to: pt(58, 33), control1: pt(54, 22), control2: pt(59, 26))
                    p.addLine(to: pt(42, 33))
                    p.addCurve(to: pt(47, 21), control1: pt(42, 28), control2: pt(45, 24))
                    p.addCurve(to: pt(50, 26), control1: pt(48, 24), control2: pt(49, 25))
                    p.addCurve(to: pt(50, 16), control1: pt(49, 22), control2: pt(49, 19))
                    p.closeSubpath()
                }, color: look.trainedRecently ? Artwork.emberFlameBright : Artwork.emberFlameCore)
                    .scaled(by: coreScale, around: base),
            ]
            if stage >= 4 {
                parts += [pt(33, 15), pt(68, 11)].map { spark in
                    FigurePart(path: Path { p in
                        p.move(to: pt(spark.x, spark.y - 2.5))
                        p.addLine(to: pt(spark.x + 1.6, spark.y))
                        p.addLine(to: pt(spark.x, spark.y + 2.5))
                        p.addLine(to: pt(spark.x - 1.6, spark.y))
                        p.closeSubpath()
                    }, color: Artwork.emberFlameCore, role: .silhouette)
                }
            }
            return parts
        case .pip:
            let featherScale: CGFloat = [0.55, 0.8, 1, 1, 1.15][stage]
            let base = pt(51, 32)
            var feathers = [
                FigurePart(path: Path { p in
                    p.move(to: pt(47, 32))
                    p.addCurve(to: pt(52, 17), control1: pt(44, 22), control2: pt(47, 16))
                    p.addCurve(to: pt(52, 31), control1: pt(50, 21), control2: pt(50, 26))
                    p.closeSubpath()
                }, color: palette.body, role: .silhouette),
            ]
            if stage >= 1 {
                feathers.append(FigurePart(path: Path { p in
                    p.move(to: pt(52, 31))
                    p.addCurve(to: pt(65, 21), control1: pt(54, 22), control2: pt(60, 18))
                    p.addCurve(to: pt(55, 32), control1: pt(60, 24), control2: pt(57, 27))
                    p.closeSubpath()
                }, color: palette.body, role: .silhouette))
            }
            if stage >= 3 {
                feathers.append(FigurePart(path: Path { p in
                    p.move(to: pt(48, 32))
                    p.addCurve(to: pt(37, 22), control1: pt(46, 26), control2: pt(41, 22))
                    p.addCurve(to: pt(46, 33), control1: pt(41, 26), control2: pt(44, 29))
                    p.closeSubpath()
                }, color: palette.body, role: .silhouette))
            }
            return feathers.map { $0.scaled(by: featherScale, around: base) }
        case .pebble:
            return []
        }
    }

    /// What grows on top of the head in front of the body: Pebble's moss and crystals.
    private func headFront(look: PartnerLook) -> [FigurePart] {
        guard self == .pebble else { return [] }
        let stage = min(max(look.growthStage, 0), 4)
        guard stage >= 1 else { return [] }
        let mossScale: CGFloat = [0, 0.75, 1, 1, 1.1][stage]
        var parts = [
            FigurePart(path: Path { p in
                p.move(to: pt(38, 42))
                p.addCurve(to: pt(50, 37), control1: pt(40, 35), control2: pt(47, 33))
                p.addCurve(to: pt(62, 41), control1: pt(53, 32), control2: pt(61, 34))
                p.addCurve(to: pt(38, 42), control1: pt(55, 39), control2: pt(45, 39))
                p.closeSubpath()
            }, color: Artwork.moss, role: .silhouette).scaled(by: mossScale, around: pt(50, 40)),
        ]
        if stage >= 3 {
            parts += Crystal.parts(base: pt(67.5, 45.5), height: 12.5, width: 7)
        }
        if stage >= 4 {
            parts += Crystal.parts(base: pt(32.5, 47), height: 9, width: 5)
        }
        return parts
    }
}

/// Where the face sits: the centres of the eyes, the middle of the mouth line and the top of the head.
struct FaceAnchor {
    let leftEye: CGPoint
    let rightEye: CGPoint
    let mouth: CGPoint
    let headTop: CGFloat

    init(for species: Species) {
        switch species {
        case .pebble:
            leftEye = pt(39, 61)
            rightEye = pt(61, 61)
            mouth = pt(50, 69)
            headTop = 40
        case .pip:
            leftEye = pt(39.5, 55)
            rightEye = pt(60.5, 55)
            mouth = pt(50, 61)
            headTop = 30
        case .sprout, .ember:
            leftEye = pt(39.5, 55)
            rightEye = pt(60.5, 55)
            mouth = pt(50, 63)
            headTop = 30
        }
    }
}

/// Eyes and mouth per mood. Pip has a beak instead of a mouth.
private enum Face {
    static func parts(_ mood: CreatureMood, anchor a: FaceAnchor, beak: Bool, palette: PartnerPalette) -> [FigurePart] {
        let eyes: [FigurePart]
        switch mood {
        case .content:
            eyes = openEye(a.leftEye) + openEye(a.rightEye)
        case .happy:
            eyes = openEye(a.leftEye, size: 1.05) + openEye(a.rightEye, size: 1.05) + blush(a)
        case .sluggish:
            eyes = lidded(a.leftEye, outerDrop: 0, palette: palette) + lidded(a.rightEye, outerDrop: 0, palette: palette)
        case .tired:
            eyes = lidded(a.leftEye, outerDrop: -1.6, palette: palette) + lidded(a.rightEye, outerDrop: 1.6, palette: palette)
        case .hungry:
            eyes = openEye(a.leftEye, size: 1.1, second: true) + openEye(a.rightEye, size: 1.1, second: true)
        case .asleep:
            eyes = [a.leftEye, a.rightEye].map { c in
                FigurePart(path: Path { p in
                    p.move(to: pt(c.x - 3.4, c.y))
                    p.addQuadCurve(to: pt(c.x + 3.4, c.y), control: pt(c.x, c.y + 3))
                }, color: Color.onRibbon, paint: .stroke(2))
            }
        }
        return eyes + (beak ? self.beak(mood, at: a.mouth) : mouth(mood, at: a.mouth))
    }

    static func sleepingZs() -> [FigurePart] {
        [(pt(72, 22), CGFloat(8)), (pt(84, 11), CGFloat(5))].map { letter in
            let (origin, size) = letter
            return FigurePart(path: Path { p in
                p.move(to: origin)
                p.addLine(to: pt(origin.x + size, origin.y))
                p.addLine(to: pt(origin.x, origin.y + size))
                p.addLine(to: pt(origin.x + size, origin.y + size))
            }, color: Color.ink, paint: .stroke(1.8))
        }
    }

    private static func openEye(_ c: CGPoint, size s: CGFloat = 1, second: Bool = false) -> [FigurePart] {
        var parts = [
            FigurePart(path: Path(ellipseIn: CGRect(x: c.x - 3.3 * s, y: c.y - 4.3 * s, width: 6.6 * s, height: 8.6 * s)), color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: c.x + 1 * s - 1.1 * s, y: c.y - 1.6 * s - 1.1 * s, width: 2.2 * s, height: 2.2 * s)), color: Color.white),
        ]
        if second {
            parts.append(FigurePart(path: Path(ellipseIn: CGRect(x: c.x - 1.8 * s, y: c.y + 1.2 * s, width: 1.2 * s, height: 1.2 * s)), color: Color.white))
        }
        return parts
    }

    /// An eye with the lid half down, in the body's shadow tone. `outerDrop` tilts the lid line:
    /// negative lowers its left end, positive its right end.
    private static func lidded(_ c: CGPoint, outerDrop: CGFloat, palette: PartnerPalette) -> [FigurePart] {
        let eye = Path(ellipseIn: CGRect(x: c.x - 3.3, y: c.y - 4.3, width: 6.6, height: 8.6))
        let leftY = c.y - 0.4 + max(-outerDrop, 0)
        let rightY = c.y - 0.4 + max(outerDrop, 0)
        let lidArea = Path { p in
            p.move(to: pt(c.x - 4, c.y - 5))
            p.addLine(to: pt(c.x + 4, c.y - 5))
            p.addLine(to: pt(c.x + 4, rightY))
            p.addLine(to: pt(c.x - 4, leftY))
            p.closeSubpath()
        }
        return [
            FigurePart(path: eye, color: Color.onRibbon),
            FigurePart(path: Path(ellipseIn: CGRect(x: c.x + 0.5 - 1, y: c.y + 0.6 - 1, width: 2, height: 2)), color: Color.white),
            FigurePart(path: eye.intersection(lidArea), color: palette.shadow),
            FigurePart(path: Path { p in
                p.move(to: pt(c.x - 3.6, leftY))
                p.addLine(to: pt(c.x + 3.6, rightY))
            }, color: Color.onRibbon, paint: .stroke(1.6)),
        ]
    }

    private static func blush(_ a: FaceAnchor) -> [FigurePart] {
        [pt(a.leftEye.x - 5, a.leftEye.y + 6.5), pt(a.rightEye.x + 5, a.rightEye.y + 6.5)].map { c in
            FigurePart(path: Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 1.8, width: 6, height: 3.6)), color: Artwork.blush)
        }
    }

    private static func mouth(_ mood: CreatureMood, at m: CGPoint) -> [FigurePart] {
        switch mood {
        case .content:
            return [FigurePart(path: Path { p in
                p.move(to: pt(m.x - 4, m.y))
                p.addQuadCurve(to: pt(m.x + 4, m.y), control: pt(m.x, m.y + 3.5))
            }, color: Color.onRibbon, paint: .stroke(2.2))]
        case .happy:
            return [FigurePart(path: Path { p in
                p.move(to: pt(m.x - 5, m.y - 0.5))
                p.addQuadCurve(to: pt(m.x + 5, m.y - 0.5), control: pt(m.x, m.y + 7))
                p.closeSubpath()
            }, color: Color.onRibbon, paint: .fillAndStroke(1.2))]
        case .sluggish:
            return [FigurePart(path: Path { p in
                p.move(to: pt(m.x - 4, m.y + 1))
                p.addQuadCurve(to: pt(m.x, m.y + 1), control: pt(m.x - 2, m.y - 0.6))
                p.addQuadCurve(to: pt(m.x + 4, m.y + 1), control: pt(m.x + 2, m.y + 2.6))
            }, color: Color.onRibbon, paint: .stroke(2.2))]
        case .tired:
            return [FigurePart(path: Path { p in
                p.move(to: pt(m.x - 3.5, m.y + 2.5))
                p.addQuadCurve(to: pt(m.x + 3.5, m.y + 2.5), control: pt(m.x, m.y - 0.5))
            }, color: Color.onRibbon, paint: .stroke(2.2))]
        case .hungry:
            return [
                FigurePart(path: Path(ellipseIn: CGRect(x: m.x - 2.5, y: m.y - 0.8, width: 5, height: 4.6)), color: Color.onRibbon),
                FigurePart(path: Path(ellipseIn: CGRect(x: m.x - 1.5, y: m.y + 1.9, width: 3, height: 1.8)), color: Artwork.tongue),
            ]
        case .asleep:
            return [FigurePart(path: Path(ellipseIn: CGRect(x: m.x - 1.5, y: m.y, width: 3, height: 2.4)), color: Color.onRibbon)]
        }
    }

    private static func beak(_ mood: CreatureMood, at m: CGPoint) -> [FigurePart] {
        if mood == .hungry {
            return [
                FigurePart(path: Path { p in
                    p.move(to: pt(m.x - 4, m.y))
                    p.addLine(to: pt(m.x + 4, m.y))
                    p.addLine(to: pt(m.x, m.y + 3.5))
                    p.closeSubpath()
                }, color: Artwork.pipBeak, paint: .fillAndStroke(2)),
                FigurePart(path: Path { p in
                    p.move(to: pt(m.x - 3, m.y + 4.8))
                    p.addLine(to: pt(m.x + 3, m.y + 4.8))
                    p.addLine(to: pt(m.x, m.y + 7.5))
                    p.closeSubpath()
                }, color: Artwork.pipBeak, paint: .fillAndStroke(2)),
            ]
        }
        return [FigurePart(path: Path { p in
            p.move(to: pt(m.x - 4, m.y))
            p.addLine(to: pt(m.x + 4, m.y))
            p.addLine(to: pt(m.x, m.y + 5.5))
            p.closeSubpath()
        }, color: Artwork.pipBeak, paint: .fillAndStroke(2))]
    }
}

/// The six things a partner can wear, each in one flat colour with one darker tone for depth.
private enum Accessory {
    static func scarfBand(_ a: FaceAnchor) -> [FigurePart] {
        [FigurePart(path: Path(CGRect(x: 0, y: scarfTop(a), width: 100, height: 5.5)), color: Artwork.scarf, role: .shading)]
    }

    static func scarfTail(_ a: FaceAnchor) -> [FigurePart] {
        let top = scarfTop(a) + 3
        return [FigurePart(path: Path { p in
            p.move(to: pt(57, top))
            p.addLine(to: pt(64, top))
            p.addLine(to: pt(66, top + 10))
            p.addLine(to: pt(59, top + 10))
            p.closeSubpath()
        }, color: Artwork.scarfShade)]
    }

    /// The scarf sits just under the mouth, where a neck would be.
    private static func scarfTop(_ a: FaceAnchor) -> CGFloat {
        a.headTop == 30 ? 70 : 76
    }

    static func cap(_ a: FaceAnchor) -> [FigurePart] {
        let top = a.headTop
        return [
            FigurePart(path: Path(roundedRect: CGRect(x: 60, y: top + 5.5, width: 17, height: 4), cornerRadius: 2), color: Artwork.capShade),
            FigurePart(path: Path { p in
                p.move(to: pt(34, top + 8))
                p.addCurve(to: pt(50, top - 5), control1: pt(34, top + 1), control2: pt(41, top - 5))
                p.addCurve(to: pt(66, top + 8), control1: pt(59, top - 5), control2: pt(66, top + 1))
                p.closeSubpath()
            }, color: Artwork.cap),
            FigurePart(path: Path(ellipseIn: CGRect(x: 48.5, y: top - 7.5, width: 3, height: 3)), color: Artwork.capShade),
        ]
    }

    static func crown(_ a: FaceAnchor) -> [FigurePart] {
        let top = a.headTop
        return [
            FigurePart(path: Path { p in
                p.move(to: pt(39, top + 6))
                p.addLine(to: pt(39, top - 4))
                p.addLine(to: pt(44.5, top + 1))
                p.addLine(to: pt(50, top - 7))
                p.addLine(to: pt(55.5, top + 1))
                p.addLine(to: pt(61, top - 4))
                p.addLine(to: pt(61, top + 6))
                p.closeSubpath()
            }, color: Artwork.crown, paint: .fillAndStroke(1)),
            FigurePart(path: Path(ellipseIn: CGRect(x: 48.5, y: top + 0.5, width: 3, height: 3)), color: Artwork.scarf),
        ]
    }

    static func bow(_ a: FaceAnchor) -> [FigurePart] {
        let c = pt(33, a.headTop + 9)
        return [
            FigurePart(path: Path { p in
                p.move(to: c)
                p.addLine(to: pt(c.x - 7, c.y - 5))
                p.addLine(to: pt(c.x - 7, c.y + 5))
                p.closeSubpath()
                p.move(to: c)
                p.addLine(to: pt(c.x + 7, c.y - 5))
                p.addLine(to: pt(c.x + 7, c.y + 5))
                p.closeSubpath()
            }, color: Artwork.bow, paint: .fillAndStroke(1.5)),
            FigurePart(path: Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), color: Artwork.bowShade),
        ]
    }

    static func glasses(_ a: FaceAnchor) -> [FigurePart] {
        let radius: CGFloat = 5.6
        return [
            FigurePart(path: Path { p in
                p.addEllipse(in: CGRect(x: a.leftEye.x - radius, y: a.leftEye.y - radius, width: radius * 2, height: radius * 2))
                p.addEllipse(in: CGRect(x: a.rightEye.x - radius, y: a.rightEye.y - radius, width: radius * 2, height: radius * 2))
                p.move(to: pt(a.leftEye.x + radius, a.leftEye.y - 0.5))
                p.addQuadCurve(to: pt(a.rightEye.x - radius, a.rightEye.y - 0.5), control: pt(50, a.leftEye.y - 3))
            }, color: Color.onRibbon, paint: .stroke(1.6)),
        ]
    }

    static func backpack(_ a: FaceAnchor) -> [FigurePart] {
        let rect = a.headTop == 30 ? CGRect(x: 22, y: 36, width: 56, height: 32) : CGRect(x: 18, y: 46, width: 64, height: 28)
        return [FigurePart(path: Path(roundedRect: rect, cornerRadius: 8), color: Artwork.backpack, role: .silhouette)]
    }

    static func backpackStraps(_ a: FaceAnchor) -> [FigurePart] {
        let xs: [CGFloat] = a.headTop == 30 ? [31, 65] : [29, 67]
        return xs.map { x in
            FigurePart(path: Path(CGRect(x: x, y: a.headTop, width: 4, height: 50)), color: Artwork.backpackStrap, role: .shading)
        }
    }

    /// The band Pip and Pebble wear after a workout: white with a red stripe.
    static func sweatband(_ a: FaceAnchor) -> [FigurePart] {
        let top = a.leftEye.y - 4.3 - 6.7
        return [
            FigurePart(path: Path(CGRect(x: 0, y: top, width: 100, height: 4.2)), color: Artwork.sweatband, role: .shading),
            FigurePart(path: Path(CGRect(x: 0, y: top + 1.5, width: 100, height: 1.2)), color: Artwork.scarf, role: .shading),
        ]
    }

    /// The flower Sprout carries after a workout, held at its right arm.
    static func handFlower() -> [FigurePart] {
        [
            FigurePart(path: Path { p in
                p.move(to: pt(82, 64))
                p.addLine(to: pt(84, 52))
            }, color: Artwork.sproutLeafDark, paint: .stroke(1.6)),
        ] + Flower.parts(center: pt(84, 49.5), petal: 4.4, spread: 2.6)
    }
}

private enum Flower {
    /// Five round petals around a yellow heart.
    static func parts(center c: CGPoint, petal: CGFloat, spread: CGFloat) -> [FigurePart] {
        (0..<5).map { index in
            let angle = Double(index) * 2 * .pi / 5 - .pi / 2
            let x = c.x + spread * CGFloat(cos(angle))
            let y = c.y + spread * CGFloat(sin(angle))
            return FigurePart(path: Path(ellipseIn: CGRect(x: x - petal / 2, y: y - petal / 2, width: petal, height: petal)), color: Artwork.blossom)
        } + [FigurePart(path: Path(ellipseIn: CGRect(x: c.x - petal * 0.35, y: c.y - petal * 0.35, width: petal * 0.7, height: petal * 0.7)), color: Artwork.emberFlameCore)]
    }
}

private enum Crystal {
    /// A standing crystal with one lit face.
    static func parts(base: CGPoint, height: CGFloat, width: CGFloat) -> [FigurePart] {
        let half = width / 2
        let outline = Path { p in
            p.move(to: pt(base.x - half, base.y))
            p.addLine(to: pt(base.x - half, base.y - height * 0.65))
            p.addLine(to: pt(base.x, base.y - height))
            p.addLine(to: pt(base.x + half, base.y - height * 0.65))
            p.addLine(to: pt(base.x + half, base.y))
            p.closeSubpath()
        }
        let lit = Path { p in
            p.move(to: pt(base.x - half, base.y))
            p.addLine(to: pt(base.x - half, base.y - height * 0.65))
            p.addLine(to: pt(base.x, base.y - height))
            p.addLine(to: pt(base.x, base.y))
            p.closeSubpath()
        }
        return [
            FigurePart(path: outline, color: Artwork.crystalShade, role: .silhouette),
            FigurePart(path: lit, color: Artwork.crystal),
        ]
    }
}

private extension FigurePart {
    func widened(by transform: CGAffineTransform) -> FigurePart {
        FigurePart(path: path.applying(transform), color: color, paint: paint, role: role)
    }

    func scaled(by factor: CGFloat, around point: CGPoint) -> FigurePart {
        let transform = CGAffineTransform(translationX: point.x, y: point.y).scaledBy(x: factor, y: factor).translatedBy(x: -point.x, y: -point.y)
        return FigurePart(path: path.applying(transform), color: color, paint: paint, role: role)
    }
}

/// Artwork colours next to the palettes. A partner looks the same in light and dark mode.
enum Artwork {
    static let sproutLeaf = color(0x6CC24A)
    static let sproutLeafDark = color(0x3E8E36)
    static let emberFlame = color(0xFF6A2B)
    static let emberFlameCore = color(0xFFD54F)
    static let emberFlameBright = color(0xFFF1A6)
    static let pipBeak = color(0xFF8A3D)
    static let moss = color(0x6CC24A)
    static let blossom = color(0xFF8FB8)
    static let blush = color(0xF7A6BA)
    static let tongue = color(0xF27C93)
    static let scarf = color(0xE5484D)
    static let scarfShade = color(0xC23A3F)
    static let cap = color(0x4F7BE8)
    static let capShade = color(0x3E62C4)
    static let crown = color(0xF2B807)
    static let bow = color(0xFF7EB0)
    static let bowShade = color(0xE8609A)
    static let backpack = color(0xC98A4B)
    static let backpackStrap = color(0x9C6532)
    static let sweatband = color(0xF7F4F0)
    static let crystal = color(0xC2EBFA)
    static let crystalShade = color(0x7FC4E6)

    /// An sRGB colour from a 0xRRGGBB value.
    static func color(_ hex: UInt32) -> Color {
        Color(
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
