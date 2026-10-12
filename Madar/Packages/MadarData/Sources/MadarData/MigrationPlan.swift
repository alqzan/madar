import SwiftData

/// V1 is converted by LegacyGenerationMigration into a separately staged generation.
/// V2 to V3 is a lightweight additive migration for PrayerLog.fridayKind.
public enum MadarMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [MadarSchemaV2.self, MadarSchema.self] }
    public static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: MadarSchemaV2.self, toVersion: MadarSchema.self)]
    }
}
