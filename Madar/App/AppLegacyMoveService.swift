import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarPrayer
import MadarQuran
import MadarCommands

/// What one room of the old Madar holds, read from the file before anything is written.
struct LegacyMoveRoom: Identifiable, Hashable, Codable {
    let id: String, title: String, symbol: String
    var lines: [String]
    var isEmpty: Bool { lines.isEmpty }
}
struct LegacyMovePreview: Identifiable {
    let id = UUID()
    let fileName: String, data: Data, rooms: [LegacyMoveRoom]
    var hasContent: Bool { rooms.contains { !$0.isEmpty } }
}
/// The result per room after a move: what was added, what the owner already had, and what could not move.
struct LegacyMoveOutcome: Identifiable, Hashable, Codable {
    let id: String, title: String
    var added = 0, keptNative = 0, waiting = 0, failed: String?
    /// Added rows per record model, so the result names real things («١٢ صلاة») instead of «records».
    var parts: [String: Int] = [:]
}
struct LegacyMoveReceipt: Codable, Equatable {
    var at: Date, fileName: String, outcomes: [LegacyMoveOutcome], undoneAt: Date?
    var added: Int { outcomes.reduce(0) { $0 + $1.added } }
}

/// Item 24 (owner's go, 25 Oct 2026): file → preview per room → «انقل» → result with one undo. Undo compares record
/// snapshots, so commands, direct rows and settings all revert together, and rows changed after the move are kept.
@MainActor struct AppLegacyMoveService {
    let app: AppSession
    private var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }

    private var folder: URL {
        let base = app.managedStore?.root ?? URL.applicationSupportDirectory.appending(path: "Madar", directoryHint: .isDirectory)
        return base.appending(path: "LegacyMove", directoryHint: .isDirectory)
    }
    private var undoURL: URL { folder.appending(path: "undo.json") }
    /// `complete` is nil while a move runs; a file left that way (the move was cut short) undoes against the store as it is.
    private struct UndoFile: Codable { var receipt: LegacyMoveReceipt; var before: [DataRecord]; var after: [DataRecord]; var complete: Bool? }

    static let models: [String: Set<String>] = ["prayer": ["PrayerLog", "QadaItem"], "quran": ["HifzSession", "MistakeSpot", "HifzPlan"],
        "habits": ["Habit", "HabitEvent"], "personal": ["Letter", "UpcomingDay"], "money": ["MoneyTransaction", "Account", "Card"]]

    func open(_ url: URL) throws -> LegacyMovePreview {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw LegacyMoveError.notOldMadar }
        let rooms = preview(data)
        guard rooms.contains(where: { !$0.isEmpty }) else { throw LegacyMoveError.notOldMadar }
        return LegacyMovePreview(fileName: url.lastPathComponent, data: data, rooms: rooms)
    }

    func counted(_ n: Int, _ forms: [String]) -> String { arabicCount(n, forms, digits) }
    static let nouns: [(model: String, forms: [String])] = [
        ("PrayerLog", ["صلاة واحدة", "صلاتان", "صلوات", "صلاة"]), ("QadaItem", ["قضاء واحد", "قضاءان", "قضاءات", "قضاءً"]),
        ("HifzPlan", ["خطة الحفظ", "خطتان", "خطط", "خطة"]), ("HifzSession", ["جلسة واحدة", "جلستان", "جلسات", "جلسة"]),
        ("MistakeSpot", ["موضع خطأ واحد", "موضعا خطأ", "مواضع خطأ", "موضع خطأ"]), ("Habit", ["عادة واحدة", "عادتان", "عادات", "عادة"]),
        ("HabitEvent", ["مرة واحدة", "مرتان", "مرات", "مرة"]), ("Letter", ["رسالة واحدة", "رسالتان", "رسائل", "رسالة"]),
        ("UpcomingDay", ["يوم مهم واحد", "يومان مهمان", "أيام مهمة", "يومًا مهمًا"]), ("Account", ["حساب واحد", "حسابان", "حسابات", "حسابًا"]),
        ("Card", ["بطاقة واحدة", "بطاقتان", "بطاقات", "بطاقة"]), ("MoneyTransaction", ["حركة واحدة", "حركتان", "حركات", "حركة"])]
    /// «١٢ صلاة، قضاءان» for what one room added.
    func phrase(_ parts: [String: Int]) -> String {
        Self.nouns.compactMap { noun in parts[noun.model].flatMap { $0 > 0 ? counted($0, noun.forms) : nil } }.joined(separator: "، ")
    }

    func preview(_ data: Data) -> [LegacyMoveRoom] {
        let place = app.activePlace, zone = place.timeZone, uuid = StableIdentity.uuid(for:)
        let observed = GregorianDay.containing(app.prayerNow(), in: zone)
        var rooms: [LegacyMoveRoom] = []
        var prayer = LegacyMoveRoom(id: "prayer", title: "الصلاة", symbol: "moon.stars", lines: [])
        if let plan = try? LegacyPrayerImport.plan(backup: data, home: place, uuid: uuid) {
            if !plan.logs.isEmpty { prayer.lines.append(counted(plan.logs.count, ["صلاة واحدة مسجّلة", "صلاتان مسجّلتان", "صلوات مسجّلة", "صلاة مسجّلة"])) }
            if !plan.qada.isEmpty { prayer.lines.append(counted(plan.qada.count, ["قضاء واحد", "قضاءان", "قضاءات", "قضاءً"])) }
        }
        rooms.append(prayer)
        var quran = LegacyMoveRoom(id: "quran", title: "القرآن", symbol: "book", lines: [])
        if let catalog = try? QuranResources.catalog(), let plan = try? LegacyQuranImport.plan(backup: data, timeZone: zone, catalog: catalog, uuid: uuid) {
            if !plan.sessions.isEmpty { quran.lines.append(counted(plan.sessions.count, ["جلسة واحدة", "جلستان", "جلسات", "جلسة"])) }
            if !plan.spots.isEmpty { quran.lines.append(counted(plan.spots.count, ["موضع خطأ واحد", "موضعا خطأ", "مواضع خطأ", "موضع خطأ"])) }
            if plan.plan != nil { quran.lines.append("خطة الحفظ") }
        }
        rooms.append(quran)
        var habits = LegacyMoveRoom(id: "habits", title: "العادات", symbol: "circle.dashed", lines: [])
        if let plan = try? LegacyHabitImport.plan(backup: data, observedDay: observed, zone: zone, uuid: uuid) {
            let live = plan.habits.filter { $0.deletedAt == nil }.count, times = plan.events.filter { $0.deletedAt == nil }.count
            if live > 0 { habits.lines.append(counted(live, ["عادة واحدة", "عادتان", "عادات", "عادة"])) }
            if times > 0 { habits.lines.append(counted(times, ["مرة واحدة", "مرتان", "مرات", "مرة"])) }
        }
        rooms.append(habits)
        var personal = LegacyMoveRoom(id: "personal", title: "رسائلك وأيامك", symbol: "envelope", lines: [])
        if let plan = try? LegacyPersonalImport.plan(backup: data, observedDay: observed, zone: zone, uuid: uuid) {
            if !plan.letters.isEmpty { personal.lines.append(counted(plan.letters.count, ["رسالة واحدة", "رسالتان", "رسائل", "رسالة"])) }
            if !plan.days.isEmpty { personal.lines.append(counted(plan.days.count, ["يوم مهم واحد", "يومان مهمان", "أيام مهمة", "يومًا مهمًا"])) }
        }
        rooms.append(personal)
        var money = LegacyMoveRoom(id: "money", title: "المال", symbol: "banknote", lines: [])
        if let plan = try? LegacyMoneyImport.plan(backup: data, existing: [], timeZone: zone, uuid: uuid) {
            let moves = plan.steps.filter { if case .ingest = $0 { true } else if case .logExpense = $0 { true } else { false } }.count
            let accounts = plan.steps.filter { if case .saveAccount = $0 { true } else if case .saveCard = $0 { true } else { false } }.count
            if moves > 0 { money.lines.append(counted(moves, ["حركة واحدة", "حركتان", "حركات", "حركة"])) }
            if accounts > 0 { money.lines.append(counted(accounts, ["حساب أو بطاقة", "حسابان أو بطاقتان", "حسابات وبطاقات", "حسابًا وبطاقة"])) }
            if plan.cycleSettings != nil { money.lines.append("إعدادات الدورة") }
        }
        rooms.append(money)
        return rooms
    }

    /// Every room runs on its own; one that fails leaves the others moved and says so. Undo covers the whole run.
    func commit(_ preview: LegacyMovePreview, progress: @escaping @MainActor (String) -> Void) async throws -> LegacyMoveReceipt {
        try await app.performLegacyMove { now in
            let current = try RecordBridge.all(ModelContext(app.container), syncedOnly: false)
            // An earlier move not yet undone keeps its «before», so one undo always returns to the store before any move.
            let earlier = (try? Data(contentsOf: undoURL)).flatMap { try? JSONDecoder().decode(UndoFile.self, from: $0) }
            let before = earlier.flatMap { $0.receipt.undoneAt == nil ? $0.before : nil } ?? current
            // Written before the first room, so a move cut short (killed, disk full) can still be undone.
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let url = undoURL
            func save(_ file: UndoFile) throws { try JSONEncoder().encode(file).write(to: url, options: [.atomic, .completeFileProtection]) }
            let started = LegacyMoveReceipt(at: now, fileName: preview.fileName, outcomes: [], undoneAt: nil)
            try save(UndoFile(receipt: earlier?.receipt.undoneAt == nil ? earlier?.receipt ?? started : started, before: before, after: earlier?.after ?? current, complete: nil))
            let zone = app.activePlace.timeZone, writer = AppSession.legacyMoveWriter
            var outcomes: [LegacyMoveOutcome] = []
            func summarize(_ room: LegacyMoveRoom, _ counts: [String: Int]) -> LegacyMoveOutcome {
                var o = LegacyMoveOutcome(id: room.id, title: room.title)
                o.keptNative = counts.filter { $0.key.hasSuffix(".keptNative") }.values.reduce(0, +)
                o.waiting = counts.filter { $0.key.hasPrefix("message.state.") && !$0.key.hasSuffix(".ok") }.values.reduce(0, +)
                return o
            }
            for room in preview.rooms where !room.isEmpty {
                progress(room.title)
                do {
                    let counts: [String: Int]
                    switch room.id {
                    case "prayer": counts = try app.importLegacyPrayer(preview.data, writer: writer, now: now)
                    case "quran": counts = try app.importLegacyQuran(preview.data, fileName: preview.fileName, writer: writer, now: now)
                    case "habits": counts = try LegacyHabitTrial.importBackup(preview.data, to: app.container, zone: zone, now: now, writer: writer)
                    case "personal": counts = try LegacyPersonalTrial.importBackup(preview.data, to: app.container, zone: zone, now: now, writer: writer)
                    default: counts = try await app.importLegacyMoney(preview.data, now: now)
                    }
                    outcomes.append(summarize(room, counts))
                } catch {
                    var o = LegacyMoveOutcome(id: room.id, title: room.title); o.failed = error.localizedDescription; outcomes.append(o)
                }
            }
            let after = try RecordBridge.all(ModelContext(app.container), syncedOnly: false)
            // «Added» is what the owner can now see: live rows of the room's own records that were not there before.
            let existed = Set(current.filter(\.isLive).map { $0.model + $0.id.uuidString })
            for index in outcomes.indices {
                let models = Self.models[outcomes[index].id] ?? []
                let fresh = after.filter { $0.isLive && models.contains($0.model) && !existed.contains($0.model + $0.id.uuidString) }
                outcomes[index].added = fresh.count
                outcomes[index].parts = Dictionary(grouping: fresh, by: \.model).mapValues(\.count)
            }
            let receipt = LegacyMoveReceipt(at: now, fileName: preview.fileName, outcomes: outcomes, undoneAt: nil)
            let shown = receipt.added > 0 || earlier?.receipt.undoneAt != nil || earlier == nil ? receipt : earlier!.receipt
            try save(UndoFile(receipt: shown, before: before, after: after, complete: true))
            return receipt
        }
    }

    /// The last move that can still be undone, if any.
    func lastMove() -> LegacyMoveReceipt? {
        guard let data = try? Data(contentsOf: undoURL), let file = try? JSONDecoder().decode(UndoFile.self, from: data) else { return nil }
        return file.receipt.undoneAt == nil ? file.receipt : nil
    }

    func undo() async throws -> ImportUndo.Plan {
        let file = try JSONDecoder().decode(UndoFile.self, from: Data(contentsOf: undoURL))
        return try await app.performLegacyMove { now in
            let context = ModelContext(app.container)
            let current = try RecordBridge.all(context, syncedOnly: false)
            let plan = try ImportUndo.plan(before: file.before, after: file.complete == true ? file.after : current, current: current, now: now)
            for row in plan.writes { try RecordBridge.upsert(row, in: context) }
            func tag(_ r: DataRecord) -> String { r.model + r.id.uuidString + (r.fields["mergedInto"]?.string ?? "") }
            let gone = Set(plan.removals.map(tag)), ids = Set(plan.removals.map(\.id))
            for instance in try RecordBridge.instances(context) where ids.contains(instance.id) {
                if gone.contains(tag(try instance.record())) { context.delete(instance) }
            }
            try context.save()
            // Quran's derived cache follows the sessions that remain.
            if let catalog = try? QuranResources.catalog() {
                try QuranMutationHandler.rebuildCache(try QuranRepository(context: context, catalog: catalog), at: now, writer: AppSession.legacyMoveWriter)
                try context.save()
            }
            // The snapshots are the owner's data; once undone they are no longer needed on disk.
            try? FileManager.default.removeItem(at: undoURL)
            return plan
        }
    }
}

enum LegacyMoveError: LocalizedError {
    case notOldMadar
    var errorDescription: String? { "هذا الملف ليس نسخة من مدار القديم. صدّر من مدار القديم نسخة احتياطية بصيغة JSON، ثم اخترها كما هي." }
}
