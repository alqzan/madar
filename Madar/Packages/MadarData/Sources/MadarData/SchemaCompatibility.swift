import Foundation

enum SchemaCompatibility {
    static func validateDeviceVersion(at directory: URL) throws {
        let stamp = directory.appendingPathComponent("DeviceSchemaVersion.json")
        guard FileManager.default.fileExists(atPath: stamp.path) else { return }
        let version = try JSONDecoder().decode(Int.self, from: Data(contentsOf: stamp))
        guard (1...MadarSchema.version).contains(version) else {
            throw version > MadarSchema.version ? DataError.newerStore : DataError.invalidValue("device store version")
        }
    }
    static func modelNames(version: Int) throws -> [String] {
        switch version {
        case 1: MadarSchemaV1.syncedNames
        case 2: MadarSchemaV2.syncedNames
        case 3: MadarSchemaV3.syncedNames
        case 4: MadarSchemaV4.syncedNames
        case 5: MadarSchemaV5.syncedNames
        case 6: MadarSchemaV6.syncedNames
        case 7: MadarSchemaV7.syncedNames
        case 8: MadarSchemaV8.syncedNames
        case 9: MadarSchemaV9.syncedNames
        case 10: MadarSchemaV10.syncedNames
        case 11: MadarSchemaV11.syncedNames
        case 12: MadarSchemaV12.syncedNames
        case 13: MadarSchemaV13.syncedNames
        case 14: MadarSchemaV14.syncedNames
        case 15: MadarSchemaV15.syncedNames
        case 16: MadarSchemaV16.syncedNames
        case 17: MadarSchemaV17.syncedNames
        case MadarSchema.version: MadarSchema.syncedNames
        default: throw version > MadarSchema.version ? DataError.newerStore : DataError.unsupportedBackup
        }
    }
    /// Called only after the source's schema, original manifest and every original byte hash pass.
    static func currentRecords(_ records: [DataRecord], from version: Int) throws -> [DataRecord] {
        _ = try modelNames(version:version)
        return records.map { original in
            var row = original
            if version == 1 {
                if row.model == "Transaction" { row.model = "MoneyTransaction" }
                // These are model-name discriminators. sourceModel is provenance and must stay unchanged.
                for key in ["targetModel","pinnedEventKind","eventKind"] where row.fields[key] == .string("Transaction") { row.fields[key] = .string("MoneyTransaction") }
            }
            if version < 3, row.model == "PrayerLog" {
                row.fields["fridayKind"] = .null
            }
            // V5 (M5-D01): the new money fields take their dictionary defaults; no existing value changes.
            if version < 5 {
                switch row.model {
                case "Account": row.fields["last4"] = .null; row.fields["tracked"] = .bool(true)
                case "Card": row.fields["kind"] = .string("credit")
                case "EnvelopePlan": row.fields["period"] = .string("perCycle"); row.fields["startDayKey"] = .null
                case "ZakatProfile":
                    row.fields["nisabBasis"] = .string("gold"); row.fields["nisabSilverMg"] = .number(595_000)
                    row.fields["silverPricePerGramMinor"] = .null; row.fields["silverPriceSetAt"] = .null
                default: break
                }
            }
            // V6 (M5-V04): a plan written before the repayment fields has neither.
            if version < 6, row.model == "EnvelopePlan" {
                row.fields["repaymentTotalMinor"] = .null; row.fields["repaymentPaychecks"] = .null
            }
            // V7 (M5-X00): rows written before the flexible schedule and the stamp's reason have none of them.
            if version < 7 {
                switch row.model {
                case "Obligation": row.fields["repeatEvery"] = .null; row.fields["repeatUnit"] = .null; row.fields["firstDueDayKey"] = .null
                case "MoneyTransaction": row.fields["budgetIgnoreReason"] = .null
                default: break
                }
            }
            // V8 (M3-V09): older entries have no dedicated tag field; archived Day One JSON remains intact.
            if version < 8, row.model == "Entry" { row.fields["tags"] = .null }
            // V9 (M5-V15): the balance record can now point to an installment obligation.
            if version < 9, row.model == "Reconciliation" { row.fields["obligationID"] = .null }
            // V10 (M5-V16): a category may guide future purchases to a preferred card; history stays unchanged.
            if version < 10, row.model == "Category" { row.fields["preferredCardID"] = .null }
            // V11: old one-time days keep their original disappear-after-date behavior.
            if version < 11, row.model == "UpcomingDay" { row.fields["countUpAfter"] = .bool(false) }
            // V12: a habit time recorded before the diary link has none.
            if version < 12, row.model == "HabitEvent", row.fields["entryID"] == nil { row.fields["entryID"] = .null }
            // V13: every trip recorded before multi-country legs is its own journey.
            if version < 13, row.model == "Trip", row.fields["journeyID"] == nil { row.fields["journeyID"] = .null }
            // V14: pre-existing categories have no recorded provenance and must not train merchant suggestions.
            if version < 14, row.model == "MoneyTransaction", row.fields["categorySource"] == nil { row.fields["categorySource"] = .null }
            // V15: every older habit policy has no day interval.
            if version < 15, row.model == "HabitPolicy", row.fields["intervalDays"] == nil { row.fields["intervalDays"] = .null }
            // V16: existing intentions have no later check-ins; existing media has no generated voice metadata.
            if version < 16 {
                if row.model == "Niyya" {
                    row.fields["weeklyReview"] = .null; row.fields["monthlyReview"] = .null
                } else if row.model == "Media" {
                    row.fields["title"] = .null; row.fields["voiceTone"] = .null; row.fields["audioLevelsJSON"] = .null
                }
            }
            // V18 (D7): a trip recorded before the dismissal date has none.
            if version < 18, row.model == "Trip", row.fields["dismissedAt"] == nil { row.fields["dismissedAt"] = .null }
            return row
        }
    }
}
