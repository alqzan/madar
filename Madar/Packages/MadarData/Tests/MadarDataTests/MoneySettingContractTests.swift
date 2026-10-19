import Testing
@testable import MadarData
struct MoneySettingContractTests {
    @Test func agreedDefaultsAndFreeScheduleValidation() throws {
        let s = try SettingsSchema.bundled()
        #expect(try s.definition(for: "mal.offsetCapDailies").defaultValue == .number(3))
        #expect(try s.definition(for: "mal.bigExpenseRule").defaultValue == .string("dailies"))
        #expect(try s.definition(for: "mal.reconcileEveryDays").defaultValue == .number(90))
        #expect(try s.definition(for: "mal.cashbackDestination").defaultValue == .string(""))
        try s.validate(.string(""), for: "mal.cashbackDestination")
        try s.validate(.string("57F4B8D3-A5C8-4D8F-8F49-FE54E923C428"), for: "mal.cashbackDestination")
        #expect(throws: DataError.self) { try s.validate(.string("not-an-envelope"), for: "mal.cashbackDestination") }
        try s.validate(.number(1), for: "mal.reconcileEveryDays")
        try s.validate(.number(365), for: "mal.reconcileEveryDays")
        #expect(throws: DataError.self) { try s.validate(.number(0), for: "mal.reconcileEveryDays") }
        #expect(throws: DataError.self) { try s.validate(.number(366), for: "mal.reconcileEveryDays") }
        let valid: JSONValue = .object(["enabled": .bool(true), "every": .number(6), "unit": .string("month"), "firstDayKey": .string("2027-02-18")])
        try s.validate(valid, for: "mal.salarySchedule")
        #expect(throws: DataError.self) { try s.validate(.object(["enabled": .bool(true), "every": .number(6), "unit": .string("month"), "firstDayKey": .string("2026-02-31")]), for: "mal.salarySchedule") }
        #expect(throws: DataError.self) { try s.validate(.number(-1), for: "mal.offsetCapDailies") }
        #expect(throws: DataError.self) { try s.validate(.object(["enabled": .bool(true), "every": .number(0), "unit": .string("month"), "firstDayKey": .string("2027-02-18")]), for: "mal.salarySchedule") }
    }
}
