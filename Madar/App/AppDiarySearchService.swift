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
        let container=app.container,zone=app.activePlace.timeZone,grid=diaryCalendar,today=try currentDay()
        return try await Task.detached(priority:.userInitiated) { try Self.buildSearchIndex(container:container,zone:zone,grid:grid,today:today) }.value
    }
    nonisolated private static func buildSearchIndex(container:ModelContainer,zone:TimeZone,grid:DiaryCalendarGrid,today:GregorianDay) throws -> DiarySearchIndex {
        let context=ModelContext(container)
        let entries=Self.visible(try context.fetch(FetchDescriptor<Entry>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil })))
        let trips=try context.fetch(FetchDescriptor<Trip>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil && !$0.dismissed }))
        var mediaDescriptor=FetchDescriptor<Media>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil }); mediaDescriptor.propertiesToFetch=[\.id,\.kind]
        let media=Dictionary(try context.fetch(mediaDescriptor).map{($0.id,$0.kind)}, uniquingKeysWith: { first, _ in first })
        var documents:[DiarySearchDocument]=[]
        for row in entries {
            guard let day=try? GregorianDay(row.dayKey) else { continue }
            let place=row.place ?? trips.first { trip in trip.start.map{row.eventAt >= $0} == true && trip.end.map{row.eventAt < $0} != false }?.city
            let kind=row.mediaID.flatMap{media[$0]} == "audio" ? "audio" : row.attachmentMediaIDs.contains{media[$0]=="photo"} ? "photo" : row.ink == "ghad" ? "tomorrow" : "writing"
            var kinds:Set<String>=[kind]
            if row.attachmentMediaIDs.contains(where:{media[$0]=="photo"}) {kinds.insert("photo")}
            if row.ink == "ghad" {kinds.insert("tomorrow")}
            let text=row.textFormat == "markdown" ? DayOneMarkdown.plain(row.text) : row.text
            documents.append(.init(id:row.id.uuidString,day:day,text:text.isEmpty ? (kind == "audio" ? "تسجيل صوتي" : kind == "photo" ? "صورة من يومك" : "مرفق من يومك") : text,kind:kind,kinds:kinds,place:place,projectID:row.projectID,tags:row.tags ?? []))
        }
        for row in try context.fetch(FetchDescriptor<MarginNote>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil })) {
            if let day=try? GregorianDay(row.writtenDayKey) { documents.append(.init(id:row.id.uuidString,day:day,text:row.text,kind:"margin")) }
        }
        for row in try context.fetch(FetchDescriptor<Niyya>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil })) {
            if let day=try? GregorianDay(row.dayKey) { documents.append(.init(id:row.id.uuidString,day:day,text:row.text,kind:"intention")) }
        }
        for row in try context.fetch(FetchDescriptor<DayPage>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil })) {
            guard let day=try? GregorianDay(row.dayKey) else { continue }
            if let text=row.questionAnswer,!text.isEmpty { documents.append(.init(id:row.id.uuidString+"answer",day:day,text:text)) }
            if let id=row.photoMediaID,media[id]=="photo",!entries.contains(where:{$0.dayKey==row.dayKey && $0.attachmentMediaIDs.contains(id)}) { documents.append(.init(id:row.id.uuidString+"photo",day:day,text:"صورة من يومك",kind:"photo")) }
        }
        for row in try context.fetch(FetchDescriptor<Letter>(predicate:#Predicate { $0.deletedAt == nil && $0.mergedInto == nil && $0.state == "opened" })) {
            documents.append(.init(id:row.id.uuidString,day:GregorianDay.containing(row.openedAt ?? row.createdAt,in:zone),text:row.text,kind:"letter"))
        }
        return try .init(documents:documents.sorted{$0.day > $1.day},parser:.init(today:today,zone:zone,weekStart:grid.weekStart,sightingOffset:grid.offset,places:Set(documents.compactMap(\.place)).sorted(),tags:Set(documents.flatMap(\.tags)).sorted()))
    }
}
