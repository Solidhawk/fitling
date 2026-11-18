import SwiftData

enum FitlingMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FitlingSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
