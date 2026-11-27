import Foundation
import Supabase
import FitlingCore

/// Searches the shared product cache on the server by name.
protocol ProductSearching: Sendable {
    /// At most `limit` shared products whose `search_name` contains the term. Throws `RemoteStoreError`.
    func search(_ term: String, limit: Int) async throws -> [ProductRecord]
}

struct SupabaseProductSearch: ProductSearching {
    let client: SupabaseClient

    func search(_ term: String, limit: Int) async throws -> [ProductRecord] {
        do {
            return try await client.from("products")
                .select()
                .is("owner_id", value: nil)
                .is("deleted_at", value: nil)
                .imatch("search_name", pattern: Self.pattern(term))
                .limit(limit)
                .execute()
                .value
        } catch is URLError {
            throw RemoteStoreError.network
        } catch {
            throw RemoteStoreError.rejected(String(describing: error))
        }
    }

    /// The term as a regular expression that finds it anywhere, each character taken literally. A LIKE pattern cannot
    /// do that: PostgREST reads "*" in it as "%" (products.ts, containsPattern).
    static func pattern(_ term: String) -> String {
        var pattern = ""
        for character in term {
            if "\\^$.|?*+()[]{}".contains(character) { pattern.append("\\") }
            pattern.append(character)
        }
        return pattern
    }
}
