import Foundation
import SwiftData
import Testing
import FitlingCore
@testable import Fitling

/// Phase 2 tables in the sync: every column goes up and comes back on another device.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct FoodSyncTests {
    let userID = UUID()
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let today = Day(ordinal: 20775)

    func makeEngine(_ remote: FakeRemoteStore) throws -> SyncEngine {
        SyncEngine(container: try makeModelContainer(inMemory: true), remote: remote, tables: SyncTables.all, now: { [now] in now })
    }

    func ownProduct() -> Product {
        let product = Product(
            id: UUID(), ownerID: userID, source: "user", name: LocalizedText(["nl": "Oma's appeltaart", "en": "Apple pie"]),
            quantityUnit: "g", updatedAt: now
        )
        product.gtin = "8712100849084"
        product.brand = "Thuis"
        product.searchName = "oma's appeltaart apple pie thuis"
        product.servingSize = 120
        product.servingLabel = "1 punt"
        product.kcal100 = 280.5
        product.protein100 = 3.2
        product.carbs100 = 38
        product.sugars100 = 21.5
        product.fat100 = 12
        product.saturatedFat100 = 6.1
        product.fiber100 = 1.8
        product.salt100 = 0.3
        product.fetchedAt = now
        return product
    }

    /// Pushes from one device and pulls into a second one, which starts empty.
    func roundTrip<Model: SyncableModel>(_ model: Model, remote: FakeRemoteStore) async throws -> Model? {
        let phone = try makeEngine(remote)
        phone.context.insert(model)
        #expect(await phone.sync() == .completed)
        let tablet = try makeEngine(remote)
        #expect(await tablet.sync() == .completed)
        return try tablet.context.fetch(FetchDescriptor<Model>()).first
    }

    @Test func productRecordKeepsEveryColumn() async throws {
        let product = ownProduct()
        let sent = product.record
        let received = try #require(try await roundTrip(product, remote: FakeRemoteStore()))
        #expect(received.record == sent)
        #expect(!received.needsPush)
    }

    @Test func foodEntryRecordKeepsEveryColumn() async throws {
        let entry = FoodEntry(
            id: UUID(), userID: userID, consumedOn: today, meal: .dinner, name: "Oma's appeltaart",
            quantity: 1.5, quantityUnit: "serving", kcal: 504.9, updatedAt: now
        )
        entry.productID = UUID()
        entry.proteinG = 5.8
        entry.carbsG = nil
        entry.fatG = 21.6
        let sent = entry.record
        let received = try #require(try await roundTrip(entry, remote: FakeRemoteStore()))
        #expect(received.record == sent)
        #expect(received.carbsG == nil)
    }

    @Test func waterEntryRecordKeepsEveryColumn() async throws {
        let entry = WaterEntry(id: UUID(), userID: userID, consumedOn: today, amountMl: 250, updatedAt: now)
        let sent = entry.record
        let received = try #require(try await roundTrip(entry, remote: FakeRemoteStore()))
        #expect(received.record == sent)
    }

    @Test func favoriteProductRecordKeepsEveryColumn() async throws {
        let favorite = FavoriteProduct(id: UUID(), userID: userID, productID: UUID(), updatedAt: now)
        let sent = favorite.record
        let received = try #require(try await roundTrip(favorite, remote: FakeRemoteStore()))
        #expect(received.record == sent)
    }

    @Test func sharedProductsAreNeverPushed() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let shared = Product(id: UUID(), ownerID: nil, source: "off", name: LocalizedText(["nl": "Pindakaas"]), quantityUnit: "g", updatedAt: now)
        // Even with the flag set by mistake, a shared row stays local.
        shared.needsPush = true
        engine.context.insert(shared)
        engine.context.insert(ownProduct())

        #expect(await engine.sync() == .completed)

        let pushed = remote.upserts.filter { $0.table == "products" }.flatMap(\.ids)
        #expect(pushed.count == 1)
        #expect(!pushed.contains(shared.id))
    }

    @Test func sharedProductsAreNotPulled() async throws {
        let remote = FakeRemoteStore()
        let own = ownProduct().record
        var shared = own
        shared.id = UUID()
        shared.ownerID = nil
        shared.source = "off"
        try remote.serve(own, table: "products", syncedAt: now)
        try remote.serve(shared, table: "products", syncedAt: now)
        let engine = try makeEngine(remote)

        #expect(await engine.sync() == .completed)

        #expect(try engine.context.fetch(FetchDescriptor<Product>()).map(\.id) == [own.id])
    }

    @Test func ownProductsGoUpBeforeTheEntriesThatUseThem() async throws {
        let remote = FakeRemoteStore()
        let engine = try makeEngine(remote)
        let product = ownProduct()
        let entry = FoodEntry(id: UUID(), userID: userID, consumedOn: today, meal: .lunch, name: "Taart", quantity: 100, quantityUnit: "g", kcal: 280.5, updatedAt: now)
        entry.productID = product.id
        engine.context.insert(entry)
        engine.context.insert(product)

        await engine.sync()

        let tables = remote.upserts.map(\.table)
        let productIndex = try #require(tables.firstIndex(of: "products"))
        let entryIndex = try #require(tables.firstIndex(of: "food_entries"))
        #expect(productIndex < entryIndex)
    }
}
