import SwiftUI
import MadarCore
import MadarDesign

struct MihbaraHomeView: View {
    let app: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reading: MihbaraHomeReading?
    @State private var shelf = "reading"
    @State private var tableID: UUID?
    @State private var sheet: MihbaraSheet?
    @State private var manuallyOpen = false
    @State private var libraryQuery = ""
    @State private var libraryShelf = "all"
    private var theme: RoomTheme { .init(room: "mihbara", dark: colorScheme == .dark) }
    private var service: AppMihbaraService { .init(app: app) }
    private var tableBook: MihbaraBook? { reading?.books.first { $0.id == tableID } ?? reading?.books.first { $0.shelf == "reading" } }
    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 60)) { tick in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Button { dismiss() } label: { Label("رجوع", systemImage: "chevron.right") }.accessibilityIdentifier("mihbara-back"); Spacer(); Text("المحبرة").font(MadarTypography.title()); Image(systemName: "books.vertical").font(.title2) }
                    if let r = reading {
                        MadarDateLabel(app.dateLabels(r.day)).foregroundStyle(theme.secondaryInk)
                        shelfView(r)
                        desk(r)
                    }
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 28).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.onChange(of: tick.date) { load() }
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
        .task { load() }.onChange(of: app.prayerRevision) { load() }.onChange(of: reading?.day) { folded = false; manuallyOpen = false }
        .sheet(item: $sheet) { target in
            NavigationStack {
                if let r = reading {
                    switch target {
                    case .add: MihbaraPaperEditor(app: app, readingBooks: r.books.filter { $0.shelf == "reading" })
                    case .library: library(r)
                    case .book(let id): if let b = r.books.first(where: { $0.id == id }) { MihbaraBookCard(app: app, book: b, books: r.books) { tableID = id; sheet = nil } }
                    case .hadith(let n): if let h = r.collection.hadiths.first(where: { $0.number == n }) { MihbaraHadithView(app: app, hadith: h, collection: r.collection, day: r.day) }
                    }
                }
            }.environment(\.roomTheme, theme).presentationDragIndicator(.visible)
        }
    }
    private func load() { do { reading = try service.load() } catch { app.errorMessage = error.localizedDescription } }
    private func shelfView(_ r: MihbaraHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("رفّك").font(MadarTypography.cardTitle()); Spacer(); Button { sheet = .add } label: { Label("كتاب ورقي", systemImage: "plus") }.accessibilityIdentifier("mihbara-add-paper") }
            HStack(spacing: 8) {
                ForEach([("reading","أقرؤها الآن"),("want","أبي أقرأها"),("finished","أنهيتها")], id: \.0) { value in
                    Button { shelf = value.0 } label: { Text(value.1).font(MadarTypography.caption()).padding(.horizontal, 10).frame(minHeight: 44).background(shelf == value.0 ? theme.ink : .clear, in: .capsule).foregroundStyle(shelf == value.0 ? theme.background : theme.ink) }.accessibilityIdentifier("mihbara-shelf-" + value.0)
                }
            }.fixedSize(horizontal: false, vertical: true)
            let books = r.books.filter { $0.shelf == shelf }
            if books.isEmpty {
                VStack(alignment: .leading, spacing: 6) { Text(r.books.isEmpty ? "أضف كتابك الأول" : "مساحة لكتابك القادم").font(MadarTypography.cardTitle()); Text(r.books.isEmpty ? "ضع كتابًا من مكتبتك على الرف، واحفظ أين وصلت." : "انقل كتابًا إلى هذا الرف من بطاقته.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }.frame(maxWidth: .infinity, minHeight: 95, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(books) { b in
                            Button { sheet = .book(b.id) } label: {
                                VStack(spacing: 8) {
                                    if b.id == tableBook?.id {
                                        VStack(spacing: 10) { Text(b.title).font(MadarTypography.caption()); Text("على الطاولة").font(MadarTypography.fine()) }.padding(12).frame(width: 110, height: 145).foregroundStyle(theme.secondaryInk).overlay { RoundedRectangle(cornerRadius: 5).stroke(theme.line, style: .init(lineWidth: 1, dash: [4,4])) }
                                    } else {
                                    VStack(spacing: 8) { Text(b.title).font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).lineLimit(3); Text(b.author).font(MadarTypography.fine()).lineLimit(1); Spacer(minLength: 0); Rectangle().frame(height: 1).opacity(0.4); if let p = b.progress { Text(service.digits.string(Int(p * 100)) + "٪").font(MadarTypography.fine()) } }
                                        .padding(12).frame(width: 110, height: 145).foregroundStyle(theme.color("onNavy")).background(theme.color("navy"), in: .rect(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 9, topTrailingRadius: 9)).overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 5) }.shadow(color: theme.ink.opacity(0.14), radius: 5, x: 0, y: 5)
                                    }
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("mihbara-book-" + b.id.uuidString)
                        }
                    }.padding(.bottom, 8)
                }.scrollIndicators(.hidden)
            }
            Rectangle().fill(theme.color("wood").gradient).frame(height: 9).shadow(color: theme.ink.opacity(0.14), radius: 5, y: 5)
            HStack { Button("كل كتبي ‹") { sheet = .library }.accessibilityIdentifier("mihbara-library"); Spacer(); Text(service.digits.string(r.books.count) + " على رفوفك").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            if !r.books.filter({ $0.shelf == "old" }).isEmpty {
                HStack { Text("قديمًا").font(MadarTypography.section()); ForEach(r.books.filter { $0.shelf == "old" }) { b in Button(b.title) { sheet = .book(b.id) }.font(MadarTypography.caption()).opacity(0.7) } }.padding(12).background(theme.surface, in: .rect(cornerRadius: 14))
            }
        }
    }
    private func desk(_ r: MihbaraHomeReading) -> some View {
        let hadith = r.todayHadiths.first
        let open = (r.opensAfterFajr || manuallyOpen || app.string("mihbara.rahlOpens") == "untilDone") && hadith != nil
        return VStack(alignment: .leading, spacing: 22) {
            HStack { deskLabel("على الطاولة", title: true); Spacer(); deskLabel("كتابك وورد يومك") }
            if open, let h = hadith {
                HStack { deskLabel("على الرَّحل، ورد اليوم أولًا"); Spacer(); Button("اطوه ⌃") { manuallyOpen = false; folded = true }.font(MadarTypography.caption()).padding(9).background(theme.color("desk"), in: .capsule).foregroundStyle(theme.color("onDesk")) }
                if !folded {
                    VStack(spacing: 0) {
                        MihbaraOpenBook(theme: theme, sunnah: true, rightHeader: r.collection.title, rightTitle: h.title, rightText: excerpt(h.text), leftTitle: "حديث واحد", leftText: "ورد اليوم\n" + service.digits.string(r.readCount) + " من " + service.digits.string(r.collection.hadiths.count), foot: service.digits.string(h.number), action: "افهمه") { sheet = .hadith(h.number) }
                        ZStack { RoundedRectangle(cornerRadius: 7).fill(theme.color("desk")).frame(width: 225, height: 13).rotationEffect(.degrees(17)); RoundedRectangle(cornerRadius: 7).fill(theme.color("desk")).frame(width: 225, height: 13).rotationEffect(.degrees(-17)); Circle().fill(theme.color("goldUnderstand")).frame(width: 11) }.frame(height: 58).accessibilityHidden(true)
                    }.transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else { Button("افتح ورد اليوم") { folded = false }.buttonStyle(.borderedProminent).tint(theme.color("sunnahLeather")) }
            } else {
                Button { manuallyOpen = true; folded = false; if let h = hadith { sheet = .hadith(h.number) } } label: {
                    HStack { Image(systemName: r.completedToday > 0 ? "checkmark.seal" : "book.closed"); VStack(alignment: .leading, spacing: 4) { Text(r.completedToday > 0 ? "أتممت ورد اليوم" : r.readCount == 42 ? "أتممت الأربعين النووية" : "وردك بعد الفجر").font(MadarTypography.cardTitle()); if r.completedToday > 0 { Text("الحديث القادم في يومك الجديد").font(MadarTypography.caption()) } }; Spacer() }.padding(16).background(theme.color("sunnahLeather"), in: .rect(cornerRadius: 12)).foregroundStyle(theme.onAccent)
                }.buttonStyle(.plain).disabled(hadith == nil).accessibilityIdentifier("mihbara-wird-closed")
            }
            HStack { deskLabel("كتاب القراءة"); Spacer(); deskLabel("موضعك محفوظ") }
            if let b = tableBook {
                MihbaraOpenBook(theme: theme, sunnah: false, rightHeader: b.author, rightTitle: b.title, rightText: b.pages.map { service.digits.string($0) + " صفحة" } ?? "كتاب ورقي", leftTitle: "وصلت إلى", leftText: b.page.map { "صفحة " + service.digits.string($0) } ?? "بداية الكتاب", foot: b.progress.map { service.digits.string(Int($0 * 100)) + "٪" } ?? "", action: "أكمل") { sheet = .book(b.id) }
            } else {
                Button { sheet = .add } label: { VStack(spacing: 12) { Image(systemName: "book.pages").font(.largeTitle); Text("مكان كتابك").font(MadarTypography.cardTitle()); Text("أضف كتابًا ورقيًا وابدأ من موضعك").font(MadarTypography.caption()) }.frame(maxWidth: .infinity, minHeight: 210).background(theme.surface, in: .rect(cornerRadius: 5)).overlay { RoundedRectangle(cornerRadius: 5).stroke(theme.line, style: .init(lineWidth: 1, dash: [4,4])) } }.buttonStyle(.plain).foregroundStyle(theme.ink)
            }
        }.padding(18).padding(.vertical, 8).background(LinearGradient(colors: [theme.color("wood").opacity(0.78), theme.color("wood")], startPoint: .top, endPoint: .bottom), in: .rect(topLeadingRadius: 26, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 26)).animation(reduceMotion ? nil : .smooth(duration: 0.35), value: open && !folded)
    }
    @State private var folded = false
    private func deskLabel(_ text: String, title: Bool = false) -> some View { Text(text).font(title ? MadarTypography.cardTitle() : MadarTypography.fine()).foregroundStyle(theme.color("onDesk")).padding(.horizontal, 10).padding(.vertical, 7).background(theme.color("desk"), in: .capsule) }
    private func excerpt(_ text: String) -> String { text.count <= 165 ? text : String(text.prefix(165)).split(separator: " ").dropLast().joined(separator: " ") + "…" }
    private func library(_ r: MihbaraHomeReading) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("مكتبتي").font(MadarTypography.title()); Spacer(); Button("تمّ") { sheet = nil } }
                ZStack {
                    UnevenRoundedRectangle(topLeadingRadius: 70, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 70).fill(theme.color("navy").gradient)
                    Circle().fill(theme.color("goldUnderstand")).frame(width: 40, height: 40).offset(x: -55, y: -5)
                    Rectangle().fill(theme.surface).frame(width: 5)
                    Rectangle().fill(theme.surface).frame(height: 4)
                }.frame(height: 125).padding(.horizontal, 65).accessibilityHidden(true)
                TextField("ابحث في كتبك…", text: $libraryQuery).font(MadarTypography.body()).padding(15).background(theme.surface, in: .capsule).accessibilityIdentifier("mihbara-library-search")
                Picker("رفّ الكتب", selection: $libraryShelf) { Text("كل الكتب").tag("all"); Text("أقرؤها الآن").tag("reading"); Text("أبي أقرأها").tag("want"); Text("أنهيتها").tag("finished"); Text("قديمًا").tag("old") }.pickerStyle(.menu)
                Text("البحث يُبرز المطابق، وكل كتبك تبقى في مكانها.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                ForEach(r.books) { b in
                    let queryMatches = libraryQuery.isEmpty || (b.title + " " + b.author).folding(options: [.diacriticInsensitive,.caseInsensitive], locale: Locale(identifier: "ar")).contains(libraryQuery.folding(options: [.diacriticInsensitive,.caseInsensitive], locale: Locale(identifier: "ar")))
                    Button { sheet = .book(b.id) } label: {
                        HStack { Image(systemName: "book.closed"); VStack(alignment: .leading) { Text(b.title).font(MadarTypography.cardTitle()); Text(b.author).font(MadarTypography.caption()) }; Spacer(); Text(b.shelf == "reading" ? "أقرؤه" : b.shelf == "want" ? "أبي أقرأه" : "أنهيته").font(MadarTypography.fine()) }.padding(16).background(theme.surface, in: .rect(cornerRadius: 14))
                    }.buttonStyle(.plain).opacity(queryMatches && (libraryShelf == "all" || libraryShelf == b.shelf) ? 1 : 0.3)
                }
            }.padding(20)
        }.background(theme.background).foregroundStyle(theme.ink)
    }

}
private enum MihbaraSheet: Identifiable { case add, library, book(UUID), hadith(Int); var id: String { String(describing: self) } }

struct MihbaraOpenBook: View {
    var theme: RoomTheme; var sunnah: Bool; var rightHeader: String; var rightTitle: String; var rightText: String; var leftTitle: String; var leftText: String; var foot: String; var action: String; var open: () -> Void
    @Environment(\.dynamicTypeSize) private var type
    var body: some View {
        VStack(spacing: 0) {
            if type.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { Text(rightTitle).font(MadarTypography.cardTitle()); Text(rightText).font(MadarTypography.body()); Text(leftTitle + " " + leftText).font(MadarTypography.body()); Button(action, action: open).frame(minHeight: 44) }.padding(18).background(theme.surface)
            } else {
                HStack(spacing: 2) {
                    page(header: rightHeader, title: rightTitle, text: rightText, footer: foot)
                    page(header: "موضعك", title: leftTitle, text: leftText, footer: foot)
                }.padding(sunnah ? 6 : 2).background(sunnah ? theme.color("sunnahLeather") : theme.surface, in: .rect(cornerRadius: 5)).shadow(color: theme.ink.opacity(0.25), radius: 9, y: 9)
                HStack { Spacer(); Button(action, action: open).font(MadarTypography.section()).frame(width: 50, height: 56).foregroundStyle(sunnah ? theme.color("goldUnderstandText") : theme.background).background(sunnah ? theme.color("notebookYellow") : theme.color("ribbonRead"), in: .rect(bottomLeadingRadius: 12, bottomTrailingRadius: 2)).offset(y: -6).accessibilityIdentifier(sunnah ? "mihbara-wird-open" : "mihbara-book-continue") }.padding(.horizontal, 12).frame(height: 24)
            }
        }
    }
    private func page(header: String, title: String, text: String, footer: String) -> some View {
        VStack(spacing: 15) { Text(header).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2); Spacer(minLength: 0); Text(title).font(.custom("Amiri-Bold", size: 23, relativeTo: .title2)).multilineTextAlignment(.center); Text(text).font(.custom("Amiri-Regular", size: sunnah ? 19 : 21, relativeTo: .body)).multilineTextAlignment(.center).lineLimit(sunnah ? 6 : 4); Spacer(minLength: 0); Text(footer).font(.custom("Amiri-Regular", size: 14, relativeTo: .caption)) }.padding(.horizontal, 12).padding(.vertical, 18).frame(maxWidth: .infinity).frame(minHeight: 265).background(theme.surface).overlay(alignment: .leading) { LinearGradient(colors: [theme.ink.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 15).allowsHitTesting(false) }
    }
}
