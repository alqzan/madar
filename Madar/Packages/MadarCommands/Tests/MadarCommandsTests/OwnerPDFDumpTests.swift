import Foundation
import Testing
@testable import MadarCommands

/// Local only: reads the owner's PDF (path in `MADAR_TRIAL_PDF`) the way the app does and writes each
/// page's raw text to `MADAR_TRIAL_PDF_DUMP` as JSON, to tune running-line and printed-index detection.
/// Skipped without both variables; owner data never enters the repository.
@Suite struct OwnerPDFDumpTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MADAR_TRIAL_PDF"] != nil && ProcessInfo.processInfo.environment["MADAR_TRIAL_PDF_DUMP"] != nil, "Owner PDF trial only"))
    func dumpOwnerPDFPages() async throws {
        let env = ProcessInfo.processInfo.environment
        let path = try #require(env["MADAR_TRIAL_PDF"]), out = try #require(env["MADAR_TRIAL_PDF_DUMP"])
        let reader = PDFBookTextReader(data: try Data(contentsOf: URL(fileURLWithPath: path)), language: "ar")
        var pages: [String] = []
        for index in 0..<(try await reader.pageCount()) {
            pages.append((try? await reader.page(at: index, optical: true).text) ?? "")
        }
        try JSONEncoder().encode(pages).write(to: URL(fileURLWithPath: out))
        #expect(!pages.isEmpty)
    }

    /// Prints the printed contents found in a dump made by the test above (`MADAR_TRIAL_PDF_PAGES`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MADAR_TRIAL_PDF_PAGES"] != nil, "Owner PDF trial only"))
    func ownerPrintedContents() throws {
        let path = try #require(ProcessInfo.processInfo.environment["MADAR_TRIAL_PDF_PAGES"])
        let texts = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let entries = PDFBookEPUB.printedContents(texts)
        for entry in entries { print("TOC", entry.page + 1, entry.title) }
        #expect(entries.count >= 3)
    }
}
