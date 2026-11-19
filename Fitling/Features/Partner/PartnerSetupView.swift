import SwiftUI
import FitlingCore

/// The partner choice: the four species, then name, colour and voice with a preview of how the
/// partner starts out.
struct PartnerSetupView: View {
    @State private var viewModel: PartnerSetupViewModel
    private let onFinished: @MainActor (Creature) async -> Void

    init(viewModel: PartnerSetupViewModel, onFinished: @escaping @MainActor (Creature) async -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.m), GridItem(.flexible(), spacing: Spacing.m)], spacing: Spacing.m) {
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
                        TextField(text: $viewModel.name, prompt: Text(species.nameKey)) {
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
            VStack(spacing: Spacing.s) {
                FigureView(species: species)
                    .frame(width: 72, height: 72)
                NamePlate(species.nameKey, fill: species.ribbon)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(species.tint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.ink, lineWidth: selected ? 3 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(species.nameKey))
        .accessibilityHint(Text(species.noteKey))
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
                        Circle().fill(species.palette(index).body)
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

extension Species {
    /// The species name in the user's language, as a starting name for the partner.
    var displayName: String {
        switch self {
        case .sprout: String(localized: "creature.sprout.name")
        case .ember: String(localized: "creature.ember.name")
        case .pip: String(localized: "creature.pip.name")
        case .pebble: String(localized: "creature.pebble.name")
        }
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
