import SwiftUI
import FitlingCore

struct AddProductView: View {
    @State private var viewModel: AddProductViewModel
    private let onSaved: (Product) -> Void

    init(viewModel: AddProductViewModel, onSaved: @escaping (Product) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section {
                TextField("product.add.name", text: $viewModel.name)
                    .accessibilityIdentifier("product.add.name")
                TextField("product.add.brand", text: $viewModel.brand)
                TextField("product.add.barcode", text: $viewModel.gtin)
                    .keyboardType(.numberPad)
            }
            .listRowBackground(Color.card)

            Section {
                Picker("portion.unit", selection: $viewModel.isMillilitre) {
                    Text("portion.unit.gram").tag(false)
                    Text("portion.unit.millilitre").tag(true)
                }
                .pickerStyle(.segmented)
                numberField("product.add.kcal", value: $viewModel.kcal, identifier: "product.add.kcal")
                numberField("product.add.protein", value: $viewModel.protein, identifier: "product.add.protein")
                numberField("product.add.carbs", value: $viewModel.carbs, identifier: "product.add.carbs")
                numberField("product.add.fat", value: $viewModel.fat, identifier: "product.add.fat")
            } header: {
                Text("product.add.per100").foregroundStyle(Color.ink).textCase(nil)
            }
            .listRowBackground(Color.card)

            Section {
                numberField("product.add.serving", value: $viewModel.servingSize, identifier: "product.add.serving")
            } footer: {
                Text("product.add.serving.footer").footerStyle()
            }
            .listRowBackground(Color.card)

            Section {
                SubmitButton(title: "product.add.save", isWorking: false) {
                    if let product = viewModel.save() { onSaved(product) }
                }
                .disabled(!viewModel.canSave)
                .accessibilityIdentifier("product.add.save")
                .buttonRow()
            } footer: {
                Text("product.add.rules").footerStyle()
            }
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .navigationTitle("product.add.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func numberField(_ key: LocalizedStringKey, value: Binding<Double?>, identifier: String) -> some View {
        TextField(key, value: value, format: .number)
            .keyboardType(.decimalPad)
            .monospacedDigit()
            .accessibilityIdentifier(identifier)
    }
}
