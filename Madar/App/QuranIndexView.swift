import SwiftUI
import MadarDesign

struct QuranIndexView: View {
    let service: AppQuranService
    let initialUnit: QuranUIIndexUnit
    let initialItemID: String?
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var unit = QuranUIIndexUnit.surah
    @State private var items: [QuranUIIndexItem] = []
    @State private var selected: QuranUIIndexItem?
    @State private var reader: Int?
    @State private var query = ""
    @State private var error: String?
    @State private var attempt = 0
    @State private var isLoading = true
    #if DEBUG
    @State private var injectedReadFailure = false
    #endif
    @State private var appliedInitialSelection = false
    init(
        service: AppQuranService, initialUnit: QuranUIIndexUnit = .surah, initialItemID: String? = nil,
        close: @escaping () -> Void
    ) {
        self.service = service
        self.initialUnit = initialUnit
        self.initialItemID = initialItemID
        self.close = close
        _unit = State(initialValue: initialUnit)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QuranScreenHeader(title: "الفهرس", close: close)
                HStack(spacing: 4) {
                    ForEach(QuranUIIndexUnit.allCases) { option in
                        Button {
                            guard unit != option else { return }
                            items = []; selected = nil; error = nil; isLoading = true
                            withAnimation(MadarMotion.quick.animation(reduceMotion: reduceMotion)) {
                                unit = option; query = ""
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: option.icon).font(.system(size: 18));
                                Text(option.title).font(quranFont(11))
                            }.frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(
                                unit == option ? theme.onAccent : theme.ink
                            ).background(unit == option ? theme.accent : .clear, in: Capsule())
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-index-unit-" + option.id)
                            .accessibilityAddTraits(unit == option ? .isSelected : [])
                    }
                }.padding(4).background(theme.color("track"), in: Capsule())
                if isLoading {
                    ProgressView("تُجهّز الفهرس…").frame(maxWidth: .infinity, minHeight: 80)
                        .accessibilityIdentifier("quran-index-loading")
                } else if error == nil {
                HStack {
                    let held = items.filter(\.memorized).count, form = unit.counted(held);
                    Text("في صدرك").font(quranFont(12));
                    if form.number { Text(service.numerals.string(held)).font(quranSerif(25)) };
                    Text(form.noun).font(form.number ? quranFont(12) : quranSerif(20)); Spacer();
                    Text("المس لتفاصيله").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                }
                if unit == .ayah {
                    TextField("ابحث في الآيات", text: $query).font(quranFont(15)).padding(12).background(
                        theme.surface, in: .rect(cornerRadius: 14)
                    ).accessibilityIdentifier("quran-index-search")
                }
                if unit == .surah && !type.isAccessibilitySize {
                    QuranSurahRopes(items: items, choose: { selected = $0 })
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: type.isAccessibilitySize ? 280 : unit == .ayah ? 300 : 90))
                        ], spacing: 8
                    ) {
                        ForEach(filtered) { item in
                            Button {
                                selected = item
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(quranFont(13, bold: true));
                                    if unit == .ayah { Text(item.subtitle).font(.custom("Amiri-Regular", size: 20)) };
                                    ProgressView(value: item.fraction).tint(theme.color("memorized"));
                                    Text(status(item)).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                }.padding(10).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading).background(
                                    theme.surface, in: .rect(cornerRadius: 13)
                                ).contentShape(Rectangle())
                            }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-index-item-" + item.id)
                        }
                    }
                }
                if unit == .ayah && !query.isEmpty && !items.isEmpty && filtered.isEmpty {
                    Text("لا آية تطابق «\(query)»؛ جرّب كلمة أقصر").font(quranFont(13)).foregroundStyle(
                        theme.secondaryInk
                    ).accessibilityIdentifier("quran-index-no-results")
                }
                }
                if let error {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(quranFont(13)).accessibilityIdentifier("quran-index-read-error");
                        Button {
                            self.error = nil; attempt += 1
                        } label: { Text("أعد المحاولة").font(quranFont(13, bold: true)).frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier(
                            "quran-index-retry")
                    }
                }
                QuranPaperCard {
                    Text(
                        "المحفوظ مصمت، المراجَع بنقطة، المستحق بخط مائل، وورد اليوم بإطار. طول حبل السورة يتبع عدد آياتها."
                    ).font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                }
            }.padding(16)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review"))
            .accessibilityIdentifier("quran-index-screen")
            .task(id: "\(unit.id)-\(attempt)") {
                let requestedUnit = unit, requestedAttempt = attempt
                items = []; error = nil; isLoading = true
                defer {
                    if unit == requestedUnit, attempt == requestedAttempt, !Task.isCancelled { isLoading = false }
                }
                do {
                    #if DEBUG
                    let environment = ProcessInfo.processInfo.environment
                    if !injectedReadFailure,
                       UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
                       environment["MADAR_UI_QURAN_INDEX_FAIL_UNIT_ONCE"] == requestedUnit.id {
                        injectedReadFailure = true
                        throw CocoaError(.fileReadUnknown)
                    }
                    #endif
                    let result = try await service.index(requestedUnit)
                    try Task.checkCancellation()
                    guard unit == requestedUnit, attempt == requestedAttempt else { return }
                    items = result
                    if !appliedInitialSelection {
                        appliedInitialSelection = true
                        if unit == initialUnit, let initialItemID,
                           let target = result.first(where: { $0.id == initialItemID }) { selected = target }
                    }
                } catch is CancellationError {
                } catch {
                    guard !Task.isCancelled, unit == requestedUnit, attempt == requestedAttempt else { return }
                    self.error = quranUserMessage(error)
                }
            }
            .sheet(item: $selected) { item in
                VStack(alignment: .leading, spacing: 15) {
                    Text(item.title).font(quranSerif(28)).accessibilityIdentifier(
                        "quran-index-selected-item-" + item.id);
                    Text(item.subtitle).font(quranFont(14)); Text(status(item)).font(quranFont(14, bold: true));
                    Button {
                        selected = nil; reader = item.firstPage
                    } label: { Text("افتح في المصحف").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }; Button { selected = nil } label: { Text("تمّ").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface).foregroundStyle(
                    theme.ink
                ).presentationDetents([.height(310), .large]).environment(\.layoutDirection, .rightToLeft)
            }
            .fullScreenCover(isPresented: Binding(get: { reader != nil }, set: { if !$0 { reader = nil } })) {
                QuranMushafView(service: service, initialPage: reader ?? 1, close: { reader = nil })
            }
    }
    private var filtered: [QuranUIIndexItem] {
        if query.isEmpty { return items }
        let needle = QuranIndexSearch.normalize(query)
        return items.filter { $0.title.contains(query) || $0.searchText.contains(needle) }
    }
    private func status(_ i: QuranUIIndexItem) -> String {
        (i.memorized ? "محفوظ" : i.fraction > 0 ? "حفظ جزئي" : "لم تحفظه") + (i.reviewed ? "، راجعته" : "")
            + (i.due ? "، مستحق" : "") + (i.isToday ? "، ورد اليوم" : "")
    }
}
struct QuranSurahRopes: View {
    let items: [QuranUIIndexItem]
    let choose: (QuranUIIndexItem) -> Void
    @Environment(\.roomTheme) private var theme
    private struct Rope { let item: QuranUIIndexItem; let rect: CGRect }
    private func layout(_ width: CGFloat) -> [Rope] {
        var result: [Rope] = [], x = width, y: CGFloat = 0
        for item in items {
            let w = max(width * 0.05, min(width, CGFloat(item.weight) / 286 * width))
            if x - w < 0 { x = width; y += 25 }
            result.append(Rope(item: item, rect: CGRect(x: x - w, y: y, width: w, height: 20))); x -= w + width * 0.0114
        }
        return result
    }
    var body: some View {
        GeometryReader { proxy in
            let ropes = layout(proxy.size.width)
            Canvas { context, _ in
                for rope in ropes {
                    let i = rope.item, r = rope.rect, path = Path(roundedRect: r, cornerRadius: 6)
                    context.fill(path, with: .color(theme.color("track")))
                    let saved = CGRect(
                        x: r.maxX - r.width * i.fraction, y: r.minY, width: r.width * i.fraction, height: r.height)
                    context.fill(Path(roundedRect: saved, cornerRadius: 6), with: .color(theme.color("memorized")))
                    if i.fraction > 0 { context.stroke(path, with: .color(theme.color("hifzText")), lineWidth: 1) }
                    if i.reviewed {
                        context.fill(
                            Path(ellipseIn: CGRect(x: r.midX - 1.5, y: r.maxY - 4, width: 3, height: 3)),
                            with: .color(theme.surface))
                    }
                    if i.due {
                        var stripe = Path(); stripe.move(to: CGPoint(x: r.minX + 2, y: r.maxY - 1));
                        stripe.addLine(to: CGPoint(x: r.maxX - 2, y: r.minY + 1));
                        context.stroke(stripe, with: .color(theme.color("due")), lineWidth: 1)
                    }
                    if i.isToday { context.stroke(path, with: .color(theme.color("hifz")), lineWidth: 1.5) }
                    if r.width >= 47 {
                        if !i.memorized {
                            context.fill(
                                Path(roundedRect: r.insetBy(dx: 3, dy: 2), cornerRadius: 3), with: .color(theme.surface)
                            )
                        }
                        context.draw(
                            Text(i.title).font(.custom("Amiri-Bold", size: 12)).foregroundStyle(
                                i.memorized ? theme.onAccent : theme.ink), at: CGPoint(x: r.midX, y: r.midY))
                    }
                }
            }.onTapGesture { point in
                if let rope = ropes.first(where: { $0.rect.insetBy(dx: -2, dy: -2).contains(point) }) {
                    choose(rope.item)
                }
            }
            .accessibilityElement().accessibilityLabel("حبال السور، طول الحبل بعدد آياته")
        }.frame(height: layout(350).last.map { $0.rect.maxY } ?? 0)
    }
}
