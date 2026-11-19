import Foundation
import SwiftData

/// A local model that syncs with one table. Each model writes its own fetch descriptors: a
/// predicate over a generic model type is not something SwiftData is known to translate.
protocol SyncableModel: PersistentModel {
    associatedtype Record: SyncRecord

    static var tableName: String { get }
    /// The column that tells rows apart on the server.
    static var keyColumn: String { get }
    /// The rows the server has not seen yet.
    static var pending: FetchDescriptor<Self> { get }
    static func matching(ids: [UUID]) -> FetchDescriptor<Self>
    /// A new local row for a record this device has never seen.
    static func make(from record: Record) -> Self

    var syncID: UUID { get }
    var updatedAt: Date { get set }
    var needsPush: Bool { get set }
    var deletedAt: Date? { get }
    var record: Record { get }
    /// Takes over the server's version.
    func apply(_ record: Record)
}

/// One table in a sync round. The engine walks a list of these in the order of ARCHITECTURE §3.5.
@MainActor
protocol SyncTable {
    func push(with engine: SyncEngine) async throws(RemoteStoreError)
    func pull(with engine: SyncEngine) async throws(RemoteStoreError)
}

struct ModelTable<Model: SyncableModel>: SyncTable {
    func push(with engine: SyncEngine) async throws(RemoteStoreError) {
        try await engine.push(Model.self)
    }

    func pull(with engine: SyncEngine) async throws(RemoteStoreError) {
        try await engine.pull(Model.self)
    }
}
