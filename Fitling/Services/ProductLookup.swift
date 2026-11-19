import Foundation
import Observation
import Supabase
import SwiftData
import FitlingCore

/// What the server knows about a barcode (the Edge Function `lookup-product`).
protocol ProductSource: Sendable {
    /// The shared product, or nil when no source knows the barcode. Throws `RemoteStoreError`.
    func lookUp(gtin: String) async throws -> ProductRecord?
}

struct SupabaseProductSource: ProductSource {
    let client: SupabaseClient

    private struct Body: Encodable {
        let gtin: String
    }

    func lookUp(gtin: String) async throws -> ProductRecord? {
        do {
            return try await client.functions.invoke(
                "lookup-product",
                options: FunctionInvokeOptions(body: Body(gtin: gtin))
            ) { data, _ in
                try PostgrestClient.Configuration.jsonDecoder.decode(ProductRecord.self, from: data)
            }
        } catch FunctionsError.httpError(404, _) {
            return nil
        } catch is URLError {
            throw RemoteStoreError.network
        } catch {
            throw RemoteStoreError.rejected(String(describing: error))
        }
    }
}

enum ProductLookupResult: Equatable, Sendable {
    /// The product, stored on this device under this id.
    case found(UUID)
    case notFound
    /// Not an EAN-8, EAN-13 or UPC-A with a valid check digit: a misread.
    case invalidBarcode
    /// The server could not be asked and this device has no copy.
    case unavailable
}

/// Finds the product behind a scanned barcode: on the device first, then on the server
/// (ARCHITECTURE §5, steps 1 and 2).
@MainActor
final class ProductLookup {
    /// A shared product is asked again after this long; the user's own products never expire.
    static let freshFor: TimeInterval = 30 * 24 * 60 * 60

    private let context: ModelContext
    private let source: any ProductSource
    private let now: () -> Date

    init(context: ModelContext, source: any ProductSource, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.source = source
        self.now = now
    }

    func lookUp(scanned code: String) async -> ProductLookupResult {
        guard let gtin = Barcode.normalized(code) else { return .invalidBarcode }
        let local = localProduct(gtin: gtin)
        if let local, isFresh(local) { return .found(local.id) }
        do {
            guard let record = try await source.lookUp(gtin: gtin) else {
                return local.map { .found($0.id) } ?? .notFound
            }
            return .found(store(record).id)
        } catch {
            // Offline or a server problem: an old copy is better than nothing.
            return local.map { .found($0.id) } ?? .unavailable
        }
    }

    /// The user's own product with this barcode comes before a shared one.
    private func localProduct(gtin: String) -> Product? {
        let descriptor = FetchDescriptor<Product>(predicate: #Predicate<Product> { $0.gtin == gtin && $0.deletedAt == nil })
        let products = (try? context.fetch(descriptor)) ?? []
        return products.first { $0.ownerID != nil } ?? products.first
    }

    private func isFresh(_ product: Product) -> Bool {
        if product.ownerID != nil { return true }
        guard let fetchedAt = product.fetchedAt else { return false }
        return now().timeIntervalSince(fetchedAt) < Self.freshFor
    }

    private func store(_ record: ProductRecord) -> Product {
        let id = record.id
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate<Product> { $0.id == id })
        descriptor.fetchLimit = 1
        let product: Product
        if let existing = try? context.fetch(descriptor).first {
            existing.apply(record)
            product = existing
        } else {
            product = Product.make(from: record)
            context.insert(product)
        }
        try? context.save()
        return product
    }
}
