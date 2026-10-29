import Foundation

public struct DiarySearchDocument: Sendable, Identifiable {
    public let id: String
    public let day: GregorianDay
    public let text: String
    public let kind: String
    public let kinds: Set<String>
    public let place: String?
    public let projectID: UUID?
    public let tags: [String]
    public init(id: String, day: GregorianDay, text: String, kind: String = "writing", kinds: Set<String>? = nil, place: String? = nil, projectID: UUID? = nil, tags: [String] = []) { self.id=id; self.day=day; self.text=text; self.kind=kind; self.kinds=kinds ?? [kind]; self.place=place; self.projectID=projectID; self.tags=tags }
}
public enum DiarySearchRule: Sendable, Equatable {
    case range(GregorianDay, GregorianDay), month(Int, Int?, FirstCalendar), year(Int, FirstCalendar), weekday(Int), kind(String), place(String), project(UUID), tag(String), words(String)
}
public struct DiarySearchChip: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let label: String
    public let rule: DiarySearchRule
    public init(label: String, rule: DiarySearchRule) { id=UUID(); self.label=label; self.rule=rule }
}
public struct DiarySearchParser: Sendable {
    public let today: GregorianDay
    public let zone: TimeZone
    public let weekStart: Int
    public let sightingOffset: Int
    public let places: [String]
    public let projects: [String: UUID]
    public let tags: [String]
    public init(today: GregorianDay, zone: TimeZone, weekStart: Int = 7, sightingOffset: Int = 0, places: [String] = [], projects: [String: UUID] = [:], tags: [String] = []) { self.today=today; self.zone=zone; self.weekStart=weekStart; self.sightingOffset=sightingOffset; self.places=places; self.projects=projects; self.tags=tags }
    public static func normalize(_ value: String) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩"), persian = Array("۰۱۲۳۴۵۶۷۸۹"), western = Array("0123456789")
        var result = value.lowercased()
        for (a,b) in zip(digits,western) { result=result.replacingOccurrences(of: String(a), with: String(b)) }
        for (a,b) in zip(persian,western) { result=result.replacingOccurrences(of: String(a), with: String(b)) }
        return result.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) && $0.value != 0x0640 }.map(String.init).joined()
            .replacingOccurrences(of: "[أإآٱ]", with: "ا", options: .regularExpression).replacingOccurrences(of: "ى", with: "ي")
            .replacingOccurrences(of: "[ؤئ]", with: "ء", options: .regularExpression).replacingOccurrences(of: "ة", with: "ه")  // «مسئولية» finds «مسؤولية»
    }
    private func calendar(_ first: FirstCalendar) -> Calendar { var c=Calendar(identifier: first == .hijri ? .islamicUmmAlQura : .gregorian); c.timeZone=zone; return c }
    private func date(_ y: Int,_ m: Int,_ d: Int,_ first: FirstCalendar) -> GregorianDay? {
        let c=calendar(first); guard let date=c.date(from: DateComponents(year:y,month:m,day:d,hour:12)), c.component(.day,from:date)==d, c.component(.month,from:date)==m else { return nil }
        return GregorianDay.containing(date,in:zone).adding(days:first == .hijri ? -sightingOffset : 0)
    }
    private func parts(_ day: GregorianDay,_ first: FirstCalendar) -> DateComponents { calendar(first).dateComponents([.year,.month,.day], from:day.adding(days:first == .hijri ? sightingOffset : 0).date(in:zone).addingTimeInterval(12*3600)) }
    private var months: [(String,Int,FirstCalendar)] {
        let g=["يناير","فبراير","مارس","ابريل","مايو","يونيو","يوليو","اغسطس","سبتمبر","اكتوبر","نوفمبر","ديسمبر"]
        let h=["محرم","صفر","ربيع الاول","ربيع الثاني","جمادي الاولي","جمادي الاخره","رجب","شعبان","رمضان","شوال","ذو القعده","ذو الحجه"]
        return g.enumerated().map{($0.element,$0.offset+1,.gregorian)} + h.enumerated().map{($0.element,$0.offset+1,.hijri)}
    }
    private func endpoint(_ raw: String) -> GregorianDay? {
        let s=raw.trimmingCharacters(in:.whitespaces)
        if let d=try? GregorianDay(s) { return d }
        for (name,m,first) in months where s.contains(name) {
            let values=s.replacingOccurrences(of:name,with:"").split(separator:" ").compactMap{Int($0)}
            guard let d=values.first, (1...31).contains(d) else { continue }
            return date(values.count>1 ? values[1] : parts(today,first).year!,m,d,first)
        }
        return nil
    }
    public func parse(_ input: String) -> [DiarySearchChip] {
        var source=Self.normalize(input).replacingOccurrences(of:"[؟?«»\"،]",with:" ",options:.regularExpression)
        var chips:[DiarySearchChip]=[]
        func take(_ pattern:String,_ transform:([String])->DiarySearchRule?) {
            guard let regex=try? NSRegularExpression(pattern:"(?<![\\p{L}\\p{N}])(?:"+pattern+")(?![\\p{L}\\p{N}])") else { return }
            let matches=regex.matches(in:source,range:NSRange(source.startIndex...,in:source))
            for match in matches.reversed() {
                let values=(0..<match.numberOfRanges).map { i -> String in guard let range=Range(match.range(at:i),in:source) else{return ""}; return String(source[range]) }
                guard let rule=transform(values), let range=Range(match.range,in:source) else { continue }
                chips.append(.init(label:values[0].trimmingCharacters(in:.whitespaces),rule:rule)); source.replaceSubrange(range,with:" ")
            }
        }
        take("من (.+?) الي (.+)$") { v in guard let a=endpoint(v[1]),let b=endpoint(v[2]),a<=b else{return nil};return .range(a,b) }
        take("اول امس|امس|اليوم") { v in let d=today.adding(days:v[0]=="اليوم" ? 0 : v[0]=="امس" ? -1 : -2);return .range(d,d) }
        take("(?:العام|السنه) الماضي(?:ه)?") { _ in .year(today.year-1,.gregorian) }
        take("الشهر الماضي") { _ in let start=date(today.year,today.month,1,.gregorian)!;let end=start.adding(days:-1);return .range(date(end.year,end.month,1,.gregorian)!,end) }
        take("الاسبوع الماضي") { _ in let weekday=calendar(.gregorian).component(.weekday,from:today.date(in:zone));let current=today.adding(days:-(weekday-weekStart+7)%7);return .range(current.adding(days:-7),current.adding(days:-1)) }
        take("قبل (?:([0-9]+) )?(اشهر|شهور|شهر|سنوات|سنه|عام)") { v in
            let n=Int(v[1]) ?? 1;guard n>0,n<=1000 else{return nil};let component:Calendar.Component=["اشهر","شهور","شهر"].contains(v[2]) ? .month : .year
            guard let d=calendar(.gregorian).date(byAdding:component,value:-n,to:today.date(in:zone)) else{return nil};let day=GregorianDay.containing(d,in:zone);return .range(day.adding(days:-3),day.adding(days:3))
        }
        for (name,m,first) in months {
            take("(?:في )?"+name+"(?: ([0-9]{4}))?(?: (الماضي|الماضيه|السابق))?") { v in
                if !v[2].isEmpty { let p=parts(today,first),y=(p.year ?? today.year)-((p.month ?? today.month)<=m ? 1:0);return .month(m,y,first) }
                return .month(m,Int(v[1]),first)
            }
        }
        for tag in tags.sorted(by: { $0.count > $1.count }) {
            take("#" + NSRegularExpression.escapedPattern(for: Self.normalize(tag))) { _ in .tag(tag) }
        }
        for (name,id) in projects.sorted(by:{$0.key.count>$1.key.count}) { take("(?:مشروع |⌗)"+NSRegularExpression.escapedPattern(for:Self.normalize(name))+"(?= |$)") { _ in .project(id) } }
        for place in places.sorted(by:{$0.count>$1.count}) { take("في "+NSRegularExpression.escapedPattern(for:Self.normalize(place))+"(?= |$)") { _ in .place(place) } }
        let weekdays=[("الاحد",1),("الاثنين",2),("الثلاثاء",3),("الاربعاء",4),("الخميس",5),("الجمعه",6),("السبت",7),("الجمعات",6)]
        for (name,n) in weekdays { take("(?:يوم |في )?"+name) { _ in .weekday(n) } }
        for (name,kind) in [("صور","photo"),("تسجيلات","audio"),("نيات","intention"),("لغد","tomorrow"),("رسائل","letter"),("هوامش","margin")] { take(name) { _ in .kind(kind) } }
        take("(?<![0-9])[0-9]{4}(?![0-9])") { v in guard let y=Int(v[0]),y>=1300,y<=2200 else{return nil};return .year(y,y>=1900 ? .gregorian:.hijri) }
        for filler in ["ماذا كتبت عن","ماذا كتبت","متي","هل","عن"] { source=source.replacingOccurrences(of:"(?<![\\p{L}])"+filler+"(?![\\p{L}])",with:" ",options:.regularExpression) }
        let rest=source.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        if !rest.isEmpty { chips.append(.init(label:rest,rule:.words(rest))) }
        return chips
    }
    public func matches(_ document:DiarySearchDocument, chips:[DiarySearchChip]) -> Bool {
        chips.allSatisfy { chip in switch chip.rule {
        case .range(let a,let b): document.day>=a && document.day<=b
        case .month(let m,let y,let first): parts(document.day,first).month==m && (y==nil || parts(document.day,first).year==y)
        case .year(let y,let first): parts(document.day,first).year==y
        case .weekday(let n): calendar(.gregorian).component(.weekday,from:document.day.date(in:zone))==n
        case .kind(let kind): document.kinds.contains(kind)
        case .place(let place): Self.normalize(document.place ?? "")==Self.normalize(place)
        case .project(let id): document.projectID==id
        case .tag(let tag): document.tags.contains { Self.normalize($0)==Self.normalize(tag) }
        case .words(let words): Self.contains(document.text,words:words)
        } }
    }
    public static func contains(_ text:String,words:String) -> Bool {
        func variants(_ token:String)->Set<String> {
            var result:Set<String>=[token]
            for _ in 0..<3 { for word in result { for prefix in ["وال","فال","بال","لل","ال","و","ف","ب","ل"] where word.hasPrefix(prefix) && word.count>prefix.count+1 { result.insert(String(word.dropFirst(prefix.count))) } } }
            return result
        }
        let tokens=normalize(text).components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty}.map(variants)
        return normalize(words).components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty}.allSatisfy { needle in let v=variants(needle);return tokens.contains{!$0.isDisjoint(with:v)} }
    }
}
