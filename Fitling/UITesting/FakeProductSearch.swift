#if DEBUG
import Foundation

/// A product search that answers from a fixed list, for the unit tests and the UI test. Never
/// compiled into a release build.
@MainActor
final class FakeProductSearch: ProductSearching {
    var records: [ProductRecord] = []
    private(set) var terms: [String] = []

    func search(_ term: String, limit: Int) async throws -> [ProductRecord] {
        terms.append(term)
        return Array(records.filter { $0.searchName.contains(term) }.prefix(limit))
    }
}
#endif
