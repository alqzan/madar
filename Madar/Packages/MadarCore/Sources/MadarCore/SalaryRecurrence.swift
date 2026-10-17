import Foundation

/// Salary forecasts keep the owner's free anchor and interval. The calendar matters for months and years only.
public struct SalaryRecurrence: Sendable {
    public let every: Int
    public let unit: RecurrenceUnit
    public let first: GregorianDay
    public let hijri: Bool
    public init?(every: Int, unit: RecurrenceUnit, first: GregorianDay, hijri: Bool = false) {
        guard (1...unit.maxEvery).contains(every) else { return nil }; self.every = every; self.unit = unit; self.first = first; self.hijri = hijri
    }
    public func occurrence(_ index: Int) -> GregorianDay? {
        guard index >= 0, index <= 1_000_000 else { return nil }
        if !hijri || unit == .day || unit == .week { return Recurrence(every: every, unit: unit, first: first)?.occurrence(index) }
        var c = Calendar(identifier: .islamicUmmAlQura); c.timeZone = .gmt
        guard let date = c.date(byAdding: unit == .year ? .year : .month, value: every * index, to: first.date(in: .gmt)) else { return nil }
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = .gmt
        let p = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let y = p.year, let m = p.month, let d = p.day else { return nil }
        return try? .init(year: y, month: m, day: d)
    }
    private func index(onOrAfter day: GregorianDay) -> Int {
        var low = 0, high = 1
        while let key = occurrence(high), key < day, high < 524288 { high *= 2 }
        while low < high { let mid = low + (high - low) / 2; if let key = occurrence(mid), key < day { low = mid + 1 } else { high = mid } }
        return low
    }
    public func preview(from day: GregorianDay, count: Int = 3) -> [GregorianDay] { let start = index(onOrAfter: day); return (0..<max(0, min(12, count))).compactMap { occurrence(start + $0) } }
    /// RM9: use the scheduled occurrence nearest one interval after the actual salary, so an early salary does not
    /// produce a two-day cycle. The anchor remains the owner's first due day, never the early payment's day.
    public func expectedEnd(after actual: GregorianDay) -> GregorianDay? {
        let target: GregorianDay?
        if unit == .day || unit == .week { target = actual.adding(days: every * (unit == .week ? 7 : 1)) }
        else { target = SalaryRecurrence(every: every, unit: unit, first: actual, hijri: hijri)?.occurrence(1) }
        guard let target else { return nil }
        let i = index(onOrAfter: target), candidates = [occurrence(i), i > 0 ? occurrence(i - 1) : nil].compactMap { $0 }.filter { $0 > actual }
        return candidates.min { abs(MadarCalendarDays.distance(from: target, to: $0)) < abs(MadarCalendarDays.distance(from: target, to: $1)) }
    }
}
