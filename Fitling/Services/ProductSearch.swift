import Foundation
import Supabase
import FitlingCore

/// Searches the shared product cache on the server by name.
protocol ProductSearching: Sendable {
    /// At most `limit` shared products whose `search_name` holds every word of the term, best first. Throws
    /// `RemoteStoreError`.
    func search(_ term: String, limit: Int) async throws -> [ProductRecord]
}

struct SupabaseProductSearch: ProductSearching {
    let client: SupabaseClient

    private struct Parameters: Encodable {
        let searchKey: String
        let maxResults: Int

        enum CodingKeys: String, CodingKey {
            case searchKey = "search_key"
            case maxResults = "max_results"
        }
    }

    func search(_ term: String, limit: Int) async throws -> [ProductRecord] {
        do {
            // Every word in any order, ranked as FoodLog.bestMatches (supabase/search-products.sql).
            return try await client.rpc("search_products", params: Parameters(searchKey: term, maxResults: limit))
                .execute()
                .value
        } catch is URLError {
            throw RemoteStoreError.network
        } catch {
            throw RemoteStoreError.rejected(String(describing: error))
        }
    }
}
