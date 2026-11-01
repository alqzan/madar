import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

/// The small lattice arch beside prayer sheet titles.
struct PrayerSheetArch: View {
    @Environment(\.roomTheme) private var theme
    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let shape = PrayerHorseshoe().path(in: rect)
            ZStack {
                shape.fill(theme.color("goldSoft"))
                PrayerLatticePattern(spacing: 7).stroke(theme.accent.opacity(0.5), lineWidth: 1).mask { shape.fill() }
                shape.stroke(theme.color("goldMid").opacity(0.7), lineWidth: 1)
            }
        }
    }
}

/// «قضيتُها»: confirms one make-up. Friday noon asks for its kind explicitly (RP5).
struct PrayerMakeUpSheet: View {
    let item: PrayerQada
    let isFridayNoon: Bool
    let dateLabel: String
    let isSaving: Bool
    let continuesPendingAction: Bool
    let rootDraftChanged: (UUID, Bool) -> Void
    let makeUp: (FridayPrayerKind?, @escaping (Bool) -> Void) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var fridayKind: FridayPrayerKind?
    @State private var rootBlockerID = UUID()
    @State private var contentHeight: CGFloat = 420
    private var hasUnsavedInput: Bool { continuesPendingAction || fridayKind != item.fridayKind }

    init(item: PrayerQada, isFridayNoon: Bool, dateLabel: String, isSaving: Bool, rootBlockerID: UUID?,
         rootDraftChanged: @escaping (UUID, Bool) -> Void,
         makeUp: @escaping (FridayPrayerKind?, @escaping (Bool) -> Void) -> Void) {
        self.item = item; self.isFridayNoon = isFridayNoon; self.dateLabel = dateLabel; self.isSaving = isSaving
        self.continuesPendingAction = rootBlockerID != nil
        self.rootDraftChanged = rootDraftChanged; self.makeUp = makeUp
        _rootBlockerID = State(initialValue: rootBlockerID ?? UUID())
        _fridayKind = State(initialValue: item.fridayKind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                PrayerSheetArch().frame(width: 34, height: 52).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("قضاء \(prayerTitle(item.reference.prayer))").font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title))
                        .accessibilityAddTraits(.isHeader)
                    MadarDateLabel(dateLabel).foregroundStyle(theme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(theme.color("missed")).frame(width: 2)
                PrayerQadaCitation()
            }
            .fixedSize(horizontal: false, vertical: true)
            if isFridayNoon {
                HStack(spacing: 10) {
                    Text("ظهر الجمعة:").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                    ForEach([FridayPrayerKind.jumuah, .dhuhr], id: \.self) { kind in
                        let on = fridayKind == kind
                        Button { if item.fridayKind == nil { fridayKind = kind } } label: {
                            Text(kind == .jumuah ? "صلاة الجمعة" : "الظهر").font(on ? PrayerHomeType.smallBold : PrayerHomeType.small)
                                .foregroundStyle(on ? theme.color("accentText") : theme.ink)
                                .padding(.horizontal, 16).frame(minHeight: 40)
                                .background(on ? theme.color("goldSoft") : .clear, in: .capsule)
                                .overlay { Capsule().stroke(on ? theme.accent : theme.ink.opacity(0.14), lineWidth: on ? 1.5 : 1) }
                                .frame(minHeight: 44).contentShape(.rect)
                        }
                        .buttonStyle(.madarPlain).accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("prayer-makeup-friday-kind-\(kind.rawValue)")
                    }
                    Spacer(minLength: 0)
                }
            }
            Button { makeUp(isFridayNoon ? fridayKind : nil) { ok in if ok { dismiss() } } } label: { // AU-41: close only once the make-up is saved.
                Text("قضيتُها الآن").font(PrayerHomeType.strong).foregroundStyle(theme.background)
                    .frame(maxWidth: .infinity, minHeight: 56).background(theme.ink, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.madarPlain).disabled(isSaving || (isFridayNoon && fridayKind == nil))
            .opacity(isSaving || (isFridayNoon && fridayKind == nil) ? 0.4 : 1)
            .accessibilityIdentifier("prayer-makeup-confirm")
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 + 20 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.height(min(max(contentHeight, 300), 700)), .large])
        .presentationBackground(theme.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .onChange(of: hasUnsavedInput, initial: true) { _, dirty in rootDraftChanged(rootBlockerID, dirty) }
        .onDisappear { rootDraftChanged(rootBlockerID, false) }
    }
}
