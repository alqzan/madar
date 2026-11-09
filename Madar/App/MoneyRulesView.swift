import SwiftUI
import MadarCore
import MadarData
import MadarDesign
import MadarMoney
import MadarCommands

/// Category picker for one movement: «تذكّر لهذا التاجر» turns the choice into a merchant rule.
struct MoneyCategorizeSheet: View {
    let app: AppSession
    let draft: MoneyMessageDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var loading = true
    @State private var categories: [MoneyRuleCategory] = []
    @State private var loadFailure: String?
    @State private var failure: String?
    @State private var rootBlockerID = UUID()
    @State private var saving = false
    @State private var pendingCategoryID: UUID?
    @State private var commandID = UUID()
    @State private var injectedFailure = false
    private var service: AppMoneyService { .init(app: app) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { dismiss() } label: { Label("إلغاء", systemImage: "xmark").font(MadarTypography.caption()).frame(minHeight: 44) }.madarWaitsForSave()
                        .disabled(saving).accessibilityIdentifier("money-categorize-close")
                    Spacer()
                    Text("صنّف الحركة").font(MadarTypography.section()).accessibilityAddTraits(.isHeader)
                }
                Text(draft.title).font(MadarTypography.cardTitle()).foregroundStyle(theme.secondaryInk)
                VStack(alignment: .leading, spacing: 6) {
                    Text("لهذه العملية فقط. إذا تكرّر اختيارك اقترحه مدار في المرات القادمة.")
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
                    Button { loadCategories() } label: { Text("أعِد المحاولة").frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("money-categorize-load-retry")
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
        .task { loadCategories() }.madarSheetLock(saving: saving)
        .onChange(of: saving, initial: true) { _, blocked in app.setMoneyRootDraftBlocker(rootBlockerID, active: blocked) }
        .onDisappear { app.setMoneyRootDraftBlocker(rootBlockerID, active: false) }
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
        if pendingCategoryID != category.id {
            pendingCategoryID = category.id; commandID = UUID()
        }
        let commandID = commandID
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
                    "id": .string(draft.id.uuidString), "categoryID": .string(category.id.uuidString)
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
