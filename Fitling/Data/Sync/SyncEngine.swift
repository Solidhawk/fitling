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
        .completed
    }

    func push<Model: SyncableModel>(_ type: Model.Type) async throws {
    }

    func pull<Model: SyncableModel>(_ type: Model.Type) async throws {
    }
}
