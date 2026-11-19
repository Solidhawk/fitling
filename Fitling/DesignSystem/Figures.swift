import SwiftUI
import FitlingCore

/// How the four species from PRODUCT.md look: the catalog on the welcome screen, the choice in
/// partner setup and the partner itself.
extension Species {
    /// The main colour of the species: its name plate and its own ribbon.
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

    /// The partner as the catalog shows it.
    var parts: [FigurePart] {
        parts(for: .catalog)
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
        /// Light on top, shadow underneath, and bands such as a scarf: flat tones instead of a
        /// gradient, only inside the body.
        case shading
        /// Eyes, mouth, beak, speckles, accessories.
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

/// A catalog partner: still, as it looks once it has grown a little.
struct FigureView: View {
    let species: Species

    var body: some View {
        PartnerCanvas(species: species, look: .catalog, motion: .still)
    }
}

/// Draws a partner in one look and one moment of its movement.
struct PartnerCanvas: View {
    let species: Species
    let look: PartnerLook
    let motion: PartnerMotion

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: side / 100, y: side / 100)
            context.fill(Path(ellipseIn: FigurePart.groundShadow).applying(look.widening), with: .color(Color.cardShadow))

            // Squashed and lifted around the point under the feet, so the partner stays on its shadow.
            context.translateBy(x: 50, y: FigurePart.baseline - motion.lift)
            context.scaleBy(x: 2 - motion.squash, y: motion.squash)
            context.translateBy(x: -50, y: -FigurePart.baseline)

            let parts = species.parts(for: look)
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

/// The partner as it moves: it bobs, faster and higher with more energy, and breathes slowly
/// while asleep. With Reduce Motion on it stands still.
struct PartnerFigure: View {
    let species: Species
    let look: PartnerLook
    /// 0 is asleep, 1 is full of energy (`CreatureSnapshot.energy`).
    var energy = 0.7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

/// One moment of the partner's movement, in drawing units.
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
