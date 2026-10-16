import SwiftData

/// V1 uses staged conversion. V2 adds Friday kind; V4 adds only HabitEvent.
public enum MadarMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [MadarSchemaV2.self, MadarSchemaV3.self, MadarSchema.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: MadarSchemaV2.self, toVersion: MadarSchemaV3.self),
         .lightweight(fromVersion: MadarSchemaV3.self, toVersion: MadarSchema.self)]
    }
}
