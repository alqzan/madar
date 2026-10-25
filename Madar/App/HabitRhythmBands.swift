import SwiftUI
import MadarCore
import MadarDesign
import MadarCommands

/// Item 26, owner's pick «ب»: each rhythm draws itself above its group in «كل عاداتي». A day is steps, a week its
/// seven days, a month a crescent ring of its days, a year twelve arcs. Every mark is a real logged day.
struct HabitRhythmBand:View {
    let frequency:HabitFrequency
    let rows:[HabitReading]
    let today:GregorianDay
    let digits:MadarNumberFormatter
    @Environment(\.roomTheme) private var theme
    /// The engine's period runs from `start` up to, not including, `end`.
    private var period:HabitPeriodResult? { rows.compactMap { $0.summary.current }.first }
    /// Days in the current window on which any habit of this rhythm was logged.
    private var marked:Set<GregorianDay> {
        guard let p = period else { return [] }
        return Set(rows.flatMap { $0.times.map(\.day) }.filter { $0 >= p.start && $0 < p.end })
    }
    var body:some View {
        Group {
            if frequency == .weekly {
                VStack(alignment:.leading,spacing:10) { label; drawing }
            } else {
                HStack(spacing:16) { drawing.frame(width:84,height:84); label }
            }
        }
        .padding(.horizontal,16).padding(.vertical,12).frame(maxWidth:.infinity,alignment:.leading)
        .background(theme.surface.opacity(0.55),in:.rect(cornerRadius:20))
        .overlay { RoundedRectangle(cornerRadius:20).stroke(theme.line.opacity(0.7)) }
        .accessibilityElement().accessibilityLabel(caption).accessibilityIdentifier("habits-band-"+frequency.rawValue)
    }
    private var label:some View { Text(caption).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true) }
    @ViewBuilder private var drawing:some View {
        switch frequency {
        case .daily: steps
        case .weekly: week
        case .monthly: crescent
        case .yearly: arcs
        }
    }

    // MARK: Day: the last seven days as steps

    /// Each of the last seven days is a step whose height is how much of that day's daily habits was done; the room's
    /// hero already counts today, so the band shows the week of days behind it.
    private var lastSeven:[(day:GregorianDay,share:Double)] {
        Self.dailySteps(summaries: rows.map(\.summary), today: today)
    }
    /// Use the rule and exclusions of each historical day, including partial count/duration progress.
    static func dailySteps(summaries: [HabitSummary], today: GregorianDay) -> [(day: GregorianDay, share: Double)] {
        guard !summaries.isEmpty else { return [] }
        return (0..<7).reversed().map { back in
            let day = today.adding(days:-back)
            let due = summaries.compactMap { summary in
                summary.periods.last { $0.rule.frequency == .daily && $0.start <= day && day < $0.end }
            }.filter { $0.target > 0 }
            let progress = due.reduce(0.0) { $0 + min(1, max(0, Double($1.value) / Double($1.target))) }
            return (day, due.isEmpty ? 0 : progress / Double(due.count))
        }
    }
    private var steps:some View {
        HStack(alignment:.bottom,spacing:4) {
            ForEach(lastSeven,id:\.day) { item in
                let isToday = item.day == today, full = item.share >= 1
                RoundedRectangle(cornerRadius:4).fill(item.share > 0 ? theme.accentFill.opacity(full ? 1 : 0.55) : .clear)
                    .overlay { RoundedRectangle(cornerRadius:4).stroke(isToday ? theme.accent : full ? theme.accentFill : theme.line,lineWidth:isToday ? 1.6 : 1) }
                    .frame(height:12+64*max(0.06,item.share))
            }
        }.frame(maxHeight:.infinity,alignment:.bottom)
    }

    // MARK: Week: its seven days

    private var week:some View {
        let days = period.map { p in (0..<7).map { p.start.adding(days:$0) }.filter { $0 < p.end } } ?? []
        return HStack(spacing:6) {
            ForEach(days,id:\.self) { day in
                let on = marked.contains(day), isToday = day == today
                VStack(spacing:5) {
                    Circle().fill(on ? theme.accentFill : .clear)
                        .overlay { Circle().stroke(on ? theme.accentFill : isToday ? theme.accent : theme.line,lineWidth:isToday ? 2 : 1.2) }
                        .overlay { if on { Image(systemName:"checkmark").font(.system(size:12,weight:.bold)).foregroundStyle(theme.onAccent) } }
                        .frame(width:30,height:30).opacity(day > today ? 0.55 : 1)
                    Text(Self.weekday(day)).font(MadarTypography.fine()).foregroundStyle(isToday ? theme.ink : theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.7)
                }.frame(maxWidth:.infinity)
            }
        }
    }
    static func weekday(_ day:GregorianDay)->String {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = .gmt
        return ["أحد","اثنين","ثلاثاء","أربعاء","خميس","جمعة","سبت"][calendar.component(.weekday,from:day.date(in:.gmt))-1]
    }

    // MARK: Month: a crescent ring of its days

    private var crescent:some View {
        let p = period, total = p.map { max(1,span($0.start,$0.end)) } ?? 30, index = p.map { min(total,span($0.start,today)+1) } ?? 1
        return ZStack {
            ForEach(0..<total,id:\.self) { i in
                let day = p?.start.adding(days:i), on = day.map(marked.contains) ?? false, isToday = day == today
                Circle().fill(on ? theme.accentFill : i < index ? theme.line : theme.line.opacity(0.45))
                    .frame(width:isToday ? 8 : on ? 6 : 4,height:isToday ? 8 : on ? 6 : 4)
                    .overlay { if isToday { Circle().stroke(theme.accent,lineWidth:1.5).frame(width:12,height:12) } }
                    .offset(y:-36).rotationEffect(.degrees(Double(i)/Double(total)*360))
            }
            // The lit share of the ring is the month so far, as a crescent grows.
            Circle().trim(from:0,to:Double(index)/Double(total)).stroke(theme.accentFill.opacity(0.18),style:.init(lineWidth:10,lineCap:.round)).frame(width:72,height:72).rotationEffect(.degrees(-90))
            VStack(spacing:0) { Text(digits.string(index)).font(MadarTypography.section()); Text("من "+digits.string(total)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
        }
    }

    // MARK: Year: twelve arcs

    private var arcs:some View {
        let p = period, count = marked.count
        return ZStack {
            ForEach(0..<12,id:\.self) { m in
                let on = p.map { monthOn(m,$0) } ?? false, current = p.map { monthIndex(today,$0) == m } ?? false
                Circle().trim(from:Double(m)/12+0.008,to:Double(m+1)/12-0.008)
                    .stroke(on ? theme.accentFill : current ? theme.accent : theme.line,style:.init(lineWidth:on ? 7 : current ? 4 : 3,lineCap:.round))
                    .frame(width:72,height:72).rotationEffect(.degrees(-90))
            }
            VStack(spacing:0) { Text(digits.string(count)).font(MadarTypography.section()); Text("هذه السنة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.7) }.frame(width:56)
        }
    }
    private func monthIndex(_ day:GregorianDay,_ p:HabitPeriodResult)->Int { min(11,max(0,span(p.start,day)*12/max(1,span(p.start,p.end)))) }
    private func monthOn(_ m:Int,_ p:HabitPeriodResult)->Bool { marked.contains { monthIndex($0,p) == m } }

    // MARK: Words

    private var caption:String {
        let open = rows.filter { !$0.paused && $0.summary.current.map { $0.target > 0 && !$0.met } == true }
        switch frequency {
        case .daily:
            let week = lastSeven
            guard !week.isEmpty else { return "لا عادة يومية جارية" }
            let full = week.filter { $0.share >= 1 }.count
            return full == 0 ? "أسبوعك خطوات صغيرة؛ يكفي أن تبدأ" : full == 7 ? "سبعة أيام تامة، ما شاء الله" : "في آخر سبعة أيام، "+arabicCount(full,["يوم واحد تمّ كله","يومان تمّا كلهما","أيام تمّت كلها","يومًا تمّت كلها"],digits)
        case .weekly:
            guard let next = open.first, let p = next.summary.current else { return "عادات الأسبوع تمّت" }
            return "هذا الأسبوع "+next.name+"، "+habitProgressText(p.value,p.target,p.rule.unit,digits)
        case .monthly:
            guard let next = open.first, let p = next.summary.current else { return "عادات الشهر تمّت" }
            if let due = p.dueDays.first(where: { $0 >= today }) { return next.name+" "+habitRelativeAhead(span(today,due),digits) }
            return next.name+"، "+habitProgressText(p.value,p.target,p.rule.unit,digits)
        case .yearly:
            let row = rows.first { $0.summary.current?.met != true } ?? rows.first
            guard let row else { return "" }
            guard let last = row.lastTime else { return row.name+"، لم تسجّلها بعد" }
            if row.summary.current?.met != true, HabitRhythmMath.days(last.day,today) >= 365 { return row.name+"، مرّت سنة ولم تفعلها" }
            return row.name+"، آخر مرة "+habitSince(last.day,today,digits)
        }
    }
    private func span(_ a:GregorianDay,_ b:GregorianDay)->Int {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = .gmt
        return calendar.dateComponents([.day],from:a.date(in:.gmt),to:b.date(in:.gmt)).day ?? 0
    }
}

/// «اليوم»، «أمس»، «منذ ٥ أيام»، «منذ ٣ أسابيع»، «منذ ٨ أشهر»، «منذ سنتين».
func habitSince(_ day:GregorianDay,_ today:GregorianDay,_ digits:MadarNumberFormatter)->String {
    var calendar = Calendar(identifier:.gregorian); calendar.timeZone = .gmt
    let from = day.date(in:.gmt), to = today.date(in:.gmt)
    let days = calendar.dateComponents([.day],from:from,to:to).day ?? 0
    if days <= 0 { return "اليوم" }
    if days == 1 { return "أمس" }
    if days < 14 { return "منذ "+arabicCount(days,["يوم","يومين","أيام","يومًا"],digits) }
    let months = calendar.dateComponents([.month],from:from,to:to).month ?? 0
    if months < 1 { return "منذ "+arabicCount(days/7,["أسبوع","أسبوعين","أسابيع","أسبوعًا"],digits) }
    if months < 12 { return "منذ "+arabicCount(months,["شهر","شهرين","أشهر","شهرًا"],digits) }
    return "منذ "+arabicCount(months/12,["سنة","سنتين","سنوات","سنة"],digits)
}
/// «اليوم»، «غدًا»، «بعد يومين»، «بعد ٥ أيام».
func habitRelativeAhead(_ days:Int,_ digits:MadarNumberFormatter)->String {
    days <= 0 ? "اليوم" : days == 1 ? "غدًا" : "بعد "+arabicCount(days,["يوم","يومين","أيام","يومًا"],digits)
}
