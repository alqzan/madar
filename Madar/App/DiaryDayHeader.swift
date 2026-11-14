import SwiftUI
import MadarCore
import MadarDesign

/// The day page's heading: both dates, a visible today marker, a direct return on past days and, on Fridays, the chosen ornament.
/// It owns no state of its own: the page hands it the day and a binding for the tab choice.
struct DiaryDayHeader: View {
    @Bindable var app: AppSession
    let theme: RoomTheme
    let shownDay: GregorianDay
    let today: GregorianDay
    let appearance: DiaryDayAppearance?
    let friday: Bool
    @Binding var selected: GregorianDay?
    var onReturnToToday: (() -> Void)? = nil
    private var service: AppDiaryService { AppDiaryService(app: app) }
    private var first: FirstCalendar { app.diaryFirstCalendar }
    private var fridayStyle: DiaryFridayStyle { DiaryFridayStyle(app) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if shownDay == today {
                Text("اليوم").font(DiaryType.label).foregroundStyle(theme.accent)
                    .accessibilityIdentifier("diary-day-today-label")
            }
            Text(
                service.weekday(shownDay) + "، "
                    + (first == .gregorian && appearance?.night == true ? "ليلة " : "")
                    + service.dateTitle(
                        first == .gregorian ? appearance?.hijriDisplayDay ?? shownDay : shownDay,
                        calendar: first == .hijri ? .gregorian : .hijri)
                    + (friday ? "، " + service.dateTitle(shownDay, calendar: first) : "")
            )
            .font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-day-secondary-date")
            let title = Text(
                friday
                    ? "جمعة مباركة"
                    : (first == .hijri && appearance?.night == true ? "ليلة " : "")
                        + service.dateTitle(first == .hijri ? appearance?.hijriDisplayDay ?? shownDay : shownDay, calendar: first)
            ).foregroundStyle(friday ? theme.accent : theme.ink).font(
                .custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .largeTitle)
            ).lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier("diary-day-title")
            if friday {
                VStack(spacing: 4) {
                    title
                    if shownDay != today { dateChoice("العودة إلى اليوم", id: "today", value: today) }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 8) {
                        title
                        Spacer(minLength: 4)
                        if shownDay != today { dateChoice("العودة إلى اليوم", id: "today", value: today) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        title
                        if shownDay != today { dateChoice("العودة إلى اليوم", id: "today", value: today) }
                    }
                }
            }
        }.padding(.horizontal, 18).padding(.vertical, 4).frame(
            maxWidth: .infinity, alignment: friday ? .center : .leading
        ).padding(.top, friday && fridayStyle != .ribbon ? 34 : 0).background {
            if friday { ornament }
        }
    }

    /// OR-16: the Friday title wears the look chosen in the diary settings.
    @ViewBuilder private var ornament: some View {
        switch fridayStyle {
        case .ribbon: DiaryFridayFrame().stroke(theme.accent.opacity(0.65), lineWidth: 0.7).padding(.horizontal, 12)
        case .mihrab:
            ZStack(alignment: .top) {
                DiaryMihrabShape().stroke(theme.accent.opacity(0.55), lineWidth: 1).padding(.horizontal, 56)
                DiaryStarShape().fill(theme.accent).frame(width: 22, height: 22).padding(.top, 16)
            }.accessibilityHidden(true).accessibilityIdentifier("diary-friday-mihrab")
        case .medallion:
            ZStack {
                Circle().stroke(theme.accent.opacity(0.6), lineWidth: 1)
                DiaryStarShape().fill(theme.accent).frame(width: 18, height: 18)
            }.frame(width: 36, height: 36).frame(maxHeight: .infinity, alignment: .top).accessibilityHidden(true)
                .accessibilityIdentifier("diary-friday-medallion")
        }
    }
    private func dateChoice(_ title: String, id: String, value: GregorianDay) -> some View {
        let label = id == "today" && shownDay != today ? "العودة إلى اليوم" : title
        return Button {
            if id == "today", shownDay != today, let onReturnToToday { onReturnToToday() }
            else { selected = value }
        } label: {
            Text(label).font(DiaryType.label).frame(minHeight: 38).padding(.horizontal, 10).background(
                shownDay == value ? theme.surface : .clear, in: .rect(topLeadingRadius: 10, topTrailingRadius: 10)
            ).overlay {
                UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).stroke(
                    shownDay == value ? theme.color("ink3Text") : theme.line)
            }.contentShape(.rect.inset(by: -3))
        }
        .buttonStyle(.madarPlain).accessibilityIdentifier("diary-day-" + id).accessibilityAddTraits(
            shownDay == value ? .isSelected : [])
    }
}
