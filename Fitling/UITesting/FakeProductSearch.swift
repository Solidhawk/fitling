#if DEBUG
import Foundation
import FitlingCore

/// A product search that answers from a fixed list, for the unit tests and the UI test. Never
/// compiled into a release build. It finds and ranks as the server does (FoodLog.bestMatches).
@MainActor
final class FakeProductSearch: ProductSearching {
    var records: [ProductRecord] = []
    private(set) var terms: [String] = []

    func search(_ term: String, limit: Int) async throws -> [ProductRecord] {
        terms.append(term)
        return Array(FoodLog.bestMatches(records, key: term, searchName: \.searchName, isVerified: \.isVerified).prefix(limit))
    }
}
#endif
