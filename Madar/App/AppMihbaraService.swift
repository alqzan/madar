import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarPrayer

struct MihbaraBook: Identifiable, Equatable {
    var id: UUID; var title: String; var author: String; var shelf: String; var pages: Int?; var page: Int?; var finished: Date?; var updated: Date
    var progress: Double? { MihbaraReading.progress(page: page, pages: pages) }
}
struct MihbaraHadith: Codable, Identifiable { var number: Int; var title: String; var text: String; var id: Int { number } }
struct MihbaraCollection: Codable {
    var collectionID: String; var editionID: String; var title: String; var source: String; var edition: String; var license: String; var licenseURL: String; var hadiths: [MihbaraHadith]
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "nawawi40", withExtension: "json") else { throw DataError.invalidValue("نص الأربعين غير موجود") }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.collectionID == "nawawi40", value.hadiths.count == 42, Set(value.hadiths.map(\.number)) == Set(1...42), value.hadiths.allSatisfy({ !$0.text.isEmpty }) else { throw DataError.invalidValue("تعذر التحقق من مجموعة الحديث") }
        return value
    }
}
struct MihbaraHomeReading {
    var books: [MihbaraBook]; var collection: MihbaraCollection; var todayHadiths: [MihbaraHadith]; var readCount: Int; var completedToday: Int; var opensAfterFajr: Bool; var day: GregorianDay
}
@MainActor struct AppMihbaraService {
    unowned let app: AppSession
    var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }
    func load(at instant: Date? = nil) throws -> MihbaraHomeReading {
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        let c = ModelContext(app.container), now = instant ?? app.prayerNow(), day = try DiaryLineRenderer.today(context: c, now: now)
        let storedBooks = try c.fetch(FetchDescriptor<Book>())
        var books: [MihbaraBook] = []
        for row in storedBooks where row.deletedAt == nil && row.mergedInto == nil {
            var page = row.currentPage
            if row.kind == "paper", let data = row.locatorJSON, let position = try? JSONDecoder().decode(PaperBookPosition.self, from: data) { page = position.page }
            books.append(MihbaraBook(id: row.id, title: row.title, author: row.author, shelf: row.shelf, pages: row.pages, page: page, finished: row.finishedAt, updated: row.updatedAt))
        }
        books.sort { $0.updated == $1.updated ? $0.id.uuidString < $1.id.uuidString : $0.updated > $1.updated }
        let collection = try MihbaraCollection.load()
        let rows = try c.fetch(FetchDescriptor<HadithProgress>()).filter { $0.collectionID == collection.collectionID && $0.deletedAt == nil && $0.mergedInto == nil }
        let read = Set(rows.filter { $0.readAt != nil }.map(\.number))
        let today = Set(try rows.filter { row in
            guard let readAt = row.readAt else { return false }
            return try DiaryLineRenderer.today(context: c, now: readAt) == day
        }.map(\.number))
        let numbers = MihbaraReading.nextHadith(numbers: collection.hadiths.map(\.number), read: read, readToday: today, count: Int(app.number("mihbara.wirdCount")))
        let prayer = try PrayerRepository(context: c), civil = GregorianDay.containing(now, in: app.activePlace.timeZone)
        let fajr = prayer.occurrence(.init(day: civil, prayer: .fajr))?.time
        return .init(books: books, collection: collection, todayHadiths: collection.hadiths.filter { numbers.contains($0.number) }, readCount: read.count, completedToday: today.count, opensAfterFajr: fajr.map { now >= $0 } ?? false, day: day)
    }
}
