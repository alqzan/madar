import Foundation
import SwiftData
import MadarCore
import MadarData

extension AppDiaryService {
    func yearbookPreview(_ options: DiaryExportOptions, knownYears: [Int] = []) async throws -> (years: [Int], pages: [DiaryExportPage]) {
        try authorizeRead()
        let container = app.container, generation = app.storeGeneration
        let configuration = dayReadConfiguration, zone = app.activePlace.timeZone
        let today = try await currentDayOffMain()
        let preview = try await Self.readYearbookPreview(options, knownYears: knownYears, container: container, today: today, configuration: configuration, zone: zone)
        try Task.checkCancellation()
        try authorizeRead()
        guard app.storeGeneration == generation, app.container === container else { throw CancellationError() }
        return (preview.years, try Self.finishExportPages(preview.batch, context: ModelContext(container)))
    }

    @concurrent private static func readYearbookPreview(
        _ options: DiaryExportOptions, knownYears: [Int], container: ModelContainer, today: GregorianDay, configuration: DiaryDayReadConfiguration, zone: TimeZone
    ) async throws -> (years: [Int], batch: DiaryExportPageBatch) {
        let context = ModelContext(container)
        let years = try knownYears.isEmpty ? readExportYears(context: context, today: today, zone: zone) : knownYears
        var selected = options
        selected.year = options.year ?? years.first ?? today.year
        let batch = try readExportPageBatch(selected, context: context, today: today, configuration: configuration)
        return (years, batch)
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
