import Foundation
import Observation
import SwiftData
import FitlingCore

/// Choosing what to log: search by name (on the device first, then online), recent products,
/// favourites, or a scanned barcode.
@Observable
@MainActor
final class LogFoodViewModel {
    /// What a scan led to.
    enum ScanOutcome: Equatable {
        /// Ready to log: the product sheet opens.
        case product(UUID)
        /// Nobody knows this barcode: offer to add it as the user's own product.
        case unknown(gtin: String)
        /// Offline and not on the device: keep the barcode, try again later.
        case unavailable(gtin: String)
    }

    /// Online results appear from this many characters on, so a single letter does not ask the
    /// server for everything.
    static let onlineSearchMinimum = 3
    static let onlineSearchLimit = 30

    let meal: MealSlot
    let day: Day
    var query = ""
    private(set) var localResults: [Product] = []
    private(set) var onlineResults: [Product] = []
    private(set) var isSearchingOnline = false
    private(set) var recent: [Product] = []
    private(set) var favorites: [Product] = []
    private(set) var scanOutcome: ScanOutcome?

    let diary: FoodDiary
    private let lookup: ProductLookup
    private let search: any ProductSearching
    private var searchGeneration = 0

    init(meal: MealSlot, day: Day, diary: FoodDiary, lookup: ProductLookup, search: any ProductSearching) {
        self.meal = meal
        self.day = day
        self.diary = diary
        self.lookup = lookup
        self.search = search
        reloadLists()
    }

    func reloadLists() {
        recent = diary.recentProducts()
        favorites = diary.favoriteProducts()
    }

    /// Local results at once; online results after them, without the products already shown.
    func runSearch() async {
        searchGeneration += 1
        let generation = searchGeneration
        let term = FoodDiary.searchKey(query)
        localResults = diary.searchLocally(term)
        onlineResults = []
        guard term.count >= Self.onlineSearchMinimum else { return }
        isSearchingOnline = true
        defer { if generation == searchGeneration { isSearchingOnline = false } }
        guard let records = try? await search.search(term, limit: Self.onlineSearchLimit), generation == searchGeneration else { return }
        let shown = Set(localResults.map(\.id))
        onlineResults = records.filter { !shown.contains($0.id) }.map(store)
    }

    /// A barcode from the camera or typed in. A misread does nothing: the scanner keeps looking.
    func handleScan(_ code: String) async {
        switch await lookup.lookUp(scanned: code) {
        case let .found(id):
            scanOutcome = .product(id)
        case .notFound:
            scanOutcome = Barcode.normalized(code).map { .unknown(gtin: $0) }
        case .unavailable:
            scanOutcome = Barcode.normalized(code).map { .unavailable(gtin: $0) }
        case .invalidBarcode:
            break
        }
    }

    func clearScanOutcome() {
        scanOutcome = nil
    }

    func product(_ id: UUID) -> Product? {
        diary.product(id)
    }

    /// A search result from the server is kept on the device, so it can be logged and shows up
    /// under recent afterwards.
    private func store(_ record: ProductRecord) -> Product {
        if let existing = diary.product(record.id) {
            existing.apply(record)
            return existing
        }
        let product = Product.make(from: record)
        diary.context.insert(product)
        try? diary.context.save()
        return product
    }
}
