import SwiftUI
import MadarCore
import MadarDesign

/// The five built lobby blocks at the four sizes (§7.1 «ما تعرضه كل ودجة»). Room identities: prayer warm paper with
/// gold arches, Quran green cover with gold, diary the day's photo, year and upcoming on lobby paper.
struct BahwBlockView: View {
    let service: AppBahwService
    let block: BahwBlock
    let size: BahwBlockSize
    @Environment(\.roomTheme) private var lobby
    private var dark: Bool { lobby.dark }
    private var room: RoomTheme {
        switch block { case .salah: RoomTheme(room: "salah", dark: dark); case .quran: RoomTheme(room: "quran", dark: dark); case .notes: RoomTheme(room: "notes", dark: dark); default: lobby }
    }
    var body: some View {
        content
            .padding(size == .icon ? 8 : 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(block == .quran ? room.color("gold").opacity(0.35) : room.line) }
            .clipShape(.rect(cornerRadius: 22))
    }
    private var background: Color { block == .quran ? room.color("cover") : room.surface }
    private var digits: MadarNumberFormatter { service.digits }
    private var big: Font { .custom("thmanyahserifdisplay-Bold", size: size == .icon ? 22 : 40, relativeTo: .largeTitle) }
    private var label: Font { .custom("thmanyahsans-Bold", size: 14, relativeTo: .footnote) }
    private var small: Font { .custom("thmanyahsans-Regular", size: 12, relativeTo: .caption) }

    @ViewBuilder private var content: some View {
        switch block {
        case .salah: salah
        case .quran: quran
        case .notes: notes
        case .year: year
        case .upcoming: upcoming
        default: EmptyView()
        }
    }
    private func title(_ color: Color) -> some View {
        Label(block.title, systemImage: block.symbol).font(label).foregroundStyle(color).labelStyle(.titleAndIcon).lineLimit(1)
    }

    // MARK: prayer
    @ViewBuilder private var salah: some View {
        if let model = service.prayer() {
            if size == .icon {
                VStack(spacing: 2) { Text(model.nextName ?? "الصلاة").font(small).foregroundStyle(room.secondaryInk); Text(model.nextTime ?? "").font(big).minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: size == .small ? 8 : 6) {
                    HStack { title(room.accent).accessibilityLabel("الصلاة في " + service.session.cityName); Spacer(); Text(digits.string(model.done) + " من " + digits.string(5)).font(small).foregroundStyle(room.secondaryInk).accessibilityIdentifier("bahw-salah-done") }
                    HStack(alignment: .bottom, spacing: size == .small ? 4 : 10) {
                        ForEach(model.arches) { arch in
                            VStack(spacing: 4) {
                                ZStack {
                                    PrayerHorseshoe().fill(arch.done ? room.color("goldMid") : room.surface)
                                    PrayerHorseshoe().stroke(room.accent, lineWidth: arch.next ? 2.4 : 1)
                                    if arch.done { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(room.ink) }
                                }.frame(maxWidth: size == .small ? 26 : 34).frame(height: size == .small ? 36 : 40).accessibilityHidden(true)
                                if size != .small { Text(arch.name + " " + arch.time).font(small).lineLimit(1).minimumScaleFactor(0.7) }
                            }.frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore).accessibilityLabel(arch.name + "، " + arch.clock24 + (arch.done ? "، صُلّيت" : ""))
                                .accessibilityIdentifier("foundation-prayer-time-" + arch.id)
                        }
                    }
                    Spacer(minLength: 0)
                    if let name = model.nextName {
                        let layout = size == .small ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 8))
                        layout {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("القادمة").font(small).foregroundStyle(room.secondaryInk)
                                Text(name + " " + (model.nextTime ?? "")).font(.custom("thmanyahserifdisplay-Bold", size: size == .small ? 20 : 24, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            if size != .small { Spacer(minLength: 0) }
                            if let after = model.nextAfter { Text(after).font(label).foregroundStyle(room.accent).lineLimit(1).minimumScaleFactor(0.8) }
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("bahw-salah-next")
                    }
                }
            }
        } else { Text("المواقيت غير متاحة لهذا الموقع اليوم.").font(small).foregroundStyle(room.secondaryInk) }
    }

    // MARK: Quran
    @ViewBuilder private var quran: some View {
        let gold = room.color("gold"), on = room.color("onCover")
        if let model = service.quran() {
            if size == .icon {
                VStack(spacing: 2) { Image(systemName: "book").foregroundStyle(gold); Text(model.coverage).font(small).foregroundStyle(on).multilineTextAlignment(.center).minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    title(gold)
                    Text("في صدرك").font(small).foregroundStyle(on)
                    Text(model.coverage).font(.custom("thmanyahserifdisplay-Bold", size: size == .small ? 24 : 30, relativeTo: .title)).foregroundStyle(gold).lineLimit(2).minimumScaleFactor(0.6).accessibilityIdentifier("bahw-quran-coverage")
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        ForEach(Array(model.days.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: 2).fill(day.review > 0 || day.hifz > 0 ? room.color("memorized") : on.opacity(0.18)).frame(height: 12)
                        }
                    }.accessibilityLabel("مراجعة آخر سبعة أيام")
                    Text(model.next).font(small).foregroundStyle(on).lineLimit(1)
                }
            }
        } else { Text("افتح القرآن لتبدأ.").font(small).foregroundStyle(on) }
    }

    // MARK: diary
    @ViewBuilder private var notes: some View {
        let model = service.diary()
        let count = model?.count ?? 0
        if size == .icon {
            VStack(spacing: 2) { Image(systemName: "pencil").foregroundStyle(room.accent); Text(count == 0 ? "اكتب" : service.lineCount(count)).font(small).multilineTextAlignment(.center).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let data = model?.photo, let image = UIImage(data: data) {
                    Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipShape(.rect(cornerRadius: 14)).padding(.bottom, 8).accessibilityHidden(true)
                }
                title(room.accent)
                Text(count == 0 ? "اكتب سطر اليوم" : service.lineCount(count)).font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title2)).lineLimit(2).minimumScaleFactor(0.7).accessibilityIdentifier("bahw-notes-count")
                if let last = model?.last { Text("آخرها " + service.time(last) + (model?.photo != nil ? "، وصورة" : "")).font(small).foregroundStyle(room.secondaryInk).lineLimit(1) }
                if model?.photo == nil { Spacer(minLength: 0) }
            }
        }
    }

    // MARK: year
    @ViewBuilder private var year: some View {
        let model = service.year()
        if size == .icon {
            VStack(spacing: 2) { Text("مضى").font(small).foregroundStyle(lobby.secondaryInk); Text(percent(model.hijri)).font(big) }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if size == .small {
            VStack(alignment: .leading, spacing: 6) {
                title(lobby.accent)
                Text(percent(model.hijri)).font(big)
                strip(model.hijri, month: model.hijriMonthIndex, hijri: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                title(lobby.accent)
                yearRow(digits.string(model.hijriYear) + "هـ", model.hijri, month: model.hijriMonthIndex, hijri: true)
                yearRow(digits.string(model.gregorianYear) + "م", model.gregorian, month: model.gregorianMonthIndex, hijri: false)
                Spacer(minLength: 0)

            }
        }
    }
    private func yearRow(_ name: String, _ period: MadarPeriod, month: Int, hijri: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(label)
                Spacer()
                Text("بقي " + digits.string(period.remaining) + " " + service.dayCount(period.remaining)).font(small).foregroundStyle(lobby.secondaryInk)
                Text(percent(period)).font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3)).foregroundStyle(hijri ? lobby.color("amberText") : lobby.color("gregorianInk"))
            }
            strip(period, month: month, hijri: hijri)
        }.accessibilityElement(children: .combine).accessibilityIdentifier(hijri ? "bahw-year-hijri" : "bahw-year-gregorian")
    }
    /// Twelve month segments; passed months filled, the current one by its share. Ramadan and Eid gold, Arafah green.
    private func strip(_ period: MadarPeriod, month: Int, hijri: Bool) -> some View {
        let fill = hijri ? lobby.color("amber") : lobby.color("lapis")
        let monthShare = Double(period.elapsed) / Double(max(1, period.length)) * 12 - Double(month)
        return HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(lobby.line.opacity(0.7))
                        RoundedRectangle(cornerRadius: 2).fill(fill).frame(width: geometry.size.width * (index < month ? 1 : index == month ? min(1, max(0.08, monthShare)) : 0))
                    }
                }.frame(height: 10)
                .overlay(alignment: .top) {
                    if hijri, [8, 9, 11].contains(index) { Capsule().fill(index == 11 ? lobby.color("green") : lobby.color("amber")).frame(width: 2, height: 16).offset(y: -4) }
                }
            }
        }.environment(\.layoutDirection, .rightToLeft).accessibilityHidden(true)
    }
    private func percent(_ period: MadarPeriod) -> String { digits.string(period.basisPoints / 100) + "٪\u{061C}" }
    private func markTitle(_ name: MadarLandmark.Name) -> String {
        switch name { case .ramadan: "رمضان"; case .eidAlFitr: "العيد"; case .arafah: "عرفة"; case .hijriNewYear: "رأس السنة"; case .gregorianYearEnd: "نهاية السنة" }
    }

    // MARK: upcoming
    @ViewBuilder private var upcoming: some View {
        let items = service.upcoming(limit: size == .small ? 3 : size == .large ? max(4, Int(service.session.number("bahw.upcomingCount"))) : 4)
        if size == .icon, let first = items.first {
            ring(first, diameter: 54).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if size == .small, let first = items.first {
            VStack(alignment: .leading, spacing: 6) {
                title(lobby.accent)
                HStack { ring(first, diameter: 66); VStack(alignment: .leading) { Text(first.title).font(label); Text(service.shortDate(first.day, hijri: false)).font(small).foregroundStyle(lobby.secondaryInk) } }
                ForEach(items.dropFirst()) { item in Text(item.title + " بعد " + digits.string(item.daysLeft) + " " + service.dayCount(item.daysLeft)).font(small).foregroundStyle(lobby.secondaryInk).lineLimit(1) }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack { title(lobby.accent); Spacer(); Text("كل حلقة على مقياس سنة").font(small).foregroundStyle(lobby.secondaryInk) }
                HStack(alignment: .top, spacing: 6) {
                    ForEach(items.prefix(4)) { item in
                        VStack(spacing: 6) {
                            ring(item, diameter: 64)
                            Text(item.title).font(label).lineLimit(1).minimumScaleFactor(0.75)
                            Text(service.shortDate(item.day, hijri: false)).font(small).foregroundStyle(lobby.secondaryInk).lineLimit(1)
                        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.title + " بعد " + digits.string(item.daysLeft) + " " + service.dayCount(item.daysLeft)).accessibilityIdentifier("bahw-upcoming-item")
                    }
                }
                // Large: the rest of `bahw.upcomingCount` as lines.
                ForEach(items.dropFirst(4)) { item in
                    HStack { Text(item.title).font(label); Spacer(); Text(digits.string(item.daysLeft) + " " + service.dayCount(item.daysLeft)).font(small).foregroundStyle(lobby.secondaryInk) }
                        .accessibilityElement(children: .combine).accessibilityIdentifier("bahw-upcoming-item")
                }
            }
        }
    }
    /// The ring closes as the day nears; the number inside is the days left.
    private func ring(_ item: BahwUpcomingItem, diameter: CGFloat) -> some View {
        ZStack {
            Circle().stroke(lobby.line, lineWidth: 5)
            Circle().trim(from: 0, to: service.upcomingCloseness(daysLeft: item.daysLeft)).stroke(lobby.color("clay"), style: .init(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(digits.string(item.daysLeft)).font(.custom("thmanyahserifdisplay-Bold", size: diameter * 0.34, relativeTo: .title2)).minimumScaleFactor(0.5)
                Text(service.dayCount(item.daysLeft)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(lobby.secondaryInk)
            }
        }.frame(width: diameter, height: diameter).accessibilityHidden(true)
    }
}
