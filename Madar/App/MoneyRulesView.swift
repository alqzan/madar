import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// «قواعد التاجر» (`mal/09-Z-R19-mer`): lanterns per category, the merchants each one knows, and conflicts to settle.
struct MoneyRulesView: View {
    let app: AppSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var reading: MoneyRulesReading?
    @State private var selected: UUID?
    @State private var expanded: UUID?
    @State private var failure: String?
    @State private var runFailure: String?
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    private var service: AppMoneyService { .init(app: app) }
    private static let ignoreLantern = UUID(uuidString: "00000000-0000-0000-0000-00000000F00D")!
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("قواعد التاجر").font(MadarTypography.cardTitle()).accessibilityIdentifier("money-rules-title")
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title3).frame(width: 52, height: 52).overlay { Circle().stroke(theme.color("reserveText"), lineWidth: 1.2) }
                    }.buttonStyle(.madarPlain).accessibilityLabel("إغلاق").accessibilityIdentifier("money-rules-close")
                    Spacer()
                }.padding(.top, 8)
                if let reading {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(service.digits.string(reading.rules.count)).font(.custom("thmanyahserifdisplay-Black", size: 52, relativeTo: .largeTitle))
                        Text(reading.rules.count == 1 ? "تاجر يعرفه مدار" : "تجار يعرفهم مدار").font(MadarTypography.cardTitle())
                        Spacer()
                        if reading.applied > 0 {
                            (Text("طُبّقت ") + Text(service.counted(reading.applied, ("مرة واحدة", "مرتان", "مرات", "مرةً"))).bold().foregroundStyle(theme.color("surplusText")) + Text(" بدلًا منك"))
                                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("money-rules-count")
                    if !reading.conflicts.isEmpty { conflicts(reading) }
                    if reading.rules.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("لم يتعلّم مدار تاجرًا بعد").font(MadarTypography.cardTitle())
                            Text("حين تصنّف حركة في رسائل البنك وتختار «تذكّر لهذا التاجر»، يصل التاجر بعدها مصنّفًا.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                        }.padding(.vertical, 20).accessibilityIdentifier("money-rules-empty")
                    } else {
                        lanterns(reading)
                        merchants(reading)
                    }
                    if let runFailure { Text(runFailure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("money-rule-failure") }
                    Label("يتعلّم مدار التاجر من اختيارك، ولا يغيّر نقل القاعدة أو نسيانها حركاتك السابقة.", systemImage: "lightbulb")
                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.top, 6)
                } else if let failure { Text(failure).font(MadarTypography.body()); Button("أعِد المحاولة", action: load).frame(minHeight: 44) }
                else { ProgressView().frame(maxWidth: .infinity, minHeight: 240) }
            }.padding(.horizontal, 16).padding(.bottom, 30).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.clipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
            .task { load() }.onChange(of: app.prayerRevision) { load() }
            .accessibilityIdentifier("money-rules")
    }
    private func symbol(_ icon: String) -> String { MoneyCategoryIcon.symbol(icon) }
    private func conflicts(_ r: MoneyRulesReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.conflicts.count == 1 ? "تعارض واحد" : "تعارضات").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("dueText"))
                Text("اختر ما يثبت").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(r.conflicts) { conflict in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(conflict.merchant).font(MadarTypography.cardTitle()).lineLimit(1)
                            HStack(spacing: 8) {
                                ForEach(conflict.options, id: \.categoryID) { option in
                                    Button { run("money.saveMerchantRule", ["merchant": .string(conflict.merchant), "categoryID": .string(option.categoryID.uuidString), "ignore": .bool(false)]) } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: MoneyCategoryIcon.symbol(r.allCategories.first { $0.id == option.categoryID }?.icon ?? "", name: option.name))
                                            Text(option.name).font(MadarTypography.caption()).bold().lineLimit(1)
                                            Text(service.counted(option.count, ("مرة واحدة", "مرتان", "مرات", "مرةً"))).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                        }.frame(width: 104, height: 84).overlay { RoundedRectangle(cornerRadius: 8).stroke(theme.color("bills"), lineWidth: 1) }
                                    }.buttonStyle(.madarPlain).accessibilityIdentifier("money-conflict-option")
                                }
                            }
                        }.padding(12).overlay { RoundedRectangle(cornerRadius: 10).stroke(theme.color("dueText").opacity(0.7), lineWidth: 1.2) }
                    }
                }
            }
        }
    }
    private func lanterns(_ r: MoneyRulesReading) -> some View {
        let ignored = r.rules.filter(\.ignore)
        let items = r.categories.map { ($0.id, $0.name, MoneyCategoryIcon.symbol($0.icon, name: $0.name), $0.merchants, $0.times) }
            + (ignored.isEmpty ? [] : [(Self.ignoreLantern, "خارج الميزانية", "nosign", ignored.count, ignored.reduce(0) { $0 + $1.count })])
        let current = selected ?? items.first?.0
        let tints = ["dueText", "surplusText", "accent", "bills", "reserveText"]
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                Rectangle().fill(theme.color("reserve")).frame(height: 1.5).padding(.horizontal, -16)
                HStack(alignment: .top, spacing: 18) {
                    ForEach(Array(items.enumerated()), id: \.element.0) { index, item in
                        let tint = theme.color(tints[index % tints.count]), active = item.0 == current
                        Button { selected = item.0; expanded = nil } label: {
                            VStack(spacing: 6) {
                                Rectangle().fill(theme.color("reserve")).frame(width: 1.5, height: 18)
                                ZStack {
                                    Capsule().fill(active ? tint : .clear).frame(width: 62, height: 86)
                                    Capsule().stroke(tint, lineWidth: 1.4).frame(width: 62, height: 86)
                                    VStack(spacing: 4) {
                                        Image(systemName: item.2).font(.body)
                                        Text(service.digits.string(item.3)).font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .headline))
                                    }.foregroundStyle(active ? theme.background : tint)
                                }.shadow(color: active ? tint.opacity(0.45) : .clear, radius: 14)
                                Text(item.1).font(MadarTypography.caption()).bold().foregroundStyle(active ? tint : theme.ink).lineLimit(1)
                                Text(service.counted(item.4, ("مرة واحدة", "مرتان", "مرات", "مرةً"))).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            }.frame(minWidth: 72)
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("money-lantern-" + item.1)
                    }
                }.padding(.horizontal, 4)
            }
        }
    }
    private func merchants(_ r: MoneyRulesReading) -> some View {
        let current = selected ?? r.categories.first?.id ?? (r.rules.contains(where: \.ignore) ? Self.ignoreLantern : nil)
        let list = r.rules.filter { current == Self.ignoreLantern ? $0.ignore : (!$0.ignore && $0.categoryID == current) }
        let name = current == Self.ignoreLantern ? "خارج الميزانية" : r.allCategories.first { $0.id == current }?.name ?? ""
        let maxCount = max(1, list.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title2)).foregroundStyle(theme.color("dueText"))
                Text(service.counted(list.count, ("تاجر واحد", "تاجران", "تجار", "تاجرًا"))).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Spacer()
                Text("اضغط تاجرًا لتنقله").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }.padding(.bottom, 8)
            DoubleRule().stroke(theme.color("reserveText"), lineWidth: 0.8).frame(height: 3)
            ForEach(list) { rule in
                VStack(alignment: .leading, spacing: 10) {
                    Button { expanded = expanded == rule.id ? nil : rule.id } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.merchant).font(MadarTypography.cardTitle()).lineLimit(1)
                                if let last = rule.lastAt {
                                    Text("آخرها " + app.dateLabels(.containing(last, in: app.activePlace.timeZone), compact: true).combined).font(MadarTypography.fine()).foregroundStyle(theme.color("accent"))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .trailing) {
                                    Rectangle().fill(theme.line).frame(height: 8)
                                    Rectangle().fill(theme.color("due")).frame(width: proxy.size.width * CGFloat(rule.count) / CGFloat(maxCount), height: 8)
                                }.frame(maxHeight: .infinity)
                            }.frame(width: 110, height: 20)
                            Text(service.digits.string(rule.count)).font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .headline)).frame(minWidth: 30)
                            Image(systemName: expanded == rule.id ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(theme.secondaryInk)
                        }.frame(minHeight: 56).contentShape(.rect)
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("money-rule-" + rule.merchant)
                    if expanded == rule.id { ruleEditor(rule, r) }
                }.padding(.vertical, 8).padding(.horizontal, expanded == rule.id ? 10 : 0)
                    .background(expanded == rule.id ? theme.surface : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
            }
        }
    }
    private func ruleEditor(_ rule: MoneyRuleRow, _ r: MoneyRulesReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("تعلّمه")
                MadarDateLabel(app.dateLabels(.containing(rule.learnedAt, in: app.activePlace.timeZone), compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
            }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(r.allCategories) { category in
                        let current = !rule.ignore && category.id == rule.categoryID
                        Button { if !current { run("money.saveMerchantRule", ["merchant": .string(rule.merchant), "categoryID": .string(category.id.uuidString), "ignore": .bool(false)]) } } label: {
                            VStack(spacing: 4) { Image(systemName: MoneyCategoryIcon.symbol(category.icon, name: category.name)); Text(category.name).font(MadarTypography.caption()).bold().lineLimit(1) }
                                .frame(width: 92, height: 64).overlay { RoundedRectangle(cornerRadius: 8).stroke(current ? theme.color("dueText") : theme.line, lineWidth: current ? 1.6 : 1) }
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("money-rule-move-" + category.name)
                    }
                    Button { run("money.forgetMerchantRule", ["id": .string(rule.id.uuidString)]) } label: {
                        Text("انسه").font(MadarTypography.caption()).bold().foregroundStyle(theme.color("dueText")).frame(width: 72, height: 64)
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(theme.color("dueText"), lineWidth: 1.4) }
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("money-rule-forget")
                }
            }
        }
    }
    private func run(_ name: String, _ payload: [String: MadarCore.JSONValue]) {
        runFailure = nil
        // AU-42: a refused move or forget says so instead of quietly showing the old rule again.
        Task {
            do { try await app.executeMoneyCommand(name, payload: payload) } catch { runFailure = "لم يُحفظ التغيير على القاعدة. حاول مرة أخرى." }
            expanded = nil; load()
        }
    }
    private func load() {
        do { reading = try service.loadRules(); failure = nil } catch { failure = "تعذّرت قراءة القواعد" }
    }
}

/// Category picker for one movement: «تذكّر لهذا التاجر» turns the choice into a merchant rule.
struct MoneyCategorizeSheet: View {
    let app: AppSession
    let draft: MoneyMessageDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var remember = true
    @State private var loading = true
    @State private var categories: [MoneyRuleCategory] = []
    @State private var loadFailure: String?
    @State private var failure: String?
    @State private var saving = false
    @State private var pendingCategoryID: UUID?
    @State private var pendingRemember = true
    @State private var commandID = UUID()
    @State private var injectedFailure = false
    private var service: AppMoneyService { .init(app: app) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { dismiss() } label: { Label("إلغاء", systemImage: "xmark").font(MadarTypography.caption()).frame(minHeight: 44) }
                        .disabled(saving).accessibilityIdentifier("money-categorize-close")
                    Spacer()
                    Text("صنّف الحركة").font(MadarTypography.section()).accessibilityAddTraits(.isHeader)
                }
                Text(draft.title).font(MadarTypography.cardTitle()).foregroundStyle(theme.secondaryInk)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("تذكّر لهذا التاجر", isOn: $remember).disabled(saving)
                        .tint(theme.color("surplusText").mix(with: theme.ink, by: 0.35))
                        .accessibilityIdentifier("money-categorize-remember")
                    Text("يصل «" + draft.title + "» بعدها بهذا التصنيف، وتبقى الموافقة لك.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14).background(theme.surface, in: .rect(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                if let failure {
                    Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.color("dueText"))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface, in: .rect(cornerRadius: 14)).accessibilityIdentifier("money-categorize-error")
                }
                if loading {
                    ProgressView("يقرأ التصنيفات…").frame(maxWidth: .infinity, minHeight: 120)
                } else if let loadFailure {
                    Text(loadFailure).font(MadarTypography.body()).foregroundStyle(theme.color("dueText"))
                    Button("أعِد المحاولة") { loadCategories() }.frame(minHeight: 44).accessibilityIdentifier("money-categorize-load-retry")
                } else if categories.isEmpty {
                    Text("لا توجد تصنيفات متاحة لهذه الحركة.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                            Button { save(category) } label: {
                                HStack(spacing: 12) {
                                    if saving && pendingCategoryID == category.id { ProgressView().tint(theme.color("reserveText")) }
                                    else { Image(systemName: draft.categoryID == category.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(draft.categoryID == category.id ? theme.color("surplusText") : theme.secondaryInk) }
                                    Label(category.name, systemImage: MoneyCategoryIcon.symbol(category.icon, name: category.name))
                                        .font(MadarTypography.cardTitle())
                                    Spacer()
                                    if failure != nil && pendingCategoryID == category.id {
                                        Label("حاول مرة أخرى", systemImage: "arrow.clockwise")
                                            .font(MadarTypography.fine()).foregroundStyle(theme.color("dueText"))
                                    } else if draft.categoryID == category.id {
                                        Text("الحالي").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.madarPlain).disabled(saving).accessibilityIdentifier("money-categorize-" + category.name)
                            if index < categories.count - 1 { Rectangle().fill(theme.line.opacity(0.55)).frame(height: 1) }
                        }
                    }
                    .padding(.horizontal, 14).background(theme.surface, in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft).toolbarVisibility(.hidden, for: .navigationBar)
        .task { loadCategories() }.interactiveDismissDisabled(saving)
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("money-categorize-sheet")
    }

    private func loadCategories() {
        loading = true; loadFailure = nil
        do { categories = try service.categories() }
        catch { loadFailure = "تعذّرت قراءة التصنيفات. أعد المحاولة." }
        loading = false
    }

    private func save(_ category: MoneyRuleCategory) {
        guard !saving else { return }
        if pendingCategoryID != category.id || pendingRemember != remember {
            pendingCategoryID = category.id; pendingRemember = remember; commandID = UUID()
        }
        let commandID = commandID
        let remember = remember
        saving = true; failure = nil
        Task { @MainActor in
            do {
                #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if !injectedFailure, UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
                   environment["MADAR_UI_MONEY_CATEGORIZE_FAILURE_ONCE"] == "1" {
                    injectedFailure = true
                    throw DataError.authenticationFailed
                }
                #endif
                try await app.executeMoneyCommand("money.categorize", payload: [
                    "id": .string(draft.id.uuidString), "categoryID": .string(category.id.uuidString), "remember": .bool(remember)
                ], id: commandID)
                dismiss()
            } catch {
                self.failure = "تعذّر حفظ التصنيف. بقي اختيارك هنا؛ حاول مرة أخرى."
            }
            saving = false
        }
    }
}

/// A category's own symbol, else one read from its name, else a tag.
enum MoneyCategoryIcon {
    static func symbol(_ icon: String, name: String = "") -> String {
        if !icon.isEmpty, UIImage(systemName: icon) != nil { return icon }
        let guesses: [(String, String)] = [("مطعم", "fork.knife"), ("مطاعم", "fork.knife"), ("قهوة", "cup.and.saucer"), ("بقالة", "cart"), ("بنزين", "fuelpump"), ("وقود", "fuelpump"),
                                           ("صحة", "cross.case"), ("سفر", "airplane"), ("ملابس", "tshirt"), ("فواتير", "doc.text"), ("هدايا", "gift"), ("أخرى", "shippingbox")]
        return guesses.first { name.contains($0.0) }?.1 ?? "tag"
    }
}
