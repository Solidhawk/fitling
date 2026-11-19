import SwiftUI
import FitlingCore

/// Where the app gets products from: the Edge Function for barcodes and the shared cache for
/// names. Real in the app, fakes in the tests and the UI test.
struct FoodServices {
    let source: any ProductSource
    let search: any ProductSearching
}

struct LogFoodView: View {
    @State private var viewModel: LogFoodViewModel
    @State private var path: [LogStep] = []
    @State private var scanning = false
    @Environment(\.dismiss) private var dismiss
    private let onLogged: () -> Void

    enum LogStep: Hashable {
        case portion(UUID)
        case addProduct(gtin: String?)
    }

    init(viewModel: LogFoodViewModel, onLogged: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onLogged = onLogged
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if viewModel.query.isEmpty {
                    Section {
                        Button {
                            scanning = true
                        } label: {
                            Label("log.scan", systemImage: "barcode.viewfinder")
                        }
                        .accessibilityIdentifier("log.scan")
                        Button {
                            path.append(.addProduct(gtin: nil))
                        } label: {
                            Label("log.ownProduct", systemImage: "square.and.pencil")
                        }
                    }
                    .listRowBackground(Color.card)
                    productSection("log.favorites", viewModel.favorites)
                    productSection("log.recent", viewModel.recent)
                    if viewModel.favorites.isEmpty && viewModel.recent.isEmpty {
                        Section {
                            Text("log.empty").footerStyle()
                        }
                        .listRowBackground(Color.clear)
                    }
                } else {
                    productSection("log.results.device", viewModel.localResults)
                    productSection("log.results.online", viewModel.onlineResults)
                    if viewModel.isSearchingOnline {
                        ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                    } else if viewModel.localResults.isEmpty && viewModel.onlineResults.isEmpty {
                        Section {
                            Text("log.results.none").footerStyle()
                            Button("log.ownProduct") { path.append(.addProduct(gtin: nil)) }
                        }
                        .listRowBackground(Color.card)
                    }
                }
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle(viewModel.meal.titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: Text("log.search.prompt"))
            .task(id: viewModel.query) {
                // Waits for a pause in typing, so every keystroke does not search online.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await viewModel.runSearch()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
            .navigationDestination(for: LogStep.self) { step in
                switch step {
                case let .portion(id):
                    if let product = viewModel.product(id) {
                        PortionView(
                            viewModel: PortionViewModel(product: product, diary: viewModel.diary, meal: viewModel.meal, day: viewModel.day),
                            onSaved: onLogged
                        )
                    }
                case let .addProduct(gtin):
                    AddProductView(viewModel: AddProductViewModel(diary: viewModel.diary, gtin: gtin)) { product in
                        path.removeLast()
                        path.append(.portion(product.id))
                    }
                }
            }
            .sheet(isPresented: $scanning) {
                ScanSheet { code in
                    Task { await viewModel.handleScan(code) }
                }
            }
            .onChange(of: viewModel.scanOutcome) { _, outcome in
                guard let outcome else { return }
                if case let .product(id) = outcome {
                    scanning = false
                    path.append(.portion(id))
                    viewModel.clearScanOutcome()
                }
            }
            .alert(
                "scan.unknown.title",
                isPresented: Binding(get: { unknownGtin != nil }, set: { if !$0 { viewModel.clearScanOutcome() } })
            ) {
                Button("scan.unknown.add") {
                    let gtin = unknownGtin
                    scanning = false
                    viewModel.clearScanOutcome()
                    path.append(.addProduct(gtin: gtin))
                }
                Button("common.cancel", role: .cancel) { viewModel.clearScanOutcome() }
            } message: {
                Text("scan.unknown.body")
            }
            .alert(
                "common.connection.title",
                isPresented: Binding(get: { offlineGtin != nil }, set: { if !$0 { viewModel.clearScanOutcome() } })
            ) {
                Button("common.ok", role: .cancel) { viewModel.clearScanOutcome() }
            } message: {
                Text("scan.offline.body")
            }
        }
    }

    private var unknownGtin: String? {
        if case let .unknown(gtin) = viewModel.scanOutcome { return gtin }
        return nil
    }

    private var offlineGtin: String? {
        if case let .unavailable(gtin) = viewModel.scanOutcome { return gtin }
        return nil
    }

    @ViewBuilder
    private func productSection(_ titleKey: LocalizedStringKey, _ products: [Product]) -> some View {
        if !products.isEmpty {
            Section(titleKey) {
                ForEach(products) { product in
                    Button {
                        path.append(.portion(product.id))
                    } label: {
                        ProductRow(product: product)
                    }
                }
            }
            .listRowBackground(Color.card)
        }
    }
}

struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(product.name.text(preferring: Locale.preferredLanguages))
                    .foregroundStyle(Color.ink)
                if let brand = product.brand {
                    Text(brand).font(.footnote).foregroundStyle(Color.inkSoft)
                }
            }
            Spacer()
            if let kcal = product.kcal100 {
                Text("log.kcalPer100 \(kcal.formatted(.number.precision(.fractionLength(0)))) \(product.quantityUnit)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Color.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
