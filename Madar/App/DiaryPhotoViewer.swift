import SwiftUI
import Photos
import ImageIO
import MadarCore
import MadarDesign

/// One photo in the day's viewer: a photo already on the page (it has a line, so it takes a comment), or a photo from the
/// day's library that is not on the page yet (viewable; pinning or commenting adds it).
struct DiaryViewerItem: Identifiable, Equatable {
    let id: String
    var mediaID: UUID?
    var assetID: String?
    var lineID: String?
    var comment: String
    var data: Data?
    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.lineID == b.lineID && a.comment == b.comment }
}
struct DiaryPhotoViewerStart: Identifiable { let id: String }

/// Owner 12 Nov: «ابغى استعرض الصور مستعرضة، أسحب منها واحد، وأعلّق عليه، والباقي يكون موجود للاستعراض».
/// The day's photos full size on the diary's paper, swiped through like an album; under each, its comment. A comment on a page
/// photo is that photo's own line (`diary.editEntry`, which keeps the photo attached); a library photo is pinned with its comment.
struct DiaryPhotoViewer: View {
    @Bindable var app: AppSession
    let day: GregorianDay
    let load: () async -> [DiaryViewerItem]
    @State var selection: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var items: [DiaryViewerItem] = []
    @State private var editing = false
    @State private var draft = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool
    private var service: AppDiaryService { AppDiaryService(app: app, clock: { app.prayerNow() }) }
    private var current: DiaryViewerItem? { items.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $selection) {
                ForEach(items) { item in DiaryZoomablePhoto(item: item).tag(item.id) }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            commentPanel
        }
        .background(theme.background.ignoresSafeArea())
        .task { items = await load() }
        .onChange(of: selection) { _, _ in editing = false; error = nil; focused = false }
        .accessibilityElement(children: .contain).accessibilityIdentifier("diary-photo-viewer")
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.madarPlain).foregroundStyle(theme.ink).accessibilityLabel("أغلق الصور").accessibilityIdentifier("diary-photo-viewer-close")
            Spacer()
            if let index = items.firstIndex(where: { $0.id == selection }), items.count > 1 {
                Text(service.digits.string(index + 1) + " من " + service.digits.string(items.count))
                    .font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-photo-viewer-count")
            }
        }.padding(.horizontal, 12)
    }

    @ViewBuilder private var commentPanel: some View {
        if let item = current {
            VStack(alignment: .leading, spacing: 10) {
                if editing {
                    TextField(item.lineID == nil ? "اكتب تعليقًا؛ تُثبَّت الصورة في الصفحة معه" : "تعليقك على هذه الصورة", text: $draft, axis: .vertical)
                        .font(DiaryType.writing).lineLimit(1...6).focused($focused).padding(10)
                        .background(theme.surface, in: .rect(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(theme.line) }
                        .accessibilityIdentifier("diary-photo-comment-field")
                    HStack(spacing: 12) {
                        Button("إلغاء") { editing = false; focused = false }.font(DiaryType.label).frame(minHeight: 44)
                            .accessibilityIdentifier("diary-photo-comment-cancel")
                        Spacer()
                        Button { Task { await save(item) } } label: {
                            HStack(spacing: 6) { if saving { ProgressView() }; Text("احفظ التعليق") }
                                .font(DiaryType.label).padding(.horizontal, 18).frame(minHeight: 44)
                                .foregroundStyle(theme.onAccent).background(theme.accent, in: .capsule)
                        }.buttonStyle(.madarPlain).disabled(saving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("diary-photo-comment-save")
                    }
                } else {
                    if !item.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(item.comment).font(DiaryType.writing).lineSpacing(6).foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("diary-photo-comment-text")
                    }
                    HStack(spacing: 10) {
                        Button { draft = item.comment; editing = true; focused = true } label: {
                            Label(item.comment.isEmpty ? "علّق على هذه الصورة" : "عدّل التعليق", systemImage: "text.bubble")
                                .font(DiaryType.label).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.madarPlain).foregroundStyle(theme.ink).accessibilityIdentifier("diary-photo-comment-open")
                        Spacer()
                        if item.lineID == nil {
                            Button { Task { await pin(item, comment: "") } } label: {
                                HStack(spacing: 6) { if saving { ProgressView() }; Label("ثبّتها في الصفحة", systemImage: "pin") }
                                    .font(DiaryType.label).padding(.horizontal, 14).frame(minHeight: 44)
                                    .foregroundStyle(theme.onAccent).background(theme.accent, in: .capsule)
                            }.buttonStyle(.madarPlain).disabled(saving).accessibilityIdentifier("diary-photo-pin")
                        } else {
                            Label("في الصفحة", systemImage: "checkmark").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                        }
                    }
                }
                if let error { Text(error).font(MadarTypography.caption()).foregroundStyle(theme.ink) }
            }.padding(.horizontal, 18).padding(.vertical, 12)
                .background(theme.background).overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 0.7) }
        }
    }

    private func save(_ item: DiaryViewerItem) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !saving else { return }
        if item.lineID == nil { await pin(item, comment: text); return }
        guard let line = item.lineID else { return }
        saving = true; defer { saving = false }
        do {
            try await service.edit(line, text: text)
            editing = false; focused = false
            await reload(keeping: item)
        } catch { self.error = madarUserMessage(error) }
    }
    private func pin(_ item: DiaryViewerItem, comment: String) async {
        guard !saving, let id = item.assetID, let asset = DiaryPhotoLibrary.asset(id) else { return }
        saving = true; defer { saving = false }
        guard let data = await DiaryPhotoLibrary.data(asset), let copy = DiaryPhotoLibrary.smallCopy(of: data) else { error = "تعذّر قراءة الصورة من تطبيق الصور."; return }
        do {
            try await service.appendMedia(data: copy, kind: "photo", contentType: "image/jpeg", caption: comment, day: "today", writingDay: day, assetID: id)
            app.diaryPhotoEpoch += 1
            editing = false; focused = false
            await reload(keeping: item)
        } catch { self.error = madarUserMessage(error) }
    }
    /// A comment saves a new revision of the line and a pin turns a library photo into a page photo, so ids change; stay on the same picture.
    private func reload(keeping item: DiaryViewerItem) async {
        let fresh = await load()
        items = fresh
        if let same = fresh.first(where: { ($0.mediaID != nil && $0.mediaID == item.mediaID) || ($0.assetID != nil && $0.assetID == item.assetID && $0.lineID != nil) }) ?? fresh.first(where: { $0.id == item.id }) {
            selection = same.id
        }
    }
}

/// A full photo that pinches and double-taps to zoom. Full size comes from the Photos library when the photo is there,
/// otherwise from the diary's own copy; it is decoded off the main thread and only for pages the user reaches.
private struct DiaryZoomablePhoto: View {
    let item: DiaryViewerItem
    @Environment(\.roomTheme) private var theme
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var settled: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragged: CGSize = .zero
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .scaleEffect(scale).offset(offset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .gesture(MagnifyGesture().onChanged { value in scale = min(4, max(1, settled * value.magnification)) }
                            .onEnded { _ in settled = scale; if scale == 1 { offset = .zero; dragged = .zero } })
                        .simultaneousGesture(DragGesture().onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: dragged.width + value.translation.width, height: dragged.height + value.translation.height)
                        }.onEnded { _ in dragged = offset }, including: scale > 1 ? .all : .subviews)
                        .onTapGesture(count: 2) {
                            withAnimation(.snappy) { if scale > 1 { scale = 1; offset = .zero; dragged = .zero } else { scale = 2.5 }; settled = scale }
                        }
                        .accessibilityLabel(item.comment.isEmpty ? "صورة من هذا اليوم" : item.comment)
                } else {
                    ProgressView()
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: item.id) {
            if let id = item.assetID, let asset = DiaryPhotoLibrary.asset(id), let data = await DiaryPhotoLibrary.data(asset) {
                image = await Self.decode(data)
            }
            if image == nil, let data = item.data { image = await Self.decode(data) }
        }
        .onDisappear { scale = 1; settled = 1; offset = .zero; dragged = .zero }
    }
    @concurrent static func decode(_ data: Data) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 2_400]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}
