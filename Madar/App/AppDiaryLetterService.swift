import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer
import MadarCommands

/// §7.3 N04. Sealed text never leaves the store for display: a card carries text only once the letter is opened.
struct DiaryLetterCard: Identifiable, Equatable {
    let id: UUID
    let state: DiaryLetterState
    let writtenDay: GregorianDay
    let waitingFor: String
    let text: String?
    let openedAt: Date?
}
struct DiaryProjectCard: Identifiable, Equatable {
    struct Line: Identifiable, Equatable { let id: UUID; let day: GregorianDay; let text: String }
    let id: UUID
    let name: String
    let intention: String
    let keyword: String?
    let finishedAt: Date?
    let reflection: String?
    let lines: [Line]
}
struct DiaryLetterChoice: Identifiable, Equatable { let id: String; let title: String; let trigger: DiaryLetterTrigger; let target: UUID? }

extension AppDiaryService {
    private func command(_ name: String, _ payload: [String: MadarCore.JSONValue]) async throws { try await app.executeDiaryCommand(name, payload: payload) }
    /// Runs the forward-only state check (diary open and foreground).
    func refreshLetters() async throws {
        try authorizeRead()
        guard try DiaryLetterCheck.pending(context: ModelContext(app.container), now: app.prayerNow()) else { return }
        try await command("diary.refreshLetters", [:])
    }
    func letters() throws -> [DiaryLetterCard] {
        try authorizeRead()
        let context = ModelContext(app.container)
        let projects = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Project>()).map { ($0.id, $0.name) })
        return try context.fetch(FetchDescriptor<Letter>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).compactMap { row in
            guard let state = DiaryLetterState(rawValue: row.state), let trigger = DiaryLetterTrigger(rawValue: row.triggerKind) else { return nil }
            return .init(id: row.id, state: state, writtenDay: writtenDay(row.createdAt), waitingFor: waitingFor(trigger, value: row.triggerValue, target: row.triggerTargetID.flatMap { projects[$0] }),
                         text: state == .opened ? row.text : nil, openedAt: row.openedAt)
        }
    }
    /// Display only: Letter stores no day, so the written day is read from createdAt in the place active then.
    func writtenDay(_ at: Date) -> GregorianDay {
        let place = (try? PrayerRepository(context: ModelContext(app.container)).place(at: at)) ?? app.activePlace
        return GregorianDay.containing(at, in: place.timeZone)
    }
    func waitingFor(_ trigger: DiaryLetterTrigger, value: String?, target: String?) -> String {
        switch trigger {
        case .date: return value.flatMap { try? GregorianDay($0) }.map { "تُفتح في " + dateTitle($0, calendar: FirstCalendar(rawValue: app.string("core.firstCalendar")) ?? .hijri) } ?? "تُفتح في يومها"
        case .hijriDate: return value.map { "تُفتح في " + hijriTitle($0) } ?? "تُفتح في يومها"
        case .tripStart: return "تُفتح حين تصل في سفرك القادم"
        case .tripEnd: return "تُفتح حين تعود من سفرك"
        case .projectFinished: return target.map { "تُفتح حين ينتهي «" + $0 + "»" } ?? "تُفتح حين ينتهي مشروعها"
        case .ramadanStart: return "تُفتح في أول يوم من رمضان القادم"
        }
    }
    func hijriTitle(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return key }
        let months = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        return digits.string(parts[2]) + " " + months[max(0, min(11, parts[1] - 1))] + " " + digits.string(parts[0])
    }
    /// Only triggers that can happen in this build; a project choice appears only when an open project exists.
    func letterChoices() throws -> [DiaryLetterChoice] {
        try authorizeRead()
        let context = ModelContext(app.container), now = clock()
        var choices: [DiaryLetterChoice] = [.init(id: "date", title: "في تاريخ", trigger: .date, target: nil), .init(id: "hijri", title: "في تاريخ هجري", trigger: .hijriDate, target: nil),
                                            .init(id: "ramadan", title: "أول رمضان القادم", trigger: .ramadanStart, target: nil)]
        if let trip = try PrayerRepository(context: context).activeTrip(at: now) {
            choices.append(.init(id: "trip-end", title: "حين أعود من " + trip.city, trigger: .tripEnd, target: trip.id))
        } else {
            choices.append(.init(id: "trip-start", title: "حين أصل في سفري القادم", trigger: .tripStart, target: nil))
        }
        for project in try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil && $0.finishedAt == nil })) {
            choices.append(.init(id: "project-" + project.id.uuidString, title: "حين ينتهي «" + project.name + "»", trigger: .projectFinished, target: project.id))
        }
        return choices
    }
    func sealLetter(_ text: String, choice: DiaryLetterChoice, date: Date) async throws {
        var payload: [String: MadarCore.JSONValue] = ["id": .string(UUID().uuidString), "text": .string(text), "trigger": .string(choice.trigger.rawValue)]
        let zone = app.activePlace.timeZone
        switch choice.trigger {
        case .date: payload["value"] = .string(GregorianDay.containing(date, in: zone).description)
        case .hijriDate: payload["value"] = .string(DiaryLetters.hijriKey(HijriCalendar.date(for: date, timeZone: zone)))
        default: break
        }
        if let target = choice.target { payload["targetID"] = .string(target.uuidString) }
        try await command("diary.sealLetter", payload)
    }
    /// Opens once and returns the text; reading an opened letter again changes nothing.
    func openLetter(_ id: UUID) async throws -> String {
        try await command("diary.openLetter", ["id": .string(id.uuidString)])
        guard let row = try ModelContext(app.container).fetch(FetchDescriptor<Letter>(predicate: #Predicate { $0.id == id })).first, row.state == DiaryLetterState.opened.rawValue else { throw DataError.invalidValue("missing letter") }
        return row.text
    }
    func rescheduleLetter(_ id: UUID, to date: Date) async throws {
        try await command("diary.rescheduleLetter", ["id": .string(id.uuidString), "dayKey": .string(GregorianDay.containing(date, in: app.activePlace.timeZone).description)])
    }
    /// Sealed letters written on this day: shown on the page as a blurred line, never their text.
    func sealedLetters(writtenOn day: GregorianDay) throws -> Int { try letters().filter { $0.writtenDay == day && $0.state != .opened }.count }

    func projects() throws -> [DiaryProjectCard] {
        try authorizeRead()
        let context = ModelContext(app.container)
        let entries = Self.visible(try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil && $0.projectID != nil }, sortBy: [SortDescriptor(\.eventAt)])))
        return try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }, sortBy: [SortDescriptor(\.createdAt)])).map { project in
            .init(id: project.id, name: project.name, intention: project.intention, keyword: project.keyword, finishedAt: project.finishedAt, reflection: project.reflection,
                  lines: entries.filter { $0.projectID == project.id }.compactMap { row in (try? GregorianDay(row.dayKey)).map { .init(id: row.id, day: $0, text: row.text) } })
        }
    }
    /// «يتعلّق بـ«…»؟» for one line: open projects whose keyword the line mentions, unless it is linked already.
    func suggestions(for text: String, linked: UUID?) throws -> [DiaryProjectCard] {
        guard linked == nil else { return [] }
        return try projects().filter { $0.finishedAt == nil && $0.keyword.map { DiaryProjectKeyword.mentions(text, keyword: $0) } == true }
    }
    func saveProject(_ id: UUID = UUID(), name: String, intention: String, keyword: String) async throws {
        try await command("diary.saveProject", ["id": .string(id.uuidString), "name": .string(name), "intention": .string(intention), "keyword": .string(keyword)])
    }
    func finishProject(_ id: UUID, reflection: String) async throws { try await command("diary.finishProject", ["id": .string(id.uuidString), "reflection": .string(reflection)]) }
    func deleteProject(_ id: UUID) async throws { try await command("diary.deleteProject", ["id": .string(id.uuidString)]) }
    func link(_ entry: String, to project: UUID?) async throws {
        try await command("diary.linkEntry", ["entryID": .string(entry), "projectID": project.map { .string($0.uuidString) } ?? .null])
    }
    /// Line id → linked project name, and per-line suggestions, for the day page.
    func projectNotes(_ day: GregorianDay) throws -> (links: [String: String], suggestions: [String: DiaryProjectCard]) {
        try authorizeRead()
        let key = day.description, context = ModelContext(app.container)
        let projects = try projects(), names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        let rows = Self.visible(try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.dayKey == key && $0.deletedAt == nil && $0.mergedInto == nil })))
        var links: [String: String] = [:], suggestions: [String: DiaryProjectCard] = [:]
        for row in rows {
            if let id = row.projectID, let name = names[id] { links[row.id.uuidString] = name }
            else if row.projectID == nil, let match = projects.first(where: { $0.finishedAt == nil && $0.keyword.map { DiaryProjectKeyword.mentions(row.text, keyword: $0) } == true }) { suggestions[row.id.uuidString] = match }
        }
        return (links, suggestions)
    }
}
