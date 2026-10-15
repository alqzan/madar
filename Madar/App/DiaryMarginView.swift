import SwiftUI
import MadarCore
import MadarDesign

struct DiaryMarginView: View {
    let page: DiaryDisplayDay
    let snapshot: DiaryHomeSnapshot
    let service: AppDiaryService
    let showAuto: Bool
    let showLines: Bool
    let ink: Color
    let another: (() -> Void)?
    let open: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var originals: [DiaryDisplayLine] { page.lines.filter { $0.kind != "margin" && (showAuto || !["salah", "quran"].contains($0.kind)) } }
    private var replies: [DiaryDisplayLine] { page.lines.filter { $0.kind == "margin" } }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ذكرى اليوم").font(DiaryType.heading).foregroundStyle(theme.accent)
                    MadarDateLabel("من صفحتك في " + service.bothDates(page.day))
                        .font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                }
                Spacer(minLength: 0)
                if let another {
                    Button(action: another) { Label("ذكرى أخرى", systemImage: "shuffle").font(MadarTypography.caption()).padding(.horizontal, 12).frame(minHeight: 44).overlay { Capsule().stroke(theme.line) } }
                        .buttonStyle(.plain).accessibilityIdentifier("diary-another-memory")
                }
            }
            VStack(alignment: .leading, spacing: 20) {
                header
                if showLines {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(originals) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(service.time(line.at)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink3Text")).frame(width: 42, alignment: .leading)
                            Text(line.text).font(DiaryType.writing).lineSpacing(11).italic(line.kind != "normal")
                                .foregroundStyle(line.kind == "normal" ? theme.ink : theme.color("autoInkText"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 10).frame(minHeight: 34)
                    }
                    if originals.isEmpty { Text("ذكرى حفظتها بالصورة.").font(DiaryType.writing).padding(.vertical, 24) }
                    ForEach(replies) { line in
                        VStack(alignment: .leading, spacing: 7) {
                            Text("في هامشها · " + (page.marginDays[line.id].map { service.bothDates($0) } ?? "تاريخ الكتابة غير متاح")).font(DiaryType.label)
                            Text(line.text).font(DiaryType.writing).italic().lineSpacing(11)
                        }.foregroundStyle(ink).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .leading) { Rectangle().fill(ink).frame(width: 2) }
                            .padding(.vertical, 12).accessibilityIdentifier("diary-margin-reply")
                    }
                }
                }
                Spacer(minLength: 30)
                Button(action: open) { Label("افتح اليوم كاملًا", systemImage: "arrow.up.left").font(MadarTypography.caption()).frame(minHeight: 44) }
                    .buttonStyle(.plain).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-open-memory")
            }
            .padding(18).frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
            .background {
                ZStack {
                    theme.surface
                    Canvas { context, size in
                        var rule = Path()
                        for y in stride(from: 48.0, through: size.height, by: 34) { rule.move(to: .init(x: 0, y: y)); rule.addLine(to: .init(x: size.width, y: y)) }
                        context.stroke(rule, with: .color(theme.line), lineWidth: 1)
                    }
                }.clipShape(.rect(cornerRadius: 7))
            }
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(theme.line) }
            .shadow(color: theme.ink.opacity(0.07), radius: 8, y: 8)
            .rotationEffect(typeSize.isAccessibilitySize ? .zero : .degrees(-1))
            .padding(.horizontal, 5).padding(.top, 5)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("diary-margin-home")
    }
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { dates; photo }
            VStack(alignment: .leading, spacing: 12) { dates; photo }
        }
    }
    private var dates: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(service.distance(page.day, snapshot.today)).font(MadarTypography.caption()).foregroundStyle(theme.accent)
            Text(service.dateTitle(page.day, calendar: FirstCalendar(rawValue: service.app.string("core.firstCalendar")) ?? .hijri)).font(DiaryType.title)
            Text(service.weekday(page.day) + "، " + service.dateTitle(page.day, calendar: service.app.string("core.firstCalendar") == "gregorian" ? .hijri : .gregorian))
                .font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var photo: some View {
        if let data = page.photo, let image = UIImage(data: data) {
            VStack(spacing: 6) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 110, height: 112).clipped()
                if let place = page.place { Text(place).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink3Text")) }
            }.padding(7).background(theme.surface).shadow(color: theme.ink.opacity(0.14), radius: 4, y: 4)
                .rotationEffect(.degrees(5))
                .overlay(alignment: .top) { Rectangle().fill(theme.line.opacity(0.8)).frame(width: 60, height: 17).rotationEffect(.degrees(-8)).offset(y: -12) }
                .padding(.top, 8).accessibilityLabel("صورة من الذكرى")
        }
    }
}
