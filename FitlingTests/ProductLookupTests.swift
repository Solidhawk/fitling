import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

@MainActor
@Suite struct ProductLookupTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let source = FakeProductSource()
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let gtin = "8712100849084"

    init() throws {
        container = try makeModelContainer(inMemory: true)
    }

    func makeLookup() -> ProductLookup {
        ProductLookup(context: context, source: source, now: { [now] in now })
    }

    func sharedRecord(kcal: Double = 338, fetchedAt: Date) -> ProductRecord {
        ProductRecord(
            id: UUID(), ownerID: nil, source: "off", sourceID: gtin, gtin: gtin, name: LocalizedText(["de": "Double Caramel"]),
            brand: "Magnum", searchName: "double caramel magnum", quantityUnit: "ml", servingSize: 88, servingLabel: nil,
            kcal100: kcal, protein100: 3.2, carbs100: 36, sugars100: 33, fat100: 20, saturatedFat100: 14, fiber100: nil,
            salt100: 0.17, imageURL: nil, isVerified: true, fetchedAt: fetchedAt, updatedAt: fetchedAt, deletedAt: nil, syncedAt: fetchedAt
        )
    }

    @discardableResult
    func storeLocally(_ record: ProductRecord) -> Product {
        let product = Product.make(from: record)
        context.insert(product)
        try? context.save()
        return product
    }

    func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 24 * 60 * 60)
    }

    @Test func usesTheLocalProductWhenFresh() async {
        let product = storeLocally(sharedRecord(fetchedAt: daysAgo(10)))
        #expect(await makeLookup().lookUp(scanned: gtin) == .found(product.id))
        #expect(source.calls.isEmpty)
    }

    @Test func asksTheServerWhenStale() async {
        let old = sharedRecord(kcal: 300, fetchedAt: daysAgo(40))
        let product = storeLocally(old)
        var refreshed = old
        refreshed.kcal100 = 338
        refreshed.fetchedAt = now
        source.products[gtin] = refreshed

        #expect(await makeLookup().lookUp(scanned: gtin) == .found(product.id))
        #expect(source.calls == [gtin])
        #expect(product.kcal100 == 338)
        #expect(product.fetchedAt == now)
    }

    @Test func storesAProductTheDeviceDidNotHave() async throws {
        let record = sharedRecord(fetchedAt: now)
        source.products[gtin] = record
        #expect(await makeLookup().lookUp(scanned: gtin) == .found(record.id))
        let stored = try #require(try context.fetch(FetchDescriptor<Product>()).first)
        #expect(stored.record.name == record.name)
        #expect(!stored.needsPush)
    }

    @Test func keepsTheStaleProductWhenOffline() async {
        let product = storeLocally(sharedRecord(fetchedAt: daysAgo(40)))
        source.isOffline = true
        #expect(await makeLookup().lookUp(scanned: gtin) == .found(product.id))
    }

    @Test func reportsNotFound() async {
        #expect(await makeLookup().lookUp(scanned: gtin) == .notFound)
    }

    @Test func offlineWithoutACopyIsUnavailable() async {
        source.isOffline = true
        #expect(await makeLookup().lookUp(scanned: gtin) == .unavailable)
    }

    @Test func invalidBarcodeNeverReachesTheServer() async {
        #expect(await makeLookup().lookUp(scanned: "8712100849085") == .invalidBarcode)
        #expect(await makeLookup().lookUp(scanned: "abc") == .invalidBarcode)
        #expect(source.calls.isEmpty)
    }

    @Test func aUPCCodeIsLookedUpUnderItsThirteenDigitKey() async {
        _ = await makeLookup().lookUp(scanned: "036000291452")
        #expect(source.calls == ["0036000291452"])
    }

    @Test func theUsersOwnProductComesFirstAndNeverExpires() async {
        storeLocally(sharedRecord(fetchedAt: daysAgo(40)))
        var own = sharedRecord(fetchedAt: daysAgo(400))
        own.id = UUID()
        own.ownerID = UUID()
        own.source = "user"
        let mine = storeLocally(own)
        #expect(await makeLookup().lookUp(scanned: gtin) == .found(mine.id))
        #expect(source.calls.isEmpty)
    }
}
