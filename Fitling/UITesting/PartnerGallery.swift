#if DEBUG
import SwiftUI
import FitlingCore

/// Every look of one species on one screen, for approving the partners (TASKS 3.3). On top the
/// sixteen species to pick from; below, row by row: the six moods, the workout sweatband, lean,
/// half round and fully round, the six forms, the four other colours, and the six accessories.
struct PartnerGallery: View {
    @State private var species: Species = .bumblebee

    init() {}

    static let looks: [PartnerLook] = {
        var looks = CreatureMood.allCases.map { PartnerLook(mood: $0) }
        looks.append(PartnerLook(trainedRecently: true))
        looks += [0, 0.65, 1].map { PartnerLook(bodyShape: $0) }
        looks += (0..<PartnerLayers.formCount).map { PartnerLook(growthStage: $0) }
        looks += (1..<PartnerLayers.hues.count).map { PartnerLook(colorIndex: $0) }
        looks += CreatureItem.allCases.map { PartnerLook(items: [$0]) }
        return looks
    }()

    var body: some View {
        VStack(spacing: Spacing.s) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 8), spacing: Spacing.xs) {
                ForEach(Species.allCases, id: \.self) { candidate in
                    Button {
                        species = candidate
                    } label: {
                        FigureView(species: candidate)
                            .aspectRatio(1, contentMode: .fit)
                            .background(candidate.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.ink, lineWidth: candidate == species ? 2 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(candidate.name))
                    .accessibilityIdentifier("gallery.\(candidate.rawValue)")
                }
            }
            NamePlate(resource: species.name, fill: species.ribbon)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 5), spacing: Spacing.xs) {
                ForEach(Self.looks.indices, id: \.self) { index in
                    PartnerCanvas(species: species, look: Self.looks[index], motion: .still)
                        .aspectRatio(1, contentMode: .fit)
                        .background(species.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ground)
        // A container, so the buttons inside keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gallery")
    }
}
#endif
