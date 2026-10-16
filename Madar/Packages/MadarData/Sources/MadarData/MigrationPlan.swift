import SwiftData

/// V1 uses staged conversion. V3 adds Friday kind; V4 adds only HabitEvent; V5 adds only defaulted or optional money
/// fields (RM1 card kind, RM3 plan period and start, RM5 account last 4 and wallet tracking, RM7 nisab basis).
public enum MadarMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [MadarSchemaV2.self, MadarSchemaV3.self, MadarSchemaV4.self, MadarSchema.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: MadarSchemaV2.self, toVersion: MadarSchemaV3.self),
         .lightweight(fromVersion: MadarSchemaV3.self, toVersion: MadarSchemaV4.self),
         .lightweight(fromVersion: MadarSchemaV4.self, toVersion: MadarSchema.self)]
    }
}
