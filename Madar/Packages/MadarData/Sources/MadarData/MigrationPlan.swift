import SwiftData

/// Fresh-store baseline. Future schema versions must add tested forward-only stages.
public enum MadarMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [MadarSchema.self] }
    public static var stages: [MigrationStage] { [] }
}
