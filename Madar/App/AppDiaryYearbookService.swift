import Foundation
import MadarCore
import MadarData

extension AppDiaryService {
    func yearbookPages(year:Int,margins:Bool,sources:Bool,photos:Bool) throws -> [DiaryExportPage] {
        try exportPages(.init(year: year, margins: margins, sources: sources, photos: photos))
    }

    func exportYearbook(pages: [DiaryExportPage], year: Int, index: Bool) async throws -> DiaryExportArtifact {
        try authorizeRead()
        try Task.checkCancellation()
        guard !pages.isEmpty, pages.allSatisfy({ $0.day.year == year }) else {
            throw DataError.invalidValue("لا توجد صفحات لهذه السنة")
        }
        let generation = app.storeGeneration
        let dates = app.yearLabels(year, first: app.diaryFirstCalendar)
        let root = FileManager.default.temporaryDirectory
            .appending(path: "DiaryExport/" + UUID().uuidString, directoryHint: .isDirectory)
        do {
            let url = try await Self.renderYearbook(pages: pages, year: year, index: index, dates: dates, digits: digits, root: root)
            try Task.checkCancellation()
            try authorizeRead()
            guard generation == app.storeGeneration else { throw CancellationError() }
            return .init(url: url, dayCount: pages.count)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    @concurrent private static func renderYearbook(
        pages: [DiaryExportPage], year: Int, index: Bool, dates: MadarDateLabels, digits: MadarNumberFormatter, root: URL
    ) async throws -> URL {
        try Task.checkCancellation()
        exportBuildProbe?()
        let bytes = DiaryPDF.render(pages, digits: digits, coverYear: year, index: index, coverDates: dates)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let url = root.appending(path: "كتاب-" + String(year) + ".pdf")
        try bytes.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
