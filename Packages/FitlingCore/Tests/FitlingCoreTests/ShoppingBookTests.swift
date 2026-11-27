import Foundation
import Testing
@testable import FitlingCore

/// The shopping list as the app and the web share it (web phase 6); ShoppingTests in the app check the same through
/// ShoppingStore and ShoppingViewModel.
@Suite struct ShoppingBookTests {
    let today = Day(isoString: "2026-11-18")!

    func item(_ name: String, aisle: String = "other", checked: Bool = false, source: String = "manual") -> ShoppingItemRow {
        ShoppingItemRow(id: UUID(), name: name, aisle: aisle, isChecked: checked, source: source)
    }

    func offer(_ title: String, shop: String, cents: Int, from: Int = 0, to: Int = 6) -> OfferRow {
        OfferRow(id: UUID(), supermarketID: shop, title: title, priceCents: cents, validFrom: today.adding(from), validTo: today.adding(to))
    }

    let shops = [SupermarketRow(id: "testmarkt", name: "Testmarkt"), SupermarketRow(id: "proefsuper", name: "Proefsuper")]

    func book(_ items: [ShoppingItemRow], offers: [OfferRow] = [], favorites: [String] = [], confirmed: Set<UUID> = []) -> ShoppingBook {
        ShoppingBook(items: items, offers: offers, supermarkets: shops, favoriteSupermarketIDs: favorites, confirmedOfferIDs: confirmed, today: today)
    }

    @Test func itemsComeUncheckedFirstInShopOrder() {
        let rows = [item("Melk", aisle: "dairy"), item("appels", aisle: "produce", checked: true), item("Brood", aisle: "bakery"), item("Eieren", aisle: "dairy")]
        #expect(book(rows).items().map(\.name) == ["Brood", "Eieren", "Melk", "appels"])
    }

    @Test func refillingKeepsOwnAndCheckedItems() {
        let own = item("Koffie")
        let oldMenu = item("Ui", aisle: "produce", source: "menu")
        let inBasket = item("Pasta", aisle: "pantry", checked: true, source: "menu")
        let lines = [ShoppingLine(productID: nil, name: "Tomaat", quantity: 2, unit: "piece", aisle: "produce"), ShoppingLine(productID: nil, name: "Zout", quantity: 0, unit: "g", aisle: "pantry")]
        let change = book([own, oldMenu, inBasket]).refill(with: lines)
        #expect(change.removed == [oldMenu.id])
        #expect(change.added == [
            NewShoppingItem(name: "Tomaat", quantity: 2, unit: "piece", aisle: "produce", productID: nil),
            // No amount without a quantity (ShoppingStore.fill).
            NewShoppingItem(name: "Zout", quantity: nil, unit: nil, aisle: "pantry", productID: nil),
        ])
    }

    @Test func uncertainOffersCountOnlyWhenConfirmed() {
        let tomatoes = item("Tomatenblokjes")
        let onion = item("Tomaat")
        let certain = offer("Tomatenblokjes 400 g", shop: "testmarkt", cents: 79)
        let elsewhere = offer("Tomatenblokjes 400 g", shop: "anderewinkel", cents: 10)
        let expired = offer("Tomatenblokjes 400 g", shop: "proefsuper", cents: 20, from: -7, to: -1)
        let offers = [certain, elsewhere, expired]
        let plain = book([tomatoes, onion], offers: offers, favorites: ["testmarkt", "proefsuper"]).offers()
        #expect(plain.cheapest[tomatoes.id]?.priceCents == 79)
        // "Tomaat" fits "Tomatenblokjes" only possibly: asked, not counted.
        #expect(plain.cheapest[onion.id] == nil)
        #expect(plain.questions.map(\.itemName) == ["Tomaat"])
        #expect(plain.totals == [StoreTotal(supermarketID: "testmarkt", totalCents: 79, itemsWithoutPrice: 1)])
        let confirmed = book([tomatoes, onion], offers: offers, favorites: ["testmarkt", "proefsuper"], confirmed: [certain.id]).offers()
        #expect(confirmed.cheapest[onion.id]?.priceCents == 79)
        #expect(confirmed.questions.isEmpty)
        #expect(confirmed.totals == [StoreTotal(supermarketID: "testmarkt", totalCents: 158, itemsWithoutPrice: 0)])
    }

    /// The same possible offer in two shops, for an item that is on the list twice: one question, with the shops by
    /// name, and all their offers (UNFORGET S24).
    @Test func questionsGroupByItemAndTitle() throws {
        let first = item("Tomaat")
        let second = item("Tomaat")
        let atTest = offer("Tomatenblokjes 400 g", shop: "testmarkt", cents: 79)
        let atProef = offer("Tomatenblokjes 400 g", shop: "proefsuper", cents: 69)
        let summary = book([first, second, item("Wasmiddel", checked: true)], offers: [atTest, atProef], favorites: ["testmarkt", "proefsuper"]).offers()
        let question = try #require(summary.questions.first)
        #expect(summary.questions.count == 1)
        #expect(question.itemName == "Tomaat" && question.offerTitle == "Tomatenblokjes 400 g")
        #expect(question.supermarketIDs == ["proefsuper", "testmarkt"])
        #expect(question.offerIDs == [atTest.id, atProef.id])
    }

    @Test func menuLinesSkipLoggedMeals() {
        let user = UUID()
        let pasta = MenuRecipe(
            id: UUID(), ownerID: nil, title: LocalizedText(["nl": "Pasta"]), servings: 2, cookMinutes: 20, kcalPerServing: 600,
            proteinGPerServing: 20, carbsGPerServing: 80, fatGPerServing: 15, mealSlots: ["dinner"]
        )
        let soup = MenuRecipe(
            id: UUID(), ownerID: nil, title: LocalizedText(["nl": "Soep"]), servings: 1, cookMinutes: 20, kcalPerServing: 300,
            proteinGPerServing: 10, carbsGPerServing: 30, fatGPerServing: 10, mealSlots: ["lunch"]
        )
        let entries = [
            MenuEntry(id: UUID(), plannedOn: today, meal: "dinner", recipeID: pasta.id, servings: 1),
            MenuEntry(id: UUID(), plannedOn: today, meal: "lunch", recipeID: soup.id, servings: 1, loggedEntryID: UUID()),
        ]
        let ingredients = [
            RecipeIngredientRow(recipeID: pasta.id, productID: nil, name: LocalizedText(["nl": "Spaghetti", "en": "Spaghetti"]), quantity: 200, unit: "g", aisle: "pantry", position: 0),
            RecipeIngredientRow(recipeID: soup.id, productID: nil, name: LocalizedText(["nl": "Bouillon"]), quantity: 500, unit: "ml", aisle: "pantry", position: 0),
        ]
        let book = MenuBook(userID: user, recipes: [pasta, soup], entries: entries, settings: MenuSettings(), excludedProductIDs: [], today: today, languages: ["nl"])
        // Half the recipe's two servings: 100 g; the soup was already eaten.
        #expect(book.shoppingLines(ingredients: ingredients) == [ShoppingLine(productID: nil, name: "Spaghetti", quantity: 100, unit: "g", aisle: "pantry")])
    }

    @Test func aNewItemIsTrimmedAndBounded() {
        #expect(ShoppingBook.newItem("  Melk ") == NewShoppingItem(name: "Melk", quantity: nil, unit: nil, aisle: "other", productID: nil))
        #expect(ShoppingBook.newItem("   ") == nil)
        #expect(ShoppingBook.newItem(String(repeating: "a", count: 130))?.name.count == 120)
        // Postgres counts code points: a flag takes two of the 120.
        #expect(ShoppingBook.newItem(String(repeating: "🇳🇱", count: 61))?.name == String(repeating: "🇳🇱", count: 60))
        #expect(ShoppingBook.newItem("Melk", quantity: 1000, unit: "ml", aisle: "dairy")?.unit == "ml")
        #expect(ShoppingBook.newItem("Melk", quantity: 0, unit: "ml")?.unit == nil)
        // `shopping_items.quantity` is numeric(8,2): a week of a huge recipe of the user's own keeps its name, not the
        // amount the database would refuse (review of Fable 5.2).
        #expect(ShoppingBook.newItem("Meel", quantity: 1_200_000, unit: "g") == NewShoppingItem(name: "Meel", quantity: nil, unit: nil, aisle: "other", productID: nil))
        #expect(ShoppingBook.newItem("Meel", quantity: 0.004, unit: "g")?.quantity == nil)
    }
}
