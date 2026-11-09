import SwiftData

/// V1 uses staged conversion. V3 adds Friday kind; V4 adds only HabitEvent; V5 adds only defaulted or optional money
/// fields (RM1 card kind, RM3 plan period and start, RM5 account last 4 and wallet tracking, RM7 nisab basis); V6 adds only the optional
/// repayment total and salary count on EnvelopePlan (M5-V04, owner 16 Oct); V7 adds only optional fields: Obligation's free
/// interval and first due day, and the budget-ignore stamp's reason on MoneyTransaction (M5-X00, owner 16 Oct); V8 adds optional
/// Day One tags to Entry (M3-V09, owner-approved idea, 18 Oct); V9 adds optional Reconciliation.obligationID (M5-V15, owner-approved, 19 Oct);
/// V11 adds default-false UpcomingDay.countUpAfter (owner, 25 Oct). V12 adds optional HabitEvent.entryID, a link to that day's diary line (owner, 25 Oct).
/// V13 adds optional Trip.journeyID so later legs of one multi-country trip share the first leg's id (OR-09, owner 26 Oct).
/// V14 adds optional MoneyTransaction.categorySource; old and imported categories do not train merchant suggestions.
/// V15 adds optional HabitPolicy.intervalDays for «كل N أيام» habits (FB-39, owner 6 Nov); older policies keep their frequency.
/// V16 adds optional diary intention reviews and generated audio insights; existing diary text, outcomes, and media bytes are retained.
/// V10 adds optional Category.preferredCardID to guide future expense entry without rewriting historical card IDs (M5-V16, owner-approved, 18 Oct).
public enum MadarMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [MadarSchemaV2.self, MadarSchemaV3.self, MadarSchemaV4.self, MadarSchemaV5.self, MadarSchemaV6.self, MadarSchemaV7.self, MadarSchemaV8.self, MadarSchemaV9.self, MadarSchemaV10.self, MadarSchemaV11.self, MadarSchemaV12.self, MadarSchemaV13.self, MadarSchemaV14.self, MadarSchemaV15.self, MadarSchema.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: MadarSchemaV2.self, toVersion: MadarSchemaV3.self),
         .lightweight(fromVersion: MadarSchemaV3.self, toVersion: MadarSchemaV4.self),
         .lightweight(fromVersion: MadarSchemaV4.self, toVersion: MadarSchemaV5.self),
         .lightweight(fromVersion: MadarSchemaV5.self, toVersion: MadarSchemaV6.self),
         .lightweight(fromVersion: MadarSchemaV6.self, toVersion: MadarSchemaV7.self),
         .lightweight(fromVersion: MadarSchemaV7.self, toVersion: MadarSchemaV8.self),
         .lightweight(fromVersion: MadarSchemaV8.self, toVersion: MadarSchemaV9.self),
         .lightweight(fromVersion: MadarSchemaV9.self, toVersion: MadarSchemaV10.self),
         .lightweight(fromVersion: MadarSchemaV10.self, toVersion: MadarSchemaV11.self),
         .lightweight(fromVersion: MadarSchemaV11.self, toVersion: MadarSchemaV12.self),
         .lightweight(fromVersion: MadarSchemaV12.self, toVersion: MadarSchemaV13.self),
         .lightweight(fromVersion: MadarSchemaV13.self, toVersion: MadarSchemaV14.self),
         .lightweight(fromVersion: MadarSchemaV14.self, toVersion: MadarSchemaV15.self),
         .lightweight(fromVersion: MadarSchemaV15.self, toVersion: MadarSchema.self)]
    }
}
