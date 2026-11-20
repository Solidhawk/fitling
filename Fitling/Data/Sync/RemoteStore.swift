import Foundation
import Supabase

/// A row as it travels to and from Supabase.
protocol SyncRecord: Codable, Sendable {
    var id: UUID { get }
    var updatedAt: Date { get }
    /// Set by the server. Nil for a record made on this device; never sent.
    var syncedAt: Date? { get }
    /// Tables without deletion markers always give nil.
    var deletedAt: Date? { get }
}

enum RemoteStoreError: Error, Equatable {
    case network
    /// The server refused the rows (a check constraint, an unknown reference); retrying will not help.
    case rejected(String)
}

/// The server side of sync. One real implementation and one for tests. Both throw nothing but
/// `RemoteStoreError`. That is not in the signatures: a generic async requirement with a typed
/// error crashes the compiler of Xcode 16.4 (Swift 6.1.2) while it emits the witness.
protocol RemoteStore: Sendable {
    /// Rows with `synced_at` after `since` (all rows when nil), newest first. With an
    /// `ownerColumn`, only rows where it is set: Row Level Security leaves those to the user's own. That order matters
    /// when a pull takes more than one page: a row that changes meanwhile moves to the front, so
    /// the pages that follow can repeat a row but never skip one.
    func fetch<Record: SyncRecord>(_ type: Record.Type, table: String, keyColumn: String, ownerColumn: String?, since: Date?, offset: Int, limit: Int) async throws -> [Record]
    func upsert<Record: SyncRecord>(_ records: [Record], table: String, keyColumn: String) async throws
}

struct SupabaseRemoteStore: RemoteStore {
    let client: SupabaseClient

    func fetch<Record: SyncRecord>(_ type: Record.Type, table: String, keyColumn: String, ownerColumn: String?, since: Date?, offset: Int, limit: Int) async throws -> [Record] {
        do {
            var query = client.from(table).select()
            if let since {
                query = query.gt("synced_at", value: since.formatted(.iso8601))
            }
            if let ownerColumn {
                query = query.not(ownerColumn, operator: .is, value: "null")
            }
            return try await query
                .order("synced_at", ascending: false)
                .order(keyColumn, ascending: false)
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value
        } catch {
            throw Self.storeError(error)
        }
    }

    func upsert<Record: SyncRecord>(_ records: [Record], table: String, keyColumn: String) async throws {
        do {
            try await client.from(table).upsert(records, onConflict: keyColumn, returning: .minimal).execute()
        } catch {
            throw Self.storeError(error)
        }
    }

    static func storeError(_ error: any Error) -> RemoteStoreError {
        error is URLError ? .network : .rejected(String(describing: error))
    }
}
