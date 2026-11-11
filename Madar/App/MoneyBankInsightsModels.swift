import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

// Owner decisions, 11 Nov 2026: what bank messages teach the money room besides movements. Three quiet things, none of them a
// notification: upcoming dues, a balance the bank printed that differs from the book, and a card tail Madar does not know yet.

/// The bank printed a balance that differs from Madar's book at that moment (one row per account, newest message).
struct MoneyBankMismatch: Identifiable, Equatable, Sendable {
    var id: UUID { accountID }
    var accountID: UUID
    var accountName: String
    var expectedMinor: Int
    var observedMinor: Int
    var at: Date
    /// The names `money.reconcile` accepts for this difference (empty for a negative, unsettleable balance).
    var names: [ReconcileName]
    var isSettleable: Bool
    var differenceMinor: Int { observedMinor - expectedMinor }
}

/// A bill or instalment reminder a bank message announced and no payment has closed yet.
struct MoneyUpcomingDue: Identifiable, Equatable, Sendable {
    var id: UUID
    var payee: String
    var amountMinor: Int
    var currency: String
    var dueAt: Date?
    var dueDay: GregorianDay?
    /// Whole civil days from today to the due day: 0 today, 2 in two days, -3 three days late. nil without a due date.
    var daysUntil: Int?
}

struct MoneyBankInsights: Equatable, Sendable {
    var mismatches: [MoneyBankMismatch] = []
    var dues: [MoneyUpcomingDue] = []
    var isEmpty: Bool { mismatches.isEmpty && dues.isEmpty }
}

/// «بطاقة تنتهي بـ٣٣١٧ من ‹الجهة› — لأي حساب تتبع؟»: one question per (sender, tail).
struct MoneyTailQuestion: Identifiable, Equatable, Sendable {
    struct Candidate: Identifiable, Equatable, Sendable {
        var kind: MoneyRepository.TailCandidate.Kind
        var uuid: UUID
        var name: String
        var bank: String
        var id: String { kind.rawValue + ":" + uuid.uuidString }
    }
    var tail: String
    var sender: String
    var candidates: [Candidate]
    var id: String { sender + "|" + tail }
}

/// «ليست لي الآن» lasts for the session only: the question comes back on the next launch.
@MainActor enum MoneyTailSkips {
    private(set) static var keys: Set<String> = []
    static func skip(_ key: String) { keys.insert(key) }
    #if DEBUG
    static func reset() { keys = [] }
    #endif
}

/// The kind of tail the owner names when answering; stored on the tail row, never used to guess.
enum MoneyTailKind: String, CaseIterable, Identifiable, Sendable {
    case card, applePay, account
    var id: String { rawValue }
    var title: String { switch self { case .card: "بطاقة"; case .applePay: "Apple Pay"; case .account: "حساب" } }
}

enum MoneyBankInsightsCopy {
    /// «اليوم»، «غدًا»، «بعد يومين»، «بعد ٣ أيام»، «تأخر يوم»، «تأخر ٣ أيام». nil: the notice printed no due date.
    static func duePhrase(daysUntil: Int?, digits: MadarNumberFormatter) -> String {
        guard let daysUntil else { return "بلا موعد محدد" }
        switch daysUntil {
        case 0: return "اليوم"
        case 1: return "غدًا"
        case 2: return "بعد يومين"
        case 3...10: return "بعد " + digits.string(daysUntil) + " أيام"
        case 11...: return "بعد " + digits.string(daysUntil) + " يومًا"
        case -1: return "تأخر يوم"
        case -2: return "تأخر يومين"
        case -10 ... -3: return "تأخر " + digits.string(-daysUntil) + " أيام"
        default: return "تأخر " + digits.string(-daysUntil) + " يومًا"
        }
    }
    /// «رصيد البنك ١٬٢٠٠ ومدار ١٬٣٠٠ — فرق ١٠٠». The amounts arrive already formatted (or masked).
    static func mismatchSentence(bank: String, book: String, difference: String) -> String {
        "رصيد البنك " + bank + " ومدار " + book + " — فرق " + difference
    }
    static func title(_ name: ReconcileName) -> String {
        name == .missedSpend ? "مصاريف فاتتني" : name == .bankFee ? "رسوم بنكية" : "تسوية بلا تفسير"
    }
    /// The `money.reconcile` row that settles one mismatch: the same shape and rule as «المطابقة مع البنك».
    static func reconcileRow(_ item: MoneyBankMismatch, name: ReconcileName?) -> MadarCore.JSONValue {
        var object: [String: MadarCore.JSONValue] = [
            "accountID": .string(item.accountID.uuidString),
            "expectedMinor": .string(String(item.expectedMinor)),
            "observedMinor": .string(String(item.observedMinor)),
            "at": .string(ISO8601DateFormatter().string(from: item.at))]
        if let name { object["name"] = .string(name.rawValue) }
        return .object(object)
    }
    static func attachPayload(_ question: MoneyTailQuestion, candidate: MoneyTailQuestion.Candidate, kind: MoneyTailKind) -> [String: MadarCore.JSONValue] {
        [candidate.kind == .account ? "accountID" : "cardID": .string(candidate.uuid.uuidString),
         "tail": .string(question.tail), "kind": .string(kind.rawValue)]
    }
}

enum MoneyBankInsightsReader {
    /// Pure store reads (no main actor): nothing is computed without a stored bank reading. Never writes, never notifies.
    static func insights(context: ModelContext, now: Date, zone: TimeZone) throws -> MoneyBankInsights {
        let repo = MoneyRepository(context: context)
        var probe = FetchDescriptor<BankReading>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil })
        probe.fetchLimit = 1
        var result = MoneyBankInsights()
        if try !context.fetch(probe).isEmpty {
            var seen = Set<UUID>()
            for item in try repo.balanceMismatches(at: now) where item.reading.status == .open && seen.insert(item.accountID).inserted {
                result.mismatches.append(.init(accountID: item.accountID, accountName: item.accountName, expectedMinor: item.reading.expectedMinor,
                    observedMinor: item.reading.observedMinor, at: item.reading.at, names: item.reading.names, isSettleable: item.isSettleable))
            }
        }
        let today = GregorianDay.containing(now, in: zone)
        result.dues = try repo.upcomingDues().map { due in
            let day = due.dueAt.map { GregorianDay.containing($0, in: zone) }
            return MoneyUpcomingDue(id: due.id, payee: due.payee, amountMinor: due.amountMinor, currency: due.currency, dueAt: due.dueAt,
                                    dueDay: day, daysUntil: day.map { MadarCalendarDays.distance(from: today, to: $0) })
        }
        return result
    }
    static func tailQuestions(context: ModelContext) throws -> [MoneyTailQuestion] {
        try MoneyRepository(context: context).unknownTails().map { item in
            MoneyTailQuestion(tail: item.tail, sender: item.sender, candidates: item.candidates.map {
                .init(kind: $0.kind, uuid: $0.id, name: $0.name, bank: $0.bank) })
        }
    }
}

@ModelActor private actor MoneyTailReadActor {
    func read() throws -> [MoneyTailQuestion] { try Task.checkCancellation(); return try MoneyBankInsightsReader.tailQuestions(context: modelContext) }
}

extension AppMoneyService {
    /// Synchronous variant for tests and callers already off the home path.
    func loadBankInsights(at instant: Date? = nil) throws -> MoneyBankInsights {
        try requireReadableStore()
        return try MoneyBankInsightsReader.insights(context: ModelContext(app.container), now: instant ?? app.prayerNow(), zone: app.activePlace.timeZone)
    }

    /// New-card questions not skipped this session, read on a background model actor.
    func loadTailQuestionsOffMain() async throws -> [MoneyTailQuestion] {
        try requireReadableStore()
        let container = app.container
        let task = Task.detached(priority: .userInitiated) { try await MoneyTailReadActor(modelContainer: container).read() }
        let all = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        return all.filter { !MoneyTailSkips.keys.contains($0.id) }
    }
}
