import Foundation
import Observation
import Supabase
import SwiftData
import FitlingCore

enum PullOutcome: Equatable, Sendable {
    /// Neither the server nor this device has a profile: onboarding may start.
    case remoteMissing
    case adoptedRemote
    /// This device has changes the server has not seen yet; they win on the next push.
    case keptLocal
    case unchanged
}

enum SyncError: Error, Equatable, Sendable {
    case network
    /// The server refused the data (for example a check constraint); retrying will not help.
    case rejected(String)
}

/// Offline-first sync of the one profile row. Network calls are async and never block the UI;
/// SwiftData is only touched on the main context.
@Observable
@MainActor
final class ProfileSync {
    private let context: ModelContext
    /// A ModelContext does not keep its container alive; work that outlives the caller (the delayed
    /// push) would otherwise touch a released store.
    private let container: ModelContainer
    private let fetchRemote: @Sendable (UUID) async throws -> ProfileRecord?
    private let upsertRemote: @Sendable (ProfileRecord) async throws -> Void
    private(set) var lastRejection: String?

    init(
        context: ModelContext,
        fetchRemote: @escaping @Sendable (UUID) async throws -> ProfileRecord?,
        upsertRemote: @escaping @Sendable (ProfileRecord) async throws -> Void
    ) {
        self.context = context
        self.container = context.container
        self.fetchRemote = fetchRemote
        self.upsertRemote = upsertRemote
    }

    static func live(client: SupabaseClient, context: ModelContext) -> ProfileSync {
        ProfileSync(
            context: context,
            fetchRemote: { id in
                let rows: [ProfileRecord] = try await client.from("profiles")
                    .select()
                    .eq("id", value: id)
                    .limit(1)
                    .execute()
                    .value
                return rows.first
            },
            upsertRemote: { record in
                try await client.from("profiles").upsert(record).execute()
            }
        )
    }

    func localProfile(userID: UUID) -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(predicate: #Predicate { $0.id == userID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func pull(userID: UUID) async throws(SyncError) -> PullOutcome {
        let remote: ProfileRecord?
        do {
            remote = try await fetchRemote(userID)
        } catch {
            throw Self.syncError(error)
        }
        let local = localProfile(userID: userID)

        switch (local, remote) {
        case (nil, nil):
            return .remoteMissing
        case (.some, nil):
            return .keptLocal
        case let (nil, .some(remote)):
            guard let profile = remote.makeProfile() else { throw .rejected("unreadable profile row") }
            context.insert(profile)
            try? context.save()
            return .adoptedRemote
        case let (.some(local), .some(remote)):
            if local.needsPush { return .keptLocal }
            guard remote.updatedAt > local.updatedAt else { return .unchanged }
            remote.apply(to: local)
            try? context.save()
            return .adoptedRemote
        }
    }

    func push(userID: UUID) async throws(SyncError) {
        guard let profile = localProfile(userID: userID), profile.needsPush else { return }
        let sentUpdatedAt = profile.updatedAt
        do {
            try await upsertRemote(ProfileRecord(profile))
        } catch {
            let failure = Self.syncError(error)
            if case let .rejected(reason) = failure { lastRejection = reason }
            throw failure
        }
        lastRejection = nil
        // An edit made while the request was in flight still needs its own push.
        if profile.updatedAt == sentUpdatedAt {
            profile.needsPush = false
            try? context.save()
        }
    }

    func deleteLocalData() throws {
        // Per object rather than `delete(model:)`: that batch delete misses objects not yet saved.
        for profile in try context.fetch(FetchDescriptor<UserProfile>()) {
            context.delete(profile)
        }
        try context.save()
    }

    nonisolated static func syncError(_ error: any Error) -> SyncError {
        error is URLError ? .network : .rejected(String(describing: error))
    }
}

extension ProfileRecord {
    /// A local profile for a row this device has never seen.
    func makeProfile() -> UserProfile? {
        guard let birthDate = BirthDateCalendar.date(from: birthDate),
              let sex = Sex(rawValue: sex),
              let activityLevel = ActivityLevel(rawValue: activityLevel),
              let goal = Goal(rawValue: goal) else { return nil }
        let profile = UserProfile(
            id: id,
            healthConsentAt: healthConsentAt,
            healthConsentVersion: healthConsentVersion,
            body: BodyProfile(birthDate: birthDate, sex: sex, heightCm: heightCm, weightKg: weightKg, activityLevel: activityLevel, goal: goal),
            targets: NutritionTargets(kcal: kcalTarget, proteinG: proteinTargetG, carbsG: carbsTargetG, fatG: fatTargetG),
            targetsAreManual: targetsAreManual,
            updatedAt: updatedAt
        )
        profile.needsPush = false
        return profile
    }
}
