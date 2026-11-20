import SwiftUI
import FitlingCore

/// How the sixteen species look: their colours and names in the catalog, the partner setup and
/// the partner itself. The figures are 3D renders (design/partners/nieuw/partners_3d.py).
extension Species {
    /// The species' own colour: its name plate and its own ribbon.
    var ribbon: Color { Color("PartnerRibbon/\(rawValue)") }

    /// The pastel ground behind the species' figure.
    var tint: Color { Color("PartnerTint/\(rawValue)") }

    var name: LocalizedStringResource {
        switch self {
        case .bumblebee: "creature.bumblebee.name"
        case .mole: "creature.mole.name"
        case .frog: "creature.frog.name"
        case .owl: "creature.owl.name"
        case .hedgehog: "creature.hedgehog.name"
        case .snail: "creature.snail.name"
        case .axolotl: "creature.axolotl.name"
        case .seal: "creature.seal.name"
        case .penguin: "creature.penguin.name"
        case .turtle: "creature.turtle.name"
        case .rabbit: "creature.rabbit.name"
        case .raccoon: "creature.raccoon.name"
        case .ladybird: "creature.ladybird.name"
        case .octopus: "creature.octopus.name"
        case .squirrel: "creature.squirrel.name"
        case .lamb: "creature.lamb.name"
        }
    }

    /// One line of character.
    var note: LocalizedStringResource {
        switch self {
        case .bumblebee: "creature.bumblebee.note"
        case .mole: "creature.mole.note"
        case .frog: "creature.frog.note"
        case .owl: "creature.owl.note"
        case .hedgehog: "creature.hedgehog.note"
        case .snail: "creature.snail.note"
        case .axolotl: "creature.axolotl.note"
        case .seal: "creature.seal.note"
        case .penguin: "creature.penguin.note"
        case .turtle: "creature.turtle.note"
        case .rabbit: "creature.rabbit.note"
        case .raccoon: "creature.raccoon.note"
        case .ladybird: "creature.ladybird.note"
        case .octopus: "creature.octopus.note"
        case .squirrel: "creature.squirrel.note"
        case .lamb: "creature.lamb.note"
        }
    }

    /// The species name in the user's language, as a starting name for the partner.
    var displayName: String { String(localized: name) }
}

/// Everything that changes how a partner looks. The values come from `CreatureSnapshot` and the
/// accessories the user put on; the catalog uses one fixed look.
struct PartnerLook: Equatable {
    var colorIndex = 0
    var mood: CreatureMood = .content
    /// 0 is lean, 1 is round (`CreatureSnapshot.bodyShape`).
    var bodyShape = CreatureEngine.startShape
    /// 0...5 (`CreatureSnapshot.growthStage`), one per form.
    var growthStage = 2
    var trainedRecently = false
    var items: [CreatureItem] = []

    /// The catalog: the partners as they look once they have grown a little.
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

    /// Width against the start shape: about 92 % when lean, 120 % when round.
    var width: CGFloat {
        1 + (CGFloat(min(max(bodyShape, 0), 1)) - CGFloat(CreatureEngine.startShape)) * 0.28
    }
}

/// One image in a partner's stack. All layers of one species and form come from the same camera
/// and scale, so they lie exactly on top of each other.
struct PartnerLayer: Equatable {
    let name: String
    /// Only the body takes the colour variant; the face and what the partner wears keep their colours.
    let takesColor: Bool
}

/// Which images make up a partner in one look, from back to front.
enum PartnerLayers {
    static let formCount = 6
    /// What the partner wears, from back to front. The sweatband after a workout goes on last.
    static let itemOrder: [CreatureItem] = [.backpack, .scarf, .glasses, .bow, .cap, .crown]
    /// The colour variants as a turn of the body's hue: the species' own colour first, then four others.
    static let hues: [Double] = [0, 40, 150, 210, 300]

    /// The rendered form (1...6) for a growth stage.
    static func form(for growthStage: Int) -> Int {
        min(max(growthStage, 0), formCount - 1) + 1
    }

    static func hue(for colorIndex: Int) -> Angle {
        .degrees(hues[min(max(colorIndex, 0), hues.count - 1)])
    }

    static func layers(_ species: Species, look: PartnerLook) -> [PartnerLayer] {
        let base = prefix(species, form: form(for: look.growthStage))
        var layers = [
            PartnerLayer(name: "\(base)-body", takesColor: true),
            PartnerLayer(name: "\(base)-face-\(look.mood.rawValue)", takesColor: false),
        ]
        for item in itemOrder where look.items.contains(item) {
            layers.append(PartnerLayer(name: "\(base)-item-\(item.rawValue)", takesColor: false))
        }
        if look.trainedRecently {
            layers.append(PartnerLayer(name: "\(base)-item-sweatband", takesColor: false))
        }
        return layers
    }

    static func prefix(_ species: Species, form: Int) -> String {
        "partner-\(species.rawValue)-\(form)"
    }
}

/// Where the head is in each render, in image fractions (origin top left). Written by the renderer
/// next to the layers; the sleeping Z's float above the head.
struct PartnerAnchor: Decodable, Equatable {
    let headTop: [Double]
    let headCenter: [Double]
    let headRadius: Double
    /// The figure's bounds without its contact shadow: left, top, right, bottom.
    let figure: [Double]

    static let all: [String: PartnerAnchor] = {
        guard let url = Bundle.main.url(forResource: "PartnerAnchors", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: PartnerAnchor].self, from: data)) ?? [:]
    }()

    static func of(_ species: Species, form: Int) -> PartnerAnchor? {
        all["\(species.rawValue)/\(form)"]
    }
}

/// How far to zoom into a render. The six forms share one camera, so a young form is small in its
/// render; on screen every form fills its frame, a young one less than a grown one, with the feet
/// on one ground line.
struct PartnerFraming: Equatable {
    /// The figure's height as a share of the frame, per form.
    static let heights: [Double] = [0.55, 0.6, 0.66, 0.72, 0.78, 0.84]
    static let maxWidth = 0.94
    /// Where the feet stand, as a share of the frame height.
    static let ground = 0.93

    let scale: Double
    let dx: Double
    let dy: Double

    static let identity = PartnerFraming(scale: 1, dx: 0, dy: 0)

    init(scale: Double, dx: Double, dy: Double) {
        self.scale = scale
        self.dx = dx
        self.dy = dy
    }

    init(figure: [Double], form: Int) {
        let width = max(figure[2] - figure[0], 0.01)
        let height = max(figure[3] - figure[1], 0.01)
        let target = Self.heights[min(max(form, 1), Self.heights.count) - 1]
        let scale = min(target / height, Self.maxWidth / width)
        self.init(scale: scale, dx: 0.5 - scale * (figure[0] + figure[2]) / 2, dy: Self.ground - scale * figure[3])
    }

    /// Where a point of the render (in image fractions) lands in the frame.
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: dx + scale * x, y: dy + scale * y)
    }
}

/// The partner as the catalog shows it: standing still.
struct FigureView: View {
    let species: Species

    var body: some View {
        PartnerCanvas(species: species, look: .catalog, motion: .still)
    }
}

/// A partner in one look and one moment of its movement: the layers stacked in a square.
struct PartnerCanvas: View {
    let species: Species
    let look: PartnerLook
    let motion: PartnerMotion

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let form = PartnerLayers.form(for: look.growthStage)
            let anchor = PartnerAnchor.of(species, form: form)
            let framing = anchor.map { PartnerFraming(figure: $0.figure, form: form) } ?? .identity
            ZStack(alignment: .topLeading) {
                ZStack {
                    ForEach(PartnerLayers.layers(species, look: look), id: \.name) { layer in
                        Image(layer.name)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .hueRotation(layer.takesColor ? PartnerLayers.hue(for: look.colorIndex) : .zero)
                    }
                }
                .frame(width: side * framing.scale, height: side * framing.scale)
                .offset(x: side * framing.dx, y: side * framing.dy)
                if look.mood == .asleep, let anchor {
                    SleepingZs(anchor: anchor, framing: framing, side: side)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
            // Wider when round, and squashed and lifted around the feet so the partner keeps its volume.
            .scaleEffect(x: look.width * (2 - motion.squash), y: motion.squash, anchor: UnitPoint(x: 0.5, y: PartnerFraming.ground))
            .offset(y: -motion.lift / 100 * side)
            // The long contact shadow of a zoomed-in young form would otherwise spill past its tile.
            .frame(width: side, height: side)
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// Two Z's rising from the head of a sleeping partner.
private struct SleepingZs: View {
    let anchor: PartnerAnchor
    let framing: PartnerFraming
    let side: CGFloat

    var body: some View {
        let top = framing.point(anchor.headCenter[0] + anchor.headRadius * 0.9, anchor.headTop[1])
        let x = top.x * side
        let y = top.y * side
        ZStack(alignment: .topLeading) {
            letter(size: side * 0.09).position(x: x, y: y)
            letter(size: side * 0.06).position(x: x + side * 0.09, y: y - side * 0.09)
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }

    private func letter(size: CGFloat) -> some View {
        Path { p in
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: size, y: 0))
            p.addLine(to: CGPoint(x: 0, y: size))
            p.addLine(to: CGPoint(x: size, y: size))
        }
        .stroke(Color.ink, style: StrokeStyle(lineWidth: max(1.5, size * 0.16), lineCap: .round, lineJoin: .round))
        .frame(width: size, height: size)
    }
}

/// The partner as it moves: it bobs, faster and higher with more energy, and breathes slowly
/// while asleep. With Reduce Motion on it stands still.
struct PartnerFigure: View {
    let species: Species
    let look: PartnerLook
    /// 0 is asleep, 1 is full of energy (`CreatureSnapshot.energy`).
    let energy: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(species: Species, look: PartnerLook, energy: Double = 0.7) {
        self.species = species
        self.look = look
        self.energy = energy
    }

    var body: some View {
        if reduceMotion {
            PartnerCanvas(species: species, look: look, motion: .still)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                PartnerCanvas(
                    species: species, look: look,
                    motion: PartnerMotion(at: timeline.date.timeIntervalSinceReferenceDate, energy: energy, asleep: look.mood == .asleep)
                )
            }
        }
    }
}

/// One moment of the partner's movement, in hundredths of the figure's size.
struct PartnerMotion: Equatable {
    /// How far the partner is off the ground.
    var lift: CGFloat = 0
    /// Height against rest; the width changes the other way, so the partner keeps its volume.
    var squash: CGFloat = 1

    static let still = PartnerMotion()

    init(lift: CGFloat = 0, squash: CGFloat = 1) {
        self.lift = lift
        self.squash = squash
    }

    init(at time: TimeInterval, energy: Double, asleep: Bool) {
        if asleep {
            self.init(squash: 1 + 0.025 * CGFloat(sin(time * 1.2)))
            return
        }
        let energy = min(max(energy, 0), 1)
        let phase = time * (2 + 4 * energy)
        let height = 0.8 + 2.4 * energy
        self.init(lift: CGFloat(height * (0.5 + 0.5 * sin(phase))), squash: 1 + 0.02 * CGFloat(cos(phase)))
    }
}
