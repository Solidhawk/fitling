#if DEBUG
import Foundation

/// A stand-in for Supabase that keeps rows the way PostgREST does: one JSON object per row,
/// merged per key on upsert (a key that was not sent keeps its old value), stamped with
/// `synced_at` by the server and handed out newest first. Used by the unit tests and by the UI
/// test, which cannot reach a real server; never compiled into a release build.
@MainActor
final class FakeRemoteStore: RemoteStore {
    struct Fetch: Equatable {
        var table: String
        var since: Date?
        var offset: Int
    }

    struct Upsert: Equatable {
        var table: String
        var ids: [UUID]
    }

    private(set) var fetches: [Fetch] = []
    private(set) var upserts: [Upsert] = []
    var rejectedIDs: Set<UUID> = []
    var isOffline = false
    var refusesReads = false
    /// The clock of the server. Every stored row gets it as `synced_at`, then it moves on a second.
    var clock = Date(timeIntervalSince1970: 1_795_000_100)
    /// Runs once, while an upsert is under way and the rows have already left the device.
    var duringUpsert: (() -> Void)?
    /// Runs once, after the first page of a pull has been handed out.
    var afterFirstFetch: (() -> Void)?
    /// The next request (read or write) waits until `releaseRequest()`, like a slow network.
    var holdsNextRequest = false

    private var rows: [String: [String: [String: Any]]] = [:]
    private var release: CheckedContinuation<Void, Never>?

    func fetch<Record: SyncRecord>(_ type: Record.Type, table: String, keyColumn: String, ownerColumn: String?, since: Date?, offset: Int, limit: Int) async throws -> [Record] {
        fetches.append(Fetch(table: table, since: since, offset: offset))
        if isOffline { throw RemoteStoreError.network }
        await holdIfAsked()
        if refusesReads { throw RemoteStoreError.rejected("permission denied for table \(table)") }
        let page = (rows[table] ?? [:])
            .filter { row in since.map { Self.syncedAt(row.value) > $0 } ?? true }
            // Like `not.is.null` on the owner column: only rows that belong to someone, which Row
            // Level Security narrows to the user's own.
            .filter { row in ownerColumn.map { column in row.value[column].map { !($0 is NSNull) } ?? false } ?? true }
            .sorted { (Self.syncedAt($0.value), $0.key) > (Self.syncedAt($1.value), $1.key) }
            .dropFirst(offset)
            .prefix(limit)
        let records: [Record]
        do {
            records = try page.map { try JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: $0.value)) }
        } catch {
            throw RemoteStoreError.rejected(String(describing: error))
        }
        if let change = afterFirstFetch {
            afterFirstFetch = nil
            change()
        }
        return records
    }

    func upsert<Record: SyncRecord>(_ records: [Record], table: String, keyColumn: String) async throws {
        upserts.append(Upsert(table: table, ids: records.map(\.id)))
        if isOffline { throw RemoteStoreError.network }
        await holdIfAsked()
        if let change = duringUpsert {
            duringUpsert = nil
            change()
        }
        // Like a real request: one refused row fails the whole batch.
        if let refused = records.first(where: { rejectedIDs.contains($0.id) }) {
            throw RemoteStoreError.rejected("row \(refused.id) breaks a check constraint")
        }
        do {
            for record in records {
                let sent = try Self.json(record)
                var row = rows[table]?[record.id.uuidString] ?? [:]
                row.merge(sent) { _, new in new }
                row["synced_at"] = clock.timeIntervalSinceReferenceDate
                rows[table, default: [:]][record.id.uuidString] = row
                clock += 1
            }
        } catch {
            throw RemoteStoreError.rejected(String(describing: error))
        }
    }

    private func holdIfAsked() async {
        guard holdsNextRequest else { return }
        holdsNextRequest = false
        await withCheckedContinuation { release = $0 }
    }

    /// Gives the work that is under way the chance to reach the held request. False when it
    /// never got there, so a test fails instead of waiting forever.
    func requestArrived() async -> Bool {
        for _ in 0..<1000 where release == nil {
            await Task.yield()
        }
        return release != nil
    }

    func releaseRequest() {
        release?.resume()
        release = nil
    }

    /// Puts a row on the server as if another device had sent it.
    func serve<Record: SyncRecord>(_ record: Record, table: String, syncedAt: Date) throws {
        var row = try Self.json(record)
        row["synced_at"] = syncedAt.timeIntervalSinceReferenceDate
        rows[table, default: [:]][record.id.uuidString] = row
    }

    func row(_ id: UUID, in table: String) -> [String: Any]? {
        rows[table]?[id.uuidString]
    }

    func rowCount(in table: String) -> Int {
        rows[table]?.count ?? 0
    }

    private static func json<Record: SyncRecord>(_ record: Record) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any] ?? [:]
    }

    private static func syncedAt(_ row: [String: Any]) -> Date {
        (row["synced_at"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)) ?? .distantPast
    }
}
#endif
