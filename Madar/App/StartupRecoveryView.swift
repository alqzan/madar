import SwiftUI
import MadarData

/// Shown when the store cannot be opened (T03). It lists the backups it can find without a session, lets the user
/// share them or the error text, and can set the unreadable store aside (never delete it) to open a clean one
/// and restore from Settings.
struct StartupRecoveryView: View {
    let error: String
    let groupDirectory: URL?
    let retry: () -> Void
    let startFresh: () async -> Void
    @State private var candidates: [StartupRecovery.Candidate] = []
    @State private var copied = false
    @State private var confirming = false
    @State private var working = false
    static let supportAddress = "alqazan.u@gmail.com"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("تعذّر فتح مدار").font(.title2.bold())
                Text("تعذّر على مدار فتح بياناته. لم يحذف هذا الإجراء شيئًا. أعِد المحاولة أولًا، وإن تكرّر فلديك نسخ محفوظة أدناه.")
                    .font(.body).foregroundStyle(.secondary)
                Text(error).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("أعِد المحاولة", action: retry).buttonStyle(.borderedProminent)
                    Button(copied ? "نُسخ" : "انسخ تفاصيل الخطأ") {
                        UIPasteboard.general.string = details
                        copied = true
                    }.buttonStyle(.bordered)
                }
                if !candidates.isEmpty {
                    Divider()
                    Text("نسخ وجدها مدار على هذا الجهاز").font(.headline)
                    ForEach(candidates) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title(item)).font(.subheadline.weight(.semibold))
                                Text(item.date.formatted(date: .abbreviated, time: .shortened) + " · " + ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.source != .preMigration { ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up") } }
                        }
                    }
                    Button("ابدأ بمخزن جديد ثم استعد من نسخة") { confirming = true }.buttonStyle(.bordered).disabled(working)
                    Text("يُنقل المخزن الذي تعذّر فتحه إلى مجلد بجانبه ولا يُحذف. بعد فتح مدار تجد الاستعادة في الإعدادات ← النسخ الاحتياطي.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Divider()
                Text("للمساعدة راسل: \(Self.supportAddress)").font(.footnote).textSelection(.enabled)
            }.padding(24)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .task { if let groupDirectory { candidates = StartupRecovery.candidates(groupDirectory: groupDirectory) } }
        .confirmationDialog("ابدأ بمخزن جديد؟", isPresented: $confirming, titleVisibility: .visible) {
            Button("انقل القديم وابدأ") { Task { working = true; await startFresh(); working = false } }
            Button("إلغاء", role: .cancel) {}
        } message: { Text("لا يُحذف شيء. يبقى المخزن القديم في مجلد جانبي.") }
    }
    private var details: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Madar \(version) (\(build)) · iOS \(UIDevice.current.systemVersion)\n\(error)"
    }
    private func title(_ item: StartupRecovery.Candidate) -> String {
        switch item.source {
        case .manual: "نسخة يدوية"
        case .automatic: "نسخة تلقائية"
        case .preMigration: "نسخة قبل الترحيل"
        }
    }
}
