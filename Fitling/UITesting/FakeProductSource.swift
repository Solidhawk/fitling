#if DEBUG
import Foundation

/// A stand-in for `lookup-product` in the unit tests and the UI test. Never compiled into a
/// release build.
@MainActor
final class FakeProductSource: ProductSource {
    var products: [String: ProductRecord] = [:]
    var isOffline = false
    private(set) var calls: [String] = []

    func lookUp(gtin: String) async throws -> ProductRecord? {
        calls.append(gtin)
        if isOffline { throw RemoteStoreError.network }
        return products[gtin]
    }
}
#endif
