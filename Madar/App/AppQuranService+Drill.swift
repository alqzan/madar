import Foundation
import MadarCore
import MadarCommands
import MadarQuran

// M2-V04 · §7.4 «مواضع الخطأ». One committed drill session per spot, so a session's range is the spot's own ayah.
extension AppQuranService {
    static func spotID(_ key: QuranMistakeKey) -> String { "\(key.ayahID):\(key.wordIndex.map(String.init) ?? "ayah")" }

    func drillBoard() throws -> QuranUIDrillBoard {
        let board = try snapshot().drillBoard
        return QuranUIDrillBoard(todayLabel: "اليوم " + numerals.string(board.todayMistakes), mineLabel: "أخطائي " + numerals.string(board.openCount),
            today: board.todayQueue.map { Self.spotID($0.key) }, mine: board.mineQueue.map { Self.spotID($0.key) },
            done: board.drilledToday, allowance: board.dailyAllowance)
    }

    func timesLabel(_ hits: Int) -> String {
        "تكرر " + count(max(1, hits), singular: "مرة", dual: "مرتين", plural: "مرات")
    }

    func drillCard(_ value: QuranDraftPayload, catalog: QuranResourceCatalog) async throws -> QuranUIDrillCard? {
        let draft = value.draft
        guard draft.kind == .drill, let key = value.drillKey, let ayah = catalog.ayah(id: key.ayahID) else { return nil }
        let snapshot = try snapshot(), board = snapshot.drillBoard
        let summary = snapshot.mistakes.first { $0.key == key }
        let tab: QuranUIDrillTab = board.todayQueue.contains { $0.key == key } ? .today : .mine
        let tokens = ayah.wordTokens.map(\.text)
        let hidden = key.wordIndex.flatMap { tokens.indices.contains($0) ? $0 : nil }
        // A word spot shows the ayah up to its hidden word; a whole-ayah spot hides the whole ayah (never its first word only).
        let words = hidden.map { Array(tokens[...$0]) } ?? tokens
        let previous = ayah.id > 1 ? catalog.ayah(id: ayah.id - 1).map { Array($0.wordTokens.map(\.text).suffix(5)) } : nil
        let answered = draft.mistakes.contains { $0.key == key && $0.kind != .mistake }
        return QuranUIDrillCard(tab: tab, todayLabel: "اليوم " + numerals.string(board.todayMistakes), mineLabel: "أخطائي " + numerals.string(board.openCount),
            done: board.drilledToday, todayTotal: min(board.dailyAllowance, board.drilledToday + max(1, board.todayQueue.count)),
            mineTotal: min(board.dailyAllowance, board.drilledToday + max(1, board.mineQueue.count)),
            title: ayah.surahNameArabic + " " + numerals.string(ayah.ayahNumber) + "، الوجه " + numerals.string(ayah.page),
            timesLabel: timesLabel(summary?.hits ?? 1), prompt: previous.map { "… " + $0.joined(separator: " ") },
            words: words, hiddenIndex: hidden, continues: hidden.map { $0 < tokens.count - 1 } ?? false,
            revealed: value.revealedAyahs?.contains(ayah.id) == true, answered: answered,
            successStreak: summary?.successStreak ?? 0, mastery: QuranMistakeEngine.masteryThreshold,
            fontName: try await page(ayah.page).postScriptName)
    }
}
