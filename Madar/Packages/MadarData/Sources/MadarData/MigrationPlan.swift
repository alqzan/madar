import SwiftData

/// V2 baseline. V1 is frozen in MadarSchemaV1 and converted by LegacyGenerationMigration
/// into a separately staged generation. Never let SwiftData infer an entity rename in place.
public enum MadarMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [MadarSchema.self] }
    public static var stages: [MigrationStage] { [] }
}
