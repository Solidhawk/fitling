import Foundation
import SwiftData
import FitlingCore

// These three never leave the device and have no table in Supabase.
extension FitlingSchemaV1 {
    /// A progress photo. Only the file name is stored here; the image sits in the app's own
    /// folder and is never uploaded.
    @Model
    final class ProgressPhoto {
        @Attribute(.unique) var id: UUID
        var takenOn: String
        var fileName: String
        var note: String?

        init(id: UUID, takenOn: Day, fileName: String) {
            self.id = id
            self.takenOn = takenOn.isoString
            self.fileName = fileName
        }
    }

    /// Workout energy from HealthKit for one day. Kept on the device: health data from Apple
    /// Health is not copied to our server.
    @Model
    final class DayActivity {
        @Attribute(.unique) var day: String
        var workoutKcal: Double
        var updatedAt: Date

        init(day: Day, workoutKcal: Double, updatedAt: Date) {
            self.day = day.isoString
            self.workoutKcal = workoutKcal
            self.updatedAt = updatedAt
        }
    }

    /// How far a table has been pulled: the highest `synced_at` seen so far.
    @Model
    final class SyncCursor {
        @Attribute(.unique) var table: String
        var syncedAt: Date

        init(table: String, syncedAt: Date) {
            self.table = table
            self.syncedAt = syncedAt
        }
    }
}
