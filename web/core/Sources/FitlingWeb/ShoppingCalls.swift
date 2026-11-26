#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif
import FitlingCore

// The shopping list for the web (phase 6): what ShoppingStore and ShoppingViewModel read and decide on iOS, from the
// same ShoppingBook. Ids go out in lower case, as Postgres writes them.

/// The list's items, the offers of the favourite supermarkets and what the user confirmed, as the web read them.
struct ShoppingInput: Decodable {
    let today: String
    let items: [ShoppingItemRow]
    let offers: [OfferRow]
    let supermarkets: [SupermarketRow]
    let favoriteSupermarketIDs: [String]
    /// Uncertain offers the user said are right, kept on the device.
    let confirmedOfferIDs: [UUID]

    func book() throws -> ShoppingBook {
        ShoppingBook(
            items: items, offers: offers, supermarkets: supermarkets, favoriteSupermarketIDs: favoriteSupermarketIDs,
            confirmedOfferIDs: Set(confirmedOfferIDs), today: try day(today, "today")
        )
    }
}

struct ShoppingRequest: Decodable {
    let shopping: ShoppingInput
}

struct ItemOfferOutput: Encodable {
    let offerID: String
    let priceCents: Int
    let supermarketID: String
    let supermarketName: String
    /// A price is only shown with the day it runs to.
    let validTo: String
}

struct ShoppingItemOutput: Encodable {
    let id: String
    let name: String
    var quantity: Double?
    var unit: String?
    let isChecked: Bool
    let source: String
    var offer: ItemOfferOutput?
}

struct StoreTotalOutput: Encodable {
    let supermarketID: String
    let name: String
    let totalCents: Int
    let itemsWithoutPrice: Int
}

struct OfferQuestionOutput: Encodable {
    let id: String
    let itemName: String
    let offerTitle: String
    /// By name.
    let supermarketNames: [String]
    let offerIDs: [String]
}

struct ShoppingOverviewAnswer: Encodable {
    let items: [ShoppingItemOutput]
    let totals: [StoreTotalOutput]
    let questions: [OfferQuestionOutput]
}

/// The list screen (ShoppingViewModel.reload): the items in the order of the shop, each with its cheapest offer, the
/// total per shop and the possible offers to ask about.
func shoppingOverview(_ request: ShoppingRequest) throws -> ShoppingOverviewAnswer {
    let book = try request.shopping.book()
    let offers = book.offers()
    let validTo = Dictionary(request.shopping.offers.map { ($0.id, $0.validTo.isoString) }, uniquingKeysWith: { first, _ in first })
    return ShoppingOverviewAnswer(
        items: book.items().map { item in
            ShoppingItemOutput(
                id: lower(item.id), name: item.name, quantity: item.quantity, unit: item.unit, isChecked: item.isChecked, source: item.source,
                offer: item.isChecked ? nil : offers.cheapest[item.id].map { match in
                    ItemOfferOutput(
                        offerID: lower(match.offerID), priceCents: match.priceCents, supermarketID: match.supermarketID,
                        supermarketName: book.supermarketName(match.supermarketID), validTo: validTo[match.offerID] ?? ""
                    )
                }
            )
        },
        totals: offers.totals.map {
            StoreTotalOutput(supermarketID: $0.supermarketID, name: book.supermarketName($0.supermarketID), totalCents: $0.totalCents, itemsWithoutPrice: $0.itemsWithoutPrice)
        },
        questions: offers.questions.map {
            OfferQuestionOutput(
                id: $0.id, itemName: $0.itemName, offerTitle: $0.offerTitle, supermarketNames: $0.supermarketIDs.map(book.supermarketName),
                offerIDs: $0.offerIDs.map(lower).sorted()
            )
        }
    )
}

struct NewItemOutput: Encodable {
    let name: String
    var quantity: Double?
    var unit: String?
    let aisle: String
    var productID: String?

    init(_ item: NewShoppingItem) {
        name = item.name
        quantity = item.quantity
        unit = item.unit
        aisle = item.aisle
        productID = item.productID.map(lower)
    }
}

struct RefillRequest: Decodable {
    let shopping: ShoppingInput
    let menu: MenuInput
    let ingredients: [RecipeIngredientRow]
}

struct RefillAnswer: Encodable {
    let removed: [String]
    let added: [NewItemOutput]
}

/// What this week's menu needs on the list (ShoppingStore.fill): earlier menu items go, unless in the basket.
func shoppingRefill(_ request: RefillRequest) throws -> RefillAnswer {
    let lines = try request.menu.book().shoppingLines(ingredients: request.ingredients)
    let change = try request.shopping.book().refill(with: lines)
    return RefillAnswer(removed: change.removed.map(lower), added: change.added.map(NewItemOutput.init))
}

struct NewItemRequest: Decodable {
    let text: String
}

struct NewItemAnswer: Encodable {
    let item: NewItemOutput?
}

/// An item as typed (ShoppingStore.add): trimmed and bounded; nil for an empty name.
func shoppingNewItem(_ request: NewItemRequest) -> NewItemAnswer {
    NewItemAnswer(item: ShoppingBook.newItem(request.text).map(NewItemOutput.init))
}
