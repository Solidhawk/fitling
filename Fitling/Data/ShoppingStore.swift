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

    func list(_ id: UUID) -> ShoppingList? {
        lists().first { $0.id == id }
    }

    /// The list to show: `preferred` while it is on the device (the list the user joined), else the first by name, made
    /// on the device (also offline) with the user as its owner when there is none.
    func ensureList(named name: String, ownerName: String, preferred: UUID? = nil) -> ShoppingList {
        let existing = lists()
        if let preferred, let kept = existing.first(where: { $0.id == preferred }) { return kept }
        if let first = existing.first { return first }
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

    private func itemModels(of list: ShoppingList) -> [ShoppingItem] {
        let listID = list.id
        return (try? context.fetch(FetchDescriptor<ShoppingItem>(
            predicate: #Predicate<ShoppingItem> { $0.listID == listID && $0.deletedAt == nil }
        ))) ?? []
    }

    /// Unchecked first, in the order of a walk through the shop, then what is in the basket (ShoppingBook.items).
    func items(of list: ShoppingList) -> [ShoppingItem] {
        let all = itemModels(of: list)
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return book(items: all).items().compactMap { byID[$0.id] }
    }

    @discardableResult
    func add(_ name: String, quantity: Double? = nil, unit: String? = nil, aisle: String = "other", to list: ShoppingList) -> ShoppingItem? {
        guard let new = ShoppingBook.newItem(name, quantity: quantity, unit: unit, aisle: aisle) else { return nil }
        return insert(new, source: "manual", into: list)
    }

    @discardableResult
    private func insert(_ new: NewShoppingItem, source: String, into list: ShoppingList) -> ShoppingItem {
        let item = ShoppingItem(id: UUID(), listID: list.id, name: new.name, aisle: new.aisle, source: source, updatedBy: userID, updatedAt: now())
        item.quantity = new.quantity
        item.unit = new.unit
        item.productID = new.productID
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

    /// Puts what this week's menu needs on the list (MenuBook.shoppingLines, ShoppingBook.refill). Items from an
    /// earlier menu are replaced; items the user added stay, and so do menu items already in the basket.
    func fill(_ list: ShoppingList, menu: MenuStore) {
        let ingredients = (try? context.fetch(FetchDescriptor<RecipeIngredient>(predicate: #Predicate<RecipeIngredient> { $0.deletedAt == nil }))) ?? []
        let lines = menu.book().shoppingLines(ingredients: ingredients.map(\.ingredientRow))
        let all = itemModels(of: list)
        let change = book(items: all).refill(with: lines)
        let removed = Set(change.removed)
        for item in all where removed.contains(item.id) {
            item.deletedAt = now()
            item.updatedAt = now()
            item.updatedBy = userID
            item.needsPush = true
        }
        for new in change.added {
            insert(new, source: "menu", into: list)
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

    /// The cheapest offer per unchecked item in the favourite supermarkets, the total per supermarket and the possible
    /// offers to ask about (ShoppingBook.offers). Uncertain matches count only after the user confirmed them.
    func offers(for list: ShoppingList, confirmed: Set<UUID>) -> ShoppingOffers {
        let offers = ((try? context.fetch(FetchDescriptor<Offer>())) ?? []).compactMap(\.offerRow)
        return book(items: itemModels(of: list), offers: offers, confirmed: confirmed).offers()
    }

    /// Everything on this device that FitlingCore reads for the list.
    private func book(items: [ShoppingItem], offers: [OfferRow] = [], confirmed: Set<UUID> = []) -> ShoppingBook {
        ShoppingBook(
            items: items.map(\.itemRow), offers: offers, supermarkets: supermarkets().map { SupermarketRow(id: $0.id, name: $0.name) },
            favoriteSupermarketIDs: favoriteSupermarketIDs(), confirmedOfferIDs: confirmed, today: today
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

// The SwiftData rows as FitlingCore reads them.

extension ShoppingItem {
    var itemRow: ShoppingItemRow {
        ShoppingItemRow(
            id: id, name: name, quantity: quantity, unit: unit, aisle: aisle, productID: productID, isChecked: isChecked, source: source
        )
    }
}

extension Offer {
    /// Nil for an offer whose days cannot be read; it never matches.
    var offerRow: OfferRow? {
        guard let from = Day(isoString: validFrom), let to = Day(isoString: validTo) else { return nil }
        return OfferRow(
            id: id, supermarketID: supermarketID, title: title, brand: brand, gtin: gtin, quantityValue: quantityValue,
            quantityUnit: quantityUnit, priceCents: priceCents, validFrom: from, validTo: to
        )
    }
}

extension RecipeIngredient {
    var ingredientRow: RecipeIngredientRow {
        RecipeIngredientRow(recipeID: recipeID, productID: productID, name: name, quantity: quantity, unit: unit, aisle: aisle, position: position)
    }
}
