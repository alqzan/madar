import Foundation
import Foundation
import Testing
@testable import MadarSnapshots

struct WidgetCatalogTests {
    @Test func timedFocusChangesAndSavedPriorityReturnsAfterTheWindow() {
        let morning = Date(timeIntervalSince1970: 1000), noon = Date(timeIntervalSince1970: 2000)
        var quran = WidgetCatalogSnapshot.Row(id: "quran", title: "القرآن", value: "وجه", glyph: "book", route: "madar://quran")
        quran.preferredFrom = morning; quran.preferredUntil = noon
        let money = WidgetCatalogSnapshot.Row(id: "money", title: "المال", value: "•••", glyph: "banknote", route: "madar://mal")
        let prayer = WidgetCatalogSnapshot.Row(id: "prayer", title: "الظهر", value: "", glyph: "moon", route: "madar://salah", targetDate: noon)
        let config = WidgetCatalogSnapshot.Config(id: UUID(), name: "صباحي", familyID: "medium", styleJSON: Data(), rows: [money, prayer, quran])
        #expect(config.visibleRows(at: morning, capacity: 3, smart: true).map(\.id) == ["quran", "prayer", "money"])
        #expect(config.visibleRows(at: noon, capacity: 3, smart: true).map(\.id) == ["money", "prayer", "quran"])
        #expect(config.visibleRows(at: morning, capacity: 2, smart: false).map(\.id) == ["money", "prayer"])
        #expect(config.visibleRows(at: morning, capacity: 0, smart: true).isEmpty)
    }
}

struct RoomWidgetSnapshotTests {
    private func row(_ id: String) -> RoomWidgetSnapshot.Row {
        .init(id: id, title: id, value: "١", route: "madar://bahw")
    }

    @Test func visibleRowsFollowTheSelectedWidgetTemplate() {
        let habits = RoomWidgetSnapshot(datePrimary: "اليوم", dateSecondary: "", heading: "", emptyTitle: "", periods: [row("weekly")])
        #expect(habits.hasVisibleRows(for: .habits, template: "periods"))
        #expect(!habits.hasVisibleRows(for: .habits, template: "summary"))

        let year = RoomWidgetSnapshot(datePrimary: "السنة", dateSecondary: "", heading: "", emptyTitle: "", rows: [row("hijri")])
        #expect(year.hasVisibleRows(for: .year, template: "hijri"))
        #expect(!year.hasVisibleRows(for: .year, template: "gregorian"))
    }

    @Test func upcomingHabitTemplateReadsLegacySnapshotsWithoutTheOptionalProjection() throws {
        let row=RoomWidgetSnapshot.Row(id:"weekly",title:"ورد الأربعاء",value:"غدًا",detail:"آخر مرة أمس",route:"madar://bahw/habits/weekly")
        let current=RoomWidgetSnapshot(datePrimary:"اليوم",dateSecondary:"",heading:"",emptyTitle:"",upcomingHabits:[row])
        #expect(current.hasVisibleRows(for:.habits,template:"coming"))

        var legacyObject=try #require(JSONSerialization.jsonObject(with:JSONEncoder().encode(current)) as? [String:Any])
        legacyObject.removeValue(forKey:"upcomingHabits")
        let legacyData=try JSONSerialization.data(withJSONObject:legacyObject)
        let legacy=try JSONDecoder().decode(RoomWidgetSnapshot.self,from:legacyData)
        #expect(legacy.upcomingHabits == nil)
        #expect(!legacy.hasVisibleRows(for:.habits,template:"coming"))
    }
}
