import SwiftUI
import FitlingCore

/// The partner choice: the sixteen species, then name, colour and voice with a preview of how the
/// partner starts out.
struct PartnerSetupView: View {
    @State private var viewModel: PartnerSetupViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let onFinished: @MainActor (Creature) async -> Void

    init(viewModel: PartnerSetupViewModel, onFinished: @escaping @MainActor (Creature) async -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Three in a row, so nearly all sixteen fit on one screen and can be compared; two at the
                    // accessibility sizes, where the names need the room.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.s), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3), spacing: Spacing.s) {
                        ForEach(Species.allCases, id: \.self) { species in
                            speciesButton(species)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("partner.setup.intro")
                        .font(.body)
                        .foregroundStyle(Color.ink)
                        .textCase(nil)
                        .padding(.bottom, Spacing.s)
                }

                if let species = viewModel.species {
                    Section {
                        TextField(text: $viewModel.name, prompt: Text(species.name)) {
                            Text("partner.setup.name")
                        }
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("partner.setup.name")
                        .onChange(of: viewModel.name) { _, name in
                            let limited = PartnerSetupViewModel.limited(name)
                            if limited != name { viewModel.name = limited }
                        }
                    } header: {
                        preview(species)
                    } footer: {
                        Text("partner.setup.name.footer").footerStyle()
                    }
                    .listRowBackground(Color.card)

                    Section("partner.setup.color") {
                        ColorSwatches(species: species, count: viewModel.colorCount, selection: $viewModel.colorIndex)
                    }
                    .listRowBackground(Color.card)

                    Section {
                        Picker("partner.setup.tone", selection: $viewModel.tone) {
                            ForEach(MessageTone.allCases, id: \.self) { tone in
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(tone.titleKey).foregroundStyle(Color.ink)
                                    Text(tone.sampleKey).font(.footnote).foregroundStyle(Color.inkSoft)
                                }
                                .tag(tone)
                            }
                        }
                        .pickerStyle(.inline)
                        .tint(Color.ink)
                        .labelsHidden()
                    } header: {
                        Text("partner.setup.tone")
                    } footer: {
                        Text("partner.setup.tone.footer").footerStyle()
                    }
                    .listRowBackground(Color.card)
                }
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .accessibilityIdentifier("partner.setup.list")
            .navigationTitle("partner.setup.title")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    if let creature = viewModel.save() {
                        Task { await onFinished(creature) }
                    }
                } label: {
                    Text("partner.setup.done")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSave)
                .accessibilityIdentifier("partner.setup.done")
                .padding(Spacing.l)
                .background(Color.ground)
            }
        }
    }

    private func speciesButton(_ species: Species) -> some View {
        let selected = viewModel.species == species
        return Button {
            viewModel.choose(species, defaultName: species.displayName)
        } label: {
            // The figure fills the tile; the name sits under it in the species' own colour.
            VStack(spacing: Spacing.xs) {
                FigureView(species: species)
                    .aspectRatio(1, contentMode: .fit)
                Text(species.name)
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(Color.onRibbon)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 2)
                    .background(species.ribbon, in: Capsule())
            }
            .padding(Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(species.tint, in: RoundedRectangle(cornerRadius: Radius.card * 0.6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card * 0.6, style: .continuous)
                    .strokeBorder(Color.ink, lineWidth: selected ? 3 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(species.name))
        .accessibilityHint(Text(species.note))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("partner.setup.species.\(species.rawValue)")
    }

    /// How the partner starts: small, at the first growth stage, happy to meet the user.
    private func preview(_ species: Species) -> some View {
        VStack(spacing: Spacing.s) {
            PartnerFigure(species: species, look: PartnerLook(colorIndex: viewModel.colorIndex, mood: .happy, growthStage: 0), energy: 0.8)
                .frame(width: 140, height: 140)
            NamePlate(verbatim: viewModel.cleanedName.isEmpty ? species.displayName : viewModel.cleanedName, fill: species.ribbon)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
        .background(species.tint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.horizontal, -Spacing.l)
        .padding(.bottom, Spacing.s)
        .textCase(nil)
        .accessibilityHidden(true)
    }
}

/// Round swatches of the partner's body colours. Colours past `count` are locked and show the
/// level that unlocks them.
struct ColorSwatches: View {
    let species: Species
    let count: Int
    @Binding var selection: Int
    let unlockLevels: [Int]
    @ScaledMetric private var size: CGFloat = 40

    init(species: Species, count: Int, selection: Binding<Int>, unlockLevels: [Int] = []) {
        self.species = species
        self.count = count
        _selection = selection
        self.unlockLevels = unlockLevels
    }

    var body: some View {
        HStack(spacing: Spacing.m) {
            ForEach(0..<(count + unlockLevels.count), id: \.self) { index in
                let locked = index >= count
                Button {
                    selection = index
                } label: {
                    ZStack {
                        Circle().fill(species.ribbon).hueRotation(PartnerLayers.hue(for: index))
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.onRibbon)
                        }
                    }
                    .frame(width: size, height: size)
                    .padding(3)
                    .overlay {
                        Circle().strokeBorder(Color.ink, lineWidth: selection == index ? 3 : 0)
                    }
                }
                .buttonStyle(.plain)
                .disabled(locked)
                .accessibilityLabel(locked
                    ? Text("partner.color.locked \(index + 1) \(unlockLevels[index - count])")
                    : Text("partner.color \(index + 1)"))
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
    }
}

extension MessageTone {
    var titleKey: LocalizedStringKey {
        switch self {
        case .sweet: "partner.tone.sweet"
        case .funny: "partner.tone.funny"
        case .coach: "partner.tone.coach"
        }
    }

    /// One reminder in this voice, so the choice is heard rather than described.
    var sampleKey: LocalizedStringKey {
        switch self {
        case .sweet: "creature.message.hungry.sweet.1"
        case .funny: "creature.message.hungry.funny.1"
        case .coach: "creature.message.hungry.coach.1"
        }
    }
}
