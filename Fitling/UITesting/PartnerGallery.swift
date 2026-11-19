#if DEBUG
import SwiftUI
import FitlingCore

/// Every look of one species on one screen, for approving the drawings (TASKS 3.3). Read row by
/// row: the six moods, the workout bonus, lean, half round and fully round, growth stages 0, 2, 3
/// and 4, the four other colours, and the six accessories.
struct PartnerGallery: View {
    @State private var species: Species = .sprout

    init() {}

    static let looks: [PartnerLook] = {
        var looks = CreatureMood.allCases.map { PartnerLook(mood: $0) }
        looks.append(PartnerLook(trainedRecently: true))
        looks += [0, 0.65, 1].map { PartnerLook(bodyShape: $0) }
        looks += [0, 2, 3, 4].map { PartnerLook(growthStage: $0) }
        looks += (1...4).map { PartnerLook(colorIndex: $0) }
        looks += CreatureItem.allCases.map { PartnerLook(items: [$0]) }
        return looks
    }()

    var body: some View {
        VStack(spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                ForEach(Species.allCases, id: \.self) { candidate in
                    Button {
                        species = candidate
                    } label: {
                        NamePlate(candidate.nameKey, fill: candidate.ribbon, edge: candidate == species ? Color.ink : nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("gallery.\(candidate.rawValue)")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: 4), spacing: Spacing.s) {
                ForEach(Self.looks.indices, id: \.self) { index in
                    PartnerCanvas(species: species, look: Self.looks[index], motion: .still)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(Spacing.xs)
                        .background(species.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ground)
        // A container, so the buttons inside keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery")
    }
}
#endif
