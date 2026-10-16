import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// «التصنيفات والحدود» (`mal/12-Z-R18-cat-1`): each category a bookshelf, its merchants the books, the shelf its limit,
/// and a dashed line where spending should be by today. The limit of the selected shelf is edited below.
struct MoneyCategoriesView: View {
    let app: AppSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var reading: MoneyCategoriesReading?
    @State private var failure: String?
    @State private var selected: UUID?
    @State private var percentMode = false
    @State private var draftMinor = 0
    @State private var draftBp = 0
    @State private var draftBase = "income"
    @State private var saving = false
    @State private var revealed = false
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private var visible: Bool { revealed || !app.bool("core.hideMoneyUntilTouch") }
    private func amount(_ minor: Int) -> String { visible ? service.amount(minor) : "•••" }
    /// The shelf plank: dark wood under every category.
    private var wood: Color { theme.color("reserveText").mix(with: theme.ink, by: 0.45) }
    /// Each shelf's books take their own binding colour, in category order (the canonical's brown, green, blue, purple, grey).
    private func binding(_ index: Int) -> Color { [theme.color("reserveText"), theme.color("surplus"), theme.color("accent"), theme.color("bills"), theme.secondaryInk][index % 5] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title3).frame(width: 52, height: 52).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1.2) }
                    }.buttonStyle(.plain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-categories-close")
                    Text("التصنيفات والحدود").font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                    Spacer()
                }.padding(.top, 8)
                if let reading {
                    header(reading)
                    if !visible { Button("أظهر الأرقام") { revealed = true }.font(MadarTypography.caption()).frame(minHeight: 44) }
                    if reading.shelves.isEmpty {
                        Text("لا تصنيفات بعد. تُنشأ حين تصنّف أول حركة في رسائل البنك.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                    }
                    ForEach(Array(reading.shelves.enumerated()), id: \.element.id) { shelf($0.element, tint: binding($0.offset)) }
                    if !reading.shelves.isEmpty {
                        HStack(spacing: 14) {
                            HStack(spacing: 4) { Rectangle().fill(wood).frame(width: 18, height: 4); Text("الرف = حدّك") }
                            HStack(spacing: 4) { DashLine().stroke(theme.color("accent"), style: .init(lineWidth: 2, dash: [3, 2])).frame(width: 2, height: 14); Text("المفروض حتى اليوم") }
                        }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity)
                    }
                    if let shelf = reading.shelves.first(where: { $0.id == selected }) ?? reading.shelves.first { editor(shelf, reading) }
                } else if let failure { Text(failure).font(MadarTypography.body()) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
            }.padding(.horizontal, 16).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .accessibilityIdentifier("money-categories")
    }

    private func header(_ r: MoneyCategoriesReading) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(amount(r.totalLimitsMinor)).font(.custom("thmanyahserifdisplay-Black", size: 30, relativeTo: .title)).lineLimit(1).minimumScaleFactor(0.6)
            Text("حدودك" + (r.incomeMinor > 0 && visible ? "، " + service.percent(r.totalLimitsMinor, of: r.incomeMinor) + " من الراتب" : "")).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Spacer(minLength: 6)
            if r.autoCategorized > 0 {
                Label(service.digits.string(r.autoCategorized) + " تصنّفت وحدها", systemImage: "checkmark").font(MadarTypography.fine()).foregroundStyle(theme.color("surplusText"))
                    .padding(.horizontal, 10).padding(.vertical, 6).overlay { Capsule().stroke(theme.line, lineWidth: 1) }.accessibilityIdentifier("money-categories-auto")
            }
        }
    }

    private func shelf(_ s: MoneyCategoryShelf, tint: Color) -> some View {
        let active = (selected ?? reading?.shelves.first?.id) == s.id
        let scale = max(1, s.limitMinor ?? max(s.spentMinor, 1))
        let used = s.percentUsed
        return Button { pick(s) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.name).font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .headline))
                    Spacer(minLength: 6)
                    Text(amount(s.spentMinor) + " من " + (s.limitMinor.map(amount) ?? "بلا حد")).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    Text(visible ? used.map { service.digits.string($0) + "٪" } ?? "—" : "•••").font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .callout))
                        .foregroundStyle((used ?? 0) >= 80 ? theme.color("dueText") : theme.color("reserveText")).frame(minWidth: 40, alignment: .trailing)
                }
                GeometryReader { proxy in
                    let w = proxy.size.width
                    ZStack(alignment: .bottomTrailing) {
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(Array(s.books.enumerated()), id: \.element.id) { index, book in
                                let width = visible ? max(14, min(w, w * CGFloat(book.amountMinor) / CGFloat(scale)) - 2) : 14
                                bookView(book, width: width, height: [32, 27, 22][index % 3], index: index, showName: index == 0, tint: tint)
                            }
                        }.frame(width: w, alignment: .trailing).padding(.bottom, 5)
                        if s.limitMinor != nil {
                            Rectangle().fill(wood).frame(width: w, height: 5)
                        } else {
                            DashLine().stroke(wood.opacity(0.6), style: .init(lineWidth: 1, dash: [4, 3])).frame(width: w, height: 1)
                        }
                        if let expected = s.expectedTodayMinor, let limit = s.limitMinor, limit > 0, visible {
                            DashLine().stroke(theme.color("accent"), style: .init(lineWidth: 2, dash: [3, 2])).frame(width: 2, height: 40)
                                .offset(x: -w * CGFloat(min(expected, limit)) / CGFloat(limit))
                        }
                    }.environment(\.layoutDirection, .leftToRight)
                }.frame(height: 40)
            }.padding(.horizontal, 10).padding(.vertical, 8).background(active ? theme.surface : Color.clear)
                .overlay { if active { RoundedRectangle(cornerRadius: 8).stroke(theme.color("reserve"), lineWidth: 1.2) } }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("money-shelf-" + s.name)
    }
    private func bookView(_ book: MoneyShelfBook, width: CGFloat, height: CGFloat, index: Int, showName: Bool, tint: Color) -> some View {
        let tints = [tint, tint.opacity(0.78), tint.opacity(0.58)]
        return ZStack {
            Rectangle().fill(tints[index % 3])
            Rectangle().fill(theme.background.opacity(0.25)).frame(height: 2).frame(maxHeight: .infinity, alignment: .top)
            HStack(spacing: 4) {
                if showName && width > 110 { Text(book.name).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).lineLimit(1) }
                if width > 40 { Text(amount(book.amountMinor)).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption)).lineLimit(1).minimumScaleFactor(0.7) }
            }.foregroundStyle(theme.background).padding(.horizontal, 4).environment(\.layoutDirection, .rightToLeft)
        }.frame(width: width, height: height).accessibilityLabel(book.name)
    }

    // MARK: The limit editor

    private func editor(_ s: MoneyCategoryShelf, _ r: MoneyCategoriesReading) -> some View {
        let limit = percentMode ? ((draftBase == "allowance" ? r.allowanceMinor : r.incomeMinor) * draftBp) / 10_000 : draftMinor
        let left = limit - s.spentMinor
        return VStack(spacing: 12) {
            HStack(spacing: 6) {
                Rectangle().fill(theme.color("reserve")).frame(height: 1); Image(systemName: "sparkle").foregroundStyle(theme.color("reserve")); Rectangle().fill(theme.color("reserve")).frame(height: 1)
            }
            HStack {
                Text("حدّ " + s.name).font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3))
                Spacer()
                HStack(spacing: 0) {
                    modeButton("ريال", !percentMode) { percentMode = false; draftMinor = limit }
                    if r.incomeMinor > 0 { modeButton("٪ راتب", percentMode) { percentMode = true; draftBase = "income"; draftBp = r.incomeMinor > 0 ? min(10_000, max(1, (draftMinor * 10_000) / r.incomeMinor)) : 0 } }
                }.overlay { Capsule().stroke(theme.color("reserve"), lineWidth: 1) }.clipShape(Capsule())
            }
            HStack {
                step("minus") { if percentMode { draftBp = max(100, draftBp - 100) } else { draftMinor = max(0, draftMinor - 10_000) } }
                Spacer()
                Text(percentMode ? service.digits.string(draftBp / 100) + "٪" : amount(draftMinor)).font(.custom("thmanyahserifdisplay-Black", size: 52, relativeTo: .largeTitle))
                    .lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier("money-limit-value")
                Spacer()
                step("plus") { if percentMode { draftBp = min(10_000, draftBp + 100) } else { draftMinor += 10_000 } }
            }.environment(\.layoutDirection, .leftToRight)
            Text(percentMode ? "= " + amount(limit) + " هذه الدورة" : r.incomeMinor > 0 && visible ? "= " + service.percent(draftMinor, of: r.incomeMinor) + " من راتبك" : "")
                .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            Text(left >= 0 ? "باقي " + amount(left) + "، يكفيك " + amount(left / max(1, r.daysLeft)) + " في اليوم" : "تجاوزت الحد بـ" + amount(-left))
                .font(MadarTypography.caption()).foregroundStyle(left >= 0 && limit > 0 && s.spentMinor * 100 / max(1, limit) < 80 ? theme.color("surplusText") : theme.color("dueText"))
                .accessibilityIdentifier("money-limit-left")
            HStack(spacing: 10) {
                if s.limitMinor != nil {
                    Button { save(s, none: true) } label: {
                        Text("بلا حد").font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 54).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
                    }.buttonStyle(.plain).disabled(saving).accessibilityIdentifier("money-limit-none")
                }
                Button { save(s, none: false) } label: {
                    Text("احفظ الحد").font(.custom("thmanyahsans-Bold", size: 18, relativeTo: .headline)).foregroundStyle(theme.background)
                        .frame(maxWidth: .infinity, minHeight: 54).background(theme.ink, in: Capsule())
                }.buttonStyle(.plain).disabled(saving).accessibilityIdentifier("money-limit-save").layoutPriority(1)
            }
        }.padding(.top, 6)
    }
    private func modeButton(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(MadarTypography.caption()).foregroundStyle(on ? theme.background : theme.ink).padding(.horizontal, 16).frame(minHeight: 44).background(on ? theme.ink : Color.clear)
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
    private func step(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3).frame(width: 64, height: 64).background(theme.surface, in: Circle()).overlay { Circle().stroke(theme.color("reserve"), lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityLabel(symbol == "plus" ? "زد الحد" : "أنقص الحد").accessibilityIdentifier("money-limit-" + symbol)
    }

    // MARK: Actions

    private func pick(_ s: MoneyCategoryShelf) {
        withAnimation(.easeOut(duration: 0.2)) { selected = s.id }
        percentMode = s.mode == "percent" && (reading?.incomeMinor ?? 0) > 0
        draftBp = s.percentBp ?? 0
        draftBase = s.mode == "percent" ? s.base : "income"
        draftMinor = s.limitMinor ?? 0
    }
    private func load() {
        do {
            let first = reading == nil
            reading = try service.loadCategories(); failure = nil
            if first, let shelf = reading?.shelves.first { pick(shelf) }
        } catch { failure = "تعذّرت قراءة التصنيفات الآن." }
    }
    private func save(_ s: MoneyCategoryShelf, none: Bool) {
        guard !saving else { return }
        var payload: [String: MadarCore.JSONValue] = ["categoryID": .string(s.id.uuidString)]
        if none { payload["mode"] = .string("none") }
        else if percentMode { payload["mode"] = .string("percent"); payload["percentBp"] = .number(Double(max(1, draftBp))); payload["base"] = .string(draftBase) }
        else { payload["mode"] = .string("fixed"); payload["limitMinor"] = .string(String(draftMinor)) }
        saving = true
        Task { try? await app.executeMoneyCommand("money.setCategoryLimit", payload: payload); saving = false; load() }
    }
}

/// A straight line along the longer side of its frame, for dashed shelves and the «today» marker.
struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if rect.width >= rect.height { p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        else { p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
        return p
    }
}
