import Foundation
import SwiftData
import FitlingCore

/// The shopping lists the user is a member of, their items and the offers that match them
/// (TASKS 6.2, 6.7).
@MainActor
struct ShoppingStore {
    let context: ModelContext
    let userID: UUID
    var timeZone: TimeZone = .current
    var now: () -> Date = Date.init
    var language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "nl"

    var today: Day {
        Day(now(), timeZone: timeZone)
    }

    // MARK: Lists

    func lists() -> [ShoppingList] {
        (try? context.fetch(FetchDescriptor<ShoppingList>(
            predicate: #Predicate<ShoppingList> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.name)]
        ))) ?? []
    }

    /// The first list, made on the device (also offline) with the user as its owner when there is none.
    func ensureList(named name: String, ownerName: String) -> ShoppingList {
        if let first = lists().first { return first }
        let list = ShoppingList(id: UUID(), name: String(name.prefix(60)), createdBy: userID, updatedAt: now())
        context.insert(list)
        context.insert(ShoppingListMember(listID: list.id, userID: userID, role: "owner", displayName: String(ownerName.prefix(40)), joinedAt: now()))
        try? context.save()
        return list
    }

    func members(of list: ShoppingList) -> [ShoppingListMember] {
        let listID = list.id
        return (try? context.fetch(FetchDescriptor<ShoppingListMember>(
            predicate: #Predicate<ShoppingListMember> { $0.listID == listID },
            sortBy: [SortDescriptor(\.joinedAt)]
        ))) ?? []
    }

    /// Owner rows made on this device that the server has not seen yet.
    func unsentMembers() -> [ShoppingListMember] {
        (try? context.fetch(FetchDescriptor<ShoppingListMember>(predicate: #Predicate<ShoppingListMember> { $0.needsPush }))) ?? []
    }

    /// Takes over the members the server knows for a list.
    func replaceMembers(of listID: UUID, with records: [ListMemberRecord]) {
        let local = (try? context.fetch(FetchDescriptor<ShoppingListMember>(predicate: #Predicate<ShoppingListMember> { $0.listID == listID }))) ?? []
        let known = Set(records.map(\.userID))
        for member in local where !known.contains(member.userID) && !member.needsPush {
            context.delete(member)
        }
        for record in records {
            if let member = local.first(where: { $0.userID == record.userID }) {
                member.role = record.role
                member.displayName = record.displayName
                member.needsPush = false
            } else {
                let member = ShoppingListMember(listID: listID, userID: record.userID, role: record.role, displayName: record.displayName, joinedAt: now())
                member.needsPush = false
                context.insert(member)
            }
        }
        try? context.save()
    }

    /// After leaving: the list and its items go from this device.
    func forget(_ list: ShoppingList) {
        let listID = list.id
        for item in (try? context.fetch(FetchDescriptor<ShoppingItem>(predicate: #Predicate<ShoppingItem> { $0.listID == listID }))) ?? [] {
            context.delete(item)
        }
        for member in members(of: list) { context.delete(member) }
        context.delete(list)
        try? context.save()
    }

    // MARK: Items

    /// Unchecked first, in the order of a walk through the shop, then what is in the basket.
    func items(of list: ShoppingList) -> [ShoppingItem] {
        let listID = list.id
        let all = (try? context.fetch(FetchDescriptor<ShoppingItem>(
            predicate: #Predicate<ShoppingItem> { $0.listID == listID && $0.deletedAt == nil }
        ))) ?? []
        let order = Dictionary(uniqueKeysWithValues: ShoppingListBuilder.aisleOrder.enumerated().map { ($1, $0) })
        return all.sorted { lhs, rhs in
            if lhs.isChecked != rhs.isChecked { return !lhs.isChecked }
            let left = order[lhs.aisle] ?? order.count
            let right = order[rhs.aisle] ?? order.count
            if left != right { return left < right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    @discardableResult
    func add(_ name: String, quantity: Double? = nil, unit: String? = nil, aisle: String = "other", to list: ShoppingList) -> ShoppingItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = ShoppingItem(id: UUID(), listID: list.id, name: String(trimmed.prefix(120)), aisle: aisle, source: "manual", updatedBy: userID, updatedAt: now())
        item.quantity = quantity.flatMap { $0 > 0 ? $0 : nil }
        item.unit = item.quantity == nil ? nil : unit
        context.insert(item)
        try? context.save()
        return item
    }

    func toggle(_ item: ShoppingItem) {
        item.isChecked.toggle()
        touch(item)
    }

    func remove(_ item: ShoppingItem) {
        item.deletedAt = now()
        touch(item)
    }

    /// Takes everything in the basket off the list.
    func clearChecked(of list: ShoppingList) {
        for item in items(of: list) where item.isChecked {
            item.deletedAt = now()
            item.updatedAt = now()
            item.updatedBy = userID
            item.needsPush = true
        }
        try? context.save()
    }

    /// Puts what the week menu needs on the list. Items from an earlier menu are replaced;
    /// items the user added stay, and so do menu items already in the basket.
    func fill(_ list: ShoppingList, from entries: [MealPlanEntry], menu: MenuStore) {
        for item in items(of: list) where item.source == "menu" && !item.isChecked {
            item.deletedAt = now()
            item.updatedAt = now()
            item.updatedBy = userID
            item.needsPush = true
        }
        let languages = [language] + Locale.preferredLanguages
        let uses = entries.filter { $0.loggedEntryID == nil }.compactMap { entry -> PlannedRecipeUse? in
            guard let recipe = menu.recipe(entry.recipeID) else { return nil }
            return PlannedRecipeUse(
                recipeServings: recipe.servings, plannedServings: entry.servings,
                ingredients: menu.ingredients(of: recipe).map { ingredient in
                    MenuIngredient(
                        productID: ingredient.productID, name: ingredient.name.text(preferring: languages),
                        quantity: ingredient.quantity, unit: ingredient.unit, aisle: ingredient.aisle
                    )
                }
            )
        }
        for line in ShoppingListBuilder.lines(for: uses) {
            let item = ShoppingItem(id: UUID(), listID: list.id, name: String(line.name.prefix(120)), aisle: line.aisle, source: "menu", updatedBy: userID, updatedAt: now())
            item.quantity = line.quantity > 0 ? line.quantity : nil
            item.unit = item.quantity == nil ? nil : line.unit
            item.productID = line.productID
            context.insert(item)
        }
        try? context.save()
    }

    // MARK: Supermarkets and offers

    func supermarkets() -> [Supermarket] {
        (try? context.fetch(FetchDescriptor<Supermarket>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    func favoriteSupermarketIDs() -> [String] {
        let userID = userID
        return ((try? context.fetch(FetchDescriptor<FavoriteSupermarket>(
            predicate: #Predicate<FavoriteSupermarket> { $0.userID == userID && $0.deletedAt == nil }
        ))) ?? []).map(\.supermarketID).sorted()
    }

    func setFavorite(_ supermarketID: String, _ isFavorite: Bool) {
        let userID = userID
        let existing = (try? context.fetch(FetchDescriptor<FavoriteSupermarket>(
            predicate: #Predicate<FavoriteSupermarket> { $0.userID == userID && $0.supermarketID == supermarketID }
        ))) ?? []
        if isFavorite {
            if let row = existing.first {
                guard row.deletedAt != nil else { return }
                row.deletedAt = nil
                row.updatedAt = now()
                row.needsPush = true
            } else {
                context.insert(FavoriteSupermarket(id: UUID(), userID: userID, supermarketID: supermarketID, updatedAt: now()))
            }
        } else {
            for row in existing where row.deletedAt == nil {
                row.deletedAt = now()
                row.updatedAt = now()
                row.needsPush = true
            }
        }
        try? context.save()
    }

    /// Replaces the supermarkets and offers on the device with what the server has now.
    func store(supermarkets: [SupermarketRecord], offers: [OfferRecord]) {
        for old in (try? context.fetch(FetchDescriptor<Supermarket>())) ?? [] { context.delete(old) }
        for record in supermarkets { context.insert(Supermarket(id: record.id, name: record.name, updatedAt: now())) }
        for old in (try? context.fetch(FetchDescriptor<Offer>())) ?? [] { context.delete(old) }
        for record in offers {
            let offer = Offer(
                id: record.id, supermarketID: record.supermarketID, externalID: record.externalID, title: record.title,
                searchTitle: record.searchTitle, priceCents: record.priceCents, validFrom: record.validFrom.isoString,
                validTo: record.validTo.isoString, fetchedAt: now()
            )
            offer.brand = record.brand
            offer.gtin = record.gtin
            offer.quantityValue = record.quantityValue
            offer.quantityUnit = record.quantityUnit
            offer.regularPriceCents = record.regularPriceCents
            offer.promoLabel = record.promoLabel
            offer.imageURL = record.imageURL
            context.insert(offer)
        }
        try? context.save()
    }

    /// When the offers on the device were fetched; nil when there are none.
    func offersFetchedAt() -> Date? {
        var descriptor = FetchDescriptor<Offer>(sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.fetchedAt
    }

    /// The cheapest offer per unchecked item in the favourite supermarkets, and the total per
    /// supermarket. Uncertain matches count only after the user confirmed them. `titles` holds the title of
    /// every matched offer.
    func offerSummary(
        for list: ShoppingList, confirmed: Set<UUID>
    ) -> (perItem: [UUID: OfferMatch], totals: [StoreTotal], matches: [OfferMatch], titles: [UUID: String]) {
        let favorites = Set(favoriteSupermarketIDs())
        let items = self.items(of: list).filter { !$0.isChecked }
        let offers = ((try? context.fetch(FetchDescriptor<Offer>())) ?? []).filter { favorites.contains($0.supermarketID) }
        let matchingItems = items.map { ListItemForMatching(id: $0.id, name: $0.name, quantity: $0.quantity, unit: $0.unit) }
        let matchingOffers = offers.compactMap { offer -> OfferForMatching? in
            guard let from = Day(isoString: offer.validFrom), let to = Day(isoString: offer.validTo) else { return nil }
            return OfferForMatching(
                id: offer.id, supermarketID: offer.supermarketID, title: offer.title, brand: offer.brand, gtin: offer.gtin,
                quantityValue: offer.quantityValue, quantityUnit: offer.quantityUnit, priceCents: offer.priceCents, validFrom: from, validTo: to
            )
        }
        let names = Set(supermarkets().filter { favorites.contains($0.id) }.map(\.name))
        let matches = OfferMatcher.matches(items: matchingItems, offers: matchingOffers, on: today, ignoredWords: names)
        let matched = Set(matches.map(\.offerID))
        return (
            OfferMatcher.cheapestPerItem(matches, confirmedOfferIDs: confirmed),
            OfferMatcher.storeTotals(itemIDs: items.map(\.id), matches: matches, confirmedOfferIDs: confirmed),
            matches,
            Dictionary(uniqueKeysWithValues: offers.filter { matched.contains($0.id) }.map { ($0.id, $0.title) })
        )
    }

    func offer(_ id: UUID) -> Offer? {
        var descriptor = FetchDescriptor<Offer>(predicate: #Predicate<Offer> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func touch(_ item: ShoppingItem) {
        item.updatedAt = now()
        item.updatedBy = userID
        item.needsPush = true
        try? context.save()
    }
}
