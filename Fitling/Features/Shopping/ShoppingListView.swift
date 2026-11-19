import SwiftUI
import FitlingCore

/// The shopping list, opened from the menu tab.
struct ShoppingListView: View {
    @State private var viewModel: ShoppingViewModel
    @State private var newItem = ""
    @State private var joining = false
    @State private var choosingShops = false
    @State private var confirmingLeave = false

    init(viewModel: ShoppingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("shopping.add.placeholder", text: $newItem)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityIdentifier("shopping.add.field")
                    Button(action: add) {
                        Label("shopping.add", systemImage: "plus.circle.fill").labelStyle(.iconOnly)
                    }
                    .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button {
                    viewModel.fillFromMenu()
                } label: {
                    Label("shopping.fromMenu", systemImage: "frying.pan")
                }
                .accessibilityIdentifier("shopping.fromMenu")
            }
            .listRowBackground(Color.card)

            if viewModel.items.isEmpty {
                Section {
                    Text("shopping.empty").footerStyle()
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(viewModel.items) { item in
                        itemRow(item)
                    }
                    .onDelete { offsets in
                        let items = viewModel.items
                        for index in offsets { viewModel.remove(items[index]) }
                    }
                    if viewModel.items.contains(where: \.isChecked) {
                        Button("shopping.clearChecked", role: .destructive) { viewModel.clearChecked() }
                    }
                }
                .listRowBackground(Color.card)
            }

            offersSection

            Section {
                ForEach(viewModel.members) { member in
                    HStack {
                        Text(verbatim: member.displayName)
                        Spacer()
                        if member.role == "owner" {
                            Text("shopping.owner").font(.footnote).foregroundStyle(Color.inkSoft)
                        }
                    }
                }
                Button {
                    Task { await viewModel.createInvite() }
                } label: {
                    Label("shopping.invite", systemImage: "person.badge.plus")
                }
                Button {
                    joining = true
                } label: {
                    Label("shopping.join", systemImage: "person.2")
                }
                if viewModel.members.count > 1 {
                    Button("shopping.leave", role: .destructive) { confirmingLeave = true }
                }
            } header: {
                Text("shopping.members")
            } footer: {
                Text(viewModel.sharingProblem?.messageKey ?? "shopping.members.footer").footerStyle()
            }
            .listRowBackground(Color.card)
        }
        .foregroundStyle(Color.ink)
        .groundBackground()
        .accessibilityIdentifier("shopping.list")
        .navigationTitle(Text(verbatim: viewModel.list?.name ?? ""))
        .refreshable { await viewModel.refresh() }
        .onAppear { viewModel.reload() }
        .task { await viewModel.refresh() }
        .sheet(isPresented: $joining) {
            JoinListSheet { code, name in await viewModel.join(code: code, name: name) }
        }
        .sheet(isPresented: $choosingShops) {
            SupermarketPicker(viewModel: viewModel)
        }
        .alert(
            "shopping.invite.title",
            isPresented: Binding(get: { viewModel.inviteCode != nil }, set: { if !$0 { viewModel.dismissInvite() } })
        ) {
            Button("shopping.invite.copy") {
                UIPasteboard.general.string = viewModel.inviteCode
                viewModel.dismissInvite()
            }
            Button("common.ok", role: .cancel) { viewModel.dismissInvite() }
        } message: {
            Text("shopping.invite.body \(viewModel.inviteCode ?? "")")
        }
        .confirmationDialog("shopping.leave.title", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("shopping.leave", role: .destructive) { Task { await viewModel.leave() } }
        }
    }

    private func add() {
        viewModel.add(newItem)
        newItem = ""
    }

    private func itemRow(_ item: ShoppingItem) -> some View {
        Button {
            viewModel.toggle(item)
        } label: {
            HStack(spacing: Spacing.m) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: item.name)
                        .strikethrough(item.isChecked)
                        .foregroundStyle(item.isChecked ? Color.inkSoft : Color.ink)
                    if let quantity = item.quantity, let unit = item.unit {
                        Text(verbatim: ShoppingAmount.text(quantity, unit))
                            .font(.footnote)
                            .foregroundStyle(Color.inkSoft)
                    }
                }
                Spacer(minLength: 0)
                if let match = viewModel.cheapest[item.id], !item.isChecked {
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text(Double(match.priceCents) / 100, format: .currency(code: "EUR"))
                            .fontWeight(.heavy)
                            .monospacedDigit()
                        Text(verbatim: viewModel.supermarketName(match.supermarketID))
                            .font(.caption)
                            .foregroundStyle(Color.inkSoft)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
    }

    @ViewBuilder
    private var offersSection: some View {
        Section {
            ForEach(viewModel.totals, id: \.supermarketID) { total in
                HStack {
                    Text(verbatim: viewModel.supermarketName(total.supermarketID))
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text(Double(total.totalCents) / 100, format: .currency(code: "EUR")).fontWeight(.heavy).monospacedDigit()
                        if total.itemsWithoutPrice > 0 {
                            Text("shopping.withoutPrice \(total.itemsWithoutPrice)").font(.caption).foregroundStyle(Color.inkSoft)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(Array(viewModel.uncertain.prefix(5).enumerated()), id: \.offset) { pair in
                let match = pair.element
                if let offer = viewModel.store.offer(match.offerID), let item = viewModel.items.first(where: { $0.id == match.itemID }) {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("shopping.uncertain \(offer.title) \(item.name)").font(.footnote)
                        }
                        Spacer()
                        Button("shopping.confirm") { viewModel.confirm(match) }
                            .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                choosingShops = true
            } label: {
                Label("shopping.shops", systemImage: "cart")
            }
        } header: {
            Text("shopping.offers")
        } footer: {
            Text("shopping.offers.footer").footerStyle()
        }
        .listRowBackground(Color.card)
    }
}

enum ShoppingAmount {
    static func text(_ quantity: Double, _ unit: String) -> String {
        let value = quantity.formatted(.number.precision(.fractionLength(0...2)))
        switch unit {
        case "g": return "\(value) \(UnitMass.grams.symbol)"
        case "ml": return "\(value) \(UnitVolume.milliliters.symbol)"
        case "tbsp": return String(localized: "menu.unit.tbsp \(value)")
        case "tsp": return String(localized: "menu.unit.tsp \(value)")
        default: return String(localized: "menu.unit.piece \(value)")
        }
    }
}

/// A code from someone else, and the name the other members will see.
private struct JoinListSheet: View {
    let onJoin: (String, String) async -> Bool
    @State private var code = ""
    @State private var name = ""
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    init(onJoin: @escaping (String, String) async -> Bool) {
        self.onJoin = onJoin
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("shopping.join.code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("shopping.join.name", text: $name)
                } footer: {
                    Text("shopping.join.footer").footerStyle()
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle("shopping.join")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("shopping.join.confirm") {
                        working = true
                        Task {
                            if await onJoin(code, name) { dismiss() }
                            working = false
                        }
                    }
                    .disabled(working || code.trimmingCharacters(in: .whitespaces).count < 6 || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// The supermarkets whose offers are shown.
private struct SupermarketPicker: View {
    let viewModel: ShoppingViewModel
    @State private var favorites: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ShoppingViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            List {
                let supermarkets = viewModel.store.supermarkets()
                if supermarkets.isEmpty {
                    Text("shopping.shops.empty").footerStyle().listRowBackground(Color.clear)
                }
                ForEach(supermarkets) { shop in
                    Toggle(isOn: Binding(
                        get: { favorites.contains(shop.id) },
                        set: { isOn in
                            if isOn { favorites.insert(shop.id) } else { favorites.remove(shop.id) }
                            Task { await viewModel.setFavorite(shop.id, isOn) }
                        }
                    )) {
                        Text(verbatim: shop.name)
                    }
                    .tint(Color.sprout)
                }
                .listRowBackground(Color.card)
            }
            .foregroundStyle(Color.ink)
            .groundBackground()
            .navigationTitle("shopping.shops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.ok") { dismiss() }
                }
            }
            .onAppear { favorites = Set(viewModel.store.favoriteSupermarketIDs()) }
        }
    }
}

extension SharingError {
    var messageKey: LocalizedStringKey {
        switch self {
        case .network: "common.connection.body"
        case .invalidInvite: "shopping.error.invalidInvite"
        case .listFull: "shopping.error.listFull"
        case .rejected: "error.server"
        }
    }
}
