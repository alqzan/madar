import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarPrayer
import MadarSnapshots
import WidgetKit

extension AppSession {
    /// Omits personal rows at construction time when whole-app protection is configured; a view mask is insufficient.
    func roomWidgetPayloads(locked:Bool,at instant:Date?=nil,readHabitReadings:(() throws -> [HabitReading])?=nil)->[BuiltRoomWidget:RoomWidgetSnapshot] {
        let now=instant ?? prayerNow(),service=AppBahwService(session:self,evaluationDate:now),today=service.today,date=dateLabels(today),digits=service.digits
        var payloads:[BuiltRoomWidget:RoomWidgetSnapshot]=[:]
        var habitReadFailed=false
        let readings:[HabitReading]
        if locked { readings=[] }
        else {
            do {
                if let readHabitReadings { readings=try readHabitReadings() }
                else { readings=try HabitRepository(context:ModelContext(container)).readings(at:now) }
            } catch { readings=[]; habitReadFailed=true }
        }
        let eligible=readings.filter{$0.summary.current?.dueDays.contains(today)==true || $0.paused}
        let ordered=habitRowsForWidgetScope(eligible, at: now).enumerated().sorted { left,right in
            let a=left.element,b=right.element
            func rank(_ r:HabitReading)->Int{(r.summary.current?.met == true ? 100 : 0)+(r.paused ? 50 : 0)+(r.isNow ? 0 : 10)+(r.summary.atRisk ? 0 : 1)}
            return rank(a)==rank(b) ? left.offset<right.offset : rank(a)<rank(b)
        }.map(\.element)
        let rows=ordered.prefix(6).compactMap { r->RoomWidgetSnapshot.Row? in
            guard let p=r.summary.current else{return nil}
            let value=r.paused ? "مجمّدة" : p.target==0 ? "إجازتها اليوم" : r.source=="walking" ? "تُحدّث من الصحة" : WidgetCopy.habitProgress(value:p.value,target:p.target,measure:p.rule.measure,unit:p.rule.unit,digits:digits)
            return .init(id:r.id.uuidString,title:r.name,value:value,detail:r.summary.atRisk ? "القليل يحفظ سلسلتك" : r.isNow ? "وقتها الآن" : r.sourceTitle.map{"تُقرأ من "+$0} ?? "",share:Double(p.value)/Double(max(1,p.target)),route:"madar://bahw/habits/"+r.id.uuidString,done:p.met)
        }
        let periods=[HabitFrequency.daily,.weekly,.monthly,.yearly].map { f->RoomWidgetSnapshot.Row in
            let group=readings.filter{$0.summary.current?.rule.frequency==f && !$0.paused && ($0.summary.current?.target ?? 0)>0},met=group.filter{$0.summary.current?.met==true}.count
            // `detail` carries the compact remainder for the lock-screen circle; empty means nothing is due in this period.
            return .init(id:f.rawValue,title:f.arabic,value:WidgetCopy.periodProgress(met:met,total:group.count,digits:digits),detail:group.isEmpty ? "" : met==group.count ? "تمّ" : digits.string(group.count-met),share:Double(met)/Double(max(1,group.count)),route:BuiltRoomWidget.habits.route,completedCount:met,targetCount:group.count)
        }
        let dueToday=eligible.filter{!$0.paused && ($0.summary.current?.target ?? 0)>0}
        payloads[.habits] = .init(datePrimary:date.primary,dateSecondary:date.secondary,heading:habitReadFailed ? "تعذّر تحديث العادات" : WidgetCopy.habitsHeading(met:dueToday.filter{$0.summary.current?.met==true}.count,total:dueToday.count,digits:digits),emptyTitle:habitReadFailed ? "افتح مدار لإعادة المحاولة" : readings.isEmpty ? "أضف أول عادة" : "لا عادات مستحقة اليوم",rows:habitReadFailed ? [] : rows,periods:habitReadFailed ? [] : periods,locked:locked)
        let year=service.year()
        var yearRows:[RoomWidgetSnapshot.Row]=[
            .init(id:"hijri",title:digits.string(year.hijriYear)+" هـ",value:digits.string(year.hijri.basisPoints/100)+"٪\u{061C}",detail:"بقي "+service.daysPhrase(year.hijri.remaining),share:Double(year.hijri.basisPoints)/10000,route:BuiltRoomWidget.year.route),
            .init(id:"gregorian",title:digits.string(year.gregorianYear)+" م",value:digits.string(year.gregorian.basisPoints/100)+"٪\u{061C}",detail:"بقي "+service.daysPhrase(year.gregorian.remaining),share:Double(year.gregorian.basisPoints)/10000,route:BuiltRoomWidget.year.route)]
        if string("core.firstCalendar")=="gregorian"{yearRows.reverse()}
        payloads[.year] = .init(datePrimary:date.primary,dateSecondary:date.secondary,heading:"عامك، يومًا بيوم",emptyTitle:"افتح السنة",rows:yearRows)
        let upcoming=locked ? [] : service.upcoming(limit:7).map { item->RoomWidgetSnapshot.Row in
            let labels=dateLabels(item.day)
            return .init(id:item.id,title:item.title,value:item.elapsedDays.map(service.sincePhrase) ?? WidgetCopy.daysLeft(item.daysLeft,digits:digits,dayCount:service.dayCount),detail:labels.primary,secondDate:labels.secondary,share:item.closed,route:BuiltRoomWidget.upcoming.route)
        }
        payloads[.upcoming] = .init(datePrimary:date.primary,dateSecondary:date.secondary,heading:"كم بقي",emptyTitle:"أضف يومًا تنتظره",rows:upcoming,locked:locked)
        let diaryRows=locked || !bool("notes.widgetContent") ? [] : diaryWidgetRows(today:today)
        payloads[.diaryWrite] = .init(datePrimary:date.primary,dateSecondary:date.secondary,heading:"اكتب سطر اليوم",emptyTitle:"فكرة صغيرة تستحق أن تبقى",rows:diaryRows)
        payloads[.money] = moneyWidgetPayload(hidden: locked || bool("core.hideMoneyOutside"), locked: locked, at: now)
        return payloads
    }
    /// Build the data-dictionary MihbaraSnapshot in the app process. A private note or a
    /// diary-linked note never enters an App Group file, even when the rest of Mihbara is visible.
    func mihbaraWidgetSnapshot(locked:Bool,at instant:Date?=nil)->MihbaraSnapshot {
        guard !locked else { return .init() }
        let now=instant ?? prayerNow(),context=ModelContext(container)
        do {
            let reading=try AppMihbaraService(app:self).load(at:now)
            let current=reading.books.first{$0.shelf=="reading"}
            let book=current.map { MihbaraSnapshot.BookSummary(id:$0.id,title:$0.title,author:$0.author,currentPage:(($0.isReadableEPUB || $0.isReadablePDF) ? MihbaraCopy.pagesRead($0) : $0.page).flatMap{$0>0 ? $0 : nil},pages:$0.pages) }
            let hadith=reading.todayHadiths.first.map { MihbaraSnapshot.HadithSummary(collectionID:reading.collection.collectionID,number:$0.number,title:$0.title) }
            let notes=try context.fetch(FetchDescriptor<NotebookNote>())
            // Owner, 30 Oct: notebook text reaches the widget only with the same opt-in as the diary's (`notes.widgetContent`, off by default).
            let notebookShown=bool("notes.widgetContent")
            let lastLine:String?=notes.filter{ notebookShown && $0.deletedAt==nil && $0.mergedInto==nil && !$0.isPrivate && $0.link != "fromDiary"}
                .sorted{$0.updatedAt>$1.updatedAt}
                .compactMap{$0.text.trimmingCharacters(in:.whitespacesAndNewlines)}
                .first{$0.isEmpty == false}
            return .init(currentBook:book,hadithToday:hadith,shelfCount:reading.books.count,lastNotebookLine:lastLine)
        } catch { return .init() }
    }
    func publishRoomWidgetSnapshots(at now:Date) throws {
        let service=AppBahwService(session:self,evaluationDate:now),prayers=try PrayerRepository(context:ModelContext(container))
        let next=service.today.adding(days:1),place=prayers.place(at:now),options=prayers.calculationOptions(at:now)
        let end:Date?
        switch DayBoundary(rawValue:string("core.dayStart")) ?? .fajr {
        case .midnight:end=next.date(in:place.timeZone)
        case .fajr:end=PrayerTimesEngine.calculate(day:next,place:place,options:options)?.fajr
        case .maghrib:end=PrayerTimesEngine.calculate(day:next,place:place,options:options)?.maghrib
        }
        let expiry=min(now.addingTimeInterval(3600),end ?? now.addingTimeInterval(900))
        let locked=string("core.faceIDLock")=="app"
        for (room,payload) in roomWidgetPayloads(locked:locked,at:now) {
            let envelope=SnapshotEnvelope(name:room.rawValue,generatedAt:now,validUntil:expiry,dayKey:service.today.description,tzID:place.timeZoneID,privacy:SnapshotPrivacy(moneyHidden:room == .money ? locked || bool("core.hideMoneyOutside") : true,notesLocked:locked),payload:payload)
            try snapshotStore.write(envelope)
            WidgetCenter.shared.reloadTimelines(ofKind:"MadarRoom-"+room.rawValue)
        }
        let mihbara=SnapshotEnvelope(name:BuiltRoomWidget.mihbara.rawValue,generatedAt:now,validUntil:expiry,dayKey:service.today.description,tzID:place.timeZoneID,privacy:SnapshotPrivacy(notesLocked:locked),payload:mihbaraWidgetSnapshot(locked:locked,at:now))
        try snapshotStore.write(mihbara)
        WidgetCenter.shared.reloadTimelines(ofKind:"MadarRoom-"+BuiltRoomWidget.mihbara.rawValue)
        // Names outlive the day so Siri can still find a habit; its period is only trusted until the day ends.
        let periodsEnd=end ?? now.addingTimeInterval(900)
        try snapshotStore.write(SnapshotEnvelope(name:HabitShortcutSnapshot.name,generatedAt:now,validUntil:now.addingTimeInterval(30*86400),dayKey:service.today.description,tzID:place.timeZoneID,privacy:SnapshotPrivacy(notesLocked:locked),payload:habitShortcutPayload(locked:locked,at:now,periodsValidUntil:periodsEnd)))
    }
    /// Same step as the lobby and habit card buttons, so «أتممت» from Siri means what a tap means.
    func habitShortcutPayload(locked:Bool,at now:Date,periodsValidUntil:Date)->HabitShortcutSnapshot {
        guard !locked else {return .init(items:[],periodsValidUntil:now)}
        let digits=AppBahwService(session:self,evaluationDate:now).digits
        let readings=(try? HabitRepository(context:ModelContext(container)).readings(at:now)) ?? []
        return .init(items:readings.compactMap { r in
            guard r.source == nil, !r.archived, !r.paused, let p=r.summary.current, p.target>0, p.rule.measure != .health else {return nil}
            let step=p.rule.measure == .duration ? 15 : 1
            let title=p.rule.measure == .once ? "أتممتها" : p.rule.measure == .duration ? "+"+digits.string(15)+" دقيقة" : "+"+digits.string(1)+" "+(p.rule.unit.map(habitUnitName) ?? "مرة")
            return .init(id:r.id,title:r.name,stepTitle:title,step:step,periodKey:p.key,done:p.met)
        },periodsValidUntil:periodsValidUntil)
    }
}


extension AppSession {
    /// Owner 27 Oct: scope changes visible rows only; the device's full-day count keeps one definition.
    func habitRowsForWidgetScope(_ rows: [HabitReading], at instant: Date? = nil) -> [HabitReading] {
        guard string("bahw.widgetScope") == "todayOnly" else { return rows }
        let today = AppBahwService(session: self, evaluationDate: instant).today
        return rows.filter { row in
            guard row.summary.current?.dueDays.contains(today) == true else { return false }
            guard let rule = row.summary.current?.rule, rule.windowStart != nil && rule.windowEnd != nil else { return true }
            return row.isNow
        }
    }
}
