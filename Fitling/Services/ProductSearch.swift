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
        // The term goes into a LIKE pattern: its own wildcards are taken literally.
        let escaped = term.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        do {
            return try await client.from("products")
                .select()
                .is("owner_id", value: nil)
                .ilike("search_name", pattern: "%\(escaped)%")
                .limit(limit)
                .execute()
                .value
        } catch is URLError {
            throw RemoteStoreError.network
        } catch {
            throw RemoteStoreError.rejected(String(describing: error))
        }
    }
}
