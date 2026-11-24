import Foundation
import SwiftData
import MadarCore
import MadarData

struct DiarySearchIndex: Sendable {
    let documents: [DiarySearchDocument]
    let parser: DiarySearchParser
    let terms: [(String, String, Int)]
    init(documents: [DiarySearchDocument], parser: DiarySearchParser) {
        self.documents = documents
        self.parser = parser
        var placeDays: [String: Set<GregorianDay>] = [:]
        var tagDays: [String: Set<GregorianDay>] = [:]
        var allTags: Set<String> = []
        for document in documents {
            if let place = document.place { placeDays[place, default: []].insert(document.day) }
            for tag in document.tags {
                allTags.insert(tag)
                tagDays[DiarySearchParser.normalize(tag), default: []].insert(document.day)
            }
        }
        let places = parser.places.map { ($0, "في " + $0, placeDays[$0]?.count ?? 0) }
        var seenTags: Set<String> = []
        let tags = allTags.sorted().compactMap { tag -> (String, String, Int)? in
            let key = DiarySearchParser.normalize(tag)
            guard seenTags.insert(key).inserted else { return nil }
            return ("#" + tag, "#" + tag, tagDays[key]?.count ?? 0)
        }
        terms = (places + tags).sorted { $0.0 < $1.0 }
    }
    @concurrent func matching(_ chips: [DiarySearchChip]) async throws -> [DiarySearchDocument] {
        try parser.matching(documents, chips: chips)
    }
}
extension AppDiaryService {
    func searchIndex() throws -> DiarySearchIndex {
        try authorizeRead()
        return try Self.buildSearchIndex(container:app.container,zone:app.activePlace.timeZone,grid:diaryCalendar,today:currentDay())
    }
    /// The same index built in the background: every entry, margin note and letter is read, so a long diary must not freeze the screen.
    func searchIndexOffMain() async throws -> DiarySearchIndex {
        try authorizeRead()
        let generation = app.storeGeneration, container = app.container
        let grid = diaryCalendar, today = try await currentDayOffMain()
        let index = try await Self.readSearchIndex(container: container, grid: grid, today: today)
        try Task.checkCancellation()
        try authorizeRead()
        guard app.storeGeneration == generation, app.container === container else { throw CancellationError() }
        return index
    }
    @concurrent private static func readSearchIndex(container: ModelContainer, grid: DiaryCalendarGrid, today: GregorianDay) async throws -> DiarySearchIndex {
        try buildSearchIndex(container: container, zone: grid.zone, grid: grid, today: today)
    }

    nonisolated private static func buildSearchIndex(container:ModelContainer,zone:TimeZone,grid:DiaryCalendarGrid,today:GregorianDay) throws -> DiarySearchIndex {
        try Task.checkCancellation()
        let context=ModelContext(container)
        let entries=Self.visible(try context.fetch(FetchDescriptor<Entry>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil })))
        let trips=try context.fetch(FetchDescriptor<Trip>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil && !$0.dismissed }))
        var mediaDescriptor=FetchDescriptor<Media>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil }); mediaDescriptor.propertiesToFetch=[\.id,\.kind]
        let media=Dictionary(try context.fetch(mediaDescriptor).map{($0.id,$0.kind)}, uniquingKeysWith: { first, _ in first })
        var documents:[DiarySearchDocument]=[]
        var entryPhotosByDay: [String: Set<UUID>] = [:]
        for row in entries {
            try Task.checkCancellation()
            guard let day=try? GregorianDay(row.dayKey) else { continue }
            let place=row.place ?? trips.first { trip in trip.start.map{row.eventAt >= $0} == true && trip.end.map{row.eventAt < $0} != false }?.city
            let photos = row.attachmentMediaIDs.filter { media[$0] == "photo" }
            if !photos.isEmpty { entryPhotosByDay[row.dayKey, default: []].formUnion(photos) }
            let kind=row.mediaID.flatMap{media[$0]} == "audio" ? "audio" : !photos.isEmpty ? "photo" : row.ink == "ghad" ? "tomorrow" : "writing"
            var kinds:Set<String>=[kind]
            if !photos.isEmpty {kinds.insert("photo")}
            if row.ink == "ghad" {kinds.insert("tomorrow")}
            let text=row.textFormat == "markdown" ? DayOneMarkdown.plain(row.text) : row.text
            documents.append(.init(id:row.id.uuidString,day:day,text:text.isEmpty ? (kind == "audio" ? "تسجيل صوتي" : kind == "photo" ? "صورة من يومك" : "مرفق من يومك") : text,kind:kind,kinds:kinds,place:place,projectID:row.projectID,tags:row.tags ?? []))
        }
        for row in try context.fetch(FetchDescriptor<MarginNote>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil })) {
            try Task.checkCancellation()
            if let day=try? GregorianDay(row.writtenDayKey) { documents.append(.init(id:row.id.uuidString,day:day,text:row.text,kind:"margin")) }
        }
        for row in try context.fetch(FetchDescriptor<Niyya>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil })) {
            try Task.checkCancellation()
            if let day=try? GregorianDay(row.dayKey) { documents.append(.init(id:row.id.uuidString,day:day,text:row.text,kind:"intention")) }
        }
        for row in try context.fetch(FetchDescriptor<DayPage>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil })) {
            try Task.checkCancellation()
            guard let day=try? GregorianDay(row.dayKey) else { continue }
            if let text=row.questionAnswer,!text.isEmpty { documents.append(.init(id:row.id.uuidString+"answer",day:day,text:text)) }
            if let id = row.photoMediaID, media[id] == "photo", entryPhotosByDay[row.dayKey]?.contains(id) != true {
                documents.append(.init(id:row.id.uuidString+"photo",day:day,text:"صورة من يومك",kind:"photo"))
            }
        }
        for row in try context.fetch(FetchDescriptor<Letter>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil && $0.state == "opened" })) {
            try Task.checkCancellation()
            documents.append(.init(id:row.id.uuidString,day:GregorianDay.containing(row.openedAt ?? row.createdAt,in:zone),text:row.text,kind:"letter"))
        }
        return .init(documents:documents.sorted{$0.day > $1.day},parser:.init(today:today,zone:zone,weekStart:grid.weekStart,sightingOffset:grid.offset,places:Set(documents.compactMap(\.place)).sorted(),tags:Set(documents.flatMap(\.tags)).sorted()))
    }
}
