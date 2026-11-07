import SwiftUI
import MadarDesign
import MadarPrayer

struct PrayerRiwaq<Content: View>: View {
    let pool: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.roomTheme) private var theme
    var body: some View {
        HStack(alignment: .top, spacing: 0) { content() }
            .padding(.horizontal, 10)
            .padding(.top, 22).padding(.bottom, 18)
            .background(alignment: .top) {
                // The water line runs edge to edge under the arches.
                Rectangle().fill(theme.ink.opacity(0.22)).frame(height: 1)
                    .padding(.top, 22 + PrayerTodayArch.archHeight)
            }
            .background(theme.color("goldSoft"), in: .rect(cornerRadius: 22))
            .background(theme.background, in: .rect(cornerRadius: 22))
            .clipShape(.rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 1) }
            .environment(\.prayerPool, pool)
    }
}

private extension EnvironmentValues {
    @Entry var prayerPool = true
}

struct PrayerTodayArch: View {
    static let archHeight: CGFloat = 92
    let cell: PrayerCell
    let isNext: Bool
    let title: String
    let tall: Bool
    let timeLabel: String
    var note: String?
    let countdown: String?
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.prayerPool) private var pool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFrontRoom) private var isFrontRoom
    @Environment(\.scenePhase) private var scenePhase

    /// Keep animated marks quiet while this retained room sits behind another room or the app is inactive.
    private var pauseContinuousMotion: Bool { reduceMotion || !isFrontRoom || scenePhase != .active }

    private var statusText: String {
        switch cell.status {
        case .jamaah: "جماعة"
        case .alone: "وحدي"
        case .qada: "قُضيت"
        case .missed: "فاتتني"
        case .unrecordedHistory: "لم أسجّل"
        case .unconfirmed: "غير محسومة"
        case .excused: "معذور"
        case .pending: "لم تُسجَّل"
        case .future: "لم يحن"
        }
    }
    var accessibilityText: String {
        let detail = note.flatMap { $0.isEmpty ? nil : $0 }
            ?? (cell.time == nil && cell.status == .future ? "سجّلها يدويًا" : statusText)
        return "\(title)، \(timeLabel)، \(detail)"
    }
    private var gold: Color { theme.color("goldMid") }
    private var logged: Bool { [.jamaah, .alone, .qada, .missed].contains(cell.status) }
    private var bodyFill: Color {
        switch cell.status {
        case .jamaah: gold.opacity(0.62)
        case .alone: gold.opacity(0.36)
        case .qada: theme.ink.opacity(0.07)
        default: theme.background
        }
    }

    @ViewBuilder var body: some View {
        if dynamicType.isAccessibilitySize {
            accessibilityRow
        } else {
            VStack(spacing: 0) {
                arch
                    .frame(height: Self.archHeight + (tall ? 12 : 0))
                    .frame(height: Self.archHeight, alignment: .bottom)
                reflection
                    .frame(height: Self.archHeight * 0.42, alignment: .top)
                    .clipped()
                VStack(spacing: 3) {
                    Text(title).font(PrayerHomeType.archName).lineLimit(1).minimumScaleFactor(0.75)
                    Text(timeLabel).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.85)
                    Text(countdown ?? note ?? statusText)
                        .font(countdown != nil || cell.status == .missed ? PrayerHomeType.smallBold : PrayerHomeType.small)
                        .foregroundStyle(countdown != nil ? theme.accent : cell.status == .missed ? theme.color("missedTextOnSurface") : cell.status == .future ? theme.secondaryInk : theme.ink.opacity(0.78))
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
    }

    private var arch: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width - 12, 58)
            let height = geometry.size.height
            let rect = CGRect(x: (geometry.size.width - width) / 2, y: 0, width: width, height: height)
            let shape = PrayerHorseshoe().path(in: rect)
            let strokeWidth: CGFloat = isNext ? 5 : cell.status == .missed ? 1.5 : cell.status == .pending ? 1 : 0
            let strokeInset = strokeWidth / 2 + (strokeWidth > 0 ? 0.5 : 0)
            let outlineRect = CGRect(x: rect.minX, y: rect.minY + strokeInset, width: rect.width, height: rect.height - strokeInset)
            let outline = PrayerHorseshoe().path(in: outlineRect)
            let spring = rect.minY + width / 2 * 1.5
            ZStack {
                // Pillars beside the arch.
                ForEach([rect.minX - 5, rect.maxX], id: \.self) { x in
                    Rectangle().fill(gold.opacity(0.1)).frame(width: 5, height: height - spring + 6)
                        .position(x: x + 2.5, y: (spring - 6 + height) / 2)
                }
                shape.fill(bodyFill)
                // Lattice: the whole head once a prayer is recorded, a frame band otherwise.
                PrayerLatticePattern(spacing: 9)
                    .stroke(theme.accent.opacity(logged ? 0.55 : 0.45), lineWidth: 1)
                    .mask {
                        if logged {
                            shape.fill().mask(alignment: .top) { Rectangle().frame(height: spring + 2) }
                        } else {
                            shape.stroke(lineWidth: 14).mask(alignment: .top) { Rectangle().frame(height: spring) }
                        }
                    }
                    .clipShape(shape)
                if !logged && !isNext {
                    // A fine rim keeps the open dome edge clean where the lattice band ends.
                    shape.trim(from: 0, to: 1).stroke(theme.accent.opacity(0.4), lineWidth: 1)
                        .mask(alignment: .top) { Rectangle().frame(height: spring) }
                }
                if isNext {
                    outline.stroke(theme.accent, style: StrokeStyle(lineWidth: 5, lineJoin: .round))
                } else if cell.status == .missed {
                    outline.stroke(theme.color("missed"), lineWidth: 1.5)
                } else if cell.status == .pending {
                    outline.stroke(gold, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                symbol.position(x: rect.midX, y: spring)
            }
        }
    }

    @ViewBuilder private var symbol: some View {
        switch cell.status {
        case .jamaah:
            PrayerStar().fill(theme.accent).frame(width: 15, height: 15)
        case .alone:
            PrayerStar().fill(gold).overlay { PrayerStar().stroke(theme.accent, lineWidth: 1) }.frame(width: 15, height: 15)
        case .qada:
            PrayerStar().fill(theme.ink.opacity(0.32)).frame(width: 15, height: 15)
        case .missed:
            PrayerStar().stroke(theme.color("missed"), lineWidth: 1.2).frame(width: 15, height: 15)
        case .pending:
            TimelineView(.animation(minimumInterval: 1 / 15, paused: pauseContinuousMotion)) { context in
                let phase = reduceMotion ? 0.25 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                Capsule().fill(theme.accent).frame(width: 14, height: 2).opacity(0.35 + 0.5 * abs(1 - 2 * phase))
            }
        default:
            // DA-02 (canonical S1): a prayer still to come carries a pale star; the next one a full accent star.
            PrayerStar().fill(isNext ? theme.accent : theme.ink.opacity(0.16)).frame(width: 15, height: 15)
        }
    }

    /// Mirrored, at about half the height, 28% opacity, with water lines every 6 points.
    @ViewBuilder private var reflection: some View {
        if pool {
            arch
                .frame(height: Self.archHeight)
                .scaleEffect(x: 1, y: -1)
                .scaleEffect(x: 1, y: 0.5, anchor: .top)
                .opacity(0.28)
                .overlay {
                    VStack(spacing: 5) { ForEach(0..<8, id: \.self) { _ in Rectangle().fill(theme.background.opacity(0.7)).frame(height: 1) } }
                }
                .overlay(alignment: .top) {
                    // A slow, restrained glint gives the next arch a quiet water reflection.
                    // Reduced Motion holds the same glint at its center frame.
                    TimelineView(.animation(minimumInterval: 1 / 12, paused: pauseContinuousMotion || !isNext)) { context in
                        let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                        let phase = (sin(time * 0.35) + 1) / 2
                        Capsule()
                            .fill(theme.color("goldMid").opacity(isNext ? 0.28 + 0.4 * phase : 0.08))
                            .frame(width: isNext ? 32 + 16 * phase : 22, height: isNext ? 2 + phase : 2)
                            .offset(x: isNext ? CGFloat(sin(time * 0.35) * 5) : 0)
                            .blur(radius: isNext ? 2 + phase : 2)
                    }
                }
                .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    var accessibilityRow: some View {
        HStack(spacing: 12) {
            symbol.frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(MadarTypography.section())
                Text("\(timeLabel)، \(countdown ?? statusText)").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 8)
            if isNext { Image(systemName: "arrow.left").foregroundStyle(theme.accent).accessibilityHidden(true) }
        }
        .frame(minHeight: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
