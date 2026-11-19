import SwiftUI
import FitlingCore

struct PortionView: View {
    @State private var viewModel: PortionViewModel
    @State private var isFavorite: Bool
    private let onSaved: () -> Void

    init(viewModel: PortionViewModel, onSaved: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        _isFavorite = State(initialValue: viewModel.isFavorite)
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: Spacing.m) {
                    ProductThumbnail(imageURL: viewModel.product.imageURL, name: viewModel.name, size: 64)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(viewModel.name).font(.headline.weight(.heavy))
                        if let brand = viewModel.product.brand {
                            Text(brand).font(.footnote).foregroundStyle(Color.inkSoft)
                        }
                    }
                }
            }
            .listRowBackground(Color.card)

            Section {
                if viewModel.units.count > 1 {
                    Picker("portion.unit", selection: $viewModel.unit) {
                        ForEach(viewModel.units, id: \.self) { unit in
                            Text(unit.titleKey).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                TextField("portion.quantity", value: $viewModel.quantity, format: .number)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityIdentifier("portion.quantity")
            } footer: {
                if viewModel.unit == .serving, let label = servingDescription {
                    Text(label).footerStyle()
                }
            }
            .listRowBackground(Color.card)

            if viewModel.needsKcal {
                Section {
                    TextField(kcalFieldKey, value: $viewModel.kcalOnPackage, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("portion.kcal")
                } footer: {
                    Text("portion.kcal.why").footerStyle()
                }
                .listRowBackground(Color.card)
            }

            if let preview = viewModel.preview {
                Section {
                    LabeledContent("targets.kcal.label") { Text(energy(preview.kcal)).fontWeight(.heavy).monospacedDigit() }
                    macroRow("targets.protein", preview.proteinG)
                    macroRow("targets.carbs", preview.carbsG)
                    macroRow("targets.fat", preview.fatG)
                } footer: {
                    if viewModel.hasUnknownMacros {
                        Text("portion.unknownMacros").footerStyle()
                    }
                }
                .listRowBackground(Color.card)
            }

            Section {
                SubmitButton(title: "portion.save", isWorking: false) {
                    if viewModel.save() != nil { onSaved() }
                }
                .disabled(!viewModel.canSave)
                .accessibilityIdentifier("portion.save")
                .buttonRow()
            }
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .accessibilityIdentifier("portion.form")
        .navigationTitle(viewModel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.toggleFavorite()
                    isFavorite = viewModel.isFavorite
                } label: {
                    Label(favoriteKey, systemImage: isFavorite ? "star.fill" : "star")
                }
            }
        }
    }

    // Typed keys, so a choice between two keys is still looked up in the String Catalog.
    private var kcalFieldKey: LocalizedStringKey {
        viewModel.product.quantityUnit == "ml" ? "portion.kcal.field.ml" : "portion.kcal.field.gram"
    }

    private var favoriteKey: LocalizedStringKey {
        isFavorite ? "portion.favorite.remove" : "portion.favorite.add"
    }

    private var servingDescription: String? {
        guard let size = viewModel.product.servingSize else { return nil }
        let amount = "\(size.formatted(.number.precision(.fractionLength(0...1)))) \(viewModel.product.quantityUnit)"
        if let label = viewModel.product.servingLabel {
            return String(localized: "portion.serving.labelled \(label) \(amount)")
        }
        return String(localized: "portion.serving.size \(amount)")
    }

    private func macroRow(_ key: LocalizedStringKey, _ grams: Double?) -> some View {
        LabeledContent(key) {
            if let grams {
                Text(Measurement(value: grams, unit: UnitMass.grams), format: .measurement(width: .abbreviated, usage: .asProvided))
                    .monospacedDigit()
            } else {
                Text("portion.unknown").foregroundStyle(Color.inkSoft)
            }
        }
    }

    private func energy(_ kcal: Double) -> String {
        Measurement(value: kcal.rounded(), unit: UnitEnergy.kilocalories).formatted(.measurement(width: .abbreviated, usage: .food))
    }
}

extension QuantityUnit {
    var titleKey: LocalizedStringKey {
        switch self {
        case .gram: "portion.unit.gram"
        case .millilitre: "portion.unit.millilitre"
        case .serving: "portion.unit.serving"
        }
    }
}
