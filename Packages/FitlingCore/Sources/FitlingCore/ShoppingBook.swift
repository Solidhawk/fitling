#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

// The shopping list of one user and the offers of their supermarkets, and what the app and the web read and decide
// from them: the order of the items, what a list filled from the menu takes off and puts on, which offers belong to
// which item, the total per shop and the possible offers to ask about. The app builds this from SwiftData, the web
// from Supabase; both write their own rows. Only rows that are not deleted.

/// An item on the list (`shopping_items`).
public struct ShoppingItemRow: Sendable, Equatable, Codable {
    public var id: UUID
    public var name: String
    public var quantity: Double?
    public var unit: String?
    public var aisle: String
    public var productID: UUID?
    public var isChecked: Bool
    /// "manual", or "menu" for what the week menu put on the list.
    public var source: String

    public init(
        id: UUID, name: String, quantity: Double? = nil, unit: String? = nil, aisle: String = "other", productID: UUID? = nil,
        isChecked: Bool = false, source: String = "manual"
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle
        self.productID = productID
        self.isChecked = isChecked
        self.source = source
    }
}

/// An offer the backend collected (`offers`), as far as matching needs it.
public struct OfferRow: Sendable, Equatable, Codable {
    public var id: UUID
    public var supermarketID: String
    public var title: String
    public var brand: String?
    public var gtin: String?
    public var quantityValue: Double?
    public var quantityUnit: String?
    public var priceCents: Int
    public var validFrom: Day
    public var validTo: Day

    public init(
        id: UUID, supermarketID: String, title: String, brand: String? = nil, gtin: String? = nil, quantityValue: Double? = nil,
        quantityUnit: String? = nil, priceCents: Int, validFrom: Day, validTo: Day
    ) {
        self.id = id
        self.supermarketID = supermarketID
        self.title = title
        self.brand = brand
        self.gtin = gtin
        self.quantityValue = quantityValue
        self.quantityUnit = quantityUnit
        self.priceCents = priceCents
        self.validFrom = validFrom
        self.validTo = validTo
    }
}

public struct SupermarketRow: Sendable, Equatable, Codable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One line of a recipe (`recipe_ingredients`), for what the week menu needs.
public struct RecipeIngredientRow: Sendable, Equatable, Codable {
    public var recipeID: UUID
    public var productID: UUID?
    public var name: LocalizedText
    public var quantity: Double
    public var unit: String
    public var aisle: String
    public var position: Int

    public init(recipeID: UUID, productID: UUID?, name: LocalizedText, quantity: Double, unit: String, aisle: String, position: Int) {
        self.recipeID = recipeID
        self.productID = productID
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle
        self.position = position
    }
}

/// An item as it goes on the list: a name of at most 120 characters, and an amount only with a quantity.
public struct NewShoppingItem: Sendable, Equatable, Codable {
    public var name: String
    public var quantity: Double?
    public var unit: String?
    public var aisle: String
    public var productID: UUID?

    public init(name: String, quantity: Double?, unit: String?, aisle: String, productID: UUID?) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle
        self.productID = productID
    }
}

/// What filling the list from the menu does: the menu items that go, the items that come.
public struct ShoppingChange: Sendable, Equatable {
    public var removed: [UUID]
    public var added: [NewShoppingItem]
}

/// A possible offer the user can say is right: asked once per item name and offer title, with the shops that have
/// that offer, by name. Saying yes confirms the offer in each of them.
public struct OfferQuestion: Sendable, Equatable, Identifiable {
    public var itemName: String
    public var offerTitle: String
    public var supermarketIDs: [String]
    public var offerIDs: Set<UUID>

    public var id: String { itemName.lowercased() + "|" + offerTitle }
}

/// The offers of the favourite supermarkets for the items not in the basket yet.
public struct ShoppingOffers: Sendable, Equatable {
    /// The cheapest usable offer per item.
    public var cheapest: [UUID: OfferMatch]
    public var totals: [StoreTotal]
    /// Possible offers for items without a price yet, in the order the matcher ranked them.
    public var questions: [OfferQuestion]
}

public struct ShoppingBook: Sendable {
    public let today: Day
    private let itemRows: [ShoppingItemRow]
    private let offerRows: [OfferRow]
    private let supermarketRows: [SupermarketRow]
    private let favorites: Set<String>
    private let confirmed: Set<UUID>

    public init(
        items: [ShoppingItemRow], offers: [OfferRow], supermarkets: [SupermarketRow], favoriteSupermarketIDs: [String],
        confirmedOfferIDs: Set<UUID>, today: Day
    ) {
        itemRows = items
        offerRows = offers
        supermarketRows = supermarkets
        favorites = Set(favoriteSupermarketIDs)
        confirmed = confirmedOfferIDs
        self.today = today
    }

    /// Unchecked first, in the order of a walk through the shop, then what is in the basket.
    public func items() -> [ShoppingItemRow] {
        let order = Dictionary(uniqueKeysWithValues: ShoppingListBuilder.aisleOrder.enumerated().map { ($1, $0) })
        return itemRows.sorted { lhs, rhs in
            if lhs.isChecked != rhs.isChecked { return !lhs.isChecked }
            let left = order[lhs.aisle] ?? order.count
            let right = order[rhs.aisle] ?? order.count
            if left != right { return left < right }
            return TrainingRecords.inOrder(lhs.name, rhs.name)
        }
    }

    /// The name of a supermarket, or its id while its name is not known.
    public func supermarketName(_ id: String) -> String {
        supermarketRows.first { $0.id == id }?.name ?? id
    }

    /// The cheapest offer per unchecked item in the favourite supermarkets, the total per supermarket and the possible
    /// offers to ask about. Uncertain matches count only after the user confirmed them; the shops' names say nothing
    /// about a product.
    public func offers() -> ShoppingOffers {
        let unchecked = items().filter { !$0.isChecked }
        let offers = offerRows.filter { favorites.contains($0.supermarketID) }
        let matches = OfferMatcher.matches(
            items: unchecked.map { ListItemForMatching(id: $0.id, name: $0.name, quantity: $0.quantity, unit: $0.unit) },
            offers: offers.map {
                OfferForMatching(
                    id: $0.id, supermarketID: $0.supermarketID, title: $0.title, brand: $0.brand, gtin: $0.gtin,
                    quantityValue: $0.quantityValue, quantityUnit: $0.quantityUnit, priceCents: $0.priceCents, validFrom: $0.validFrom,
                    validTo: $0.validTo
                )
            },
            on: today,
            ignoredWords: Set(supermarketRows.filter { favorites.contains($0.id) }.map(\.name))
        )
        let cheapest = OfferMatcher.cheapestPerItem(matches, confirmedOfferIDs: confirmed)
        let titles = Dictionary(offers.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        return ShoppingOffers(
            cheapest: cheapest,
            totals: OfferMatcher.storeTotals(itemIDs: unchecked.map(\.id), matches: matches, confirmedOfferIDs: confirmed),
            questions: questions(from: matches, items: unchecked, titles: titles, priced: cheapest)
        )
    }

    /// Uncertain matches for items without a price yet, grouped by item name and offer title.
    private func questions(from matches: [OfferMatch], items: [ShoppingItemRow], titles: [UUID: String], priced: [UUID: OfferMatch]) -> [OfferQuestion] {
        let names = Dictionary(items.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var order: [String] = []
        var groups: [String: OfferQuestion] = [:]
        for match in matches where match.confidence == .uncertain && !confirmed.contains(match.offerID) && priced[match.itemID] == nil {
            guard let itemName = names[match.itemID], let title = titles[match.offerID] else { continue }
            let key = itemName.lowercased() + "|" + title
            if groups[key] == nil {
                order.append(key)
                groups[key] = OfferQuestion(itemName: itemName, offerTitle: title, supermarketIDs: [], offerIDs: [])
            }
            if groups[key]?.supermarketIDs.contains(match.supermarketID) == false { groups[key]?.supermarketIDs.append(match.supermarketID) }
            groups[key]?.offerIDs.insert(match.offerID)
        }
        return order.compactMap { key in
            guard var question = groups[key] else { return nil }
            question.supermarketIDs.sort { TrainingRecords.inOrder(supermarketName($0), supermarketName($1)) }
            return question
        }
    }

    /// Fills the list with what the week menu needs: menu items from an earlier fill go, unless they are in the basket;
    /// the user's own items stay.
    public func refill(with lines: [ShoppingLine]) -> ShoppingChange {
        ShoppingChange(
            removed: itemRows.filter { $0.source == "menu" && !$0.isChecked }.map(\.id),
            added: lines.compactMap { Self.newItem($0.name, quantity: $0.quantity, unit: $0.unit, aisle: $0.aisle, productID: $0.productID) }
        )
    }

    /// An item as typed or as the menu needs it: trimmed, at most 120 characters, an amount only with a quantity above
    /// zero. Nil for an empty name.
    public static func newItem(_ text: String, quantity: Double? = nil, unit: String? = nil, aisle: String = "other", productID: UUID? = nil) -> NewShoppingItem? {
        // Spaces and line breaks, as trimmingCharacters(in: .whitespacesAndNewlines) on iOS.
        guard let first = text.firstIndex(where: { !$0.isWhitespace }), let last = text.lastIndex(where: { !$0.isWhitespace }) else { return nil }
        let name = text[first...last]
        let amount = quantity.flatMap { $0 > 0 ? $0 : nil }
        return NewShoppingItem(name: String(name.prefix(120)), quantity: amount, unit: amount == nil ? nil : unit, aisle: aisle, productID: productID)
    }
}

extension MenuBook {
    /// What the meals from today on that are not eaten yet need, added up per product, in the order of the shop.
    public func shoppingLines(ingredients: [RecipeIngredientRow]) -> [ShoppingLine] {
        let byRecipe = Dictionary(grouping: ingredients, by: \.recipeID)
        let uses = entries().filter { $0.loggedEntryID == nil }.compactMap { entry -> PlannedRecipeUse? in
            guard let recipe = recipe(entry.recipeID) else { return nil }
            return PlannedRecipeUse(
                recipeServings: recipe.servings, plannedServings: entry.servings,
                ingredients: (byRecipe[recipe.id] ?? []).sorted { $0.position < $1.position }.map {
                    MenuIngredient(productID: $0.productID, name: $0.name.text(preferring: languages), quantity: $0.quantity, unit: $0.unit, aisle: $0.aisle)
                }
            )
        }
        return ShoppingListBuilder.lines(for: uses)
    }
}
