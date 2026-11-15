import AppKit
import SwiftData
import SwiftUI
import Translation
import MadarCore
import MadarData
import MadarDesign

struct MacMihbaraReaderSettingsSheet: View {
    let bookIsEnglish: Bool
    let settings: [String: JSONValue]
    let set: (String, JSONValue) -> Void
    let reset: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var fonts: [(String, String)] {
        bookIsEnglish
            ? [("literata", "Literata"), ("sourceSerif", "Source Serif"), ("atkinsonHyperlegible", "Atkinson"), ("ibmPlexSerif", "Plex Serif")]
            : [("amiri", "أميري"), ("thmanyahSerif", "ثمانية نسخ"), ("thmanyahSans", "ثمانية حديث")]
    }
    private var size: Binding<Int> {
        Binding(get: { Int(settings["size"]?.number ?? 4) }, set: { set("size", .number(Double($0))) })
    }
    private var font: Binding<String> {
        Binding(get: { settings["font"]?.string ?? (bookIsEnglish ? "literata" : "amiri") }, set: { set("font", .string($0)) })
    }
    private var lineSpacing: Binding<Int> {
        Binding(get: { Int(settings["lineSpacing"]?.number ?? 2) }, set: { set("lineSpacing", .number(Double($0))) })
    }
    private var margins: Binding<Int> {
        Binding(get: { Int(settings["margins"]?.number ?? 2) }, set: { set("margins", .number(Double($0))) })
    }
    private var justify: Binding<Bool> {
        Binding(get: { boolValue("justify", default: true) }, set: { set("justify", .bool($0)) })
    }
    private var heavier: Binding<Bool> {
        Binding(get: { boolValue("heavier", default: false) }, set: { set("heavier", .bool($0)) })
    }
    private func boolValue(_ key: String, default fallback: Bool) -> Bool {
        guard case .bool(let value)? = settings[key] else { return fallback }
        return value
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("تمّ") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("إعدادات عرض الصفحة").font(MadarTypography.section())
                Spacer()
                Color.clear.frame(width: 44)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Form {
                Picker("الخط", selection: font) {
                    ForEach(fonts, id: \.0) { Text($0.1).tag($0.0) }
                }
                Stepper("حجم الخط", value: size, in: 1...7)
                Stepper("تباعد السطور", value: lineSpacing, in: 1...4)
                Stepper("هوامش الصفحة", value: margins, in: 1...4)
                Toggle("محاذاة الفقرات", isOn: justify)
                Toggle("خط أثقل", isOn: heavier)
                Button("أعِد إعدادات هذا الكتاب إلى الافتراضي", action: reset)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .formStyle(.grouped)
            .environment(\.layoutDirection, .rightToLeft)
        }
        .frame(minWidth: 440, minHeight: 350)
    }
}

struct MacMihbaraWordCardSheet: View {
    @Bindable var app: AppSession
    let book: MihbaraBook
    let selection: MacEPUBSelection
    let locatorJSON: String?
    let onQuote: () -> Void
    let onNote: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var wordSaved = false
    @State private var translationOpen = false
    @State private var translationStatus: WordTranslationStatus = .checking

    private enum WordTranslationStatus { case checking, installed, needsDownload, unsupported }
    private var language: String { book.language == "en" ? "en" : "ar" }
    private var canSaveAsWord: Bool {
        let parts = selection.selectedText.split(whereSeparator: \.isWhitespace)
        return parts.count == 1 && parts[0].unicodeScalars.contains(where: CharacterSet.letters.contains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("تمّ") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text(canSaveAsWord ? "بطاقة الكلمة" : "المقطع المحدد").font(MadarTypography.section())
                Spacer()
                Color.clear.frame(width: 44)
            }
            Text(selection.selectedText)
                .font(.custom(book.language == "en" ? "Literata-Regular" : "Amiri-Regular", size: 24, relativeTo: .title2))
                .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            ScrollView {
                Text(selection.paragraphText)
                    .font(.custom(book.language == "en" ? "Literata-Regular" : "Amiri-Regular", size: 18, relativeTo: .body))
                    .lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 220)
            HStack(spacing: 10) {
                Button("دوّن ملاحظة") { onNote(); dismiss() }
                Button("بطاقة اقتباس") { onQuote(); dismiss() }
                Button("انسخ مع التوثيق") { copyWithCitation() }
            }
            if canSaveAsWord {
                if wordSaved {
                    Label("في كلماتي", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                } else {
                    Button("أضف إلى كلماتي") { Task { await saveWord() } }
                        .disabled(locatorJSON == nil)
                }
            }
            if book.language == "en" {
                switch translationStatus {
                case .checking: ProgressView("نتحقق من توفر الترجمة")
                case .installed: Button("ترجم الفقرة") { translationOpen = true }
                case .needsDownload: Button("نزّل الترجمة وترجم الفقرة") { translationOpen = true }
                case .unsupported: EmptyView()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.layoutDirection, .rightToLeft)
        .task { refreshWordState(); await refreshTranslationAvailability() }
        .sheet(isPresented: $translationOpen) {
            MacMihbaraTranslationSheet(text: selection.paragraphText).frame(minWidth: 420, minHeight: 360)
        }
    }

    @MainActor private func refreshWordState() {
        let key = UserWordIdentity.key(language: language, word: selection.selectedText)
        let context = ModelContext(app.container)
        let descriptor = FetchDescriptor<UserWord>(predicate: #Predicate {
            $0.language == language && $0.deletedAt == nil && $0.mergedInto == nil
        })
        wordSaved = (try? context.fetch(descriptor))?.contains {
            UserWordIdentity.key(language: $0.language, word: $0.word) == key
        } ?? false
    }

    @MainActor private func saveWord() async {
        guard canSaveAsWord, !wordSaved, let locatorJSON else { return }
        do {
            try await app.executeBookCommand("word.save", payload: [
                "id": .string(UUID().uuidString), "word": .string(selection.selectedText), "language": .string(language),
                "bookID": .string(book.id.uuidString), "bookTitle": .string(book.title),
                "locator": .string(locatorJSON), "context": .string(String(selection.paragraphText.prefix(4000)))
            ], undoMessage: "أُضيفت إلى كلماتي")
            wordSaved = true
        } catch { app.errorMessage = madarUserMessage(error) }
    }

    @MainActor private func refreshTranslationAvailability() async {
        guard book.language == "en" else { translationStatus = .unsupported; return }
        if #available(macOS 15.0, *) {
            switch await LanguageAvailability().status(from: .init(identifier: "en"), to: .init(identifier: "ar")) {
            case .installed: translationStatus = .installed
            case .supported: translationStatus = .needsDownload
            case .unsupported: translationStatus = .unsupported
            @unknown default: translationStatus = .unsupported
            }
        } else { translationStatus = .unsupported }
    }

    private func copyWithCitation() {
        let source = [book.title, book.author].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let text = "«\(selection.selectedText)»\n— " + source.joined(separator: "، ")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct MacMihbaraTranslationSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var result: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("تمّ") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("ترجمة الفقرة").font(MadarTypography.section())
                Spacer()
                Color.clear.frame(width: 44)
            }
            Text("ترجمة آلية تقريبية · تُعالج على الجهاز").font(MadarTypography.fine()).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                if let result {
                    Text(result).font(.custom("Amiri-Regular", size: 20, relativeTo: .body))
                        .lineSpacing(7).frame(maxWidth: .infinity, alignment: .leading)
                } else if failed {
                    Text("تعذّرت الترجمة. تحقّق من تثبيت اللغتين ثم حاول مجددًا.").font(MadarTypography.body())
                } else { ProgressView("تُترجم الفقرة على الجهاز…").font(MadarTypography.body()) }
            }
        }
        .padding(20).environment(\.layoutDirection, .rightToLeft)
        .translationTask(source: .init(identifier: "en"), target: .init(identifier: "ar"), action: Self.translationAction(text: text) { translated in
            result = translated
            failed = translated == nil
        })
    }

    nonisolated private static func translationAction(text: String, completion: @escaping @MainActor @Sendable (String?) -> Void) -> @Sendable (TranslationSession) async -> Void {
        { session in
            do { await completion(try await session.translate(text).targetText) }
            catch { await completion(nil) }
        }
    }
}
