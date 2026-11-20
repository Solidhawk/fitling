import Foundation

/// What sync knows about a row on the device.
public struct LocalRowState: Sendable, Equatable {
    public var updatedAt: Date
    public var needsPush: Bool

    public init(updatedAt: Date, needsPush: Bool) {
        self.updatedAt = updatedAt
        self.needsPush = needsPush
    }
}

/// What sync knows about a row that came from the server.
public struct RemoteRowState: Sendable, Equatable {
    public var updatedAt: Date
    public var isDeleted: Bool

    public init(updatedAt: Date, isDeleted: Bool) {
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

public enum PullAction: Sendable, Equatable {
    case insert
    case overwrite
    case deleteLocal
    /// The device has a newer change that the server has not seen yet.
    case keepLocal
    /// A deletion of a row the device never had.
    case ignore
}

public enum PullStart: Sendable, Equatable {
    /// First pull of this table on this device.
    case everything
    /// The last pull is so long ago that deletions may have been cleaned up: empty the table first.
    case resetThenEverything
    case since(Date)
}

/// The decisions of offline-first sync, apart from storage and network (ARCHITECTURE §3).
public enum SyncRules {
    public static let pushBatchSize = 200
    /// At most the Data API's `max_rows` (1,000 on Supabase unless changed): the pull stops at the first page
    /// that comes back shorter, so a larger page would end it after one capped page and miss rows.
    public static let pullPageSize = 500
    /// Pull again from this long before the cursor, to catch transactions that committed late.
    public static let pullOverlap: TimeInterval = 5 * 60
    /// The server removes deletion markers after this long.
    public static let deletionRetention: TimeInterval = 90 * 24 * 60 * 60

    public static func pullAction(local: LocalRowState?, remote: RemoteRowState) -> PullAction {
        guard let local else { return remote.isDeleted ? .ignore : .insert }
        if local.needsPush, local.updatedAt > remote.updatedAt { return .keepLocal }
        return remote.isDeleted ? .deleteLocal : .overwrite
    }

    /// `cursor` is the highest `synced_at` seen, `lastPull` the moment of the last pull that
    /// succeeded. The retention counts from the last pull and not from the cursor: a table nobody
    /// changes keeps an old cursor, and must not be emptied and fetched again on every round.
    public static func pullStart(cursor: Date?, lastPull: Date?, now: Date) -> PullStart {
        guard let lastPull else { return .everything }
        if now.timeIntervalSince(lastPull) > deletionRetention { return .resetThenEverything }
        guard let cursor else { return .everything }
        return .since(cursor.addingTimeInterval(-pullOverlap))
    }

    /// The highest `synced_at` seen so far. Never moves back.
    public static func nextCursor(current: Date?, pageSyncedAt: [Date]) -> Date? {
        ([current].compactMap { $0 } + pageSyncedAt).max()
    }

    /// After a successful push: only when the row did not change while it was under way.
    public static func canClearPushFlag(sentUpdatedAt: Date, currentUpdatedAt: Date) -> Bool {
        sentUpdatedAt == currentUpdatedAt
    }
}
