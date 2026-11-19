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
        /// The local data was erased while the round ran (signing out); nothing from it was kept.
        case interrupted
    }

    /// String Catalog key shown while the server keeps refusing a row.
    static let rejectedProblemKey = "profile.sync.rejected"
    /// String Catalog key shown after a read the server refused.
    static let failedProblemKey = "error.server"

    /// Thrown inside a round when `eraseLocalData()` ran during one of its requests.
    private struct Interrupted: Error {}

    /// Held on purpose: a `ModelContext` does not keep its container alive, and a delayed round
    /// would otherwise touch a released store.
    private let container: ModelContainer
    private let remote: any RemoteStore
    private let tables: [any SyncTable]
    private let now: () -> Date
    private(set) var problemKey: String?
    private var isRunning = false
    private var runAgain = false
    /// Callers that asked for a round while one ran; the next round answers them.
    private var waiting: [CheckedContinuation<Outcome, Never>] = []
    private var sawRejection = false
    /// Goes up with every erase. A request that returns into another epoch is thrown away: its
    /// rows belong to the data that was just wiped, and its models may no longer exist.
    private var epoch = 0

    init(container: ModelContainer, remote: any RemoteStore, tables: [any SyncTable], now: @escaping () -> Date = Date.init) {
        self.container = container
        self.remote = remote
        self.tables = tables
        self.now = now
    }

    var context: ModelContext { container.mainContext }

    /// Whether any table holds a change the server has not seen yet.
    var hasUnsentChanges: Bool {
        false
    }

    /// One round: push every table, then pull every table. Never more than one round at a time:
    /// a call during a round waits for one more round, which includes what changed meanwhile.
    @discardableResult
    func sync() async -> Outcome {
        guard !isRunning else {
            return .interrupted
        }
        isRunning = true
        var outcome = await round()
        while runAgain {
            runAgain = false
            let answered = waiting
            waiting = []
            outcome = await round()
            answered.forEach { $0.resume(returning: outcome) }
        }
        isRunning = false
        return outcome
    }

    /// Removes everything this device stores: after signing out or deleting the account, the data
    /// of the previous user must not stay behind (ARCHITECTURE §3.7).
    func eraseLocalData() {
    }

    // Per object rather than `delete(model:)`: that batch delete misses objects not yet saved.
    private func erase<Model: PersistentModel>(_ type: Model.Type) {
        for object in (try? context.fetch(FetchDescriptor<Model>())) ?? [] {
            context.delete(object)
        }
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
        } catch is Interrupted {
            return .interrupted
        } catch {
            // A refused row is dealt with in the push itself; this is a read the server refused.
            problemKey = Self.failedProblemKey
            return .failed
        }
        problemKey = sawRejection ? Self.rejectedProblemKey : nil
        return .completed
    }

    private func ensureStill(in started: Int) throws {
        if epoch != started { throw Interrupted() }
    }

    // MARK: Push

    func push<Model: SyncableModel>(_ type: Model.Type) async throws {
        let started = epoch
        let pending = (try? context.fetch(Model.pending)) ?? []
        // Also when the network drops halfway: what did arrive keeps its cleared flag.
        defer { if epoch == started { try? context.save() } }
        var start = 0
        while start < pending.count {
            let end = min(start + SyncRules.pushBatchSize, pending.count)
            try await send(Array(pending[start..<end]), started: started)
            start = end
        }
    }

    /// One request for all rows. When the server refuses it, the rows go one by one, so a single
    /// bad row does not hold back the others (ARCHITECTURE §3.6).
    private func send<Model: SyncableModel>(_ models: [Model], started: Int) async throws {
        let sentUpdatedAt = models.map(\.updatedAt)
        do {
            try await remote.upsert(models.map(\.record), table: Model.tableName, keyColumn: Model.keyColumn)
        } catch RemoteStoreError.rejected {
            try ensureStill(in: started)
            if models.count == 1 {
                sawRejection = true
            } else {
                for model in models {
                    try await send([model], started: started)
                }
            }
            return
        }
        try ensureStill(in: started)
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
        let started = epoch
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
            try ensureStill(in: started)
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
