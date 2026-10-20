import Foundation
import SwiftData
import CryptoKit
import MadarCore
import MadarData
import MadarCommands

/// A picked Day One export, copied into protected temporary storage and parsed. Nothing is written yet.
struct DayOneImportDraft: Identifiable {
    let id = UUID()
    let fileName: String
    let folder: URL
    let archive: ZIPReader
    let plan: DayOnePlan
    let fileHash: String
}

/// M3-V09 (N01, RD8): file → preview → explicit «استورد» → result with one undo.
@MainActor struct AppDiaryImportService {
    let app: AppSession
    private static let writer = "madar.app.dayOneImport"
    private var diary: AppDiaryService { .init(app: app) }

    func open(_ url: URL) async throws -> DayOneImportDraft {
        try diary.authorizeRead()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appending(path: "DayOneImport/" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let copy = folder.appending(path: "export.zip")
        do {
            try FileManager.default.copyItem(at: url, to: copy)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: copy.path)
            let parsed = try await Task.detached(priority: .userInitiated) { () throws -> (ZIPReader, DayOnePlan, String) in
                let zip = try ZIPReader(url: copy)
                let plan = try DayOneParser.plan(zip)
                let bytes = try Data(contentsOf: copy, options: .alwaysMapped)
                return (zip, plan, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
            }.value
            return .init(fileName: url.lastPathComponent, folder: folder, archive: parsed.0, plan: parsed.1, fileHash: parsed.2)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
    func preview(_ draft: DayOneImportDraft, choice: DayOneMerge.Choice) throws -> DayOnePreview {
        try diary.authorizeRead()
        return try DayOneImportHandler.preview(draft.plan, choice: choice, context: ModelContext(app.container))
    }
    func commit(_ draft: DayOneImportDraft, choice: DayOneMerge.Choice, progress: @escaping @MainActor (Int, Int) -> Void) async throws -> DayOneReceipt {
        try diary.authorizeRead()
        let container = app.container
        return try await app.performDiaryImport { now in
            try await DayOneImportHandler.commit(draft.plan, archive: draft.archive, fileName: draft.fileName, fileHash: draft.fileHash, choice: choice,
                                                 context: ModelContext(container), now: now, writer: Self.writer, progress: progress)
        }
    }
    func undo(_ batch: UUID) async throws {
        let container = app.container
        try await app.performDiaryImport { now in try DayOneImportHandler.undo(batch: batch, context: ModelContext(container), now: now, writer: Self.writer) }
    }
    func discard(_ draft: DayOneImportDraft?) { if let draft { try? FileManager.default.removeItem(at: draft.folder) } }

    static func message(_ error: Error) -> String {
        switch error {
        case DayOneImportError.noJournal: "لم نجد في الملف دفترًا من داي ون. صدّر من داي ون بصيغة JSON، ثم اختر ملف ZIP كما هو."
        case DayOneImportError.archive(let inner): message(inner)
        case ZIPReaderError.notZIP: "هذا الملف ليس ملف ZIP. اختر الملف الذي أعطاك إياه داي ون عند التصدير بصيغة JSON."
        case ZIPReaderError.encrypted: "الملف مقفل بكلمة سر. صدّره من داي ون دون تشفير ثم أعد المحاولة."
        case ZIPReaderError.tooLarge: "في الملف مرفق أكبر مما يستطيع مدار فتحه دفعة واحدة. لم يُكتب شيء."
        case ZIPReaderError.unsupportedMethod: "الملف مضغوط بطريقة لا يقرؤها مدار. أعد التصدير من داي ون."
        case ZIPReaderError.corrupt, ZIPReaderError.checksum, ZIPReaderError.unsafePath: "الملف ناقص أو تالف. أعد التصدير من داي ون ثم جرّب مرة أخرى."
        case let error as DataError: if case .invalidValue(let text) = error, text.contains("مقفلة") { "افتح المذكرات أولًا ثم أعد المحاولة." } else { "لم يكتمل الاستيراد، ولم يتغيّر شيء في دفترك." }
        case is BackupOperationError: "مدار مشغول بنسخة احتياطية الآن. أعد المحاولة بعد قليل."
        default: "لم يكتمل الاستيراد، ولم يتغيّر شيء في دفترك."
        }
    }
}
