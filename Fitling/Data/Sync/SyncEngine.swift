import Foundation
import Observation
import SwiftData
import FitlingCore

/// Offline-first sync for every table in `tables` (ARCHITECTURE §3). The engine only carries out
/// what `SyncRules` decides; it holds no rules about times or flags of its own.
@Observable
@MainActor
final class SyncEngine {
    enum Outcome: Equatable, Sendable {
        case completed
        /// The round stopped at the first request that could not reach the server.
        case offline
        /// The server refused a read, for example because the session is no longer valid.
        case failed
        /// A round was already going; it runs once more when it is done.
        case alreadyRunning
    }

    /// String Catalog key shown while the server keeps refusing a row.
    static let rejectedProblemKey = "profile.sync.rejected"
    /// String Catalog key shown after a read the server refused.
    static let failedProblemKey = "error.server"

    /// Held on purpose: a `ModelContext` does not keep its container alive, and a delayed round
    /// would otherwise touch a released store.
    private let container: ModelContainer
    private let remote: any RemoteStore
    private let tables: [any SyncTable]
    private let now: () -> Date
    private(set) var problemKey: String?
    private var isRunning = false
    private var runAgain = false
    private var sawRejection = false

    init(container: ModelContainer, remote: any RemoteStore, tables: [any SyncTable], now: @escaping () -> Date = Date.init) {
        self.container = container
        self.remote = remote
        self.tables = tables
        self.now = now
    }

    var context: ModelContext { container.mainContext }

    /// One round: push every table, then pull every table. Never more than one round at a time.
    @discardableResult
    func sync() async -> Outcome {
        guard !isRunning else {
            runAgain = true
            return .alreadyRunning
        }
        isRunning = true
        defer { isRunning = false }
        var outcome = await round()
        while runAgain {
            runAgain = false
            outcome = await round()
        }
        return outcome
    }

    private func round() async -> Outcome {
        sawRejection = false
        do {
            for table in tables {
                try await table.push(with: self)
            }
            for table in tables {
                try await table.pull(with: self)
            }
        } catch RemoteStoreError.network {
            return .offline
        } catch {
            // A refused row is dealt with in the push itself; this is a read the server refused.
            problemKey = Self.failedProblemKey
            return .failed
        }
        problemKey = sawRejection ? Self.rejectedProblemKey : nil
        return .completed
    }

    // MARK: Push

    func push<Model: SyncableModel>(_ type: Model.Type) async throws {
        let pending = (try? context.fetch(Model.pending)) ?? []
        // Also when the network drops halfway: what did arrive keeps its cleared flag.
        defer { try? context.save() }
        var start = 0
        while start < pending.count {
            let end = min(start + SyncRules.pushBatchSize, pending.count)
            try await send(Array(pending[start..<end]))
            start = end
        }
    }

    /// One request for all rows. When the server refuses it, the rows go one by one, so a single
    /// bad row does not hold back the others (ARCHITECTURE §3.6).
    private func send<Model: SyncableModel>(_ models: [Model]) async throws {
        let sentUpdatedAt = models.map(\.updatedAt)
        do {
            try await remote.upsert(models.map(\.record), table: Model.tableName, keyColumn: Model.keyColumn)
        } catch RemoteStoreError.rejected {
            if models.count == 1 {
                sawRejection = true
            } else {
                for model in models {
                    try await send([model])
                }
            }
            return
        }
        for (model, updatedAt) in zip(models, sentUpdatedAt) where SyncRules.canClearPushFlag(sentUpdatedAt: updatedAt, currentUpdatedAt: model.updatedAt) {
            if model.deletedAt == nil {
                model.needsPush = false
            } else {
                // The server has the deletion; the local marker has done its work.
                context.delete(model)
            }
        }
    }

    // MARK: Pull

    func pull<Model: SyncableModel>(_ type: Model.Type) async throws {
        let table = Model.tableName
        let cursor = try? context.fetch(FetchDescriptor<SyncCursor>(predicate: #Predicate<SyncCursor> { $0.table == table })).first
        let since: Date?
        switch SyncRules.pullStart(cursor: cursor?.syncedAt, lastPull: cursor?.pulledAt, now: now()) {
        case .everything:
            since = nil
        case .resetThenEverything:
            // Deletions may have been cleaned up on the server: drop what is not waiting to be
            // sent. Saved right away, because a row that comes back has the same unique id.
            for model in (try? context.fetch(FetchDescriptor<Model>())) ?? [] where !model.needsPush {
                context.delete(model)
            }
            try? context.save()
            since = nil
        case let .since(date):
            since = date
        }

        var newest = cursor?.syncedAt
        var offset = 0
        var pageCount = SyncRules.pullPageSize
        while pageCount == SyncRules.pullPageSize {
            let page = try await remote.fetch(
                Model.Record.self, table: table, keyColumn: Model.keyColumn, since: since, offset: offset, limit: SyncRules.pullPageSize
            )
            apply(page, to: Model.self)
            newest = SyncRules.nextCursor(current: newest, pageSyncedAt: page.compactMap(\.syncedAt))
            offset += page.count
            pageCount = page.count
        }

        if let cursor {
            cursor.syncedAt = newest
            cursor.pulledAt = now()
        } else {
            context.insert(SyncCursor(table: table, syncedAt: newest, pulledAt: now()))
        }
        try? context.save()
    }

    private func apply<Model: SyncableModel>(_ page: [Model.Record], to type: Model.Type) {
        guard !page.isEmpty else { return }
        // Looked up by id: the unique attribute is not relied on to merge a row into an existing one.
        let known = (try? context.fetch(Model.matching(ids: page.map(\.id)))) ?? []
        var local = Dictionary(known.map { ($0.syncID, $0) }, uniquingKeysWith: { first, _ in first })
        for record in page {
            let existing = local[record.id]
            let action = SyncRules.pullAction(
                local: existing.map { LocalRowState(updatedAt: $0.updatedAt, needsPush: $0.needsPush) },
                remote: RemoteRowState(updatedAt: record.updatedAt, isDeleted: record.deletedAt != nil)
            )
            switch action {
            case .insert:
                let model = Model.make(from: record)
                context.insert(model)
                local[record.id] = model
            case .overwrite:
                existing?.apply(record)
            case .deleteLocal:
                if let existing {
                    context.delete(existing)
                    local[record.id] = nil
                }
            case .keepLocal, .ignore:
                break
            }
        }
    }
}
