import SwiftUI
import UIKit
import MadarCore
import MadarDesign

struct MihbaraPaperEditor: View {
    let app: AppSession
    let readingBooks: [MihbaraBook]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var title = ""
    @State private var author = ""
    @State private var pages = ""
    @State private var shelf = "reading"
    @State private var saving = false
    @State private var identity = UUID()
    @State private var choosingSlot = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("كتاب ورقي").font(MadarTypography.title()); Spacer(); Button("إلغاء") { dismiss() } }
                Text("كتابك على الطاولة، وموضعك في مدار.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                field("العنوان", text: $title, id: "mihbara-paper-title")
                field("المؤلف", text: $author, id: "mihbara-paper-author")
                field("عدد الصفحات، إن عرفته", text: $pages, id: "mihbara-paper-pages").keyboardType(.numberPad)
                Text("يمكنك ترك الصفحات فارغة حتى تتأكد من طبعتك.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Picker("ضعه على رف", selection: $shelf) { Text("أقرؤه الآن").tag("reading"); Text("أبي أقرأه").tag("want"); Text("أنهيته").tag("finished") }.pickerStyle(.menu).font(MadarTypography.section())
                Button { save() } label: { Text(saving ? "يُحفظ…" : "ضعه على الرف") }.buttonStyle(MadarPrimaryButton()).disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("mihbara-paper-save")
            }.padding(22)
        }.scrollDismissesKeyboard(.interactively).background(theme.background).foregroundStyle(theme.ink)
        .confirmationDialog("اختر كتابًا يرجع إلى أبي أقرأها", isPresented: $choosingSlot, titleVisibility: .visible) { ForEach(readingBooks) { old in Button(old.title) { save(replacing: old.id) } } }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
    }
    private func field(_ label: String, text: Binding<String>, id: String) -> some View { VStack(alignment: .leading, spacing: 7) { Text(label).font(MadarTypography.caption()); TextField(label, text: text).font(MadarTypography.body()).padding(15).background(theme.surface, in: .rect(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(theme.line) }.accessibilityIdentifier(id) } }
    private func save(replacing: UUID? = nil) {
        if shelf == "reading", readingBooks.count >= 3, replacing == nil { choosingSlot = true; return }
        var p: [String:MadarCore.JSONValue] = ["id":.string(identity.uuidString),"title":.string(title),"author":.string(author),"shelf":.string(shelf)]
        if !pages.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let n = mihbaraInteger(pages), n > 0 else { app.errorMessage = "اكتب عدد صفحات صحيحًا"; return }; p["pages"] = .number(Double(n))
        }
        if let replacing { p["replacing"] = .string(replacing.uuidString) }
        saving = true
        Task { do { try await app.executeBookCommand("book.savePaper", payload: p); dismiss() } catch { app.errorMessage = error.localizedDescription }; saving = false }
    }
}
struct MihbaraBookCard: View {
    let app: AppSession; let book: MihbaraBook; let books: [MihbaraBook]; var onTable: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var page = ""
    @State private var finish = false
    @State private var choosingSlot = false
    @State private var saving = false
    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text(book.title).font(MadarTypography.title()); Spacer(); Button("تمّ") { dismiss() } }
                Text(book.author).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                if let finished = book.finished { Text("أنهيته").font(MadarTypography.caption()); MadarDateLabel(app.dateLabels(GregorianDay.containing(finished, in: app.activePlace.timeZone))) }
                if book.shelf != "reading" { Button("ضعه على الطاولة") { moveToReading() }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("mihbara-put-on-table") }
                Text("وصلت إلى").font(MadarTypography.cardTitle())
                HStack { Text("صفحة"); TextField("رقم الصفحة", text: $page).keyboardType(.numberPad).padding(14).background(theme.surface, in: .rect(cornerRadius: 12)).accessibilityIdentifier("mihbara-book-page"); if let total = book.pages { Text("من " + digits.string(total)) } }.font(MadarTypography.body())
                Text("هذا يحفظ موضعك. جلسة القراءة تُحسب من وقت نشاطك في القارئ.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Toggle("أنهيت الكتاب", isOn: $finish).font(MadarTypography.section()).accessibilityIdentifier("mihbara-book-finished")
                Button("احفظ موضعي") { savePosition() }.buttonStyle(MadarPrimaryButton()).disabled(saving).accessibilityIdentifier("mihbara-book-save-position")
                Button("أعده إلى أبي أقرأها") { move("want") }.frame(minHeight: 44).accessibilityIdentifier("mihbara-book-to-want")
            }.padding(22)
        }.background(theme.background).foregroundStyle(theme.ink).scrollDismissesKeyboard(.interactively)
        .task { page = digits.string(book.page ?? 0).filter { $0.wholeNumberValue != nil } }
        .confirmationDialog("اختر كتابًا يرجع إلى أبي أقرأها", isPresented: $choosingSlot, titleVisibility: .visible) { ForEach(books.filter { $0.shelf == "reading" && $0.id != book.id }) { old in Button(old.title) { move("reading", replacing: old.id) } } }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } } }
    }
    private func moveToReading() { if books.filter({ $0.shelf == "reading" }).count >= 3 { choosingSlot = true } else { move("reading") } }
    private func move(_ shelf: String, replacing: UUID? = nil) {
        var p: [String:MadarCore.JSONValue] = ["id":.string(book.id.uuidString),"shelf":.string(shelf)]; if let replacing { p["replacing"] = .string(replacing.uuidString) }
        saving = true; Task { do { try await app.executeBookCommand("book.moveShelf", payload: p); if shelf == "reading" { onTable() } else { dismiss() } } catch { app.errorMessage = error.localizedDescription }; saving = false }
    }
    private func savePosition() {
        guard let n = mihbaraInteger(page) else { app.errorMessage = "اكتب رقم صفحة صحيحًا"; return }
        saving = true; Task { do { try await app.executeBookCommand("book.setPosition", payload: ["id":.string(book.id.uuidString),"page":.number(Double(n)),"finished":.bool(finish)]); dismiss() } catch { app.errorMessage = error.localizedDescription }; saving = false }
    }
}
struct MihbaraHadithView: View {
    let app: AppSession; let hadith: MihbaraHadith; let collection: MihbaraCollection; let day: GregorianDay
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var saving = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text(collection.title).font(MadarTypography.cardTitle()); Spacer(); Button("تمّ") { dismiss() } }
                Text(hadith.title).font(MadarTypography.title())
                MihbaraHadithText(text: hadith.text, ink: theme.ink)
                Divider()
                Text(collection.edition).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if let source = URL(string: collection.source) { Link("المصدر والنسخة", destination: source).font(MadarTypography.caption()) }
                if let license = URL(string: collection.licenseURL) { Link("حقوق النص وعزوه إلى ويكي مصدر", destination: license).font(MadarTypography.fine()) }
                Button("فهمته") { mark(true) }.buttonStyle(MadarPrimaryButton()).disabled(saving).accessibilityIdentifier("mihbara-hadith-understood")
                Button("أرجع له") { mark(false) }.frame(maxWidth: .infinity, minHeight: 44).disabled(saving).accessibilityIdentifier("mihbara-hadith-return")
            }.padding(24)
        }.background(theme.background).foregroundStyle(theme.ink)
    }
    private func mark(_ understood: Bool) { saving = true; Task { do { try await app.executeBookCommand("hadith.mark", payload: ["number":.number(Double(hadith.number)),"edition":.string(collection.editionID),"understood":.bool(understood),"day":.string(day.description)]); dismiss() } catch { app.errorMessage = error.localizedDescription }; saving = false } }
}
private func mihbaraInteger(_ value: String) -> Int? { let clean = value.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty, clean.allSatisfy({ $0.wholeNumberValue != nil }) else { return nil }; return Int(clean.compactMap { $0.wholeNumberValue.map(String.init) }.joined()) }

/// R01: the bundled Sunnah text uses native TextKit 2, without custom pagination.
private struct MihbaraHadithText: UIViewRepresentable {
    var text: String
    var ink: Color
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false; view.isScrollEnabled = false; view.backgroundColor = .clear
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true; view.semanticContentAttribute = .forceRightToLeft
        view.accessibilityIdentifier = "mihbara-hadith-text"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let style = NSMutableParagraphStyle(); style.alignment = .right; style.baseWritingDirection = .rightToLeft; style.lineSpacing = 8
        let font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: UIFont(name: "Amiri-Regular", size: 26) ?? UIFont.preferredFont(forTextStyle: .title2))
        view.attributedText = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor(ink), .paragraphStyle: style])
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return .init(width: width, height: uiView.sizeThatFits(.init(width: width, height: .greatestFiniteMagnitude)).height)
    }
}
