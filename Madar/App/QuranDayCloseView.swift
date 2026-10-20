import SwiftUI
import MadarDesign

/// M2-V05 · R18-Khitam. A live, read-only summary of committed facts.
struct QuranDayCloseView: View {
    let service: AppQuranService
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var summary: QuranUIDayClose?
    @State private var error: String?
    @State private var explainStrength = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Button(action: close) {
                        Image(systemName: "chevron.backward").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("رجوع إلى الرئيسية").accessibilityIdentifier("quran-day-close-back")
                    Text("ختام اليوم").font(serif(28)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 4).padding(.bottom, 8)
                if let summary {
                    content(summary)
                    Button("عودة إلى الرئيسية", action: close)
                        .font(font(16, bold: true)).frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(theme.onAccent).background(theme.color("accent"), in: Capsule())
                        .accessibilityIdentifier("quran-day-close-home")
                } else if let error {
                    Text(error).font(font(15))
                    Button("حاول مرة أخرى", action: load).frame(minHeight: 44)
                } else { ProgressView().padding(60) }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .accessibilityIdentifier("quran-day-close")
        .task { load() }
        .sheet(isPresented: $explainStrength) {
            VStack(alignment: .leading, spacing: 16) {
                Text("المتانة قبل وبعد").font(serif(23))
                if let summary {
                    Text("المتانة العامة: " + percent(summary.strengthBefore) + " ← " + percent(summary.strengthAfter))
                        .font(font(14, bold: true)).accessibilityIdentifier("quran-day-close-strength")
                }
                Text("مؤشر وصفي من تقييمك ومواعيد المراجعة. تُحسب «قبل» دون جلسات اليوم، و«بعد» معها، في اليوم نفسه. الوجه غير المكتمل أو بلا جدول لا يدخل المتوسط.").font(font(15))
                Button("تمّ") { explainStrength = false }.font(font(15, bold: true)).frame(maxWidth: .infinity, minHeight: 44)
            }.padding(24).foregroundStyle(theme.ink).background(theme.surface)
                .presentationDetents([.height(300)]).presentationDragIndicator(.visible)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
    private func content(_ value: QuranUIDayClose) -> some View {
        VStack(spacing: 10) {
            ZStack {
                QuranCompletionSeal().fill(theme.color("gold"))
                Image(systemName: value.title == "أتممت يومك" ? "checkmark" : "leaf")
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(theme.color("onGold"))
            }.frame(width: 66, height: 66).padding(.top, 4).padding(.bottom, 8).accessibilityHidden(true)
            Text(value.title).font(serif(30)).accessibilityIdentifier("quran-day-close-title")
            // Both calendars: the primary date as the main line, the other smaller beneath it;
            // the streak stands apart in the same mark as the Quran home instead of trailing the date.
            VStack(spacing: 3) {
                Text(value.date.primary).font(font(13)).foregroundStyle(theme.ink)
                Text(value.date.secondary).font(font(11)).foregroundStyle(theme.secondaryInk)
            }
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine).accessibilityIdentifier("quran-day-close-date")
            if !value.streak.isEmpty {
                HStack(spacing: 6) { Circle().fill(theme.color("hifz")).frame(width: 7, height: 7).accessibilityHidden(true); Text(value.streak) }
                    .font(font(12, bold: true)).foregroundStyle(theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(theme.color("hifzTint"), in: .capsule)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("quran-day-close-streak")
            }
            Color.clear.frame(height: 4)
            coverage(value)
            review(value)
            VStack(alignment: .leading, spacing: 8) {
                Text("غدًا").font(font(14, bold: true))
                Text(value.tomorrow).font(font(13)).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("quran-day-close-tomorrow")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .overlay { RoundedRectangle(cornerRadius: 17).stroke(theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
        }.padding(18).frame(maxWidth: .infinity)
            .background(theme.surface, in: .rect(cornerRadius: 26))
            .shadow(color: theme.ink.opacity(0.05), radius: 16, y: 8)
    }
    private func coverage(_ value: QuranUIDayClose) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("في صدرك").font(font(14, bold: true)); Spacer(minLength: 8)
                Text(value.addedFaces > 0 ? "+ " + faces(value.addedFaces) : value.addedAyahs > 0 ? "آيات جديدة" : "لا زيادة اليوم")
                    .font(font(12, bold: true)).foregroundStyle(theme.color("hifzText"))
            }
            Text(service.numerals.string(value.beforeFaces) + " ← " + faces(value.afterFaces))
                .font(serif(24)).accessibilityLabel(faces(value.beforeFaces) + " ← " + faces(value.afterFaces))
                .accessibilityIdentifier("quran-day-close-coverage")
            if value.addedAyahs > 0 && value.addedFaces == 0 {
                Text(QuranDayCloseCopy.ayahs(value.addedAyahs, digits: service.numerals) + "، والوجه لم يكتمل بعد")
                    .font(font(12)).foregroundStyle(theme.secondaryInk)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(theme.color("gold").opacity(0.16), in: .rect(cornerRadius: 17))
    }
    private func review(_ value: QuranUIDayClose) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("المراجعة: " + faces(value.reviewedFaces)).font(font(14, bold: true))
                    .accessibilityIdentifier("quran-day-close-reviewed")
                Spacer(minLength: 4)
                Button("قبل ← بعد") { explainStrength = true }.font(font(11)).foregroundStyle(theme.secondaryInk).frame(minHeight: 44)
                    .accessibilityLabel("المتانة قبل وبعد، على أي أساس")
            }
            if value.strengths.isEmpty {
                Text("لم تُسجّل مراجعة اليوم").font(font(13)).foregroundStyle(theme.secondaryInk)
            } else {
                ForEach(value.strengths) { row in
                    strengthRow(row)
                }
            }
        }.padding(.horizontal, 14).padding(.bottom, 16).padding(.top, 4)
            .background(theme.color("reviewTint"), in: .rect(cornerRadius: 17))
    }
    private func strengthRow(_ row: QuranUIDayCloseStrength) -> some View {
        HStack(spacing: 12) {
            Text(row.title).font(.custom("Amiri-Regular", size: 19, relativeTo: .body)).frame(width: dynamicType.isAccessibilitySize ? nil : 62, alignment: .leading)
            if !dynamicType.isAccessibilitySize {
                GeometryReader { proxy in
                    Capsule().fill(theme.color("track"))
                        .overlay(alignment: .leading) { Capsule().fill(theme.color("review")).frame(width: proxy.size.width * Double(row.after ?? 0) / 100) }
                }.frame(height: 6).accessibilityHidden(true)
            }
            HStack(spacing: 3) {
                Text(percent(row.before))
                Image(systemName: "arrow.left").font(.system(size: 10))
                Text(percent(row.after))
            }.font(font(12, bold: true)).fixedSize().environment(\.layoutDirection, .rightToLeft)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(row.title + "، قبل " + percent(row.before) + "، بعد " + percent(row.after))
    }
    private func percent(_ value: Int?) -> String { value.map { "\u{2066}" + service.numerals.percent($0) + "\u{2069}" } ?? "—" }
    private func faces(_ value: Int) -> String { QuranDayCloseCopy.faces(value, digits: service.numerals) }
    private func font(_ size: CGFloat, bold: Bool = false) -> Font { .custom(bold ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: size, relativeTo: .body) }
    private func serif(_ size: CGFloat) -> Font { .custom("Amiri-Bold", size: size, relativeTo: .title2) }
    private func load() { do { summary = try service.dayClose(); error = nil } catch { self.error = quranUserMessage(error) } }
}

private struct QuranCompletionSeal: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let center = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) / 2
            for index in 0..<16 {
                let angle = Double(index) * .pi / 8 - .pi / 2
                let length = radius * (index.isMultiple(of: 2) ? 1 : 0.66)
                let point = CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}
